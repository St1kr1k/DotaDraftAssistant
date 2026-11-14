using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Infrastructure.Recognition;
using OpenCvSharp;

namespace DraftAssistant.Tests;

/// <summary>
/// Синтетическая проверка распознавателя: "портреты" из случайных цветных эллипсов,
/// слот = уменьшенный, сдвинутый, затемнённый, зашумлённый и пережатый в JPEG портрет.
/// Реальная точность проверяется DataTool check-layout на скриншотах игры.
/// </summary>
public sealed class RecognitionTests : IDisposable
{
    private const int HeroCount = 40;
    private readonly Dictionary<int, Mat> _portraits = new();
    private readonly HeroTemplateLibrary _library;
    private readonly RecognitionOptions _options = new();
    private readonly CompositeHeroRecognizer _recognizer;

    public RecognitionTests()
    {
        for (int i = 1; i <= HeroCount; i++) _portraits[i] = Portrait(i);
        _library = HeroTemplateLibrary.FromImages(_portraits);
        _recognizer = new CompositeHeroRecognizer(
            new TemplateHeroRecognizer(_library, () => _options),
            new ColorHistogramHeroRecognizer(_library, () => _options),
            () => _options);
    }

    private static Mat Portrait(int seed)
    {
        var rnd = new Random(seed);
        var img = new Mat(144, 256, MatType.CV_8UC3, new Scalar(rnd.Next(256), rnd.Next(256), rnd.Next(256)));
        for (int k = 0; k < 14; k++)
        {
            Cv2.Ellipse(img,
                new Point(rnd.Next(256), rnd.Next(144)), new Size(rnd.Next(8, 70), rnd.Next(8, 50)),
                rnd.Next(180), 0, 360, new Scalar(rnd.Next(256), rnd.Next(256), rnd.Next(256)), -1);
        }
        Cv2.GaussianBlur(img, img, new Size(0, 0), 3);
        return img;
    }

    private static Mat Degrade(Mat portrait, int width, double shift, bool grayscale, int seed)
    {
        var rnd = new Random(seed);
        int dx = (int)((rnd.NextDouble() * 2 - 1) * shift * portrait.Width);
        int dy = (int)((rnd.NextDouble() * 2 - 1) * shift * portrait.Height);
        using var m = new Mat(2, 3, MatType.CV_32FC1);
        m.Set(0, 0, 1f); m.Set(0, 1, 0f); m.Set(0, 2, (float)dx);
        m.Set(1, 0, 0f); m.Set(1, 1, 1f); m.Set(1, 2, (float)dy);
        using var shifted = new Mat();
        Cv2.WarpAffine(portrait, shifted, m, portrait.Size(), borderMode: BorderTypes.Replicate);

        using var small = new Mat();
        Cv2.Resize(shifted, small, new Size(width, (int)Math.Round(width * 9 / 16.0)), 0, 0, InterpolationFlags.Area);
        using var dark = new Mat();
        small.ConvertTo(dark, MatType.CV_8UC3, 0.8, 10);

        using var noise = new Mat(dark.Size(), MatType.CV_16SC3);
        Cv2.Randn(noise, new Scalar(0, 0, 0), new Scalar(6, 6, 6));
        using var noisy16 = new Mat();
        dark.ConvertTo(noisy16, MatType.CV_16SC3);
        Cv2.Add(noisy16, noise, noisy16);
        var noisy = new Mat();
        noisy16.ConvertTo(noisy, MatType.CV_8UC3);

        if (grayscale)
        {
            using var g = new Mat();
            Cv2.CvtColor(noisy, g, ColorConversionCodes.BGR2GRAY);
            Cv2.CvtColor(g, noisy, ColorConversionCodes.GRAY2BGR);
        }

        Cv2.ImEncode(".jpg", noisy, out var jpg, new ImageEncodingParam(ImwriteFlags.JpegQuality, 80));
        noisy.Dispose();
        return Cv2.ImDecode(jpg, ImreadModes.Color);
    }

    [Theory]
    [InlineData(88, 0.04, false)]
    [InlineData(60, 0.06, false)]
    public void Recognizes_degraded_pick_slots(int width, double shift, bool gray)
    {
        int correct = 0;
        foreach (var (id, portrait) in _portraits)
        {
            using var slot = Degrade(portrait, width, shift, gray, id);
            var r = _recognizer.Recognize(slot, SlotKind.Pick);
            Assert.True(r.HeroId is null || r.HeroId == id, $"Ложное распознавание: слот {id} → {r.HeroId}");
            if (r.HeroId == id && r.Confidence >= 0.6) correct++;
        }
        Assert.True(correct >= HeroCount * 0.95, $"Распознано {correct}/{HeroCount}");
    }

    [Fact]
    public void Recognizes_grayscale_ban_slots_without_histogram()
    {
        int correct = _portraits.Count(kv =>
        {
            using var slot = Degrade(kv.Value, 60, 0.04, grayscale: true, kv.Key);
            var r = _recognizer.Recognize(slot, SlotKind.Ban);
            return r.HeroId == kv.Key && r.Confidence >= 0.6;
        });
        Assert.True(correct >= HeroCount * 0.95, $"Распознано {correct}/{HeroCount}");
    }

    [Fact]
    public void Unknown_image_is_not_reported_as_a_hero()
    {
        int accepted = 0;
        for (int k = 0; k < 30; k++)
        {
            using var stranger = Portrait(10_000 + k);
            using var slot = Degrade(stranger, 88, 0.04, false, k);
            var r = _recognizer.Recognize(slot, SlotKind.Pick);
            if (r.HeroId is not null && r.Confidence >= 0.6) accepted++;
        }
        Assert.True(accepted <= 1, $"Чужих изображений принято за героя: {accepted}/30");
    }

    [Fact]
    public void Flat_slot_is_empty()
    {
        using var flat = new Mat(50, 88, MatType.CV_8UC3, new Scalar(30, 32, 35));
        Assert.True(new SlotEmptinessClassifier(() => _options).IsEmpty(flat, null, out _));
    }

    public void Dispose()
    {
        _library.Dispose();
        foreach (var p in _portraits.Values) p.Dispose();
    }
}
