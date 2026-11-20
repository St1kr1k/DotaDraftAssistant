using DraftAssistant.Domain.Scoring;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Application.Recommendation;
using DraftAssistant.Application.Roles;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;
using DraftAssistant.Infrastructure.Storage;
using Xunit;

namespace DraftAssistant.Tests;

/// <summary>Окошко не должно вылезать посреди игры и в лобби.</summary>
public class DraftPipelineFalseDraftTests
{
    private static readonly SlotId[] Slots =
        new[] { DraftSide.Radiant, DraftSide.Dire }
            .SelectMany(side => Enumerable.Range(0, 5).Select(i => new SlotId(side, SlotKind.Pick, i)))
            .ToArray();

    private sealed class FakeDetector : IDraftDetector
    {
        public IReadOnlyList<SlotId> Slots => DraftPipelineFalseDraftTests.Slots;
        public DraftObservation? Next { get; set; }
        public DraftObservation? Observe() => Next;
    }

    private sealed class NoRecs : IRecommendationService
    {
        public IReadOnlyList<HeroRecommendation> Recommend(DraftState s, PlayerProfile p, PatchData d, int c, IReadOnlyDictionary<int, double>? prev = null) => [];
        public HeroRecommendation? Evaluate(int id, DraftState s, PlayerProfile p, PatchData d) => null;
    }

    private sealed class NoPatch : IPatchDataProvider
    {
        public PatchData Load(RankBracket rank) => PatchData.Empty;
    }

    private sealed class Hints : IGameStateHintSource
    {
        public GameStateHint? Current { get; set; }
    }

    /// <summary>Кадр: видны полоски игроков, в первых <paramref name="heroes"/> слотах — герои.</summary>
    private static DraftObservation Frame(int heroes, bool visible = true) =>
        new(visible, 1, Slots.Select((id, i) => i < heroes
                ? new SlotObservation(id, ObservedContent.Hero, i + 1, 0.9)
                : new SlotObservation(id, ObservedContent.Empty, null, 0.9)).ToList(),
            ObservationIssue.None, DateTimeOffset.UtcNow);

    private static (DraftPipeline Pipeline, FakeDetector Detector, Hints Hints) Create()
    {
        var heroes = JsonHeroRepository.FromHeroes(Enumerable.Range(1, 10)
            .Select(id => new Hero(id, $"h{id}", $"h{id}", PrimaryAttribute.Universal, AttackType.Melee, [], [])));
        var detector = new FakeDetector();
        var hints = new Hints();
        var pipeline = new DraftPipeline(detector, hints, new NoRecs(), new RoleTagPositionPrior(), heroes, new NoPatch(),
            () => new PlayerProfile(), new AppSettings(), NullLog.Instance);
        return (pipeline, detector, hints);
    }

    private static DraftSnapshot? Run(DraftPipeline p, FakeDetector d, DraftObservation frame, int frames)
    {
        d.Next = frame;
        for (int i = 0; i < frames; i++) p.Tick();
        return p.Last;
    }

    [Fact]
    public void Game_top_bar_with_some_heroes_is_not_a_draft()
    {
        var (p, d, _) = Create();
        var s = Run(p, d, Frame(heroes: 5), frames: 20);
        Assert.Equal(DraftPhase.Idle, s!.State.Phase);
    }

    [Fact]
    public void Lobby_with_empty_bars_is_not_a_confirmed_draft()
    {
        var (p, d, _) = Create();
        var s = Run(p, d, Frame(heroes: 0), frames: 20);
        Assert.False(s!.DraftConfirmed);
    }

    [Fact]
    public void Real_draft_is_confirmed_after_first_pick()
    {
        var (p, d, _) = Create();
        Run(p, d, Frame(heroes: 0), frames: 5);
        var s = Run(p, d, Frame(heroes: 1), frames: 5);
        Assert.NotEqual(DraftPhase.Idle, s!.State.Phase);
        Assert.True(s.DraftConfirmed);
    }

    [Fact]
    public void After_draft_ends_the_game_does_not_start_a_new_draft()
    {
        var (p, d, _) = Create();
        Run(p, d, Frame(heroes: 0), frames: 5);
        for (int k = 1; k <= 10; k++) Run(p, d, Frame(heroes: k), frames: 5);
        Assert.Equal(DraftPhase.Completed, p.Last!.State.Phase);

        // Загрузка — полосок нет, драфт закрывается; затем в игре полоска, где почти все мертвы (0–2 героя видно).
        Run(p, d, Frame(heroes: 0, visible: false), frames: 40);
        var s = Run(p, d, Frame(heroes: 1), frames: 20);
        Assert.False(s!.DraftConfirmed);
        Assert.Equal(DraftPhase.Idle, s.State.Phase);
    }

    [Fact]
    public void Gsi_outside_hero_selection_blocks_screen_draft()
    {
        var (p, d, h) = Create();
        h.Current = new GameStateHint(ExternalGameState.Unknown, null, null, DateTimeOffset.UtcNow);
        var s = Run(p, d, Frame(heroes: 0), frames: 20);
        Assert.Equal(DraftPhase.Idle, s!.State.Phase);
    }
}
