using System.Windows;
using System.Windows.Input;
using DraftAssistant.Presentation.Interop;

namespace DraftAssistant.Presentation.Popup;

/// <summary>
/// Окошко подсказок поверх Dota. По умолчанию click-through (мышь проходит в игру).
/// В режиме перемещения окно ловит мышь и перетаскивается.
/// </summary>
public partial class PopupWindow : Window
{
    private readonly PopupViewModel _vm;

    public PopupWindow(PopupViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DataContext = vm;
        SourceInitialized += (_, _) =>
        {
            NativeWindow.ExcludeFromCapture(this);
            NativeWindow.SetClickThrough(this, true);
        };
    }

    /// <summary>Пользователь закончил перетаскивание. Аргумент — прямоугольник окна в физических пикселях.</summary>
    public event EventHandler<NativeWindow.ScreenRect>? Moved;

    public bool IsMoveMode => _vm.IsMoveMode;

    public void SetMoveMode(bool on)
    {
        _vm.IsMoveMode = on;
        NativeWindow.SetClickThrough(this, !on);
        if (on) Activate();
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (!_vm.IsMoveMode || e.ButtonState != MouseButtonState.Pressed) return;
        DragMove();
        Moved?.Invoke(this, NativeWindow.GetRect(this));
    }
}
