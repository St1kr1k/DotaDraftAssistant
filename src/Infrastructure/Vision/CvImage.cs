using System.Runtime.InteropServices;
using DraftAssistant.Infrastructure.Capture;
using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>Мост между кадром захвата и OpenCV. Единственное место, где они встречаются.</summary>
public static class CvImage
{
    /// <summary>BGRA ImageFrame → BGR Mat (копия).</summary>
    public static Mat ToBgrMat(ImageFrame frame)
    {
        using var bgra = new Mat(frame.Height, frame.Width, MatType.CV_8UC4);
        int rowBytes = frame.Width * 4;
        for (int y = 0; y < frame.Height; y++)
            Marshal.Copy(frame.Bgra, y * frame.Stride, bgra.Ptr(y), rowBytes);
        var bgr = new Mat();
        Cv2.CvtColor(bgra, bgr, ColorConversionCodes.BGRA2BGR);
        return bgr;
    }

    /// <summary>Безопасный ROI: обрезает прямоугольник по границам изображения. Возвращает копию.</summary>
    public static Mat? Crop(Mat image, PixelRect rect)
    {
        var r = rect.Intersect(new PixelRect(0, 0, image.Width, image.Height));
        if (r.IsEmpty || r.Width < 4 || r.Height < 4) return null;
        using var view = new Mat(image, new Rect(r.X, r.Y, r.Width, r.Height));
        return view.Clone();
    }

    /// <summary>Центральная часть изображения без margin с каждой стороны.</summary>
    public static Mat InnerCrop(Mat image, double margin)
    {
        int mx = (int)Math.Round(image.Width * margin), my = (int)Math.Round(image.Height * margin);
        int w = Math.Max(1, image.Width - 2 * mx), h = Math.Max(1, image.Height - 2 * my);
        using var view = new Mat(image, new Rect(mx, my, w, h));
        return view.Clone();
    }

    /// <summary>Центральный кроп под заданные пропорции (для портретов другого aspect ratio).</summary>
    public static Mat CenterCropToAspect(Mat image, double aspect)
    {
        double current = (double)image.Width / image.Height;
        Rect r;
        if (current > aspect)
        {
            int w = (int)Math.Round(image.Height * aspect);
            r = new Rect((image.Width - w) / 2, 0, w, image.Height);
        }
        else
        {
            int h = (int)Math.Round(image.Width / aspect);
            r = new Rect(0, (image.Height - h) / 2, image.Width, h);
        }
        using var view = new Mat(image, r);
        return view.Clone();
    }

    public static Mat Resize(Mat image, Size size)
    {
        var dst = new Mat();
        var interpolation = size.Width < image.Width ? InterpolationFlags.Area : InterpolationFlags.Linear;
        Cv2.Resize(image, dst, size, 0, 0, interpolation);
        return dst;
    }

    public static Mat ToGray(Mat bgr)
    {
        var g = new Mat();
        Cv2.CvtColor(bgr, g, ColorConversionCodes.BGR2GRAY);
        return g;
    }

    /// <summary>Нормированная корреляция: ищет query (меньше) внутри reference (больше). Возвращает max ∈ [-1; 1].</summary>
    public static double BestCorrelation(Mat reference, Mat query)
    {
        if (query.Width > reference.Width || query.Height > reference.Height) return -1;
        using var result = new Mat();
        Cv2.MatchTemplate(reference, query, result, TemplateMatchModes.CCoeffNormed);
        Cv2.MinMaxLoc(result, out _, out double max, out _, out _);
        return double.IsNaN(max) ? -1 : max;
    }

    /// <summary>Нормализованная 2D-гистограмма Hue/Saturation.</summary>
    public static Mat HueSatHistogram(Mat bgr)
    {
        using var hsv = new Mat();
        Cv2.CvtColor(bgr, hsv, ColorConversionCodes.BGR2HSV);
        var hist = new Mat();
        Cv2.CalcHist(new[] { hsv }, new[] { 0, 1 }, null, hist, 2, new[] { 18, 8 },
            new[] { new Rangef(0, 180), new Rangef(0, 256) });
        Cv2.Normalize(hist, hist, 1, 0, NormTypes.L1);
        return hist;
    }

    public static double StdDev(Mat gray)
    {
        Cv2.MeanStdDev(gray, out _, out var std);
        return std.Val0;
    }
}
