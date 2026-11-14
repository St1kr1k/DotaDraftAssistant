using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Roles;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>Насколько кандидат подходит под позицию пользователя.</summary>
public sealed class RoleFitEvaluator(IRoleInferenceService roles) : IRoleFitEvaluator
{
    /// <summary>Уверенность ограничена, пока оценка позиций — эвристика по тегам.</summary>
    private const double HeuristicConfidence = 0.7;

    public ScoreComponent Component => ScoreComponent.RoleFit;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        var dist = roles.Infer(candidate);
        var pos = context.Profile.MyPosition;
        double p = dist[pos];
        double ratio = dist.Max > 0 ? p / dist.Max : 0;
        double value = Math.Clamp(2 * ratio - 1, -1, 1);

        var reasons = new List<Reason>();
        if (value >= 0.6)
            reasons.Add(new Reason(Component, ReasonPolarity.Positive,
                $"типичный герой для pos {(int)pos}", value, HeuristicConfidence, dist.Basis));
        else if (value <= -0.3)
            reasons.Add(new Reason(Component, ReasonPolarity.Negative,
                $"нетипичен для pos {(int)pos} (чаще pos {(int)dist.MostLikely})", -value, HeuristicConfidence, dist.Basis));

        return new ComponentScore(Component, value, HeuristicConfidence, reasons);
    }
}
