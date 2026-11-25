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

    private static RecommendationService Service(ScoringOptions? o = null, StatsRoleInference? positions = null)
    {
        // Эти тесты сравнивают оценки любых героев; режим «только мои герои» проверяется отдельно.
        o ??= new ScoringOptions { PoolOnly = false };
        IHeroEvaluator[] evaluators =
        [
            new CounterEvaluator(() => o),
            new LaneEvaluator(new RoleTagPositionPrior(), () => o),
            new TeamNeedsSynergyEvaluator(),
            new PairSynergyEvaluator(() => o),
            new MetaEvaluator(() => o),
            new SafetyEvaluator(),
            new RoleFitEvaluator(new RoleTagPositionPrior()),
            new PlayerPreferenceEvaluator(() => o),
        ];
        return new RecommendationService(Heroes, evaluators, () => o, positions);
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
        var o = new ScoringOptions { PoolOnly = false };
        o.SetWeight(ScoreComponent.Counter, 0);
        o.SetWeight(ScoreComponent.Lane, 0);
        o.SetWeight(ScoreComponent.Comfort, 100);
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
        o.SetWeight(ScoreComponent.RoleFit, 0);
        var r = Service(o).Evaluate(Axe.Id, state, new PlayerProfile(), Patch())!;
        Assert.Equal(50, r.Score);
    }

    private static PatchData PositionPatch(params PositionStats[] rows) => new()
    {
        PatchName = "test",
        PositionSource = "test",
        Positions = rows.ToDictionary(r => (r.HeroId, r.Position)),
    };

    [Fact]
    public void Hero_rarely_played_on_my_position_is_filtered_out()
    {
        // «WK мид»: Sniper почти всегда керри, на миде 3% игр с высоким винрейтом.
        var patch = PositionPatch(
            new PositionStats(Sniper.Id, Position.Carry, 9700, 4900, 0.97, 1, "test"),
            new PositionStats(Sniper.Id, Position.Mid, 300, 200, 0.03, 1, "test"),
            new PositionStats(Axe.Id, Position.Mid, 2000, 1000, 0.5, 1, "test"),
            new PositionStats(Axe.Id, Position.Offlane, 2000, 1000, 0.5, 1, "test"));
        var roles = new StatsRoleInference(() => patch, new RoleTagPositionPrior());
        var profile = new PlayerProfile { MyPosition = Position.Mid };

        var recs = Service(positions: roles).Recommend(State(), profile, patch, 10);
        Assert.DoesNotContain(recs, r => r.Hero.Id == Sniper.Id);
        Assert.Contains(recs, r => r.Hero.Id == Axe.Id);

        // Отметка ★/♥ не делает героя мидером: на позиции его почти не играют — не предлагаем.
        profile.Preferences[Sniper.Id] = HeroPreference.Comfort;
        recs = Service(positions: roles).Recommend(State(), profile, patch, 10);
        Assert.DoesNotContain(recs, r => r.Hero.Id == Sniper.Id);
    }

    [Fact]
    public void Weights_shift_from_early_to_late_as_enemies_appear()
    {
        var o = new ScoringOptions();
        var early = RecommendationService.WeightsFor(o, 0);
        var late = RecommendationService.WeightsFor(o, 5);
        Assert.Equal(0, early.Get(ScoreComponent.Meta));
        Assert.Equal(0, late.Get(ScoreComponent.Meta));
        Assert.True(early.Get(ScoreComponent.Safety) > late.Get(ScoreComponent.Safety));
        Assert.True(early.Get(ScoreComponent.Counter) < late.Get(ScoreComponent.Counter));
        Assert.Equal(100, o.WeightsEarly.Weights.Values.Sum(), 3);
        Assert.Equal(100, o.WeightsLate.Weights.Values.Sum(), 3);
    }

    [Fact]
    public void Lane_uses_likely_lane_opponent()
    {
        // Мы оффлейн: против нас скорее керри (EnemyCore с тегом Carry).
        var patch = Patch(new MatchupStats(Axe.Id, EnemyCore.Id, 3000, 1700));
        var profile = new PlayerProfile { MyPosition = Position.Offlane };
        var axe = Service().Evaluate(Axe.Id, State(), profile, patch)!;
        Assert.True(axe.Components[ScoreComponent.Lane].Value > 0);
        Assert.Contains(axe.Reasons, r => r.Component == ScoreComponent.Lane && r.Polarity == ReasonPolarity.Positive);
    }

    [Fact]
    public void Pair_synergy_rewards_good_duo_and_is_neutral_without_data()
    {
        var profile = new PlayerProfile { MyPosition = Position.Offlane };
        var none = Service().Evaluate(Axe.Id, State(), profile, Patch())!;
        Assert.Equal(0, none.Components[ScoreComponent.Pairs].Value);

        var patch = new PatchData
        {
            PatchName = "test",
            PairSource = "test",
            Pairs = new Dictionary<(int, int), PairStats> { [(Picked.Id, Axe.Id)] = new(Picked.Id, Axe.Id, 2000, 1150) },
        };
        var axe = Service().Evaluate(Axe.Id, State(), profile, patch)!;
        Assert.True(axe.Components[ScoreComponent.Pairs].Value > 0);
    }

    [Fact]
    public void Sources_are_averaged_not_summed_and_disagreement_lowers_confidence()
    {
        var (games, wins, agreement) = LocalPatchDataProvider.Merge(
        [
            (10000, 5500, "stratz"),
            (8000, 3600, "opendota"),
        ]);
        Assert.Equal(10000, games);
        Assert.InRange((double)wins / games, 0.45, 0.55);
        Assert.True(agreement < 0.5);

        var same = LocalPatchDataProvider.Merge([(10000, 5200, "stratz"), (8000, 4160, "opendota")]);
        Assert.True(same.Agreement > 0.95);
    }

    [Fact]
    public void Lane_prefers_lane_outcomes_over_general_matchup()
    {
        // Общий матчап в пользу Axe, но линию он против EnemyCore обычно проигрывает.
        var patch = new PatchData
        {
            PatchName = "test",
            LaneSource = "test",
            Matchups = new Dictionary<(int, int), MatchupStats> { [(Axe.Id, EnemyCore.Id)] = new(Axe.Id, EnemyCore.Id, 3000, 1700) },
            Lanes = new Dictionary<(int, int), LaneStats> { [(EnemyCore.Id, Axe.Id)] = new(EnemyCore.Id, Axe.Id, 2000, 1100, 400, 500) },
        };
        var profile = new PlayerProfile { MyPosition = Position.Offlane };
        var axe = Service().Evaluate(Axe.Id, State(), profile, patch)!;
        Assert.True(axe.Components[ScoreComponent.Lane].Value < 0);
        Assert.Contains(axe.Reasons, r => r.Component == ScoreComponent.Lane && r.Text.Contains("линий"));
    }

    [Fact]
    public void Meta_uses_statistics_of_selected_rank()
    {
        // Axe силён на низких рангах и слаб на высоких.
        var patch = new PatchData
        {
            PatchName = "test",
            HeroStats = new Dictionary<int, HeroPatchStats>
            {
                [Axe.Id] = new(Axe.Id, new Dictionary<int, BracketStats>
                {
                    [1] = new(20000, 11200), [2] = new(20000, 11200),
                    [7] = new(20000, 8800), [8] = new(20000, 8800),
                }),
            },
        };
        var low = new PlayerProfile { MyPosition = Position.Offlane, Rank = RankBracket.HeraldGuardian };
        var high = new PlayerProfile { MyPosition = Position.Offlane, Rank = RankBracket.DivineImmortal };
        var state = new DraftState(DraftPhase.DraftDetected, [], null, DateTimeOffset.UtcNow);
        // Мета по умолчанию выключена; сам расчёт проверяется с ненулевым весом.
        var o = new ScoringOptions { PoolOnly = false };
        o.SetWeight(ScoreComponent.Meta, 10);
        Assert.True(Service(o).Evaluate(Axe.Id, state, low, patch)!.Components[ScoreComponent.Meta].Value > 0);
        Assert.True(Service(o).Evaluate(Axe.Id, state, high, patch)!.Components[ScoreComponent.Meta].Value < 0);
        Assert.False(Service().Evaluate(Axe.Id, state, low, patch)!.Components.ContainsKey(ScoreComponent.Meta));
    }

    [Fact]
    public void Pool_only_picks_best_of_my_heroes_excluding_unavailable()
    {
        // Мои герои: Axe, Mars и уже выбранный союзником Picked. Axe контрит врага лучше Mars.
        var patch = Patch(
            new MatchupStats(Mars.Id, EnemyCore.Id, 2000, 900),
            new MatchupStats(Axe.Id, EnemyCore.Id, 2000, 1150),
            new MatchupStats(Sniper.Id, EnemyCore.Id, 2000, 1300));
        var profile = new PlayerProfile
        {
            MyPosition = Position.Offlane,
            Preferences = { [Mars.Id] = HeroPreference.Main, [Axe.Id] = HeroPreference.Comfort, [Picked.Id] = HeroPreference.Comfort },
        };
        var recs = Service(new ScoringOptions()).Recommend(State(), profile, patch, 10);

        Assert.Equal([Axe.Id, Mars.Id], recs.Select(r => r.Hero.Id).ToArray()); // Sniper не мой, Picked занят
    }

    [Fact]
    public void Pool_only_without_marked_heroes_uses_all_heroes()
    {
        var profile = new PlayerProfile { MyPosition = Position.Offlane };
        var recs = Service(new ScoringOptions()).Recommend(State(), profile, Patch(), 10);
        Assert.True(recs.Count > 2);
    }
}
