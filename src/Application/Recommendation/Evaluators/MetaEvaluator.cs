using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>Сила героя в текущем патче по винрейту в выбранных бракетах (со сглаживанием к 50%).</summary>
public sealed class MetaEvaluator(Func<ScoringOptions> options) : IMetaEvaluator
{
    public ScoreComponent Component => ScoreComponent.Meta;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        var o = options();
        if (!context.Patch.HeroStats.TryGetValue(candidate.Id, out var stats))
            return ComponentScore.Neutral(Component);

        var s = stats.Sum(o.MetaBrackets);
        if (s.Picks <= 0) return ComponentScore.Neutral(Component);

        double wr = (s.Wins + 0.5 * o.MetaPriorGames) / (s.Picks + (double)o.MetaPriorGames);
        double delta = wr - 0.5;
        double value = Math.Clamp(delta / o.MetaFullScaleWinrateDelta, -1, 1);
        double confidence = 1 - Math.Exp(-s.Picks / 3000.0);

        var reasons = new List<Reason>();
        if (Math.Abs(delta) >= 0.015)
        {
            bool good = delta > 0;
            reasons.Add(new Reason(
                Component,
                good ? ReasonPolarity.Positive : ReasonPolarity.Negative,
                good ? $"силён в патче {context.Patch.PatchName}: WR {wr:P1}"
                     : $"слаб в патче {context.Patch.PatchName}: WR {wr:P1}",
                Math.Abs(value),
                confidence,
                $"{context.Patch.Source}, бракеты {string.Join(",", o.MetaBrackets)}, {s.Picks:N0} игр"));
        }

        return new ComponentScore(Component, value, confidence, reasons);
    }
}
