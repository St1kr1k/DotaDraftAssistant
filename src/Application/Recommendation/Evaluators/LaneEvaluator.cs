using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Roles;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// Линия: матчап против тех врагов, которые скорее всего встанут против вас.
/// Лёгкая линия (pos 1 / pos 5) стоит против сложной (pos 3 / pos 4), мид — против мида.
/// Каждый враг весит столько, насколько вероятно, что он на «вашей» линии (по статистике позиций).
///
/// Если есть исходы линий (STRATZ) — используется доля выигранных линий против этого героя;
/// иначе общий матчап героев (сигнал слабее, уверенность ниже).
/// </summary>
public sealed class LaneEvaluator(IRoleInferenceService roles, Func<ScoringOptions> options) : IHeroEvaluator
{
    public ScoreComponent Component => ScoreComponent.Lane;

    public static IReadOnlyList<Position> Opponents(Position mine) => mine switch
    {
        Position.Carry or Position.HardSupport => [Position.Offlane, Position.SoftSupport],
        Position.Offlane or Position.SoftSupport => [Position.Carry, Position.HardSupport],
        _ => [Position.Mid],
    };

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        if (context.Enemies.Count == 0) return ComponentScore.Neutral(Component);
        var o = options();
        var opponents = Opponents(context.Profile.MyPosition);

        double weightSum = 0, advSum = 0, confSum = 0;
        var reasons = new List<Reason>();
        foreach (var enemy in context.Enemies)
        {
            var dist = roles.Infer(enemy);
            double onLane = opponents.Sum(p => dist[p]);
            if (onLane < 0.15) continue; // этот враг почти наверняка не на вашей линии

            double adv, conf, scale;
            int games;
            string evidence, label;
            var lane = context.Patch.GetLane(candidate.Id, enemy.Id);
            if (lane is not null && lane.Games >= 30)
            {
                double s = (lane.Score * lane.Games + 0.5 * o.MatchupPriorGames) / (lane.Games + (double)o.MatchupPriorGames);
                adv = s - 0.5;
                conf = lane.Games / (lane.Games + (double)o.MatchupPriorGames);
                scale = o.LaneFullScaleDelta;
                games = lane.Games;
                evidence = context.Patch.LaneSource;
                label = "выигранных линий";
            }
            else
            {
                var m = context.Patch.GetMatchup(candidate.Id, enemy.Id);
                if (m is null || m.Games <= 0) continue;
                double wr = (m.Wins + 0.5 * o.MatchupPriorGames) / (m.Games + (double)o.MatchupPriorGames);
                adv = wr - 0.5;
                // Общий матчап говорит о линии лишь косвенно.
                conf = m.Games / (m.Games + (double)o.MatchupPriorGames) * m.Agreement * 0.7;
                scale = o.CounterFullScaleWinrateDelta;
                games = m.Games;
                evidence = context.Patch.MatchupSource;
                label = "WR";
            }
            double norm = Math.Clamp(adv / scale, -1, 1);
            advSum += onLane * norm;
            confSum += onLane * conf;
            weightSum += onLane;

            if (onLane >= 0.4 && Math.Abs(norm) >= 0.4)
            {
                var likely = opponents.OrderByDescending(p => dist[p]).First();
                bool good = adv > 0;
                reasons.Add(new Reason(Component, good ? ReasonPolarity.Positive : ReasonPolarity.Negative,
                    good ? $"на линии против {enemy.LocalizedName} (вероятно pos {(int)likely}): {adv:+0.0%;-0.0%} {label}"
                         : $"тяжёлая линия против {enemy.LocalizedName} (вероятно pos {(int)likely}): {adv:+0.0%;-0.0%} {label}",
                    Math.Abs(norm), conf * onLane,
                    $"{evidence}, {games:N0} игр; позиции врага — {dist.Basis}"));
            }
        }

        if (weightSum <= 0) return ComponentScore.Neutral(Component);
        double value = Math.Clamp(advSum / weightSum, -1, 1);
        // Уверенность растёт, когда на линии точно кто-то есть (сумма весов ≈ 1–2 героя).
        double confidence = confSum / weightSum * Math.Min(1, weightSum);
        return new ComponentScore(Component, value, confidence, reasons);
    }
}
