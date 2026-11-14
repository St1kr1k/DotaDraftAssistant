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
        var details = new List<(Hero Enemy, double Adv, double Conf, int Games)>();

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
            details.Add((enemy, adv, conf, m.Games));
        }

        if (known == 0) return ComponentScore.Neutral(Component);

        // Делим на число ВСЕХ врагов: если по части врагов данных нет, оценка честно стягивается к нулю.
        double avgAdvantage = advantageSum / context.Enemies.Count;
        double value = Math.Clamp(avgAdvantage / o.CounterFullScaleWinrateDelta, -1, 1);
        double confidence = confidenceSum / context.Enemies.Count;

        // Объяснение — сводка по всему драфту врага: средний плюс, против кого лучше всего и почему (по статистике
        // убийств/смертей), и отдельно — против кого опасно.
        string Detail((Hero Enemy, double Adv, double Conf, int Games) d)
        {
            var why = KdaAverages.Why(context.Patch, candidate.Id, d.Enemy.Id);
            return $"{d.Enemy.LocalizedName} ({d.Adv:+0.0%;-0.0%}{(why is null ? "" : ", " + why)})";
        }
        var reasons = new List<Reason>();
        var best = details.Where(d => d.Adv >= 0.015).OrderByDescending(d => d.Adv).Take(2).ToList();
        var worst = details.Where(d => d.Adv <= -0.015).OrderBy(d => d.Adv).Take(2).ToList();
        string evidence = $"{context.Patch.MatchupSource}, {details.Sum(d => d.Games):N0} игр в матчапах";
        if (avgAdvantage >= 0.005 && best.Count > 0)
        {
            reasons.Add(new Reason(Component, ReasonPolarity.Positive,
                $"против драфта врага {avgAdvantage:+0.0%;-0.0%} WR; лучше всего — против {string.Join(", ", best.Select(Detail))}",
                Math.Abs(value), confidence, evidence));
        }
        if (worst.Count > 0)
        {
            reasons.Add(new Reason(Component, ReasonPolarity.Negative,
                $"опасно против {string.Join(", ", worst.Select(Detail))}",
                Math.Min(1, Math.Abs(worst[0].Adv) / o.CounterFullScaleWinrateDelta), worst[0].Conf, evidence));
        }
        return new ComponentScore(Component, value, confidence, reasons);
    }
}
