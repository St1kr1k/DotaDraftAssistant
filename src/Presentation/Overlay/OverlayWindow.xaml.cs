using System.Windows;
using System.Windows.Controls;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Presentation.Interop;

namespace DraftAssistant.Presentation.Overlay;

public partial class OverlayWindow : Window
{
    private readonly OverlayViewModel _vm;

    public OverlayWindow(OverlayViewModel vm)
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

    public event EventHandler? SettingsRequested;
    public event EventHandler? CalibrationRequested;
    public event EventHandler? ExitRequested;
    public event EventHandler<DraftSide?>? SideOverrideChanged;

    public void SetInteractive(bool interactive)
    {
        _vm.IsInteractive = interactive;
        NativeWindow.SetClickThrough(this, !interactive);
        if (interactive) Activate();
    }

    private void OnSettings(object sender, RoutedEventArgs e) => SettingsRequested?.Invoke(this, EventArgs.Empty);
    private void OnCalibrate(object sender, RoutedEventArgs e) => CalibrationRequested?.Invoke(this, EventArgs.Empty);
    private void OnExit(object sender, RoutedEventArgs e) => ExitRequested?.Invoke(this, EventArgs.Empty);

    private void OnSideChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded) return;
        DraftSide? side = SideBox.SelectedIndex switch
        {
            1 => DraftSide.Radiant,
            2 => DraftSide.Dire,
            _ => null,
        };
        SideOverrideChanged?.Invoke(this, side);
    }
}
