using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Roles;
using DraftAssistant.Presentation.Common;
using DraftAssistant.Presentation.Components;

namespace DraftAssistant.Presentation.Pages;

public sealed class HeroTile : ObservableObject
{
    private HeroPreference _mark;
    private bool _isDimmed, _isHighlighted;

    /// <summary>Не подходит под поиск/фильтр — показывается серым (как в Доте), но не исчезает.</summary>
    public bool IsDimmed { get => _isDimmed; set => Set(ref _isDimmed, value); }

    /// <summary>Подходит под набранный текст — подсвечивается и мерцает.</summary>
    public bool IsHighlighted { get => _isHighlighted; set => Set(ref _isHighlighted, value); }

    public required Hero Hero { get; init; }
    public required ImageSource? Portrait { get; init; }
    public required ICommand SetMain { get; init; }
    public required ICommand SetLike { get; init; }
    public required ICommand SetBan { get; init; }

    public string Name => Hero.LocalizedName;

    public HeroPreference Mark
    {
        get => _mark;
        set
        {
            if (!Set(ref _mark, value)) return;
            Raise(nameof(IsMain));
            Raise(nameof(IsLike));
            Raise(nameof(IsBan));
        }
    }

    public bool IsMain => Mark == HeroPreference.Main;
    public bool IsLike => Mark == HeroPreference.Comfort;
    public bool IsBan => Mark is HeroPreference.HardAvoid or HeroPreference.SoftAvoid;
}

public sealed class AttributeGroup
{
    public required string Title { get; init; }
    public required Brush Dot { get; init; }
    public required ICollectionView Heroes { get; init; }
}

public sealed class RoleFilter(string label, string? tag)
{
    public string Label { get; } = label;
    public string? Tag { get; } = tag;
    public bool IsSelected { get; set; }
}

/// <summary>Раздел «Герои»: сетка по атрибутам, отметки ★ основной / ♥ нравится / ⊘ не играю.</summary>
public sealed class HeroesViewModel : ObservableObject
{
    private readonly ProfileStore _profile;
    private readonly IRoleInferenceService _roles;
    private readonly Func<PatchData> _patch;
    private readonly HeroImages _images;
    private readonly List<HeroTile> _tiles;
    private string _search = "";
    private RoleFilter _role;
    private HeroTile? _hovered;

    public HeroesViewModel(IHeroRepository heroes, ProfileStore profile, IRoleInferenceService roles, Func<PatchData> patch, HeroImages images)
    {
        _profile = profile;
        _roles = roles;
        _patch = patch;
        _images = images;

        _tiles = heroes.All.Select(h => new HeroTile
        {
            Hero = h,
            Portrait = images.Tile(h.Id, TileAspect),
            Mark = profile.Current.GetPreference(h.Id),
            SetMain = new RelayCommand(_ => Toggle(h.Id, HeroPreference.Main)),
            SetLike = new RelayCommand(_ => Toggle(h.Id, HeroPreference.Comfort)),
            SetBan = new RelayCommand(_ => Toggle(h.Id, HeroPreference.HardAvoid)),
        }).ToList();

        RoleFilters =
        [
            new("Все", null), new("Carry", HeroRoleTags.Carry), new("Support", HeroRoleTags.Support),
            new("Initiator", HeroRoleTags.Initiator), new("Durable", HeroRoleTags.Durable),
            new("Disabler", HeroRoleTags.Disabler), new("Nuker", HeroRoleTags.Nuker), new("Escape", HeroRoleTags.Escape),
            new("Pusher", HeroRoleTags.Pusher),
        ];
        _role = RoleFilters[0];
        _role.IsSelected = true;

        Groups =
        [
            Group("СИЛА", "#C2413A", PrimaryAttribute.Strength),
            Group("ЛОВКОСТЬ", "#3FA35B", PrimaryAttribute.Agility),
            Group("ИНТЕЛЛЕКТ", "#3D7BD9", PrimaryAttribute.Intelligence),
            Group("УНИВЕРСАЛЬНЫЕ", "#B48AE0", PrimaryAttribute.Universal),
        ];
        Hovered = _tiles.FirstOrDefault(t => t.IsMain) ?? _tiles.FirstOrDefault();
        profile.Changed += (_, _) => Sync();
    }

    /// <summary>Пропорции плитки героя (ширина / высота).</summary>
    public const double TileAspect = 4.0 / 3.0;

    public IReadOnlyList<AttributeGroup> Groups { get; }
    public IReadOnlyList<RoleFilter> RoleFilters { get; }

    public string Search
    {
        get => _search;
        set { if (Set(ref _search, value)) Refresh(); }
    }

    public RoleFilter Role
    {
        get => _role;
        set { if (Set(ref _role, value)) Refresh(); }
    }

