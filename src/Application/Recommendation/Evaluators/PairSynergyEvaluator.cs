using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// Связки: насколько пара «кандидат + союзник» выигрывает чаще, чем ожидалось бы по силе каждого героя.
/// Дополняет TeamNeedsSynergyEvaluator («чего не хватает команде»), а не заменяет его.
/// Без данных о парах компонент нейтрален и на оценку не влияет.
/// </summary>
public sealed class PairSynergyEvaluator(Func<ScoringOptions> options) : ISynergyEvaluator
{
    private const int MinGames = 100;

    public ScoreComponent Component => ScoreComponent.Pairs;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        if (context.Allies.Count == 0 || context.Patch.Pairs.Count == 0) return ComponentScore.Neutral(Component);
        var o = options();

        double sum = 0, confSum = 0;
        int counted = 0;
        var reasons = new List<Reason>();
        foreach (var ally in context.Allies)
        {
            var pair = context.Patch.GetPair(candidate.Id, ally.Id);
            if (pair is null || pair.Games < MinGames) continue;

            double pairWr = (pair.Wins + 0.5 * o.PairPriorGames) / (pair.Games + (double)o.PairPriorGames);
            double expected = (Winrate(context.Patch, candidate.Id, o) + Winrate(context.Patch, ally.Id, o)) / 2;
            double synergy = pairWr - expected;
            double conf = pair.Games / (pair.Games + (double)o.PairPriorGames);
            sum += synergy;
            confSum += conf;
            counted++;

            if (Math.Abs(synergy) >= 0.02)
            {
                bool good = synergy > 0;
                reasons.Add(new Reason(Component, good ? ReasonPolarity.Positive : ReasonPolarity.Negative,
                    good ? $"хорошая связка с {ally.LocalizedName}: {synergy:+0.0%;-0.0%} WR вместе"
                         : $"плохо сочетается с {ally.LocalizedName}: {synergy:+0.0%;-0.0%} WR вместе",
                    Math.Abs(synergy) / o.PairFullScaleWinrateDelta, conf,
                    $"{context.Patch.PairSource}, {pair.Games:N0} игр вместе"));
            }
        }

        if (counted == 0) return ComponentScore.Neutral(Component);
        double value = Math.Clamp(sum / context.Allies.Count / o.PairFullScaleWinrateDelta, -1, 1);
        return new ComponentScore(Component, value, confSum / counted, reasons);
    }

    private static double Winrate(PatchData patch, int heroId, ScoringOptions o)
    {
        if (!patch.HeroStats.TryGetValue(heroId, out var s)) return 0.5;
        var b = s.Sum(o.MetaBrackets);
        return b.Picks > 0 ? (double)b.Wins / b.Picks : 0.5;
    }
}
