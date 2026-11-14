using DraftAssistant.Infrastructure.Vision;
using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Recognition;

/// <summary>Шаблон, подготовленный под конкретный рабочий размер слота.</summary>
public sealed class PreparedTemplate(int heroId, Mat gray, Mat innerHistogram)
{
    public int HeroId { get; } = heroId;
    /// <summary>Полный шаблон в оттенках серого, размер = рабочий размер слота.</summary>
    public Mat Gray { get; } = gray;
    /// <summary>Hue/Sat-гистограмма центральной части шаблона.</summary>
    public Mat InnerHistogram { get; } = innerHistogram;
}

/// <summary>
/// Эталонные изображения героев: data/heroes/{id}/portrait.png + любые PNG в data/heroes/{id}/templates/.
/// Исходники хранятся в исходном разрешении; под размер слота они готовятся лениво и кэшируются,
/// поэтому распознавание не привязано ни к разрешению экрана, ни к разрешению эталонов.
/// В templates/ можно класть реальные вырезки слотов со своего экрана — это заметно повышает точность.
/// </summary>
public sealed class HeroTemplateLibrary : IDisposable
{
    private readonly Dictionary<int, List<Mat>> _sources;
    /// <summary>Индексы шаблонов, которые являются портретами героя (к ним применяется увеличение).</summary>
    private readonly HashSet<Mat> _portraits = new(ReferenceEqualityComparer.Instance);
    private readonly double _portraitZoom;
    private readonly Dictionary<(int W, int H, int MarginPermille), IReadOnlyList<PreparedTemplate>> _prepared = new();
    private readonly object _gate = new();

    private HeroTemplateLibrary(Dictionary<int, List<Mat>> sources, double portraitZoom = 1.0)
    {
        _sources = sources;
        _portraitZoom = Math.Max(1.0, portraitZoom);
    }

    public int HeroCount => _sources.Count;
    public IEnumerable<int> HeroIds => _sources.Keys;

    /// <param name="portraitZoom">
    /// Во сколько раз Dota увеличивает арт героя в слоте верхней панели драфта (≈1.2):
    /// портрет из данных обрезается по центру с этим увеличением. К вашим доп. шаблонам не применяется.
    /// </param>
    public static HeroTemplateLibrary LoadFromDirectory(string heroesDirectory, IEnumerable<int> heroIds, double portraitZoom = 1.0)
    {
        var sources = new Dictionary<int, List<Mat>>();
        var portraits = new List<Mat>();
        foreach (var id in heroIds)
        {
            var dir = Path.Combine(heroesDirectory, id.ToString());
            if (!Directory.Exists(dir)) continue;

            var files = new List<string>();
            var portrait = Path.Combine(dir, "portrait.png");
            if (File.Exists(portrait)) files.Add(portrait);
            var extra = Path.Combine(dir, "templates");
            if (Directory.Exists(extra)) files.AddRange(Directory.GetFiles(extra, "*.png"));

            var mats = new List<Mat>();
            foreach (var f in files)
            {
                var m = Cv2.ImRead(f, ImreadModes.Color);
                if (m.Empty()) { m.Dispose(); continue; }
                mats.Add(m);
                if (f == portrait) portraits.Add(m);
            }
            if (mats.Count > 0) sources[id] = mats;
        }
        var lib = new HeroTemplateLibrary(sources, portraitZoom);
        foreach (var p in portraits) lib._portraits.Add(p);
        return lib;
    }

    /// <summary>Для тестов и инструментов: библиотека из готовых изображений (BGR).</summary>
    public static HeroTemplateLibrary FromImages(IReadOnlyDictionary<int, Mat> images) =>
        new(images.ToDictionary(kv => kv.Key, kv => new List<Mat> { kv.Value.Clone() }));

    public IReadOnlyList<PreparedTemplate> Prepare(Size workSize, double innerMargin)
    {
        var key = (workSize.Width, workSize.Height, (int)Math.Round(innerMargin * 1000));
        lock (_gate)
        {
            if (_prepared.TryGetValue(key, out var cached)) return cached;

            double aspect = (double)workSize.Width / workSize.Height;
            var list = new List<PreparedTemplate>();
            foreach (var (heroId, mats) in _sources)
            {
                foreach (var src in mats)
                {
                    // Если слот шире портрета, неизвестно, какую полосу арта показывает Dota, —
                    // готовим несколько вертикальных вариантов; совпадение берётся по лучшему.
                    bool zoomed = _portraitZoom > 1.0 && _portraits.Contains(src);
                    bool widerThanSource = aspect > (double)src.Width / src.Height + 0.05;
                    double[] anchors = zoomed ? [0.3] : widerThanSource ? [0.15, 0.35, 0.5] : [0.5];
                    foreach (var anchor in anchors)
                    {
                        using var cropped = zoomed ? ZoomCrop(src, aspect, _portraitZoom, anchor) : CvImage.CropToAspect(src, aspect, anchor);
                        using var resized = CvImage.Resize(cropped, workSize);
                        using var inner = CvImage.InnerCrop(resized, innerMargin);
                        list.Add(new PreparedTemplate(heroId, CvImage.ToGray(resized), CvImage.HueSatHistogram(inner)));
                    }
                }
            }
            _prepared[key] = list;
            return list;
        }
    }

    /// <summary>Центральная часть портрета, увеличенная в <paramref name="zoom"/> раз, с нужными пропорциями.</summary>
    private static Mat ZoomCrop(Mat src, double aspect, double zoom, double verticalAnchor)
    {
        double cw = src.Width / zoom, ch = cw / aspect;
        if (ch > src.Height) { ch = src.Height; cw = ch * aspect; }
        int w = Math.Max(1, (int)Math.Round(cw)), h = Math.Max(1, (int)Math.Round(ch));
        int x = (src.Width - w) / 2;
        int y = (int)Math.Round((src.Height - h) * Math.Clamp(verticalAnchor, 0, 1));
        using var view = new Mat(src, new Rect(x, y, w, h));
        return view.Clone();
    }

    public void Dispose()
    {
        lock (_gate)
        {
            foreach (var l in _prepared.Values)
                foreach (var t in l) { t.Gray.Dispose(); t.InnerHistogram.Dispose(); }
            foreach (var l in _sources.Values)
                foreach (var m in l) m.Dispose();
            _prepared.Clear();
        }
    }
}
