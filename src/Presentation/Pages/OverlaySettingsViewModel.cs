using System.Windows.Input;
using System.Windows.Media;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Presentation.Common;
using DraftAssistant.Presentation.Components;

namespace DraftAssistant.Presentation.Pages;

/// <summary>Раздел «Оверлей»: когда показывать окошко, его вид и положение.</summary>
public sealed class OverlaySettingsViewModel : ObservableObject
{
    public const double BaseWidth = 360;
    public const double BaseHeight = 300;

    private readonly SettingsStore _store;

    public OverlaySettingsViewModel(SettingsStore store)
    {
        _store = store;
        Corner = new RelayCommand(p => SnapTo(p as string ?? "tr"));
        Reset = new RelayCommand(_ => SnapTo("tr"));
        ToggleMove = new RelayCommand(_ => MoveModeRequested?.Invoke(this, EventArgs.Empty));
        store.Changed += (_, _) => RaiseAll();
    }

    private OverlayOptions O => _store.Current.Overlay;

    /// <summary>Просьба включить/выключить режим перемещения окошка в игре.</summary>
    public event EventHandler? MoveModeRequested;

    public ICommand Corner { get; }
    public ICommand Reset { get; }
    public ICommand ToggleMove { get; }

    public bool UntilMyPick
    {
        get => O.ShowMode == PopupShowMode.UntilMyPick;
        set { if (value) { O.ShowMode = PopupShowMode.UntilMyPick; _store.Save(); } }
    }

    public bool WholeDraft
    {
        get => O.ShowMode == PopupShowMode.WholeDraft;
        set { if (value) { O.ShowMode = PopupShowMode.WholeDraft; _store.Save(); } }
    }

    public bool SizeS { get => O.Size == PopupSize.Small; set { if (value) { O.Size = PopupSize.Small; _store.Save(); } } }
    public bool SizeM { get => O.Size == PopupSize.Medium; set { if (value) { O.Size = PopupSize.Medium; _store.Save(); } } }
    public bool SizeL { get => O.Size == PopupSize.Large; set { if (value) { O.Size = PopupSize.Large; _store.Save(); } } }

    public double Opacity
    {
        get => O.Opacity * 100;
        set { O.Opacity = Math.Clamp(value / 100, 0.4, 1); _store.Save(); }
    }

    public string OpacityText => $"{O.Opacity:P0}";

    /// <summary>Фон окошка в превью — тот же, что в игре: меняется вместе с ползунком.</summary>
    public Brush PreviewBackground
    {
        get
        {
            var b = new SolidColorBrush(Color.FromArgb((byte)Math.Round(Math.Clamp(O.Opacity, 0.4, 1) * 255), 9, 9, 11));
            b.Freeze();
            return b;
        }
    }

    public bool ShowReasons
    {
        get => O.ShowReasons;
        set { O.ShowReasons = value; _store.Save(); }
    }

    public bool ShowPlan
    {
        get => O.ShowPlan;
        set { O.ShowPlan = value; _store.Save(); }
    }

    public static double ScaleOf(PopupSize size) => size switch
    {
        PopupSize.Small => 0.85,
        PopupSize.Large => 1.2,
        _ => 1.0,
    };

    // Превью на холсте 1920×1080
    public double PreviewWidth => BaseWidth * ScaleOf(O.Size);
    public double PreviewHeight => BaseHeight * ScaleOf(O.Size);
    public double PreviewLeft => O.PositionX < 0 ? 1920 * (1 - O.RightMargin) - PreviewWidth : O.PositionX * 1920;
    public double PreviewTop => O.PositionY < 0 ? 1080 * O.TopOffset : O.PositionY * 1080;

    private void SnapTo(string corner)
    {
        double w = PreviewWidth / 1920, h = PreviewHeight / 1080, m = 0.0125, top = O.TopOffset;
        (O.PositionX, O.PositionY) = corner switch
        {
            "tl" => (m, top),
            "bl" => (m, 1 - h - 0.03),
            "br" => (1 - w - m, 1 - h - 0.03),
            _ => (-1d, -1d),
        };
        _store.Save();
    }

    private void RaiseAll()
    {
        foreach (var n in new[] { nameof(UntilMyPick), nameof(WholeDraft), nameof(SizeS), nameof(SizeM), nameof(SizeL),
                                  nameof(Opacity), nameof(OpacityText), nameof(ShowReasons), nameof(ShowPlan), nameof(PreviewBackground),
                                  nameof(PreviewWidth), nameof(PreviewHeight), nameof(PreviewLeft), nameof(PreviewTop) })
            Raise(n);
    }
}
