using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Domain.Roles;

/// <summary>Вероятностная оценка позиции героя (сумма = 1).</summary>
public sealed class PositionDistribution
{
    private readonly double[] _p;

    public PositionDistribution(double[] probabilities, string basis)
    {
        if (probabilities.Length != 5) throw new ArgumentException("Нужно ровно 5 позиций", nameof(probabilities));
        var sum = probabilities.Sum();
        _p = sum > 0 ? probabilities.Select(v => v / sum).ToArray() : Enumerable.Repeat(0.2, 5).ToArray();
        Basis = basis;
    }

    /// <summary>На чём основана оценка (для честного объяснения пользователю).</summary>
    public string Basis { get; }

    public double this[Position position] => _p[(int)position - 1];

    public Position MostLikely => (Position)(Array.IndexOf(_p, _p.Max()) + 1);

    public double Max => _p.Max();

    public IEnumerable<(Position Position, double Probability)> Ordered =>
        Enumerable.Range(0, 5).Select(i => ((Position)(i + 1), _p[i])).OrderByDescending(x => x.Item2);
}

public interface IRoleInferenceService
{
    PositionDistribution Infer(Hero hero);
}
