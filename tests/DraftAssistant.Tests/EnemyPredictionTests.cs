using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Application.Prediction;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Tests;

public class EnemyPredictionTests
{
    private sealed class FakeSource : IPlayerHeroSource
    {
        public Task<PlayerHeroes?> FindAsync(string nickname, CancellationToken ct) => Task.FromResult<PlayerHeroes?>(nickname switch
        {
            "pudgeking" => new PlayerHeroes(1, "pudgeking", [(14, 60), (26, 30), (8, 10)], 100),
            _ => null,
        });
    }

    private sealed class NullLog : IAppLog
    {
        public void Info(string message) { }
        public void Warn(string message) { }
        public void Error(string message, Exception? ex = null) { }
    }

    private static DraftSnapshot Snapshot(int? enemyPick, params int[] bans)
    {
        var slots = new List<SlotState>
        {
            new(new SlotId(DraftSide.Dire, SlotKind.Pick, 0), enemyPick is null ? SlotStatus.Empty : SlotStatus.Confirmed, enemyPick, 0.9),
        };
        var state = new DraftState(DraftPhase.PickPhase, slots, DraftSide.Radiant, DateTimeOffset.UtcNow) { ExtraBans = bans.ToHashSet() };
        return new DraftSnapshot(PipelineStatus.Observing, null, state, SideSource.Gsi, [], new Dictionary<int, DraftAssistant.Domain.Roles.PositionDistribution>(),
                                 PatchData.Empty, 1, false, Position.Mid, false)
        {
            PlayerNames = new Dictionary<SlotId, string> { [new SlotId(DraftSide.Dire, SlotKind.Pick, 0)] = "pudgeking" },
        };
    }

    [Fact]
    public async Task Predicts_most_played_available_hero_until_enemy_picks()
    {
        var service = new EnemyPredictionService(new FakeSource(), new NullLog());
        service.Predict(Snapshot(null));          // запускает поиск
        await Task.Delay(50);

        var p = Assert.Single(service.Predict(Snapshot(null)));
        Assert.Equal(14, p.HeroId);
        Assert.Equal(0.6, p.Share, 3);

        // Забанен самый частый — берётся следующий.
        Assert.Equal(26, Assert.Single(service.Predict(Snapshot(null, 14))).HeroId);

        // Враг выбрал героя — догадка больше не показывается.
        Assert.Empty(service.Predict(Snapshot(26)));
    }
}
