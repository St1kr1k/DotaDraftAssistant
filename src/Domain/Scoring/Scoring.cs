using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Domain.Scoring;

public enum ScoreComponent
{
    Counter,
    Synergy,
    Meta,
    RoleFit,
    Lane,
    Comfort,
    Composition,
    Strategic,
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
