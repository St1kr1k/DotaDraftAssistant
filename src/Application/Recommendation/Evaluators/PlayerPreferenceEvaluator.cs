using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// Личный комфорт. Влияние ограничено весом компонента в конфигурации,
/// поэтому main hero не может "перебить" плохой объективный драфт.
/// HardAvoid сюда не попадает — такие герои отфильтровываются до оценки.
/// </summary>
public sealed class PlayerPreferenceEvaluator(Func<ScoringOptions> options) : IPlayerPreferenceEvaluator
{
    private const string Evidence = "ваш профиль";

    public ScoreComponent Component => ScoreComponent.Comfort;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        var o = options();
        return context.Profile.GetPreference(candidate.Id) switch
        {
            HeroPreference.Main => Score(o.MainHeroValue, ReasonPolarity.Positive, "ваш основной герой"),
            HeroPreference.Comfort => Score(o.ComfortHeroValue, ReasonPolarity.Positive, "комфортный для вас герой"),
            HeroPreference.SoftAvoid => Score(o.SoftAvoidValue, ReasonPolarity.Negative, "вы отметили, что избегаете этого героя"),
            _ => new ComponentScore(Component, 0, 1, []),
        };
    }

    private ComponentScore Score(double value, ReasonPolarity polarity, string text) =>
        new(Component, value, 1, [new Reason(Component, polarity, text, Math.Abs(value), 1, Evidence)]);
}
