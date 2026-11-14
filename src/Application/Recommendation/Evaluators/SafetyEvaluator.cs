using System.Runtime.CompilerServices;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// Устойчивость к контрпику: доля «плохих» матчапов героя (минус 3% WR и хуже) по сравнению со средним героем.
/// Важно для ранних пиков, когда враги ещё могут ответить контрпиком (поздно её вес — 0).
/// </summary>
public sealed class SafetyEvaluator : IHeroEvaluator
{
    private const int MinGames = 150;
    private const double BadAdvantage = -0.03;

    private static readonly ConditionalWeakTable<PatchData, Dictionary<int, double>> Cache = new();

    public ScoreComponent Component => ScoreComponent.Safety;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        var table = Cache.GetValue(context.Patch, Build);
        if (!table.TryGetValue(candidate.Id, out var badShare) || table.Count < 10)
            return ComponentScore.Neutral(Component);

        double average = table.Values.Average();
        if (average <= 0) return ComponentScore.Neutral(Component);
        double value = Math.Clamp((average - badShare) / average, -1, 1);

        var reasons = new List<Reason>();
        if (value >= 0.4)
            reasons.Add(new Reason(Component, ReasonPolarity.Positive,
                "мало плохих матчапов — безопасный ранний пик", value, 0.7, "матчапы патча"));
        else if (value <= -0.4)
            reasons.Add(new Reason(Component, ReasonPolarity.Negative,
                "много контрпиков — рискованно брать рано", -value, 0.7, "матчапы патча"));
        return new ComponentScore(Component, value, 0.7, reasons);
    }

    private static Dictionary<int, double> Build(PatchData patch)
    {
        var result = new Dictionary<int, double>();
        foreach (var g in patch.Matchups.Values.GroupBy(m => m.HeroId))
        {
            var reliable = g.Where(m => m.Games >= MinGames).ToList();
            if (reliable.Count < 20) continue;
            int bad = reliable.Count(m => (double)m.Wins / m.Games - 0.5 <= BadAdvantage);
            result[g.Key] = (double)bad / reliable.Count;
        }
        return result;
    }
}
