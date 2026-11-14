using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Application.Abstractions;

public enum ObservedContent { Empty, Hero, Unknown }

/// <summary>Результат анализа одного слота на одном кадре (ещё НЕ состояние драфта).</summary>
public sealed record SlotObservation(SlotId Slot, ObservedContent Content, int? HeroId, double Confidence);

public enum ObservationIssue
{
    None,
    /// <summary>Разметка экрана драфта не откалибрована — распознавание слотов не выполняется.</summary>
    LayoutNotCalibrated,
}

/// <summary>Наблюдение одного кадра.</summary>
public sealed record DraftObservation(
    bool DraftScreenVisible,
    double ScreenConfidence,
    IReadOnlyList<SlotObservation> Slots,
    ObservationIssue Issue,
    DateTimeOffset Timestamp)
{
    /// <summary>Позиции, подписанные на экране (в рейтинге — только у своей команды).</summary>
    public IReadOnlyDictionary<SlotId, Position>? Roles { get; init; }

    /// <summary>Сторона, у которой видны подписи ролей, — это ваша команда.</summary>
    public DraftSide? AllySide { get; init; }

    /// <summary>Ваш слот в своей команде (по нику из GSI), если удалось определить.</summary>
    public int? OwnSlotIndex { get; init; }

    /// <summary>Герои, забаненные по сообщениям чата.</summary>
    public IReadOnlyCollection<int>? BannedHeroes { get; init; }
}

/// <summary>
/// Порт "глаз": захват + CV + распознавание. Возвращает null, если окно Dota 2 не найдено.
/// Реализация живёт в infrastructure, application видит только наблюдения.
/// </summary>
public interface IDraftDetector
{
    IReadOnlyList<SlotId> Slots { get; }
    DraftObservation? Observe();
}

public enum ExternalGameState { Unknown, HeroSelection, PostDraft, InGame }

/// <summary>Подсказка от официального Game State Integration (если настроен).</summary>
public sealed record GameStateHint(ExternalGameState State, DraftSide? Team, int? OwnHeroId, DateTimeOffset ReceivedAt, string? PlayerName = null);

public interface IGameStateHintSource
{
    GameStateHint? Current { get; }
}

public interface ISettingsRepository
{
    AppSettings LoadSettings();
    void SaveSettings(AppSettings settings);
    PlayerProfile LoadProfile();
    void SaveProfile(PlayerProfile profile);
}

public interface IAppLog
{
    void Info(string message);
    void Warn(string message);
    void Error(string message, Exception? ex = null);
}

public sealed class NullLog : IAppLog
{
    public static readonly NullLog Instance = new();
    public void Info(string message) { }
    public void Warn(string message) { }
    public void Error(string message, Exception? ex = null) { }
}
