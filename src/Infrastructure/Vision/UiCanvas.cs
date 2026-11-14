using DraftAssistant.Infrastructure.Capture;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>Прямоугольник в нормализованных координатах UI-холста (0..1).</summary>
public sealed record NormalizedRect(double X, double Y, double Width, double Height);

public enum CanvasAnchor
{
    /// <summary>Холст 16:9 центрирован по горизонтали и прижат к верху (элементы верхней панели).</summary>
    TopCenter,
    /// <summary>Холст 16:9 центрирован по обеим осям.</summary>
    Center,
}

/// <summary>
/// Пересчёт нормализованных ROI в пиксели для любого разрешения и aspect ratio.
///
/// Интерфейс Dota масштабируется относительно "безопасной" области 16:9:
///  * 16:9 (1920x1080, 2560x1440, 3840x2160) — холст = всё окно;
///  * 21:9 (3440x1440) — холст 2560x1440 по центру, по бокам поля;
///  * 16:10 (1920x1200) — холст 1920x1080, прижатый к якорю.
/// ROI хранятся в долях холста, поэтому не зависят от разрешения.
/// Предположение о поведении UI на нестандартных aspect ratio нужно подтверждать
/// калибровкой — разметка всегда сохраняется относительно холста конкретного окна.
/// </summary>
public static class UiCanvas
{
    public const double ReferenceAspect = 16.0 / 9.0;

    public static PixelRect Compute(int clientWidth, int clientHeight, CanvasAnchor anchor = CanvasAnchor.TopCenter)
    {
        if (clientWidth <= 0 || clientHeight <= 0) return default;
        double aspect = (double)clientWidth / clientHeight;
        if (aspect >= ReferenceAspect)
        {
            int w = (int)Math.Round(clientHeight * ReferenceAspect);
            return new PixelRect((clientWidth - w) / 2, 0, w, clientHeight);
        }
        else
        {
            int h = (int)Math.Round(clientWidth / ReferenceAspect);
            int y = anchor == CanvasAnchor.Center ? (clientHeight - h) / 2 : 0;
            return new PixelRect(0, y, clientWidth, h);
        }
    }

    public static PixelRect ToPixels(NormalizedRect r, PixelRect canvas) => new(
        canvas.X + (int)Math.Round(r.X * canvas.Width),
        canvas.Y + (int)Math.Round(r.Y * canvas.Height),
        Math.Max(1, (int)Math.Round(r.Width * canvas.Width)),
        Math.Max(1, (int)Math.Round(r.Height * canvas.Height)));

    public static NormalizedRect ToNormalized(PixelRect r, PixelRect canvas) => new(
        (r.X - canvas.X) / (double)canvas.Width,
        (r.Y - canvas.Y) / (double)canvas.Height,
        r.Width / (double)canvas.Width,
        r.Height / (double)canvas.Height);
}
