namespace DraftAssistant.Infrastructure.Capture;

public readonly record struct PixelRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
    public bool IsEmpty => Width <= 0 || Height <= 0;

    public PixelRect Intersect(PixelRect o)
    {
        int x = Math.Max(X, o.X), y = Math.Max(Y, o.Y);
        int r = Math.Min(Right, o.Right), b = Math.Min(Bottom, o.Bottom);
        return r > x && b > y ? new PixelRect(x, y, r - x, b - y) : default;
    }

    public PixelRect Union(PixelRect o)
    {
        if (IsEmpty) return o;
        if (o.IsEmpty) return this;
        int x = Math.Min(X, o.X), y = Math.Min(Y, o.Y);
        return new PixelRect(x, y, Math.Max(Right, o.Right) - x, Math.Max(Bottom, o.Bottom) - y);
    }

    public PixelRect Offset(int dx, int dy) => this with { X = X + dx, Y = Y + dy };
}

/// <summary>Кадр в формате BGRA, 8 бит на канал. Альфа-канал не используется.</summary>
public sealed class ImageFrame(int width, int height, int stride, byte[] bgra)
{
    public int Width { get; } = width;
    public int Height { get; } = height;
    public int Stride { get; } = stride;
    public byte[] Bgra { get; } = bgra;
}

/// <summary>Найденное окно игры. ClientRect — клиентская область в физических пикселях экрана.</summary>
public sealed record GameWindowInfo(nint Handle, PixelRect ClientRect, bool IsMinimized);

public interface IScreenCaptureService
{
    /// <summary>Найти окно Dota 2. null — игра не запущена.</summary>
    GameWindowInfo? FindGameWindow();

    /// <summary>
    /// Захватить часть клиентской области окна. Захватывается только нужный регион (ROI),
    /// а не весь экран — это основной способ не нагружать систему.
    /// </summary>
    ImageFrame? Capture(GameWindowInfo window, PixelRect regionInClient);
}
