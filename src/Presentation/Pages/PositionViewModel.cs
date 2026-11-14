using System.Windows.Input;
using System.Windows.Media;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Roles;
using DraftAssistant.Presentation.Common;
using DraftAssistant.Presentation.Components;

namespace DraftAssistant.Presentation.Pages;

public sealed class PositionCard : ObservableObject
{
    private static readonly Brush Accent = Frozen("#E5383B");
    private static readonly Brush Plain = Frozen("#8B8B93");
    private static readonly Brush Dim = Frozen("#26262C");

    private bool _isMain, _isSecondary;

    public required Position Position { get; init; }
    public required string Name { get; init; }
    public required string Description { get; init; }
    /// <summary>"top" | "mid" | "bot" — линия позиции на мини-карте (сторона Radiant).</summary>
    public required string Lane { get; init; }
    public required bool Core { get; init; }
    public required ICommand MakeMain { get; init; }
    public required ICommand MakeSecondary { get; init; }

    public int Number => (int)Position;
    public string MapLabel => $"Мини-карта: линия позиции {Number}";

    public bool IsMain { get => _isMain; set { if (Set(ref _isMain, value)) RaiseLanes(); } }
    public bool IsSecondary { get => _isSecondary; set { if (Set(ref _isSecondary, value)) RaiseLanes(); } }

    private Brush Highlight => IsMain || IsSecondary ? Accent : Plain;
    private double Width => Core ? 7 : 4;
    public Brush TopBrush => Lane == "top" ? Highlight : Dim;
    public Brush MidBrush => Lane == "mid" ? Highlight : Dim;
    public Brush BotBrush => Lane == "bot" ? Highlight : Dim;
    public double TopWidth => Lane == "top" ? Width : 4;
    public double MidWidth => Lane == "mid" ? Width : 4;
    public double BotWidth => Lane == "bot" ? Width : 4;

    private void RaiseLanes()
    {
        Raise(nameof(TopBrush)); Raise(nameof(MidBrush)); Raise(nameof(BotBrush));
    }

    private static Brush Frozen(string hex)
    {
        var b = (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;
        b.Freeze();
        return b;
    }
}

/// <summary>Кнопка выбора группы рангов.</summary>
public sealed class RankOption : ObservableObject
{
    private bool _isSelected;
    public required RankBracket Rank { get; init; }
    public required ICommand Select { get; init; }
    public string Title => RankBrackets.Title(Rank);
    public bool IsSelected { get => _isSelected; set => Set(ref _isSelected, value); }
}

/// <summary>Раздел «Позиция»: основная и запасная позиция, сводка по пулу героев.</summary>
public sealed class PositionViewModel : ObservableObject
{
    private readonly ProfileStore _profile;
    private readonly IHeroRepository _heroes;
    private readonly IRoleInferenceService _roles;

    public PositionViewModel(ProfileStore profile, IHeroRepository heroes, IRoleInferenceService roles)
    {
        _profile = profile;
        _heroes = heroes;
        _roles = roles;
        Cards =
        [
            Card(Position.Carry, "Carry", "Лёгкая линия. Фарм, поздняя игра, основной урон.", "bot", true),
            Card(Position.Mid, "Mid", "Центр. Темп, руны, ранние убийства.", "mid", true),
            Card(Position.Offlane, "Offlane", "Сложная линия. Инициация, фронтлайн, давление.", "top", true),
            Card(Position.SoftSupport, "Soft support", "Сложная линия и роуминг. Контроль, ганки.", "top", false),
            Card(Position.HardSupport, "Hard support", "Лёгкая линия. Сейв, вижн, защита керри.", "bot", false),
        ];
        Ranks = RankBrackets.All.Select(r => new RankOption
        {
            Rank = r,
            Select = new RelayCommand(_ => _profile.Update(pr => pr.Rank = r)),
        }).ToList();
        profile.Changed += (_, _) => Sync();
        Sync();
    }

    public IReadOnlyList<PositionCard> Cards { get; }
    public IReadOnlyList<RankOption> Ranks { get; }

    public string MainHero => _profile.Current.MainHeroId is { } id ? _heroes.Find(id)?.LocalizedName ?? "—" : "не выбран";
    public string PoolTitle => $"ГЕРОИ ПОД POS {(int)_profile.Current.MyPosition} В ВАШЕМ ПУЛЕ";
    public string PoolValue { get; private set; } = "";
    public string PoolHint { get; private set; } = "";

    private PositionCard Card(Position p, string name, string desc, string lane, bool core) => new()
    {
        Position = p, Name = name, Description = desc, Lane = lane, Core = core,
        MakeMain = new RelayCommand(_ => _profile.Update(pr =>
        {
            if (pr.SecondaryPosition == p) pr.SecondaryPosition = pr.MyPosition;
            pr.MyPosition = p;
        })),
        MakeSecondary = new RelayCommand(_ => _profile.Update(pr =>
        {
            if (pr.MyPosition == p) return;
            pr.SecondaryPosition = pr.SecondaryPosition == p ? null : p;
        })),
    };

    private void Sync()
    {
        var pr = _profile.Current;
        foreach (var c in Cards)
        {
            c.IsMain = c.Position == pr.MyPosition;
            c.IsSecondary = c.Position == pr.SecondaryPosition;
        }
        foreach (var r in Ranks) r.IsSelected = r.Rank == pr.Rank;

        var pool = pr.Preferences
            .Where(kv => kv.Value is HeroPreference.Main or HeroPreference.Comfort)
            .Select(kv => _heroes.Find(kv.Key)).OfType<Hero>().ToList();
        int fit = pool.Count(h => { var d = _roles.Infer(h); return d[pr.MyPosition] / Math.Max(1e-6, d.Max) >= 0.8; });
        PoolValue = pool.Count == 0 ? "пул пуст" : $"{fit} из {pool.Count} отмеченных";
        PoolHint = pool.Count == 0 ? "Отметьте героев в разделе «Герои»"
                 : fit * 2 >= pool.Count ? "Пул хорошо подходит под позицию" : "Многие ваши герои не для этой позиции";
        Raise(nameof(MainHero)); Raise(nameof(PoolTitle)); Raise(nameof(PoolValue)); Raise(nameof(PoolHint));
    }
}
