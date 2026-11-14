using System.Diagnostics;
using System.Runtime.InteropServices;

namespace DraftAssistant.Infrastructure.Capture;

/// <summary>
/// Захват через GDI BitBlt с экранного DC.
///
/// Почему так в MVP:
///  * Dota 2 в Borderless Fullscreen композитится DWM, поэтому изображение доступно обычным BitBlt;
///  * захватывается только маленький регион (полоса слотов драфта), а не весь экран — это дёшево;
///  * никакого доступа к процессу Dota, только чтение пикселей экрана.
///
/// Ограничения: окно, перекрывающее Dota, попадёт в кадр (наш overlay исключается через
/// SetWindowDisplayAffinity), а в exclusive fullscreen BitBlt может вернуть чёрный кадр.
/// Альтернатива — Windows.Graphics.Capture (захват конкретного окна даже под перекрытием),
/// подключается как ещё одна реализация IScreenCaptureService без изменения остальных слоёв.
/// </summary>
public sealed class GdiScreenCaptureService : IScreenCaptureService
{
    private static readonly string[] ProcessNames = ["dota2"];
    private nint _cachedHandle;

    public GameWindowInfo? FindGameWindow()
    {
        if (_cachedHandle != 0 && Win32.IsWindow(_cachedHandle) && Win32.IsWindowVisible(_cachedHandle))
            return Describe(_cachedHandle);

        _cachedHandle = Locate();
        return _cachedHandle == 0 ? null : Describe(_cachedHandle);
    }

    private static nint Locate()
    {
        var pids = new HashSet<uint>();
        foreach (var name in ProcessNames)
        {
            foreach (var p in Process.GetProcessesByName(name))
            {
                pids.Add((uint)p.Id);
                p.Dispose();
            }
        }
        if (pids.Count == 0) return 0;

        nint best = 0;
        long bestArea = 0;
        Win32.EnumWindows((hWnd, _) =>
        {
            if (!Win32.IsWindowVisible(hWnd)) return true;
            Win32.GetWindowThreadProcessId(hWnd, out var pid);
            if (!pids.Contains(pid)) return true;
            if (!Win32.GetClientRect(hWnd, out var r)) return true;
            long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
            if (area > bestArea) { bestArea = area; best = hWnd; }
            return true;
        }, 0);
        return best;
    }

    private static GameWindowInfo? Describe(nint hWnd)
    {
        if (!Win32.GetClientRect(hWnd, out var r)) return null;
        var origin = new Win32.POINT { X = 0, Y = 0 };
        if (!Win32.ClientToScreen(hWnd, ref origin)) return null;
        var rect = new PixelRect(origin.X, origin.Y, r.Right - r.Left, r.Bottom - r.Top);
        return new GameWindowInfo(hWnd, rect, Win32.IsIconic(hWnd) || rect.IsEmpty);
    }

    public ImageFrame? Capture(GameWindowInfo window, PixelRect regionInClient)
    {
        if (window.IsMinimized) return null;
        var client = new PixelRect(0, 0, window.ClientRect.Width, window.ClientRect.Height);
        var region = regionInClient.Intersect(client);
        if (region.IsEmpty) return null;

        int w = region.Width, h = region.Height;
        int sx = window.ClientRect.X + region.X, sy = window.ClientRect.Y + region.Y;

        nint screenDc = Win32.GetDC(0);
        nint memDc = 0, bitmap = 0, old = 0;
        try
        {
            memDc = Win32.CreateCompatibleDC(screenDc);
            var bmi = new Win32.BITMAPINFO
            {
                bmiHeader = new Win32.BITMAPINFOHEADER
                {
                    biSize = (uint)Marshal.SizeOf<Win32.BITMAPINFOHEADER>(),
                    biWidth = w,
                    biHeight = -h, // top-down
                    biPlanes = 1,
                    biBitCount = 32,
                    biCompression = 0, // BI_RGB
                },
            };
            bitmap = Win32.CreateDIBSection(screenDc, ref bmi, Win32.DIB_RGB_COLORS, out var bits, 0, 0);
            if (bitmap == 0 || bits == 0) return null;
            old = Win32.SelectObject(memDc, bitmap);

            if (!Win32.BitBlt(memDc, 0, 0, w, h, screenDc, sx, sy, Win32.SRCCOPY | Win32.CAPTUREBLT))
                return null;

            int stride = w * 4;
            var buffer = new byte[stride * h];
            Marshal.Copy(bits, buffer, 0, buffer.Length);
            return new ImageFrame(w, h, stride, buffer);
        }
        finally
        {
            if (old != 0) Win32.SelectObject(memDc, old);
            if (bitmap != 0) Win32.DeleteObject(bitmap);
            if (memDc != 0) Win32.DeleteDC(memDc);
            Win32.ReleaseDC(0, screenDc);
        }
    }
}
