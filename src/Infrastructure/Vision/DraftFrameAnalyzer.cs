using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Infrastructure.Capture;
using DraftAssistant.Infrastructure.Recognition;
using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Vision;

public sealed record SlotAnalysis(SlotId Slot, PixelRect RectInClient, SlotObservation Observation, RecognitionResult? Recognition, bool FromCache);

public sealed record FrameAnalysis(DraftObservation Observation, IReadOnlyList<SlotAnalysis> Slots, double SignatureScore);

/// <summary>
/// Анализ одного кадра: ROI → пустой ли слот → распознавание → наблюдение.
/// Не захватывает экран сам (это делает IScreenCaptureService) — поэтому тот же код
/// используется и в live-режиме, и в DataTool для проверки разметки на скриншотах.
///
/// Производительность: слот, изображение которого не изменилось с прошлого кадра
/// (по миниатюре 16x9), не распознаётся повторно — результат берётся из кэша.
/// </summary>
public sealed class DraftFrameAnalyzer
{
    private readonly ILayoutProvider _layout;
    private readonly IHeroRecognizer _recognizer;
    private readonly SlotEmptinessClassifier _emptiness;
    private readonly Func<RecognitionOptions> _options;
    private readonly Dictionary<SlotId, (Mat Thumb, SlotObservation Obs, RecognitionResult? Rec)> _cache = new();
    private int _cacheRevision = -1;
    private PlayerBarGrid? _cacheGrid;

    public DraftFrameAnalyzer(ILayoutProvider layout, IHeroRecognizer recognizer, SlotEmptinessClassifier emptiness, Func<RecognitionOptions> options)
    {
        _layout = layout;
        _recognizer = recognizer;
        _emptiness = emptiness;
        _options = options;
    }

    public bool IsCalibrated => _layout.Current.Calibrated && _layout.Current.RadiantPicks.Count > 0;

    /// <summary>Минимальный прямоугольник клиентской области, покрывающий все ROI (только его и нужно захватывать).</summary>
    public PixelRect RequiredRegion(int clientWidth, int clientHeight)
    {
        var layout = _layout.Current;
        var canvas = UiCanvas.Compute(clientWidth, clientHeight, layout.Anchor);
        var union = default(PixelRect);
        foreach (var (_, r) in layout.AllSlots()) union = union.Union(UiCanvas.ToPixels(r, canvas));
        if (layout.SignatureRegion is { } s) union = union.Union(UiCanvas.ToPixels(s, canvas));
        return union.Intersect(new PixelRect(0, 0, clientWidth, clientHeight));
    }

    /// <summary>
    /// Автоматический режим: слоты берутся из сетки, найденной по цветным полоскам игроков.
    /// Сам факт найденной сетки означает, что на экране драфт (на игровом HUD шаг слотов другой).
    /// </summary>
    public FrameAnalysis AnalyzeGrid(Mat region, PixelRect regionInClient, PlayerBarGrid grid, bool useCache = true)
    {
        var now = DateTimeOffset.UtcNow;
        if (_cacheGrid is null || !grid.SameAs(_cacheGrid))
        {
            ClearCache();
            _cacheGrid = grid;
            _cacheRevision = -2;
        }

        var slots = new List<SlotAnalysis>();
        foreach (var side in new[] { DraftSide.Radiant, DraftSide.Dire })
        {
            for (int i = 0; i < 5; i++)
            {
                var id = new SlotId(side, SlotKind.Pick, i);
                var rect = grid.Portrait(side, i);
                using var crop = CvImage.Crop(region, rect.Offset(-regionInClient.X, -regionInClient.Y));
                slots.Add(crop is null
                    ? new SlotAnalysis(id, rect, new SlotObservation(id, ObservedContent.Unknown, null, 0), null, false)
                    : AnalyzeSlot(id, rect, crop, useCache));
            }
        }

        double confidence = grid.DetectedBars / 10.0;
        var observation = new DraftObservation(true, confidence, slots.Select(s => s.Observation).ToList(), ObservationIssue.None, now);
        return new FrameAnalysis(observation, slots, confidence);
    }

    private void ClearCache()
    {
        foreach (var c in _cache.Values) c.Thumb.Dispose();
        _cache.Clear();
    }

