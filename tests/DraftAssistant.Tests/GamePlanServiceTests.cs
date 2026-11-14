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
