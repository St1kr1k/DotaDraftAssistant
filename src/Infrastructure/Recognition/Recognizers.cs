using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Infrastructure.Vision;
using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Recognition;

public sealed record HeroCandidate(int HeroId, double Score);

/// <summary>
/// Результат распознавания одного слота. HeroId = null означает "не уверен":
/// приложение покажет Unknown (xx%), а не угаданного героя.
/// </summary>
public sealed record RecognitionResult(string Method, IReadOnlyList<HeroCandidate> Candidates, int? HeroId, double Confidence)
{
    public HeroCandidate? Best => Candidates.Count > 0 ? Candidates[0] : null;
}

public interface IHeroRecognizer
{
    string Name { get; }
    RecognitionResult Recognize(Mat slotBgr, SlotKind kind);
}

/// <summary>
/// Уверенность = среднее двух составляющих:
///  * абсолютная: насколько лучший score выше MinScore;
///  * относительная: насколько лучший кандидат оторвался от второго.
/// Два похожих кандидата → низкая уверенность → Unknown, даже если score высокий.
/// </summary>
public static class ConfidenceModel
{
    public static (int? HeroId, double Confidence) Evaluate(IReadOnlyList<HeroCandidate> sorted, RecognitionOptions o)
    {
        if (sorted.Count == 0) return (null, 0);
        double best = sorted[0].Score;
        double second = sorted.Count > 1 ? sorted[1].Score : 0;
        double absolute = Math.Clamp((best - o.MinScore) / Math.Max(1e-6, o.StrongScore - o.MinScore), 0, 1);
        double margin = Math.Clamp((best - second) / Math.Max(1e-6, o.GoodMargin), 0, 1);
        double confidence = 0.5 * absolute + 0.5 * margin;
        return best < o.MinScore ? (null, confidence) : (sorted[0].HeroId, confidence);
    }

    public static IReadOnlyList<HeroCandidate> Sort(IReadOnlyDictionary<int, double> scores) =>
        scores.Select(kv => new HeroCandidate(kv.Key, kv.Value)).OrderByDescending(c => c.Score).ToList();
}

internal static class SlotWork
{
    public static Size WorkSize(Mat slot, RecognitionOptions o)
    {
        double aspect = (double)slot.Width / Math.Max(1, slot.Height);
        int w = o.WorkWidth;
        int h = Math.Max(8, (int)Math.Round(w / aspect));
        return new Size(w, h);
    }
}

/// <summary>
/// Template matching: центральная часть слота ищется внутри каждого шаблона
/// (нормированная корреляция, TM_CCOEFF_NORMED). Устойчив к яркости/контрасту
/// и к небольшому сдвигу калибровки. Работает в оттенках серого — поэтому подходит и для
/// обесцвеченных портретов в слотах банов.
/// </summary>
public sealed class TemplateHeroRecognizer(HeroTemplateLibrary library, Func<RecognitionOptions> options) : IHeroRecognizer
{
    public string Name => "template";

    public IReadOnlyDictionary<int, double> ScoreAll(Mat slotBgr)
    {
        var o = options();
        var size = SlotWork.WorkSize(slotBgr, o);
        var templates = library.Prepare(size, o.InnerMargin);
        using var resized = CvImage.Resize(slotBgr, size);
        using var gray = CvImage.ToGray(resized);
        using var query = CvImage.InnerCrop(gray, o.InnerMargin);

        var scores = new Dictionary<int, double>();
        foreach (var t in templates)
        {
            double s = Math.Max(0, CvImage.BestCorrelation(t.Gray, query));
            if (!scores.TryGetValue(t.HeroId, out var prev) || s > prev) scores[t.HeroId] = s;
        }
        return scores;
    }

    public RecognitionResult Recognize(Mat slotBgr, SlotKind kind)
    {
        var sorted = ConfidenceModel.Sort(ScoreAll(slotBgr));
        var (id, conf) = ConfidenceModel.Evaluate(sorted, options());
        return new RecognitionResult(Name, sorted, id, conf);
    }
}

/// <summary>
/// Image similarity по цвету: корреляция Hue/Saturation-гистограмм.
/// Не зависит от точного положения и хорошо отличает героев с похожим силуэтом, но разной палитрой.
/// Для банов (портрет обесцвечен) не применяется.
/// </summary>
public sealed class ColorHistogramHeroRecognizer(HeroTemplateLibrary library, Func<RecognitionOptions> options) : IHeroRecognizer
{
    public string Name => "histogram";

