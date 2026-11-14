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

/// <summary>Матчап: сколько игр HeroId сыграл против VsHeroId и сколько выиграл.</summary>
public sealed record MatchupStats(int HeroId, int VsHeroId, int Games, int Wins);

public sealed class PatchData
{
    public string PatchName { get; init; } = "unknown";
    public DateTimeOffset FetchedAt { get; init; }
    public string Source { get; init; } = "none";
    public string MatchupSource { get; init; } = "none";
    public IReadOnlyDictionary<int, HeroPatchStats> HeroStats { get; init; } = new Dictionary<int, HeroPatchStats>();
    public IReadOnlyDictionary<(int Hero, int Vs), MatchupStats> Matchups { get; init; } = new Dictionary<(int, int), MatchupStats>();

    public static PatchData Empty { get; } = new();

    /// <summary>
    /// Матчап героя против другого героя. Если данных в прямом направлении нет,
    /// используется обратное (wins инвертируются).
    /// </summary>
    public MatchupStats? GetMatchup(int heroId, int vsHeroId)
    {
        if (Matchups.TryGetValue((heroId, vsHeroId), out var m)) return m;
        if (Matchups.TryGetValue((vsHeroId, heroId), out var r))
            return new MatchupStats(heroId, vsHeroId, r.Games, r.Games - r.Wins);
        return null;
    }
}

public interface IPatchDataProvider
{
    PatchData Load();
}