    /// <param name="region">Захваченный фрагмент (BGR).</param>
    /// <param name="regionInClient">Где этот фрагмент находится в клиентской области.</param>
    public FrameAnalysis Analyze(Mat region, PixelRect regionInClient, int clientWidth, int clientHeight, bool useCache = true)
    {
        var now = DateTimeOffset.UtcNow;
        var layout = _layout.Current;
        if (!IsCalibrated)
        {
            return new FrameAnalysis(
                new DraftObservation(false, 0, [], ObservationIssue.LayoutNotCalibrated, now), [], 0);
        }

        if (_cacheRevision != _layout.Revision)
        {
            ClearCache();
            _cacheRevision = _layout.Revision;
            _cacheGrid = null;
        }

        var canvas = UiCanvas.Compute(clientWidth, clientHeight, layout.Anchor);
        var slots = new List<SlotAnalysis>();

        foreach (var (id, norm) in layout.AllSlots())
        {
            var rect = UiCanvas.ToPixels(norm, canvas);
            using var crop = CvImage.Crop(region, rect.Offset(-regionInClient.X, -regionInClient.Y));
            if (crop is null)
            {
                slots.Add(new SlotAnalysis(id, rect, new SlotObservation(id, ObservedContent.Unknown, null, 0), null, false));
                continue;
            }
            slots.Add(AnalyzeSlot(id, rect, crop, useCache));
        }

        double signatureScore = 0;
        bool visible;
        var signature = _layout.Signature;
        if (layout.SignatureRegion is { } sigNorm && signature is not null)
        {
            var sigRect = UiCanvas.ToPixels(sigNorm, canvas).Offset(-regionInClient.X, -regionInClient.Y);
            using var sigCrop = CvImage.Crop(region, sigRect);
            signatureScore = sigCrop is null ? 0 : DraftSignatureMatcher.Score(sigCrop, signature);
            visible = signatureScore >= _options().SignatureThreshold;
        }
        else
        {
            // Без сигнатуры: экран драфта считается видимым, если большинство слотов пика
            // опознаны как пустые или как герои И хотя бы один герой распознан уверенно.
            // Второе условие защищает от чёрного кадра и однотонного фона меню
            // ("все слоты пустые"). Цена: без сигнатуры драфт обнаруживается с первого пика.
            var picks = slots.Where(s => s.Slot.Kind == SlotKind.Pick).ToList();
            bool IsConfidentHero(SlotAnalysis s) =>
                s.Observation.Content == ObservedContent.Hero && s.Observation.Confidence >= 0.6;
            int plausible = picks.Count(s => s.Observation.Content == ObservedContent.Empty || IsConfidentHero(s));
            signatureScore = picks.Count == 0 ? 0 : (double)plausible / picks.Count;
            visible = picks.Count > 0
                      && plausible >= Math.Ceiling(picks.Count * 0.8)
                      && picks.Any(IsConfidentHero);
        }

        var observation = new DraftObservation(
            visible, signatureScore, slots.Select(s => s.Observation).ToList(), ObservationIssue.None, now);
        return new FrameAnalysis(observation, slots, signatureScore);
    }

    private SlotAnalysis AnalyzeSlot(SlotId id, PixelRect rect, Mat crop, bool useCache)
    {
        var o = _options();
        var thumb = MakeThumb(crop);
        if (useCache && _cache.TryGetValue(id, out var cached) && MeanAbsDiff(cached.Thumb, thumb) < o.UnchangedSlotThreshold)
        {
            thumb.Dispose();
            return new SlotAnalysis(id, rect, cached.Obs, cached.Rec, true);
        }

        SlotObservation obs;
        RecognitionResult? rec = null;
        if (_emptiness.IsEmpty(crop, _layout.EmptySlot, out var emptyScore))
        {
            obs = new SlotObservation(id, ObservedContent.Empty, null, emptyScore);
        }
        else
        {
            rec = _recognizer.Recognize(crop, id.Kind);
            obs = rec.HeroId is { } hero
                ? new SlotObservation(id, ObservedContent.Hero, hero, rec.Confidence)
                : new SlotObservation(id, ObservedContent.Unknown, null, rec.Confidence);
        }

        if (_cache.TryGetValue(id, out var old)) old.Thumb.Dispose();
        _cache[id] = (thumb, obs, rec);
        return new SlotAnalysis(id, rect, obs, rec, false);
    }

    private static Mat MakeThumb(Mat crop)
    {
        using var small = CvImage.Resize(crop, new Size(16, 9));
        return CvImage.ToGray(small);
    }

    private static double MeanAbsDiff(Mat a, Mat b)
    {
        using var diff = new Mat();
        Cv2.Absdiff(a, b, diff);
        return Cv2.Mean(diff).Val0;
    }
}
