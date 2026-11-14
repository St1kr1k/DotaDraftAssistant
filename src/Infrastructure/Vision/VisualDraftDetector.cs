using DraftAssistant.Application.Abstractions;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Infrastructure.Capture;
using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Vision;

public enum DetectionMode { None, Automatic, Manual }

/// <summary>
/// IDraftDetector: окно Dota → захват верха экрана → поиск сетки слотов по цветным полоскам
/// (автоматически, без калибровки) → распознавание героев, а раз в несколько кадров — текста
/// (роли тиммейтов, ваш ник, баны в чате).
///
/// Ручная калибровка, если она сохранена, имеет приоритет (запасной путь для нестандартных экранов).
/// </summary>
public sealed class VisualDraftDetector : IDraftDetector
{
    private const int TextEveryTicks = 12;       // ~1.5 с при 8 FPS
    private const int MaxDebugFrames = 6;

    private readonly IScreenCaptureService _capture;
    private readonly DraftFrameAnalyzer _analyzer;
    private readonly DraftTextReader? _text;
    private readonly Func<string?> _playerName;
    private readonly string? _debugDir;
    private readonly Func<bool> _saveDebugFrames;

    private PlayerBarGrid? _grid;
    private int _tick;
    private int _missedGrid;
    private DraftTextInfo? _lastText;
    private DateTimeOffset _draftSeenAt = DateTimeOffset.MinValue;
    private int _debugSavedThisDraft;

    public VisualDraftDetector(
        IScreenCaptureService capture,
        DraftFrameAnalyzer analyzer,
        DraftTextReader? text = null,
        Func<string?>? playerName = null,
        string? debugDirectory = null,
        Func<bool>? saveDebugFrames = null)
    {
        _capture = capture;
        _analyzer = analyzer;
        _text = text;
        _playerName = playerName ?? (() => null);
        _debugDir = debugDirectory;
        _saveDebugFrames = saveDebugFrames ?? (() => false);
    }

    public IReadOnlyList<SlotId> Slots => DraftLayout.StandardSlots;

    public FrameAnalysis? LastAnalysis { get; private set; }

    /// <summary>Как сейчас определяется разметка (для экрана «Настройка»).</summary>
    public DetectionMode Mode { get; private set; }

    /// <summary>Разрешение, на котором последний раз автоматически найден экран драфта.</summary>
    public string? LastAutoResolution { get; private set; }

    public DraftObservation? Observe()
    {
        var window = _capture.FindGameWindow();
        if (window is null) return null;

        var now = DateTimeOffset.UtcNow;
        if (window.IsMinimized) return new DraftObservation(false, 0, [], ObservationIssue.None, now);

        int w = window.ClientRect.Width, h = window.ClientRect.Height;
        return _analyzer.IsCalibrated ? ObserveManual(window, w, h, now) : ObserveAuto(window, w, h, now);
    }

    private DraftObservation ObserveManual(GameWindowInfo window, int w, int h, DateTimeOffset now)
    {
        Mode = DetectionMode.Manual;
        var region = _analyzer.RequiredRegion(w, h);
        if (region.IsEmpty) return new DraftObservation(false, 0, [], ObservationIssue.LayoutNotCalibrated, now);
        var frame = _capture.Capture(window, region);
        if (frame is null) return new DraftObservation(false, 0, [], ObservationIssue.None, now);
        using var mat = CvImage.ToBgrMat(frame);
        LastAnalysis = _analyzer.Analyze(mat, region, w, h);
        return LastAnalysis.Observation;
    }

    private DraftObservation ObserveAuto(GameWindowInfo window, int w, int h, DateTimeOffset now)
    {
        _tick++;
        var topRegion = new PixelRect(0, 0, w, Math.Max(40, (int)(h * PlayerBarGridDetector.SearchHeight)));
        var frame = _capture.Capture(window, topRegion);
        if (frame is null) return new DraftObservation(false, 0, [], ObservationIssue.None, now);
        using var top = CvImage.ToBgrMat(frame);

        var grid = PlayerBarGridDetector.Detect(top, w);
        if (grid is null)
        {
            // Пара пропущенных кадров (анимация, всплывающее окно) не означает конец драфта.
            if (_grid is not null && ++_missedGrid <= 4) grid = _grid;
            else
            {
                _grid = null;
                _lastText = null;
                _debugSavedThisDraft = 0;
                return new DraftObservation(false, 0, [], ObservationIssue.None, now);
            }
        }
        else
        {
            _missedGrid = 0;
            if (_grid is null) _draftSeenAt = now;
            // Держим прежнюю сетку, если новая совпадает с точностью до пикселей — кэш слотов не сбрасывается.
            if (_grid is null || !grid.SameAs(_grid)) _grid = grid;
            grid = _grid;
        }

        Mode = DetectionMode.Automatic;
        LastAutoResolution = $"{w}×{h}";
        LastAnalysis = _analyzer.AnalyzeGrid(top, topRegion, grid);

        if (_text is { Available: true } && (_lastText is null || _tick % TextEveryTicks == 0))
            _lastText = ReadText(window, top, grid, w, h);

        MaybeSaveDebugFrame(window, w, h, now);

        var t = _lastText;
        return LastAnalysis.Observation with
        {
            Roles = t?.Roles,
            AllySide = t?.AllySide,
            OwnSlotIndex = t?.OwnSlotIndex,
            BannedHeroes = t?.BannedHeroes,
        };
    }

    private DraftTextInfo? ReadText(GameWindowInfo window, Mat top, PlayerBarGrid grid, int w, int h)
    {
        Mat? chat = null;
        try
        {
            var chatRect = DraftTextReader.ChatRect(w, h);
            var chatFrame = _capture.Capture(window, chatRect);
            if (chatFrame is not null) chat = CvImage.ToBgrMat(chatFrame);
            return _text!.Read(top, grid, chat, _playerName());
        }
        finally
        {
            chat?.Dispose();
        }
    }

    /// <summary>
    /// Сохраняет пару полных кадров драфта локально (%APPDATA%\DotaDraftAssistant\debug), чтобы при
    /// проблемах с распознаванием было что приложить к сообщению об ошибке. Никуда не отправляется.
    /// </summary>
    private void MaybeSaveDebugFrame(GameWindowInfo window, int w, int h, DateTimeOffset now)
    {
        if (_debugDir is null || !_saveDebugFrames() || _debugSavedThisDraft >= 2) return;
        bool due = _debugSavedThisDraft == 0
            ? now - _draftSeenAt > TimeSpan.FromSeconds(2)
            : now - _draftSeenAt > TimeSpan.FromSeconds(45);
        if (!due) return;

        try
        {
            var frame = _capture.Capture(window, new PixelRect(0, 0, w, h));
            if (frame is null) return;
            Directory.CreateDirectory(_debugDir);
            using var mat = CvImage.ToBgrMat(frame);
            Cv2.ImWrite(Path.Combine(_debugDir, $"draft_{DateTime.Now:yyyyMMdd_HHmmss}.png"), mat);
            _debugSavedThisDraft++;

            foreach (var old in new DirectoryInfo(_debugDir).GetFiles("draft_*.png")
                         .OrderByDescending(f => f.CreationTimeUtc).Skip(MaxDebugFrames))
                old.Delete();
        }
        catch (Exception)
        {
            // Отладочные кадры не должны мешать работе.
        }
    }
}
