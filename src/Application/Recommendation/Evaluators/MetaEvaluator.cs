using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// Сила героя в текущем патче.
/// Если есть статистика позиций — винрейт именно на вашей позиции (со сглаживанием к 50%)
/// плюс небольшой бонус за популярность на ней: «массово играют и выигрывают» — надёжный сигнал,
/// а редкий герой с удачной выборкой («WK мид») не взлетает.
/// Иначе — общий винрейт героя в выбранных бракетах.
/// </summary>
public sealed class MetaEvaluator(Func<ScoringOptions> options) : IMetaEvaluator
{
    private const int MinPositionGames = 300;

    public ScoreComponent Component => ScoreComponent.Meta;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        var o = options();
        var pos = context.Profile.MyPosition;
        var p = context.Patch.GetPosition(candidate.Id, pos);
        if (p is not null && p.Games >= MinPositionGames)
        {
            double wr = (p.Wins + 0.5 * o.MetaPriorGames) / (p.Games + (double)o.MetaPriorGames);
            double delta = wr - 0.5;
            double popularity = p.Share >= 0.4 ? 0.15 : p.Share >= 0.2 ? 0.05 : -0.1;
            double value = Math.Clamp(Math.Clamp(delta / o.MetaFullScaleWinrateDelta, -1, 1) * 0.85 + popularity, -1, 1);
            double confidence = (1 - Math.Exp(-p.Games / 3000.0)) * p.Agreement;

            var reasons = new List<Reason>();
            if (Math.Abs(delta) >= 0.015)
            {
                bool good = delta > 0;
                reasons.Add(new Reason(Component, good ? ReasonPolarity.Positive : ReasonPolarity.Negative,
                    good ? $"силён на pos {(int)pos} в патче {context.Patch.PatchName}: WR {wr:P1}"
                         : $"слаб на pos {(int)pos} в патче {context.Patch.PatchName}: WR {wr:P1}",
                    Math.Abs(value), confidence,
                    $"{p.Sources}, {p.Games:N0} игр на позиции" + (p.Agreement < 0.7 ? ", источники расходятся" : "")));
            }
            return new ComponentScore(Component, value, confidence, reasons);
        }

        return ByBrackets(candidate, context, o);
    }

    private ComponentScore ByBrackets(Hero candidate, DraftContext context, ScoringOptions o)
    {
        if (!context.Patch.HeroStats.TryGetValue(candidate.Id, out var stats))
            return ComponentScore.Neutral(Component);

        var s = stats.Sum(o.MetaBrackets);
        if (s.Picks <= 0) return ComponentScore.Neutral(Component);

        double wr = (s.Wins + 0.5 * o.MetaPriorGames) / (s.Picks + (double)o.MetaPriorGames);
        double delta = wr - 0.5;
        double value = Math.Clamp(delta / o.MetaFullScaleWinrateDelta, -1, 1);
        // Общий винрейт без учёта позиции — сигнал слабее.
        double confidence = (1 - Math.Exp(-s.Picks / 3000.0)) * 0.8;

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
