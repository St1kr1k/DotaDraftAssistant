using DraftAssistant.Application.Plan;
using DraftAssistant.Application.Roles;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Tests;

public class GamePlanServiceTests
{
    private static Hero H(int id, string name, params string[] roles) =>
        new(id, name, name, PrimaryAttribute.Universal, AttackType.Melee, roles, []);

    private static readonly Hero Me = H(1, "Me", HeroRoleTags.Initiator, HeroRoleTags.Durable);
    private static readonly Hero Killer = H(2, "Killer", HeroRoleTags.Carry, HeroRoleTags.Disabler);
    private static readonly Hero Victim = H(3, "Victim", HeroRoleTags.Support);

    private static PatchData Patch()
    {
        var kda = new Dictionary<(int, int), KdaStats>
        {
            [(1, 2)] = new(1, 2, 2000, 3.0, 7.5),
            [(1, 3)] = new(1, 3, 2000, 7.0, 4.0),
            [(1, 99)] = new(1, 99, 6000, 5.0, 5.0),
        };
        return new PatchData
        {
            PatchName = "test",
            Kda = kda,
            Matchups = new Dictionary<(int, int), MatchupStats>
            {
                [(1, 2)] = new(1, 2, 2000, 860),
                [(1, 3)] = new(1, 3, 2000, 1140),
            },
            StartItems = new Dictionary<(int, Position), IReadOnlyList<StartItem>>
            {
                [(1, Position.Offlane)] = [new(44, "Tango", 2, 0.95), new(16, "Quelling Blade", 1, 0.8)],
            },
            Abilities = new Dictionary<int, IReadOnlyList<AbilityInfo>>
            {
                [2] = [new("k_ult", "Big Stun", "Magical", true, "Strong Dispels Only", false)],
                [3] = [new("v_inv", "Fade", "", false, "", true)],
            },
        };
    }

    [Fact]
    public void Plan_names_threats_targets_items_and_start_build()
    {
        var plan = new GamePlanService(new RoleTagPositionPrior())
            .Build(Me, Position.Offlane, [Killer, Victim], Patch(), RankBracket.LegendAncient);

        Assert.Equal(["Tango", "Quelling Blade"], plan.StartItems.Select(i => i.Name));
        var threat = Assert.Single(plan.Threats);
        Assert.Equal(Killer.Id, threat.Hero.Id);
        Assert.Contains(threat.Reasons, r => r.Contains("умираете чаще"));
        Assert.Contains(threat.Tips, t => t.Contains("BKB"));

        var target = Assert.Single(plan.Targets);
        Assert.Equal(Victim.Id, target.Hero.Id);
        Assert.Contains(target.Tips, t => t.Contains("побега"));

        Assert.Contains(plan.ItemTips, t => t.Contains("Невидимость у Victim"));
        Assert.Contains(plan.ItemTips, t => t.Contains("сильным диспелом"));
    }

    [Fact]
    public void Plan_without_data_is_empty_but_valid()
    {
        var plan = new GamePlanService(new RoleTagPositionPrior())
            .Build(Me, Position.Mid, [Killer], PatchData.Empty, RankBracket.CrusaderArchon);
        Assert.Empty(plan.StartItems);
        Assert.Empty(plan.Threats);
        Assert.Empty(plan.ItemTips);
    }
}

public class StartItemsTests
{
    [Fact]
    public void Start_build_fills_starting_gold_with_most_common_items()
    {
        var items = new Dictionary<int, DraftAssistant.Infrastructure.Storage.ItemDto>
        {
            [44] = new() { Id = 44, Name = "Tango", Cost = 90 },
            [16] = new() { Id = 16, Name = "Iron Branch", Cost = 50 },
            [20] = new() { Id = 20, Name = "Circlet", Cost = 155 },
            [237] = new() { Id = 237, Name = "Faerie Fire", Cost = 70 },
            [29] = new() { Id = 29, Name = "Boots", Cost = 500 },
        };
        DraftAssistant.Infrastructure.Storage.StartItemDto R(int item, int inst, int games) =>
            new() { HeroId = 92, Position = 2, ItemId = item, Instance = inst, Games = games, PositionGames = 1000 };
        var rows = new List<DraftAssistant.Infrastructure.Storage.StartItemDto>
        {
            R(44, 1, 950), R(16, 1, 800), R(16, 2, 700), R(20, 1, 450), R(237, 1, 300), R(29, 1, 160),
        };

        var built = DraftAssistant.Infrastructure.Storage.LocalPatchDataProvider.BuildStartItems(rows, items)[(92, Position.Mid)];

        Assert.Equal(["Tango", "Iron Branch", "Circlet", "Faerie Fire"], built.Select(i => i.Name));
        Assert.Equal(2, built.Single(i => i.Name == "Iron Branch").Count);
        Assert.True(built.Sum(i => items[i.ItemId].Cost * i.Count) <= 600);
    }
}

public class StartItemsCopiesTests
{
    [Fact]
    public void Repeated_copies_from_separate_rows_are_counted()
    {
        var items = new Dictionary<int, DraftAssistant.Infrastructure.Storage.ItemDto>
        {
            [44] = new() { Id = 44, Name = "Tango", Cost = 90 },
            [16] = new() { Id = 16, Name = "Iron Branch", Cost = 55 },
            [20] = new() { Id = 20, Name = "Circlet", Cost = 155 },
            [13] = new() { Id = 13, Name = "Mantle of Intelligence", Cost = 140 },
            [237] = new() { Id = 237, Name = "Faerie Fire", Cost = 65 },
        };
        DraftAssistant.Infrastructure.Storage.StartItemDto R(int item, int inst, int games) =>
            new() { HeroId = 76, Position = 2, ItemId = item, Instance = inst, Games = games, PositionGames = 58879 };
        // Как в данных STRATZ для OD: 2-я ветка — две строки (с флагом wasGiven и без), 3-я — 29%.
        var rows = new List<DraftAssistant.Infrastructure.Storage.StartItemDto>
        {
            R(44, 0, 69215), R(16, 0, 62006), R(20, 0, 58657), R(13, 0, 50013), R(16, 1, 44771), R(16, 1, 6594),
            R(237, 0, 24686), R(16, 2, 17352),
        };
        var merged = rows.GroupBy(r => (r.HeroId, r.Position, r.ItemId, r.Instance))
            .Select(g => new DraftAssistant.Infrastructure.Storage.StartItemDto
            {
                HeroId = g.Key.HeroId, Position = g.Key.Position, ItemId = g.Key.ItemId, Instance = g.Key.Instance,
                Games = g.Sum(r => r.Games), PositionGames = g.Max(r => r.PositionGames),
            }).ToList();

        var built = DraftAssistant.Infrastructure.Storage.LocalPatchDataProvider.BuildStartItems(merged, items)[(76, Position.Mid)];

        Assert.Equal(2, built.Single(i => i.Name == "Iron Branch").Count);
        Assert.Contains(built, i => i.Name == "Mantle of Intelligence");
        Assert.Contains(built, i => i.Name == "Faerie Fire");
    }
}
