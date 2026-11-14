using DraftAssistant.Domain.Player;

namespace DraftAssistant.Domain.Patch;

public sealed record BracketStats(int Picks, int Wins);

/// <summary>Статистика героя по рейтинговым бракетам (1 = Herald ... 8 = Immortal).</summary>
public sealed record HeroPatchStats(int HeroId, IReadOnlyDictionary<int, BracketStats> ByBracket)
{
    public BracketStats Sum(IEnumerable<int> brackets)
    {
        int picks = 0, wins = 0;
        foreach (var b in brackets)
        {
            if (ByBracket.TryGetValue(b, out var s)) { picks += s.Picks; wins += s.Wins; }
        }
        return new BracketStats(picks, wins);
    }
}

/// <summary>
/// Матчап: сколько игр HeroId сыграл против VsHeroId и сколько выиграл.
/// Agreement — насколько согласны источники (1 — полностью, 0 — сильно расходятся или источник один и мал).
/// </summary>
public sealed record MatchupStats(int HeroId, int VsHeroId, int Games, int Wins, double Agreement = 1);

/// <summary>
/// Герой на позиции: сколько игр на ней, сколько побед и какая доля всех игр героя приходится на эту позицию.
/// </summary>
public sealed record PositionStats(int HeroId, Position Position, int Games, int Wins, double Share, double Agreement, string Sources);

/// <summary>Связка: герои в одной команде.</summary>
public sealed record PairStats(int HeroId, int AllyId, int Games, int Wins);

/// <summary>Исход линии против героя: выиграл / ничья / проиграл линию (по STRATZ).</summary>
public sealed record LaneStats(int HeroId, int VsHeroId, int Games, int Wins, int Draws, int Losses)
{
    /// <summary>Доля «выигранной» линии: победа = 1, ничья = 0.5.</summary>
    public double Score => Games > 0 ? (Wins + 0.5 * Draws) / Games : 0.5;
}

/// <summary>Средние убийства и смерти героя в играх против другого героя (по STRATZ).</summary>
public sealed record KdaStats(int HeroId, int VsHeroId, int Games, double KillsPerGame, double DeathsPerGame);

/// <summary>Предмет стартовой закупки: Count штук берут в Share игр героя на позиции.</summary>
public sealed record StartItem(int ItemId, string Name, int Count, double Share);

/// <summary>
/// Факты о способности из открытых данных Dota (dotaconstants): тип урона, проходит ли сквозь BKB,
/// чем снимается, даёт ли невидимость. Только то, что указано в данных, без домыслов.
/// </summary>
public sealed record AbilityInfo(string Key, string Name, string DamageType, bool PiercesBkb, string Dispellable, bool Invisibility);

public sealed class PatchData
{
    public string PatchName { get; init; } = "unknown";
    /// <summary>Для какой группы рангов загружены позиции, матчапы, связки и линии.</summary>
    public RankBracket Rank { get; init; } = RankBracket.LegendAncient;
    public DateTimeOffset FetchedAt { get; init; }
    public string Source { get; init; } = "none";
    public string MatchupSource { get; init; } = "none";
    public IReadOnlyDictionary<int, HeroPatchStats> HeroStats { get; init; } = new Dictionary<int, HeroPatchStats>();
    public IReadOnlyDictionary<(int Hero, int Vs), MatchupStats> Matchups { get; init; } = new Dictionary<(int, int), MatchupStats>();
    public IReadOnlyDictionary<(int Hero, Position Position), PositionStats> Positions { get; init; } = new Dictionary<(int, Position), PositionStats>();
    public IReadOnlyDictionary<(int Hero, int Ally), PairStats> Pairs { get; init; } = new Dictionary<(int, int), PairStats>();
    public string PositionSource { get; init; } = "none";
    public string PairSource { get; init; } = "none";
    public IReadOnlyDictionary<(int Hero, int Vs), LaneStats> Lanes { get; init; } = new Dictionary<(int, int), LaneStats>();
    public string LaneSource { get; init; } = "none";
    public IReadOnlyDictionary<(int Hero, int Vs), KdaStats> Kda { get; init; } = new Dictionary<(int, int), KdaStats>();
    public IReadOnlyDictionary<(int Hero, Position Position), IReadOnlyList<StartItem>> StartItems { get; init; } =
        new Dictionary<(int, Position), IReadOnlyList<StartItem>>();
    public IReadOnlyDictionary<int, IReadOnlyList<AbilityInfo>> Abilities { get; init; } = new Dictionary<int, IReadOnlyList<AbilityInfo>>();

    public IReadOnlyList<AbilityInfo> AbilitiesOf(int heroId) => Abilities.TryGetValue(heroId, out var a) ? a : [];

    /// <summary>Исход линии героя против другого; если есть только обратная запись — победы и поражения меняются местами.</summary>
    public LaneStats? GetLane(int heroId, int vsHeroId)
    {
        if (Lanes.TryGetValue((heroId, vsHeroId), out var l)) return l;
        if (Lanes.TryGetValue((vsHeroId, heroId), out var r)) return new LaneStats(heroId, vsHeroId, r.Games, r.Losses, r.Draws, r.Wins);
        return null;
    }

    public PositionStats? GetPosition(int heroId, Position position) =>
        Positions.TryGetValue((heroId, position), out var p) ? p : null;

    public bool HasPositions => Positions.Count > 0;

    public PairStats? GetPair(int heroId, int allyId)
    {
        if (Pairs.TryGetValue((heroId, allyId), out var p)) return p;
        if (Pairs.TryGetValue((allyId, heroId), out var r)) return new PairStats(heroId, allyId, r.Games, r.Wins);
        return null;
    }

    public static PatchData Empty { get; } = new();

    /// <summary>
    /// Матчап героя против другого героя. Если данных в прямом направлении нет,
    /// используется обратное (wins инвертируются).
    /// </summary>
    public MatchupStats? GetMatchup(int heroId, int vsHeroId)
    {
        if (Matchups.TryGetValue((heroId, vsHeroId), out var m)) return m;
        if (Matchups.TryGetValue((vsHeroId, heroId), out var r))
            return new MatchupStats(heroId, vsHeroId, r.Games, r.Games - r.Wins, r.Agreement);
        return null;
    }
}

public interface IPatchDataProvider
{
    /// <summary>Данные патча для группы рангов.</summary>
    PatchData Load(RankBracket rank);
}
