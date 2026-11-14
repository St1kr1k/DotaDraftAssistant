using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// MVP-контрпик: статистика матчапов кандидата против КАЖДОГО уже выбранного врага,
/// агрегированная по всей вражеской команде.
///
/// Объяснения здесь статистические ("+3.1% WR против X"). Механические объяснения
/// (способность A против способности B) добавляет AbilityInteractionAnalyzer в следующих фазах
/// и только на основе структурированных данных — без выдумывания.
/// </summary>
public sealed class CounterEvaluator(Func<ScoringOptions> options) : ICounterpickEvaluator
{
    public ScoreComponent Component => ScoreComponent.Counter;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        if (context.Enemies.Count == 0) return ComponentScore.Neutral(Component);
        var o = options();

        double advantageSum = 0, confidenceSum = 0;
        int known = 0;
        var reasons = new List<Reason>();

        foreach (var enemy in context.Enemies)
        {
            var m = context.Patch.GetMatchup(candidate.Id, enemy.Id);
            if (m is null || m.Games <= 0) continue;

            double wr = (m.Wins + 0.5 * o.MatchupPriorGames) / (m.Games + (double)o.MatchupPriorGames);
            double adv = wr - 0.5;
            double conf = m.Games / (m.Games + (double)o.MatchupPriorGames) * m.Agreement;
            advantageSum += adv;
            confidenceSum += conf;
            known++;

            if (Math.Abs(adv) >= 0.02)
            {
                bool good = adv > 0;
                reasons.Add(new Reason(
                    Component,
                    good ? ReasonPolarity.Positive : ReasonPolarity.Negative,
                    good ? $"хорош против {enemy.LocalizedName} ({adv:+0.0%;-0.0%} WR в матчапе)"
                         : $"слаб против {enemy.LocalizedName} ({adv:+0.0%;-0.0%} WR в матчапе)",
                    Math.Abs(adv) / o.CounterFullScaleWinrateDelta,
                    conf,
                    $"{context.Patch.MatchupSource}, {m.Games:N0} игр"));
            }
        }

        if (known == 0) return ComponentScore.Neutral(Component);

        // Делим на число ВСЕХ врагов: если по части врагов данных нет, оценка честно стягивается к нулю.
        double avgAdvantage = advantageSum / context.Enemies.Count;
        double value = Math.Clamp(avgAdvantage / o.CounterFullScaleWinrateDelta, -1, 1);
        double confidence = confidenceSum / context.Enemies.Count;
        return new ComponentScore(Component, value, confidence, reasons);
    }
}
