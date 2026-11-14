using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Roles;

namespace DraftAssistant.Application.Roles;

/// <summary>
/// MVP-оценка позиции героя по его тегам ролей (Carry, Support, Durable ...).
///
/// Это эвристика, а не статистика патча — поэтому Basis явно это говорит, а RoleFitEvaluator
/// выдаёт по ней пониженную уверенность. В фазе 6 заменяется реализацией на основе
/// статистики позиций (например, Stratz) с учётом состава команды.
/// </summary>
public sealed class RoleTagPositionPrior : IRoleInferenceService
{
    // Вклад тега в позиции 1..5.
    private static readonly Dictionary<string, double[]> TagWeights = new(StringComparer.OrdinalIgnoreCase)
    {
        [HeroRoleTags.Carry] = [3.0, 1.5, 0.5, 0.0, 0.0],
        [HeroRoleTags.Nuker] = [0.3, 1.5, 0.3, 1.0, 0.6],
        [HeroRoleTags.Escape] = [0.6, 1.0, 0.3, 0.8, 0.1],
        [HeroRoleTags.Durable] = [0.6, 0.3, 2.0, 0.2, 0.1],
        [HeroRoleTags.Initiator] = [0.0, 0.4, 1.6, 1.0, 0.3],
        [HeroRoleTags.Disabler] = [0.0, 0.3, 0.6, 1.0, 1.2],
        [HeroRoleTags.Support] = [0.0, 0.0, 0.1, 2.0, 2.6],
        [HeroRoleTags.Pusher] = [0.4, 0.4, 0.5, 0.2, 0.1],
        [HeroRoleTags.Jungler] = [0.3, 0.1, 0.3, 0.5, 0.2],
    };

    private const double Smoothing = 0.15;

    private readonly Dictionary<int, PositionDistribution> _cache = new();

    public PositionDistribution Infer(Hero hero)
    {
        lock (_cache)
        {
            if (_cache.TryGetValue(hero.Id, out var cached)) return cached;
            var p = Enumerable.Repeat(Smoothing, 5).ToArray();
            foreach (var role in hero.Roles)
            {
                if (!TagWeights.TryGetValue(role, out var w)) continue;
                for (int i = 0; i < 5; i++) p[i] += w[i];
            }
            var dist = new PositionDistribution(p, "теги ролей героя (эвристика)");
            _cache[hero.Id] = dist;
            return dist;
        }
    }
}
