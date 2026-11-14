using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace DraftAssistant.Presentation.Interop;

/// <summary>Глобальные горячие клавиши (RegisterHotKey). Клавиши только слушаются — в игру ничего не отправляется.</summary>
internal sealed class HotkeyManager : IDisposable
{
    public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_NOREPEAT = 0x4000;
    private const int WM_HOTKEY = 0x0312;

    [DllImport("user32.dll")] private static extern bool RegisterHotKey(nint hWnd, int id, uint modifiers, uint vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(nint hWnd, int id);

    private readonly nint _hwnd;
    private readonly HwndSource _source;
    private readonly Dictionary<int, Action> _actions = new();
    private int _nextId = 0x5D00;

    public HotkeyManager(Window window)
    {
        _hwnd = NativeWindow.Handle(window);
        _source = HwndSource.FromHwnd(_hwnd);
        _source.AddHook(Hook);
    }

    public bool Register(uint modifiers, uint virtualKey, Action action)
    {
        int id = _nextId++;
        if (!RegisterHotKey(_hwnd, id, modifiers | MOD_NOREPEAT, virtualKey)) return false;
        _actions[id] = action;
        return true;
    }

    private nint Hook(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && _actions.TryGetValue((int)wParam, out var action))
        {
            action();
            handled = true;
        }
        return 0;
    }

    public void Dispose()
    {
        foreach (var id in _actions.Keys) UnregisterHotKey(_hwnd, id);
        _source.RemoveHook(Hook);
    }
}
