using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation;

public interface IRecommendationService
{
    IReadOnlyList<HeroRecommendation> Recommend(
        DraftState state,
        PlayerProfile profile,
        PatchData patch,
        int count,
        IReadOnlyDictionary<int, double>? previousScores = null);

    /// <summary>Оценка конкретного героя (для "Why not?" и сравнения), даже если он не в топе.</summary>
    HeroRecommendation? Evaluate(int heroId, DraftState state, PlayerProfile profile, PatchData patch);
}

/// <summary>
/// DraftScore = 50 + 50 · Σ(wᵢ · valueᵢ · confidenceᵢ) / Σ wᵢ,  результат в [0; 100].
///
/// Компонент с низкой уверенностью стягивается к нейтральному — так нехватка данных
/// не превращается в уверенный вывод. Веса берутся только из конфигурации.
/// </summary>
public sealed class RecommendationService(
    IHeroRepository heroes,
    IEnumerable<IHeroEvaluator> evaluators,
    Func<ScoringWeights> weights) : IRecommendationService
{
    private readonly IReadOnlyList<IHeroEvaluator> _evaluators = evaluators.ToList();

    public IReadOnlyList<HeroRecommendation> Recommend(
        DraftState state,
        PlayerProfile profile,
        PatchData patch,
        int count,
        IReadOnlyDictionary<int, double>? previousScores = null)
    {
        var context = BuildContext(state, profile, patch);
        var unavailable = state.UnavailableHeroes;
        var w = weights();

        return heroes.All
            .Where(h => !unavailable.Contains(h.Id))
            .Where(h => profile.GetPreference(h.Id) != HeroPreference.HardAvoid)
            .Select(h => Score(h, context, w, previousScores))
            .OrderByDescending(r => r.Score)
            .ThenBy(r => r.Hero.LocalizedName, StringComparer.Ordinal)
            .Take(count)
            .ToList();
    }

    public HeroRecommendation? Evaluate(int heroId, DraftState state, PlayerProfile profile, PatchData patch)
    {
        var hero = heroes.Find(heroId);
        return hero is null ? null : Score(hero, BuildContext(state, profile, patch), weights(), null);
    }

    private DraftContext BuildContext(DraftState state, PlayerProfile profile, PatchData patch)
    {
        var allies = state.AllyPicks.Select(heroes.Find).OfType<Hero>().ToList();
        var enemies = state.EnemyPicks.Select(heroes.Find).OfType<Hero>().ToList();
        return new DraftContext(state, profile, allies, enemies, patch);
    }

    private HeroRecommendation Score(
        Hero hero,
        DraftContext context,
        ScoringWeights w,
        IReadOnlyDictionary<int, double>? previousScores)
    {
        var components = new Dictionary<ScoreComponent, ComponentScore>();
        double weighted = 0, totalWeight = 0;

        foreach (var evaluator in _evaluators)
        {
            double weight = w.Get(evaluator.Component);
            if (weight <= 0) continue;

            var cs = evaluator.Evaluate(hero, context);
            components[evaluator.Component] = cs;
            weighted += weight * Math.Clamp(cs.Value, -1, 1) * Math.Clamp(cs.Confidence, 0, 1);
            totalWeight += weight;
        }

        double score = totalWeight > 0 ? 50 + 50 * weighted / totalWeight : 50;

        var reasons = components.Values
            .SelectMany(c => c.Reasons.Select(r => (Reason: r, Rank: r.Impact * r.Confidence * w.Get(c.Component))))
            .OrderByDescending(x => x.Rank)
            .Select(x => x.Reason)
            .ToList();

        double? previous = previousScores is not null && previousScores.TryGetValue(hero.Id, out var p) ? p : null;
        return new HeroRecommendation(hero, Math.Round(score, 1), components, reasons, previous);
    }
}
