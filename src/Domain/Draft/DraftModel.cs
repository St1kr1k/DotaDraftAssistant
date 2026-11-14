using DraftAssistant.Domain.Player;

namespace DraftAssistant.Domain.Draft;

public enum DraftSide { Radiant, Dire }

public enum SlotKind { Pick, Ban }

public readonly record struct SlotId(DraftSide Side, SlotKind Kind, int Index)
{
    public override string ToString() => $"{Side}-{Kind}-{Index + 1}";
}

public enum DraftPhase
{
    Idle,
    DraftDetected,
    BanPhase,
    PickPhase,
    Completed,
}

public enum SlotStatus
{
    /// <summary>Слот подтверждённо пуст.</summary>
    Empty,
    /// <summary>Герой подтверждён несколькими последовательными кадрами.</summary>
    Confirmed,
    /// <summary>В слоте что-то есть, но распознать уверенно не удалось.</summary>
    Unknown,
}

public sealed record SlotState(SlotId Id, SlotStatus Status, int? HeroId, double Confidence)
{
    public static SlotState Empty(SlotId id) => new(id, SlotStatus.Empty, null, 1.0);
}

public static class DraftSides
{
    public static DraftSide Opposite(this DraftSide side) =>
        side == DraftSide.Radiant ? DraftSide.Dire : DraftSide.Radiant;
}

/// <summary>
/// Центральная неизменяемая модель драфта. Создаётся трекером, читается всеми остальными.
/// </summary>
public sealed record DraftState(
    DraftPhase Phase,
    IReadOnlyList<SlotState> Slots,
    DraftSide? MySide,
    DateTimeOffset Timestamp)
{
    /// <summary>Позиции игроков, прочитанные с экрана (в рейтинге — у своей команды).</summary>
    public IReadOnlyDictionary<SlotId, Position> Positions { get; init; } = new Dictionary<SlotId, Position>();

    /// <summary>Баны, известные не из слотов, а из чата («Запрещён герой: …»).</summary>
    public IReadOnlySet<int> ExtraBans { get; init; } = new HashSet<int>();

    /// <summary>Ваш слот в своей команде, если его удалось определить.</summary>
    public int? MySlotIndex { get; init; }

    public static DraftState Initial(IEnumerable<SlotId> slots) =>
        new(DraftPhase.Idle, slots.Select(SlotState.Empty).ToList(), null, DateTimeOffset.UtcNow);

    public IEnumerable<SlotState> SlotsOf(DraftSide side, SlotKind kind) =>
        Slots.Where(s => s.Id.Side == side && s.Id.Kind == kind).OrderBy(s => s.Id.Index);

    public IReadOnlyList<int> ConfirmedHeroes(DraftSide side, SlotKind kind) =>
        SlotsOf(side, kind)
            .Where(s => s.Status == SlotStatus.Confirmed && s.HeroId.HasValue)
            .Select(s => s.HeroId!.Value)
            .ToList();

    public IReadOnlyList<int> AllyPicks => MySide is { } s ? ConfirmedHeroes(s, SlotKind.Pick) : [];
    public IReadOnlyList<int> EnemyPicks => MySide is { } s ? ConfirmedHeroes(s.Opposite(), SlotKind.Pick) : [];
    public IReadOnlyList<int> AllyBans => MySide is { } s ? ConfirmedHeroes(s, SlotKind.Ban) : [];
    public IReadOnlyList<int> EnemyBans => MySide is { } s ? ConfirmedHeroes(s.Opposite(), SlotKind.Ban) : [];

    /// <summary>Все герои, которых уже нельзя выбрать (пики и баны обеих сторон).</summary>
    public IReadOnlySet<int> UnavailableHeroes =>
        Slots.Where(s => s.Status == SlotStatus.Confirmed && s.HeroId.HasValue)
             .Select(s => s.HeroId!.Value)
             .Concat(ExtraBans)
             .ToHashSet();

    public int ConfirmedPickCount =>
        Slots.Count(s => s.Id.Kind == SlotKind.Pick && s.Status == SlotStatus.Confirmed);

    public int ConfirmedBanCount =>
        Slots.Count(s => s.Id.Kind == SlotKind.Ban && s.Status == SlotStatus.Confirmed);

    public int TotalPickSlots => Slots.Count(s => s.Id.Kind == SlotKind.Pick);

    public int RemainingPickSlots => TotalPickSlots - ConfirmedPickCount;
}