    public HeroTile? Hovered
    {
        get => _hovered;
        set
        {
            if (!Set(ref _hovered, value)) return;
            Raise(nameof(HoverPortrait)); Raise(nameof(HoverName)); Raise(nameof(HoverRoles));
            Raise(nameof(HoverMark)); Raise(nameof(HoverFit)); Raise(nameof(HoverWinrate));
        }
    }

    public ImageSource? HoverPortrait => _hovered is null ? null : _images.Portrait(_hovered.Hero.Id, 512);
    public string HoverName => _hovered?.Name ?? "";
    public string HoverRoles => _hovered is null ? "" : string.Join(" · ", _hovered.Hero.Roles);
    public string HoverMark => _hovered?.Mark switch
    {
        HeroPreference.Main => "★ Основной",
        HeroPreference.Comfort => "♥ Нравится",
        HeroPreference.HardAvoid or HeroPreference.SoftAvoid => "Не играю",
        _ => "—",
    };
    public string HoverFitLabel => $"Для pos {(int)_profile.Current.MyPosition}";
    public string HoverFit
    {
        get
        {
            if (_hovered is null) return "";
            var dist = _roles.Infer(_hovered.Hero);
            double ratio = dist[_profile.Current.MyPosition] / Math.Max(1e-6, dist.Max);
            return ratio >= 0.8 ? "типичный" : ratio >= 0.45 ? "возможен" : "нетипичный";
        }
    }
    public string HoverWinrate
    {
        get
        {
            if (_hovered is null || !_patch().HeroStats.TryGetValue(_hovered.Hero.Id, out var s)) return "нет данных";
            var sum = s.Sum([5, 6, 7, 8]);
            return sum.Picks > 0 ? $"{(double)sum.Wins / sum.Picks:P1}" : "нет данных";
        }
    }

    public string MainName => _tiles.FirstOrDefault(t => t.IsMain)?.Name ?? "нет основного";
    public int LikeCount => _tiles.Count(t => t.IsLike);
    public int BanCount => _tiles.Count(t => t.IsBan);

    private AttributeGroup Group(string title, string color, PrimaryAttribute attr)
    {
        var items = new ObservableCollection<HeroTile>(_tiles.Where(t => t.Hero.PrimaryAttribute == attr));
        var view = CollectionViewSource.GetDefaultView(items);
        var brush = (SolidColorBrush)new BrushConverter().ConvertFromString(color)!;
        brush.Freeze();
        return new AttributeGroup { Title = title, Dot = brush, Heroes = view };
    }

    private bool MatchesSearch(HeroTile t, string q) =>
        t.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
        t.Name.Replace(" ", "").Contains(q.Replace(" ", ""), StringComparison.OrdinalIgnoreCase) ||
        t.Hero.Aliases.Any(a => a.Contains(q, StringComparison.OrdinalIgnoreCase));

    /// <summary>Как в Доте: подходящие герои ярче и мерцают, остальные серые. Никто не исчезает.</summary>
    private void Refresh()
    {
        var q = _search.Trim();
        foreach (var t in _tiles)
        {
            bool roleOk = _role.Tag is not { } tag || t.Hero.HasRole(tag);
            bool searchOk = q.Length == 0 || MatchesSearch(t, q);
            t.IsDimmed = !(roleOk && searchOk);
            t.IsHighlighted = q.Length > 0 && roleOk && searchOk;
        }
    }

    /// <summary>Ввод с клавиатуры в любом месте страницы, как в Доте.</summary>
    public void TypeChar(string text)
    {
        if (string.IsNullOrEmpty(text) || char.IsControl(text[0])) return;
        Search += text;
    }

    public void Backspace()
    {
        if (_search.Length > 0) Search = _search[..^1];
    }

    public void ClearSearch() => Search = "";

    private void Toggle(int heroId, HeroPreference mark)
    {
        _profile.Update(p =>
        {
            var current = p.GetPreference(heroId);
            if (mark == HeroPreference.Main)
                foreach (var id in p.Preferences.Where(kv => kv.Value == HeroPreference.Main).Select(kv => kv.Key).ToList())
                    p.Preferences.Remove(id);
            if (current == mark) p.Preferences.Remove(heroId);
            else p.Preferences[heroId] = mark;
        });
    }

    private void Sync()
    {
        var profile = _profile.Current;
        foreach (var t in _tiles) t.Mark = profile.GetPreference(t.Hero.Id);
        Raise(nameof(MainName)); Raise(nameof(LikeCount)); Raise(nameof(BanCount));
        Raise(nameof(HoverMark)); Raise(nameof(HoverFit)); Raise(nameof(HoverFitLabel));
    }
}
