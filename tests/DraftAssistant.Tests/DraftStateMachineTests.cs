using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Draft;
using DraftAssistant.Domain.Draft;

namespace DraftAssistant.Tests;

public class DraftStateMachineTests
{
    private static DraftStateMachine Machine() => new(new StateMachineOptions { EnterFrames = 3, ExitFrames = 5 });

    [Fact]
    public void Enters_draft_after_several_visible_frames()
    {
        var m = Machine();
        m.Update(true, ExternalGameState.Unknown, 0, 10, 0);
        m.Update(true, ExternalGameState.Unknown, 0, 10, 0);
        Assert.Equal(DraftPhase.Idle, m.Phase);
        var t = m.Update(true, ExternalGameState.Unknown, 0, 10, 0);
        Assert.Equal(new PhaseTransition(DraftPhase.Idle, DraftPhase.DraftDetected), t);
    }

    [Fact]
    public void Gsi_hero_selection_enters_draft_immediately()
    {
        var m = Machine();
        m.Update(false, ExternalGameState.HeroSelection, 0, 10, 0);
        Assert.Equal(DraftPhase.DraftDetected, m.Phase);
    }

    [Fact]
    public void Full_lifecycle()
    {
        var m = Machine();
        for (int i = 0; i < 3; i++) m.Update(true, ExternalGameState.Unknown, 0, 10, 0);
        m.Update(true, ExternalGameState.Unknown, 0, 10, 2);
        Assert.Equal(DraftPhase.BanPhase, m.Phase);
        m.Update(true, ExternalGameState.Unknown, 1, 10, 2);
        Assert.Equal(DraftPhase.PickPhase, m.Phase);
        m.Update(true, ExternalGameState.Unknown, 10, 10, 2);
        Assert.Equal(DraftPhase.Completed, m.Phase);
        for (int i = 0; i < 5; i++) m.Update(false, ExternalGameState.InGame, 10, 10, 2);
        Assert.Equal(DraftPhase.Idle, m.Phase);
    }

    [Fact]
    public void Short_occlusion_does_not_abort_draft()
    {
        var m = Machine();
        for (int i = 0; i < 3; i++) m.Update(true, ExternalGameState.Unknown, 0, 10, 0);
        m.Update(true, ExternalGameState.Unknown, 2, 10, 0);
        for (int i = 0; i < 4; i++) m.Update(false, ExternalGameState.Unknown, 2, 10, 0);
        Assert.Equal(DraftPhase.PickPhase, m.Phase);
        for (int i = 0; i < 1; i++) m.Update(false, ExternalGameState.Unknown, 2, 10, 0);
        Assert.Equal(DraftPhase.Idle, m.Phase);
    }
}
