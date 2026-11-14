using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Domain.Scoring;

public enum ScoreComponent
{
    /// <summary>Против всей вражеской команды.</summary>
    Counter,
    /// <summary>Чего не хватает команде (инициация, фронтлайн, контроль…).</summary>
    Synergy,
    /// <summary>Сила героя в патче на вашей позиции.</summary>
    Meta,
    /// <summary>Насколько герой типичен для вашей позиции.</summary>
    RoleFit,
    /// <summary>Против вероятных соперников по линии.</summary>
    Lane,
    /// <summary>Ваши отметки ★/♥/избегать.</summary>
    Comfort,
    Composition,
    Strategic,
    /// <summary>Устойчивость к контрпику: мало плохих матчапов (важно для ранних пиков).</summary>
    Safety,
    /// <summary>Связки с уже выбранными союзниками (винрейт пар).</summary>
    Pairs,
}

public enum ReasonPolarity { Positive, Negative }

/// <summary>
/// Один аргумент "почему". Confidence — внутренняя уверенность в аргументе:
/// по ней UI выбирает формулировку ("сильно", "вероятно", "возможно").
/// Evidence — на чём аргумент основан (статистика, теги ролей, данные способностей...).
/// </summary>
public sealed record Reason(
    ScoreComponent Component,
    ReasonPolarity Polarity,
    string Text,
    double Impact,
    double Confidence,
    string Evidence);

/// <summary>
/// Оценка одного компонента. Value в диапазоне [-1; 1], 0 = нейтрально.
/// Confidence в [0; 1]: при низкой уверенности компонент стягивается к нейтральному.
/// </summary>
public sealed record ComponentScore(
    ScoreComponent Component,
    double Value,
    double Confidence,
    IReadOnlyList<Reason> Reasons)
{
    public static ComponentScore Neutral(ScoreComponent c) => new(c, 0, 0, []);

    /// <summary>Значение в шкале 0..100 для отображения.</summary>
    public int Display => (int)Math.Round(50 + 50 * Math.Clamp(Value, -1, 1));
}

public sealed record HeroRecommendation(
    Hero Hero,
    double Score,
    IReadOnlyDictionary<ScoreComponent, ComponentScore> Components,
    IReadOnlyList<Reason> Reasons,
    double? PreviousScore)
{
    public double? Delta => PreviousScore is { } p ? Score - p : null;
}

/// <summary>Веса — только из конфигурации, в алгоритме не захардкожены.</summary>
public sealed class ScoringWeights
{
    public Dictionary<ScoreComponent, double> Weights { get; set; } = new();

    public double Get(ScoreComponent c) => Weights.TryGetValue(c, out var w) ? w : 0;

    /// <summary>
    /// Плавный переход от весов раннего пика к весам позднего:
    /// <paramref name="t"/> = 0 — о врагах ничего не известно, 1 — выбраны все пятеро.
    /// </summary>
    public static ScoringWeights Interpolate(ScoringWeights early, ScoringWeights late, double t)
    {
        t = Math.Clamp(t, 0, 1);
        var keys = early.Weights.Keys.Union(late.Weights.Keys);
        return new ScoringWeights
        {
            Weights = keys.ToDictionary(k => k, k => early.Get(k) * (1 - t) + late.Get(k) * t),
        };
    }
}

/// <summary>Контекст оценки: всё, что evaluator может знать. Никаких координат экрана.</summary>
public sealed record DraftContext(
    DraftState State,
    PlayerProfile Profile,
    IReadOnlyList<Hero> Allies,
    IReadOnlyList<Hero> Enemies,
    PatchData Patch);

public interface IHeroEvaluator
{
    ScoreComponent Component { get; }
    ComponentScore Evaluate(Hero candidate, DraftContext context);
}

public interface ICounterpickEvaluator : IHeroEvaluator { }
public interface ISynergyEvaluator : IHeroEvaluator { }
public interface IMetaEvaluator : IHeroEvaluator { }
public interface IRoleFitEvaluator : IHeroEvaluator { }
public interface IPlayerPreferenceEvaluator : IHeroEvaluator { }
