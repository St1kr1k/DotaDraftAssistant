using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Controls;
using System.Windows.Input;
using DraftAssistant.Presentation.Common;

namespace DraftAssistant.Presentation.Main;

public partial class MainWindow : Window
{
    private readonly Dictionary<object, FrameworkElement> _pages;

    public MainWindow(MainViewModel vm, FrameworkElement heroes, FrameworkElement position, FrameworkElement overlay, FrameworkElement setup)
    {
        InitializeComponent();
        DataContext = vm;
        _pages = new()
        {
            [NavHeroes] = heroes,
            [NavPosition] = position,
            [NavOverlay] = overlay,
            [NavSetup] = setup,
        };
        NavHeroes.IsChecked = true;
        // Окно без системной рамки при разворачивании по умолчанию занимает весь монитор и уходит под панель задач.
        // Ограничиваем развёрнутый размер рабочей областью монитора (без панели задач).
        SourceInitialized += (_, _) =>
            HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook(WndProc);
    }

    private const int WM_GETMINMAXINFO = 0x0024;
    private const uint MONITOR_DEFAULTTONEAREST = 2;

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MINMAXINFO { public POINT Reserved, MaxSize, MaxPosition, MinTrackSize, MaxTrackSize; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO { public int Size; public RECT Monitor, Work; public uint Flags; }

    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    private static IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != WM_GETMINMAXINFO) return IntPtr.Zero;
        var monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info)) return IntPtr.Zero;

        var mmi = Marshal.PtrToStructure<MINMAXINFO>(lParam);
        mmi.MaxPosition.X = info.Work.Left - info.Monitor.Left;
        mmi.MaxPosition.Y = info.Work.Top - info.Monitor.Top;
        mmi.MaxSize.X = info.Work.Right - info.Work.Left;
        mmi.MaxSize.Y = info.Work.Bottom - info.Work.Top;
        Marshal.StructureToPtr(mmi, lParam, true);
        handled = true;
        return IntPtr.Zero;
    }

    public event EventHandler? RestartToUpdateRequested;

    /// <summary>Печать в любом месте окна уходит в поиск текущего раздела (если он это поддерживает).</summary>
    protected override void OnPreviewTextInput(TextCompositionEventArgs e)
    {
        if (PageHost.Content is ITypeAnywhere page && Keyboard.FocusedElement is not TextBox && !string.IsNullOrEmpty(e.Text))
        {
            page.TypeText(e.Text);
            e.Handled = true;
            return;
        }
        base.OnPreviewTextInput(e);
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (PageHost.Content is ITypeAnywhere page)
        {
            if (e.Key == Key.Escape) { page.TypeEscape(); e.Handled = true; return; }
            if (e.Key == Key.Back && Keyboard.FocusedElement is not TextBox) { page.TypeBackspace(); e.Handled = true; return; }
        }
        base.OnPreviewKeyDown(e);
    }

    public void ShowPage(string name)
    {
        var target = name switch
        {
            "position" => NavPosition,
            "overlay" => NavOverlay,
            "setup" => NavSetup,
            _ => NavHeroes,
        };
        target.IsChecked = true;
    }

    private void OnNav(object sender, RoutedEventArgs e)
    {
        if (_pages is not null && _pages.TryGetValue(sender, out var page)) PageHost.Content = page;
    }

    private void OnMinimize(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void OnMaximize(object sender, RoutedEventArgs e) =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void OnClose(object sender, RoutedEventArgs e) => Close();

    private void OnRestartToUpdate(object sender, RoutedEventArgs e) => RestartToUpdateRequested?.Invoke(this, EventArgs.Empty);
}
