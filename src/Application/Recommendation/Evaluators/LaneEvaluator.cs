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
/// Пока используется общий матчап героев, взвешенный по вероятности встретиться на линии;
/// данные исхода именно линии (STRATZ) подключаются как отдельный источник, когда доступны.
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

            var m = context.Patch.GetMatchup(candidate.Id, enemy.Id);
            if (m is null || m.Games <= 0) continue;

            double wr = (m.Wins + 0.5 * o.MatchupPriorGames) / (m.Games + (double)o.MatchupPriorGames);
            double adv = wr - 0.5;
            double conf = m.Games / (m.Games + (double)o.MatchupPriorGames) * m.Agreement;
            advSum += onLane * adv;
            confSum += onLane * conf;
            weightSum += onLane;

            if (onLane >= 0.4 && Math.Abs(adv) >= 0.02)
            {
                var likely = opponents.OrderByDescending(p => dist[p]).First();
                bool good = adv > 0;
                reasons.Add(new Reason(Component, good ? ReasonPolarity.Positive : ReasonPolarity.Negative,
                    good ? $"на линии против {enemy.LocalizedName} (вероятно pos {(int)likely}): {adv:+0.0%;-0.0%} WR"
                         : $"тяжёлая линия против {enemy.LocalizedName} (вероятно pos {(int)likely}): {adv:+0.0%;-0.0%} WR",
                    Math.Abs(adv) / o.CounterFullScaleWinrateDelta, conf * onLane,
                    $"{context.Patch.MatchupSource}, {m.Games:N0} игр; позиции врага — {dist.Basis}"));
            }
        }

        if (weightSum <= 0) return ComponentScore.Neutral(Component);
        double value = Math.Clamp(advSum / weightSum / o.CounterFullScaleWinrateDelta, -1, 1);
        // Уверенность растёт, когда на линии точно кто-то есть (сумма весов ≈ 1–2 героя).
        double confidence = confSum / weightSum * Math.Min(1, weightSum);
        return new ComponentScore(Component, value, confidence, reasons);
    }
}
