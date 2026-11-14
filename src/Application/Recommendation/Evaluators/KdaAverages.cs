using System.Runtime.CompilerServices;
using DraftAssistant.Domain.Patch;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>Средние убийства и смерти героя по всем матчапам — база для «против него умирает реже/чаще».</summary>
public static class KdaAverages
{
    private static readonly ConditionalWeakTable<PatchData, Dictionary<int, (double Kills, double Deaths)>> Cache = new();

    public static (double Kills, double Deaths)? Of(PatchData patch, int heroId) =>
        Cache.GetValue(patch, Build).TryGetValue(heroId, out var v) ? v : null;

    /// <summary>Короткое «почему» по статистике убийств и смертей, или null, если разницы нет.</summary>
    public static string? Why(PatchData patch, int heroId, int vsHeroId)
    {
        if (Of(patch, heroId) is not { } avg || avg.Deaths <= 0 || avg.Kills <= 0) return null;
        if (!patch.Kda.TryGetValue((heroId, vsHeroId), out var k) || k.Games < 100) return null;
        double d = k.DeathsPerGame / avg.Deaths, kills = k.KillsPerGame / avg.Kills;
        if (d <= 0.9) return "реже умирает";
        if (d >= 1.1) return "чаще умирает";
        if (kills >= 1.1) return "больше убивает";
        if (kills <= 0.9) return "меньше убивает";
        return null;
    }

    private static Dictionary<int, (double, double)> Build(PatchData patch)
    {
        var acc = new Dictionary<int, (double Games, double Kills, double Deaths)>();
        foreach (var k in patch.Kda.Values)
        {
            var a = acc.GetValueOrDefault(k.HeroId);
            acc[k.HeroId] = (a.Games + k.Games, a.Kills + k.KillsPerGame * k.Games, a.Deaths + k.DeathsPerGame * k.Games);
        }
        return acc.Where(kv => kv.Value.Games > 0)
            .ToDictionary(kv => kv.Key, kv => (kv.Value.Kills / kv.Value.Games, kv.Value.Deaths / kv.Value.Games));
    }
}
