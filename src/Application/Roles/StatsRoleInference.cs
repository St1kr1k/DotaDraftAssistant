using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Roles;

namespace DraftAssistant.Application.Roles;

/// <summary>
/// Позиции героя по реальной статистике патча (доля игр героя на каждой позиции).
/// Если статистики по герою нет или она слишком мала, используется эвристика по тегам ролей.
/// </summary>
public sealed class StatsRoleInference(Func<PatchData> patch, RoleTagPositionPrior fallback) : IRoleInferenceService
{
    /// <summary>Минимум игр героя по всем позициям, чтобы доверять статистике.</summary>
    public const int MinGames = 200;

    private readonly Dictionary<int, PositionDistribution> _cache = new();
    private PatchData? _cachedFor;

    public PositionDistribution Infer(Hero hero)
    {
        var data = patch();
        lock (_cache)
        {
            if (!ReferenceEquals(_cachedFor, data)) { _cache.Clear(); _cachedFor = data; }
            if (_cache.TryGetValue(hero.Id, out var cached)) return cached;

            var dist = FromStats(hero, data) ?? fallback.Infer(hero);
            _cache[hero.Id] = dist;
            return dist;
        }
    }

    /// <summary>Доля игр героя на позиции (0..1) или null, если статистики нет.</summary>
    public double? Share(Hero hero, Position position)
    {
        var dist = Infer(hero);
        return dist.Basis.StartsWith("статистика", StringComparison.Ordinal) ? dist[position] : null;
    }

    private static PositionDistribution? FromStats(Hero hero, PatchData data)
    {
        if (!data.HasPositions) return null;
        var rows = Enum.GetValues<Position>().Select(p => data.GetPosition(hero.Id, p)).ToArray();
        int total = rows.Sum(r => r?.Games ?? 0);
        if (total < MinGames) return null;

        var shares = rows.Select(r => r?.Share ?? 0).ToArray();
        if (shares.Sum() <= 0) return null;
        var sources = string.Join("+", rows.OfType<PositionStats>().Select(r => r.Sources).Distinct());
        return new PositionDistribution(shares, $"статистика позиций ({sources}, {total:N0} игр)");
    }
}
