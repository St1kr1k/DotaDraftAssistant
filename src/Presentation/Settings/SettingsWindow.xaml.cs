using System.ComponentModel;
using System.Windows;
using System.Windows.Data;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Presentation.Components;
using DraftAssistant.Presentation.Interop;

namespace DraftAssistant.Presentation.Settings;

public sealed record Option<T>(T Value, string Label);

public sealed class HeroPreferenceRow(Hero hero, HeroPreference preference) : ObservableObject
{
    private HeroPreference _preference = preference;
    public int HeroId { get; } = hero.Id;
    public string Name { get; } = hero.LocalizedName;
    public string Roles { get; } = string.Join(", ", hero.Roles);
    public HeroPreference Preference { get => _preference; set => Set(ref _preference, value); }
}

public partial class SettingsWindow : Window
{
    private static readonly Option<Position>[] Positions =
    [
        new(Position.Carry, "Pos 1 — Carry"),
        new(Position.Mid, "Pos 2 — Mid"),
        new(Position.Offlane, "Pos 3 — Offlane"),
        new(Position.SoftSupport, "Pos 4 — Soft support"),
        new(Position.HardSupport, "Pos 5 — Hard support"),
    ];

    private static readonly Option<HeroPreference>[] Preferences =
    [
        new(HeroPreference.Neutral, "—"),
        new(HeroPreference.Main, "★ Основной"),
        new(HeroPreference.Comfort, "Комфортный"),
        new(HeroPreference.SoftAvoid, "Избегать (штраф)"),
        new(HeroPreference.HardAvoid, "Не показывать"),
    ];

    private readonly List<HeroPreferenceRow> _rows;
    private readonly ICollectionView _view;

    public SettingsWindow(IHeroRepository heroes, PlayerProfile profile)
    {
        InitializeComponent();
        SourceInitialized += (_, _) => NativeWindow.ExcludeFromCapture(this);

        PositionBox.ItemsSource = Positions;
        PositionBox.SelectedValue = profile.MyPosition;
        SecondaryBox.ItemsSource = new[] { new Option<Position?>(null, "нет") }
            .Concat(Positions.Select(p => new Option<Position?>(p.Value, p.Label))).ToList();
        SecondaryBox.SelectedValue = profile.SecondaryPosition;
        PreferenceColumn.ItemsSource = Preferences;

        _rows = heroes.All.Select(h => new HeroPreferenceRow(h, profile.GetPreference(h.Id))).ToList();
        _view = CollectionViewSource.GetDefaultView(_rows);
        _view.Filter = Matches;
        HeroGrid.ItemsSource = _view;
    }

    /// <summary>Сохранённый профиль (null, если окно закрыто без сохранения).</summary>
    public PlayerProfile? Result { get; private set; }

    private bool Matches(object o)
    {
        if (o is not HeroPreferenceRow row) return false;
        if (OnlyMarked.IsChecked == true && row.Preference == HeroPreference.Neutral) return false;
        var f = FilterBox.Text?.Trim();
        return string.IsNullOrEmpty(f)
               || row.Name.Contains(f, StringComparison.OrdinalIgnoreCase)
               || row.Roles.Contains(f, StringComparison.OrdinalIgnoreCase);
    }

    private void OnFilterChanged(object sender, RoutedEventArgs e) => _view?.Refresh();

    private void OnSave(object sender, RoutedEventArgs e)
    {
        HeroGrid.CommitEdit();
        var mains = _rows.Where(r => r.Preference == HeroPreference.Main).ToList();
        if (mains.Count > 1)
        {
            ErrorText.Text = $"Основной герой может быть только один (выбрано: {string.Join(", ", mains.Select(m => m.Name))})";
            return;
        }

        Result = new PlayerProfile
        {
            MyPosition = PositionBox.SelectedValue is Position p ? p : Position.Offlane,
            SecondaryPosition = SecondaryBox.SelectedValue as Position?,
            Preferences = _rows.Where(r => r.Preference != HeroPreference.Neutral)
                               .ToDictionary(r => r.HeroId, r => r.Preference),
        };
        DialogResult = true;
    }
}
