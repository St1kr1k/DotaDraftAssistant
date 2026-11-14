using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Draft;
using DraftAssistant.Domain.Draft;

namespace DraftAssistant.Tests;

public class DraftStateTrackerTests
{
    private static readonly SlotId S1 = new(DraftSide.Dire, SlotKind.Pick, 0);
    private static readonly SlotId S2 = new(DraftSide.Dire, SlotKind.Pick, 1);

    private static DraftStateTracker Tracker(TrackerOptions? o = null) =>
        new([S1, S2], o ?? new TrackerOptions { ConfirmFrames = 3, MinConfidence = 0.6, ReplaceConfirmedFrames = 6, ClearConfirmedFrames = 20, UnknownFrames = 3 });

    private static SlotObservation Hero(SlotId s, int id, double c = 0.9) => new(s, ObservedContent.Hero, id, c);
    private static SlotObservation Empty(SlotId s) => new(s, ObservedContent.Empty, null, 1);
    private static SlotObservation Unknown(SlotId s, double c = 0.4) => new(s, ObservedContent.Unknown, null, c);

    private static SlotState Slot(DraftStateTracker t, SlotId id) => t.Slots.Single(s => s.Id == id);

    [Fact]
    public void Hero_is_confirmed_only_after_consecutive_frames()
    {
        var t = Tracker();
        Assert.False(t.Update([Hero(S1, 74, 0.91)]));
        Assert.False(t.Update([Hero(S1, 74, 0.94)]));
        Assert.Equal(SlotStatus.Empty, Slot(t, S1).Status);
        Assert.True(t.Update([Hero(S1, 74, 0.93)]));
        Assert.Equal(SlotStatus.Confirmed, Slot(t, S1).Status);
        Assert.Equal(74, Slot(t, S1).HeroId);
    }

    [Fact]
    public void Alternating_heroes_do_not_change_state()
    {
        var t = Tracker();
        for (int i = 0; i < 10; i++)
        {
            t.Update([Hero(S1, 1)]);
            t.Update([Hero(S1, 2)]);
        }
        Assert.Equal(SlotStatus.Empty, Slot(t, S1).Status);
    }

    [Fact]
    public void Low_confidence_never_confirms_a_hero()
    {
        var t = Tracker();
        for (int i = 0; i < 10; i++) t.Update([Hero(S1, 5, 0.41)]);
        var s = Slot(t, S1);
        Assert.Equal(SlotStatus.Unknown, s.Status);
        Assert.Null(s.HeroId);
        Assert.Equal(0.41, s.Confidence, 2);
    }

    [Fact]
    public void Confirmed_pick_survives_single_bad_frames()
    {
        var t = Tracker();
        for (int i = 0; i < 3; i++) t.Update([Hero(S1, 10)]);

        // Одиночные ошибки: другой герой, пустота, мусор.
        Assert.False(t.Update([Hero(S1, 11)]));
        Assert.False(t.Update([Empty(S1)]));
        Assert.False(t.Update([Unknown(S1)]));
        Assert.Equal(10, Slot(t, S1).HeroId);
    }

    [Fact]
    public void Replacing_confirmed_hero_requires_more_frames()
    {
        var t = Tracker();
        for (int i = 0; i < 3; i++) t.Update([Hero(S1, 10)]);
        for (int i = 0; i < 5; i++) t.Update([Hero(S1, 11)]);
        Assert.Equal(10, Slot(t, S1).HeroId);
        t.Update([Hero(S1, 11)]);
        Assert.Equal(11, Slot(t, S1).HeroId);
    }

    [Fact]
    public void Same_hero_cannot_be_confirmed_in_two_slots()
    {
        var t = Tracker();
        for (int i = 0; i < 3; i++) t.Update([Hero(S1, 10)]);
        for (int i = 0; i < 10; i++) t.Update([Hero(S2, 10)]);
        Assert.Equal(SlotStatus.Confirmed, Slot(t, S1).Status);
        Assert.NotEqual(SlotStatus.Confirmed, Slot(t, S2).Status);
    }

    [Fact]
    public void Reset_clears_everything()
    {
        var t = Tracker();
        for (int i = 0; i < 3; i++) t.Update([Hero(S1, 10)]);
        t.Reset();
        Assert.All(t.Slots, s => Assert.Equal(SlotStatus.Empty, s.Status));
    }
}
