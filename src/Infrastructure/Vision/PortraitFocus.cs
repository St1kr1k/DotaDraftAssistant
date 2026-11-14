using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>
/// Где на портрете героя «главное»: ищется горизонтальное окно с наибольшим количеством деталей
/// (контуров). Фон на портретах размыт, а лицо, броня и оружие — нет, поэтому окно с максимумом
/// контуров почти всегда попадает на героя, а не на фон или плечо. Слабая тяга к центру
/// не даёт уехать в край на однородных картинках.
/// </summary>
public static class PortraitFocus
{
    /// <summary>Центр окна по горизонтали в долях ширины (0..1) для кропа с соотношением сторон <paramref name="aspect"/>.</summary>
    public static double FindCenterX(string imagePath, double aspect)
    {
        using var img = Cv2.ImRead(imagePath, ImreadModes.Grayscale);
        if (img.Empty()) return 0.5;

        int w = img.Width, h = img.Height;
        int window = Math.Min(w, (int)Math.Round(h * aspect));
        if (window >= w) return 0.5;

        using var gx = new Mat();
        using var gy = new Mat();
        Cv2.Sobel(img, gx, MatType.CV_32F, 1, 0);
        Cv2.Sobel(img, gy, MatType.CV_32F, 0, 1);
        using var mag = new Mat();
        Cv2.Magnitude(gx, gy, mag);

        // Верхние 2/3 картинки важнее: там лицо.
        var columns = new double[w];
        for (int y = 0; y < h; y++)
        {
            double rowWeight = y < h * 0.66 ? 1.0 : 0.5;
            for (int x = 0; x < w; x++) columns[x] += mag.At<float>(y, x) * rowWeight;
        }

        double total = columns.Sum();
        if (total <= 0) return 0.5;

        double best = double.MinValue;
        int bestStart = (w - window) / 2;
        double sum = 0;
        for (int x = 0; x < window; x++) sum += columns[x];
        for (int start = 0; start + window <= w; start++)
        {
            if (start > 0) sum += columns[start + window - 1] - columns[start - 1];
            double center = (start + window / 2.0) / w;
            double prior = 1 - 0.35 * Math.Abs(center - 0.5);
            double score = sum / total * prior;
            if (score > best) { best = score; bestStart = start; }
        }
        return (bestStart + window / 2.0) / w;
    }
}
