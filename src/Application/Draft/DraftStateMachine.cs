using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Draft;

namespace DraftAssistant.Application.Draft;

public sealed record PhaseTransition(DraftPhase From, DraftPhase To);

/// <summary>
/// IDLE → DRAFT_DETECTED → BAN_PHASE → PICK_PHASE → DRAFT_COMPLETED → IDLE.
///
/// Переходы основаны на наблюдаемых фактах (виден ли экран драфта, сколько пиков/банов подтверждено,
/// что сообщает GSI), а не на таймингах драфта. Гистерезис считается в кадрах.
/// </summary>
public sealed class DraftStateMachine
{
    private readonly StateMachineOptions _options;
    private int _visibleFrames;
    private int _hiddenFrames;

    public DraftStateMachine(StateMachineOptions options) => _options = options;

    public DraftPhase Phase { get; private set; } = DraftPhase.Idle;

    public PhaseTransition? Update(
        bool draftScreenVisible,
        ExternalGameState externalState,
        int confirmedPicks,
        int totalPickSlots,
        int confirmedBans)
    {
        bool visible = draftScreenVisible || externalState == ExternalGameState.HeroSelection;
        if (visible) { _visibleFrames++; _hiddenFrames = 0; }
        else { _hiddenFrames++; _visibleFrames = 0; }

        var next = Phase switch
        {
            DraftPhase.Idle =>
                externalState == ExternalGameState.HeroSelection || _visibleFrames >= _options.EnterFrames
                    ? DraftPhase.DraftDetected
                    : DraftPhase.Idle,

            DraftPhase.DraftDetected or DraftPhase.BanPhase or DraftPhase.PickPhase =>
                InDraft(externalState, confirmedPicks, totalPickSlots, confirmedBans),

            DraftPhase.Completed =>
                _hiddenFrames >= _options.ExitFrames && externalState != ExternalGameState.HeroSelection
                    ? DraftPhase.Idle
                    : DraftPhase.Completed,

            _ => Phase,
        };

        if (next == Phase) return null;
        var transition = new PhaseTransition(Phase, next);
        Phase = next;
        return transition;
    }

    private DraftPhase InDraft(ExternalGameState ext, int picks, int totalPicks, int bans)
    {
        if (totalPicks > 0 && picks >= totalPicks) return DraftPhase.Completed;
        if (ext is ExternalGameState.PostDraft or ExternalGameState.InGame) return DraftPhase.Completed;

        // Экран драфта пропал надолго, а GSI не подтверждает выбор героев — драфт прерван.
        if (_hiddenFrames >= _options.ExitFrames && ext != ExternalGameState.HeroSelection)
            return DraftPhase.Idle;

        if (picks > 0) return DraftPhase.PickPhase;
        if (bans > 0) return DraftPhase.BanPhase;
        return Phase == DraftPhase.BanPhase ? DraftPhase.BanPhase : DraftPhase.DraftDetected;
    }

    public void Reset()
    {
        Phase = DraftPhase.Idle;
        _visibleFrames = 0;
        _hiddenFrames = 0;
    }
}