    public IReadOnlyDictionary<int, double> ScoreAll(Mat slotBgr)
    {
        var o = options();
        var size = SlotWork.WorkSize(slotBgr, o);
        var templates = library.Prepare(size, o.InnerMargin);
        using var resized = CvImage.Resize(slotBgr, size);
        using var inner = CvImage.InnerCrop(resized, o.InnerMargin);
        using var hist = CvImage.HueSatHistogram(inner);

        var scores = new Dictionary<int, double>();
        foreach (var t in templates)
        {
            double s = Math.Max(0, Cv2.CompareHist(hist, t.InnerHistogram, HistCompMethods.Correl));
            if (double.IsNaN(s)) s = 0;
            if (!scores.TryGetValue(t.HeroId, out var prev) || s > prev) scores[t.HeroId] = s;
        }
        return scores;
    }

    public RecognitionResult Recognize(Mat slotBgr, SlotKind kind)
    {
        var sorted = ConfidenceModel.Sort(ScoreAll(slotBgr));
        var (id, conf) = ConfidenceModel.Evaluate(sorted, options());
        return new RecognitionResult(Name, sorted, id, conf);
    }
}

/// <summary>
/// Объединяет несколько методов: взвешенное среднее score каждого героя, затем общая модель уверенности.
/// Новые методы (OCR через Windows.Media.Ocr, feature matching, лёгкая CNN) добавляются сюда же.
/// </summary>
public sealed class CompositeHeroRecognizer(
    TemplateHeroRecognizer template,
    ColorHistogramHeroRecognizer histogram,
    Func<RecognitionOptions> options) : IHeroRecognizer
{
    public string Name => "composite";

    public RecognitionResult Recognize(Mat slotBgr, SlotKind kind)
    {
        var o = options();
        var parts = new List<(IReadOnlyDictionary<int, double> Scores, double Weight)>
        {
            (template.ScoreAll(slotBgr), o.TemplateWeight),
        };
        if (kind == SlotKind.Pick && o.HistogramWeight > 0)
            parts.Add((histogram.ScoreAll(slotBgr), o.HistogramWeight));

        double totalWeight = parts.Sum(p => p.Weight);
        var fused = new Dictionary<int, double>();
        foreach (var (scores, weight) in parts)
            foreach (var (hero, s) in scores)
                fused[hero] = fused.GetValueOrDefault(hero) + s * weight / totalWeight;

        var sorted = ConfidenceModel.Sort(fused);
        var (id, conf) = ConfidenceModel.Evaluate(sorted, o);
        return new RecognitionResult(Name, sorted, id, conf);
    }
}

/// <summary>Пустой слот: плоское изображение или совпадение с сохранённым эталоном пустого слота.</summary>
public sealed class SlotEmptinessClassifier(Func<RecognitionOptions> options)
{
    public bool IsEmpty(Mat slotBgr, Mat? emptyReference, out double score)
    {
        var o = options();
        var size = SlotWork.WorkSize(slotBgr, o);
        using var resized = CvImage.Resize(slotBgr, size);
        using var gray = CvImage.ToGray(resized);

        double std = CvImage.StdDev(gray);
        if (std < o.EmptySlotMaxStdDev)
        {
            score = 1;
            return true;
        }

        if (emptyReference is null || emptyReference.Empty())
        {
            score = 0;
            return false;
        }

        using var refResized = CvImage.Resize(emptyReference, size);
        using var refGray = CvImage.ToGray(refResized);
        using var query = CvImage.InnerCrop(gray, o.InnerMargin);
        score = Math.Max(0, CvImage.BestCorrelation(refGray, query));
        return score >= o.EmptySlotThreshold;
    }
}

/// <summary>Узнаёт экран драфта по статичному фрагменту интерфейса, сохранённому при калибровке.</summary>
public static class DraftSignatureMatcher
{
    public static double Score(Mat currentRegionBgr, Mat referenceBgr)
    {
        if (referenceBgr.Empty() || currentRegionBgr.Empty()) return 0;
        using var resized = CvImage.Resize(currentRegionBgr, new Size(referenceBgr.Width, referenceBgr.Height));
        using var a = CvImage.ToGray(resized);
        using var b = CvImage.ToGray(referenceBgr);
        return Math.Max(0, CvImage.BestCorrelation(b, a));
    }
}
