using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Roles;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// Насколько кандидат подходит под позицию пользователя.
/// По статистике позиций — уверенно; по тегам ролей — с пониженной уверенностью.
/// (Герои, которых на позиции почти не играют, отсекаются ещё до оценки — см. RecommendationService.)
/// </summary>
public sealed class RoleFitEvaluator(IRoleInferenceService roles) : IRoleFitEvaluator
{
    public ScoreComponent Component => ScoreComponent.RoleFit;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        var dist = roles.Infer(candidate);
        bool fromStats = dist.Basis.StartsWith("статистика", StringComparison.Ordinal);
        double confidence = fromStats ? 0.9 : 0.6;

        var pos = context.Profile.MyPosition;
        double p = dist[pos];
        double ratio = dist.Max > 0 ? p / dist.Max : 0;
        double value = Math.Clamp(2 * ratio - 1, -1, 1);

        var reasons = new List<Reason>();
        if (value >= 0.6)
        {
            reasons.Add(new Reason(Component, ReasonPolarity.Positive,
                fromStats ? $"на pos {(int)pos} его играют в {p:P0} игр" : $"типичный герой для pos {(int)pos}",
                value, confidence, dist.Basis));
        }
        else if (value <= -0.3)
        {
            reasons.Add(new Reason(Component, ReasonPolarity.Negative,
                fromStats ? $"чаще играют на pos {(int)dist.MostLikely}, на pos {(int)pos} — {p:P0} игр"
                          : $"нетипичен для pos {(int)pos} (чаще pos {(int)dist.MostLikely})",
                -value, confidence, dist.Basis));
        }

        return new ComponentScore(Component, value, confidence, reasons);
    }
}
