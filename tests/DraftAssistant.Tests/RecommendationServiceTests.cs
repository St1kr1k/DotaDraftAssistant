using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Recommendation;
using DraftAssistant.Application.Recommendation.Evaluators;
using DraftAssistant.Application.Roles;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Scoring;
using DraftAssistant.Infrastructure.Storage;

namespace DraftAssistant.Tests;

public class RecommendationServiceTests
{
    // Мини-база: id 1..6
    private static readonly Hero Axe = H(1, "Axe", HeroRoleTags.Initiator, HeroRoleTags.Durable, HeroRoleTags.Disabler);
    private static readonly Hero Sniper = H(2, "Sniper", HeroRoleTags.Carry, HeroRoleTags.Nuker);
    private static readonly Hero Mars = H(3, "Mars", HeroRoleTags.Initiator, HeroRoleTags.Durable, HeroRoleTags.Disabler);
    private static readonly Hero Lion = H(4, "Lion", HeroRoleTags.Support, HeroRoleTags.Disabler, HeroRoleTags.Nuker);
    private static readonly Hero EnemyCore = H(5, "Enemy Core", HeroRoleTags.Carry);
    private static readonly Hero Picked = H(6, "Picked", HeroRoleTags.Carry);

    private static Hero H(int id, string name, params string[] roles) =>
        new(id, name, name, PrimaryAttribute.Universal, AttackType.Melee, roles, []);

    private static readonly IHeroRepository Heroes = JsonHeroRepository.FromHeroes([Axe, Sniper, Mars, Lion, EnemyCore, Picked]);

    private static RecommendationService Service(ScoringOptions? o = null)
    {
        o ??= new ScoringOptions();
        IHeroEvaluator[] evaluators =
        [
            new CounterEvaluator(() => o),
            new TeamNeedsSynergyEvaluator(),
            new MetaEvaluator(() => o),
            new RoleFitEvaluator(new RoleTagPositionPrior()),
            new PlayerPreferenceEvaluator(() => o),
        ];
        return new RecommendationService(Heroes, evaluators, () => o.Weights);
    }

    /// <summary>Radiant = мы: союзник Picked; Dire = враги: EnemyCore.</summary>
    private static DraftState State()
    {
        var slots = new List<SlotState>
        {
            new(new SlotId(DraftSide.Radiant, SlotKind.Pick, 0), SlotStatus.Confirmed, Picked.Id, 0.95),
            new(new SlotId(DraftSide.Dire, SlotKind.Pick, 0), SlotStatus.Confirmed, EnemyCore.Id, 0.95),
        };
        return new DraftState(DraftPhase.PickPhase, slots, DraftSide.Radiant, DateTimeOffset.UtcNow);
    }

    private static PatchData Patch(params MatchupStats[] matchups) => new()
    {
        PatchName = "test",
        Matchups = matchups.ToDictionary(m => (m.HeroId, m.VsHeroId)),
    };

    [Fact]
    public void Picked_and_hard_avoided_heroes_are_excluded()
    {
        var profile = new PlayerProfile { Preferences = { [Lion.Id] = HeroPreference.HardAvoid } };
        var recs = Service().Recommend(State(), profile, Patch(), 10);
        Assert.DoesNotContain(recs, r => r.Hero.Id == Picked.Id || r.Hero.Id == EnemyCore.Id || r.Hero.Id == Lion.Id);
    }

    [Fact]
    public void Main_hero_with_bad_matchup_does_not_beat_objectively_better_hero()
    {
        // Axe и Mars одинаковые по ролям. Mars — main hero, но сильно проигрывает врагу.
        var patch = Patch(
            new MatchupStats(Mars.Id, EnemyCore.Id, 2000, 800),   // 40% WR
            new MatchupStats(Axe.Id, EnemyCore.Id, 2000, 1100));  // 55% WR
        var profile = new PlayerProfile { MyPosition = Position.Offlane, Preferences = { [Mars.Id] = HeroPreference.Main } };

        var recs = Service().Recommend(State(), profile, patch, 10);
        var axe = recs.Single(r => r.Hero.Id == Axe.Id);
        var mars = recs.Single(r => r.Hero.Id == Mars.Id);

        Assert.True(axe.Score > mars.Score, $"Axe {axe.Score} должен быть выше Mars {mars.Score}");
        Assert.Contains(mars.Reasons, r => r.Component == ScoreComponent.Comfort && r.Polarity == ReasonPolarity.Positive);
        Assert.Contains(mars.Reasons, r => r.Component == ScoreComponent.Counter && r.Polarity == ReasonPolarity.Negative);
    }

    [Fact]
    public void Comfort_breaks_ties_between_equal_heroes()
    {
        var profile = new PlayerProfile { MyPosition = Position.Offlane, Preferences = { [Mars.Id] = HeroPreference.Comfort } };
        var recs = Service().Recommend(State(), profile, Patch(), 10);
        Assert.True(recs.Single(r => r.Hero.Id == Mars.Id).Score > recs.Single(r => r.Hero.Id == Axe.Id).Score);
    }

    [Fact]
    public void Weights_come_from_configuration()
    {
        var patch = Patch(
            new MatchupStats(Mars.Id, EnemyCore.Id, 2000, 800),
            new MatchupStats(Axe.Id, EnemyCore.Id, 2000, 1100));
        var profile = new PlayerProfile { MyPosition = Position.Offlane, Preferences = { [Mars.Id] = HeroPreference.Main } };

        // Если пользователь сам выставит Comfort огромным весом, а Counter обнулит — порядок меняется.
        var o = new ScoringOptions();
        o.Weights.Weights[ScoreComponent.Counter] = 0;
        o.Weights.Weights[ScoreComponent.Comfort] = 1;
        var recs = Service(o).Recommend(State(), profile, patch, 10);
        Assert.True(recs.Single(r => r.Hero.Id == Mars.Id).Score > recs.Single(r => r.Hero.Id == Axe.Id).Score);
    }

    [Fact]
    public void Team_needs_rewards_missing_initiation()
    {
        var profile = new PlayerProfile { MyPosition = Position.Offlane };
        var axe = Service().Evaluate(Axe.Id, State(), profile, Patch())!;
        Assert.Contains(axe.Reasons, r => r.Component == ScoreComponent.Synergy && r.Text.Contains("инициац"));
    }

    [Fact]
    public void Score_is_neutral_without_any_data()
    {
        var state = new DraftState(DraftPhase.DraftDetected, [], null, DateTimeOffset.UtcNow);
        var o = new ScoringOptions();
        o.Weights.Weights[ScoreComponent.RoleFit] = 0;
        var r = Service(o).Evaluate(Axe.Id, state, new PlayerProfile(), Patch())!;
        Assert.Equal(50, r.Score);
    }
}
