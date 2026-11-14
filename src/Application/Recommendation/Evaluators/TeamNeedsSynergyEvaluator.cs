using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Recommendation.Evaluators;

/// <summary>
/// "Чего сейчас не хватает всей команде?" — оценивает кандидата относительно состава союзников.
///
/// MVP опирается на теги ролей (Initiator, Durable, Disabler, Nuker, Pusher). Это грубая модель:
/// тег Nuker — лишь приближение магического урона. В фазе 8 теги заменяются структурированными
/// данными способностей (HeroAbilityData): тип урона, save, контроль, waveclear и т.д.
/// </summary>
public sealed class TeamNeedsSynergyEvaluator : ISynergyEvaluator
{
    private sealed record Need(string Tag, int MinAllies, string Lacking, string Fills);

    private static readonly Need[] Needs =
    [
        new(HeroRoleTags.Initiator, 1, "у команды нет инициации", "закрывает нехватку инициации"),
        new(HeroRoleTags.Durable, 1, "у команды нет фронтлайна", "добавляет фронтлайн (Durable)"),
        new(HeroRoleTags.Disabler, 2, "у команды мало контроля", "добавляет контроль (Disabler)"),
        new(HeroRoleTags.Nuker, 2, "мало магического урона (по тегу Nuker)", "добавляет магический урон (Nuker)"),
        new(HeroRoleTags.Pusher, 3, "нечем пушить/снимать волны", "добавляет пуш (Pusher)"),
    ];

    private const string Evidence = "теги ролей союзников и кандидата";

    public ScoreComponent Component => ScoreComponent.Synergy;

    public ComponentScore Evaluate(Hero candidate, DraftContext context)
    {
        var allies = context.Allies;
        if (allies.Count == 0) return ComponentScore.Neutral(Component);

        double value = 0;
        var reasons = new List<Reason>();

        // Чем больше союзников выбрано, тем увереннее мы знаем, чего команде не хватает.
        double certainty = Math.Min(1.0, allies.Count / 3.0);

        foreach (var need in Needs)
        {
            if (allies.Count < need.MinAllies) continue;
            if (allies.Any(a => a.HasRole(need.Tag))) continue;
            if (!candidate.HasRole(need.Tag)) continue;

            double impact = 0.4 * certainty;
            value += impact;
            reasons.Add(new Reason(Component, ReasonPolarity.Positive,
                $"{need.Fills}: {need.Lacking}", impact, certainty, Evidence));
        }

        // Анти-синергия: третий "кэрри" в команде, где уже два.
        int carries = allies.Count(a => a.HasRole(HeroRoleTags.Carry));
        if (carries >= 2 && candidate.HasRole(HeroRoleTags.Carry) && !candidate.HasRole(HeroRoleTags.Support))
        {
            value -= 0.35;
            reasons.Add(new Reason(Component, ReasonPolarity.Negative,
                $"в команде уже {carries} героя с тегом Carry — будет тесно по фарму", 0.35, 0.6, Evidence));
        }

        // Баланс типа атаки: четвёртый ranged без фронтлайна — хрупкий состав.
        int ranged = allies.Count(a => a.AttackType == AttackType.Ranged);
        bool hasFrontline = allies.Any(a => a.HasRole(HeroRoleTags.Durable));
        if (ranged >= 3 && !hasFrontline && candidate.AttackType == AttackType.Ranged && !candidate.HasRole(HeroRoleTags.Durable))
        {
            value -= 0.2;
            reasons.Add(new Reason(Component, ReasonPolarity.Negative,
                "ещё один хрупкий ranged-герой без фронтлайна в команде", 0.2, 0.5, Evidence));
        }

        if (value == 0 && reasons.Count == 0) return new ComponentScore(Component, 0, certainty, []);
        return new ComponentScore(Component, Math.Clamp(value, -1, 1), Math.Max(0.4, certainty), reasons);
    }
}
