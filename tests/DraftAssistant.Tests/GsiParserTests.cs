using DraftAssistant.Application.Abstractions;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Infrastructure.Gsi;

namespace DraftAssistant.Tests;

public class GsiParserTests
{
    [Fact]
    public void Parses_hero_selection_with_team_and_hero()
    {
        const string json = """
        {
          "provider": { "name": "Dota 2", "appid": 570 },
          "map": { "game_state": "DOTA_GAMERULES_STATE_HERO_SELECTION" },
          "player": { "team_name": "dire" },
          "hero": { "id": 2, "name": "npc_dota_hero_axe" }
        }
        """;
        var hint = GsiListener.Parse(json, DateTimeOffset.UnixEpoch)!;
        Assert.Equal(ExternalGameState.HeroSelection, hint.State);
        Assert.Equal(DraftSide.Dire, hint.Team);
        Assert.Equal(2, hint.OwnHeroId);
    }

    [Fact]
    public void Missing_blocks_are_tolerated()
    {
        var hint = GsiListener.Parse("""{ "provider": {} }""", DateTimeOffset.UnixEpoch)!;
        Assert.Equal(ExternalGameState.Unknown, hint.State);
        Assert.Null(hint.Team);
        Assert.Null(hint.OwnHeroId);
    }

    [Theory]
    [InlineData("DOTA_GAMERULES_STATE_STRATEGY_TIME", ExternalGameState.PostDraft)]
    [InlineData("DOTA_GAMERULES_STATE_GAME_IN_PROGRESS", ExternalGameState.InGame)]
    [InlineData("DOTA_GAMERULES_STATE_INIT", ExternalGameState.Unknown)]
    public void Maps_game_states(string raw, ExternalGameState expected) =>
        Assert.Equal(expected, GsiListener.MapGameState(raw));
}
