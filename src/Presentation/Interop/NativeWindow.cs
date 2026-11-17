using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace DraftAssistant.Presentation.Interop;

/// <summary>Стили окна overlay. Только собственные окна приложения — с окном Dota ничего не делается.</summary>
public static class NativeWindow
{
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_LAYERED = 0x00080000;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const uint WDA_EXCLUDEFROMCAPTURE = 0x00000011;

    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOACTIVATE = 0x0010;

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLongPtr(nint hWnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern nint SetWindowLongPtr(nint hWnd, int index, nint value);
    [DllImport("user32.dll")] private static extern bool SetWindowDisplayAffinity(nint hWnd, uint affinity);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(nint hWnd, nint after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint hWnd, out ScreenRect rect);

    /// <summary>Прямоугольник окна в физических пикселях экрана.</summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct ScreenRect
    {
        public int Left, Top, Right, Bottom;
        public readonly int Width => Right - Left;
        public readonly int Height => Bottom - Top;
    }

    public static ScreenRect GetRect(Window w) => GetWindowRect(Handle(w), out var r) ? r : default;

    public static nint Handle(Window w) => new WindowInteropHelper(w).EnsureHandle();

    /// <summary>Click-through: мышь проходит сквозь overlay в Dota.</summary>
    public static void SetClickThrough(Window w, bool enabled)
    {
        var h = Handle(w);
        long style = GetWindowLongPtr(h, GWL_EXSTYLE);
        style |= WS_EX_LAYERED | WS_EX_TOOLWINDOW;
        style = enabled ? style | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE : style & ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
        SetWindowLongPtr(h, GWL_EXSTYLE, (nint)style);
    }

    /// <summary>
    /// Исключить окно из захвата экрана (Windows 10 2004+). Иначе overlay, лежащий поверх Dota,
    /// попадал бы в кадры собственного анализатора.
    /// </summary>
    public static bool ExcludeFromCapture(Window w) => SetWindowDisplayAffinity(Handle(w), WDA_EXCLUDEFROMCAPTURE);

    /// <summary>Поставить окно в прямоугольник в физических пикселях.</summary>
    public static void Place(Window w, int x, int y, int width, int height) =>
        SetWindowPos(Handle(w), 0, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);

    /// <summary>Переместить окно в физических пикселях (без пересчёта DPI WPF).</summary>
    public static void MoveTo(Window w, int x, int y) =>
        SetWindowPos(Handle(w), 0, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}
