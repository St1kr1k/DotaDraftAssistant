using DraftAssistant.Application.Recommendation.Evaluators;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Roles;

namespace DraftAssistant.Application.Plan;

/// <summary>Враг в плане: почему он опасен (или лёгкая цель) и что с этим делать.</summary>
public sealed record PlanEnemy(Hero Hero, IReadOnlyList<string> Reasons, IReadOnlyList<string> Tips);

/// <summary>План на игру после вашего пика. Всё — из статистики и свойств способностей, без выдуманных советов.</summary>
public sealed record GamePlan(
    Hero MyHero,
    Position Position,
    IReadOnlyList<StartItem> StartItems,
    string? LaneAdvice,
    IReadOnlyList<PlanEnemy> Threats,
    IReadOnlyList<PlanEnemy> Targets,
    IReadOnlyList<string> ItemTips,
    string Basis);

public sealed class GamePlanService(IRoleInferenceService roles)
{
    private const int MatchupPrior = 40;

    public GamePlan Build(Hero me, Position position, IReadOnlyList<Hero> enemies, PatchData patch, RankBracket rank)
    {
        var laneOpponents = LaneEvaluator.Opponents(position);
        var (avgKills, avgDeaths) = AverageKda(me.Id, patch);

        var rated = new List<(Hero Enemy, double Threat, double Target, List<(string Text, bool Bad)> Reasons, bool OnLane, double? Lane)>();
        foreach (var e in enemies)
        {
            var reasons = new List<(string Text, bool Bad)>();
            double threat = 0, target = 0;

            var m = patch.GetMatchup(me.Id, e.Id);
            if (m is { Games: > 0 })
            {
                double wr = (m.Wins + 0.5 * MatchupPrior) / (m.Games + (double)MatchupPrior);
                double adv = wr - 0.5;
                threat += -adv / 0.04;
                target += adv / 0.04;
                if (Math.Abs(adv) >= 0.015) reasons.Add(($"вы выигрываете {wr:P0} игр против него", adv < 0));
            }

            bool onLane = laneOpponents.Sum(p => roles.Infer(e)[p]) >= 0.4;
            double? laneScore = null;
            var lane = patch.GetLane(me.Id, e.Id);
            if (onLane && lane is { Games: >= 30 })
            {
                laneScore = (lane.Score * lane.Games + 0.5 * MatchupPrior) / (lane.Games + (double)MatchupPrior);
                double d = (laneScore.Value - 0.5) / 0.08;
                threat += -d;
                target += d;
                if (Math.Abs(laneScore.Value - 0.5) >= 0.03) reasons.Add(($"линию против него выигрываете в {laneScore:P0} случаев", laneScore < 0.5));
            }

            if (patch.Kda.TryGetValue((me.Id, e.Id), out var kda) && kda.Games >= 100 && avgDeaths > 0 && avgKills > 0)
            {
                double deathRatio = kda.DeathsPerGame / avgDeaths;
                double killRatio = kda.KillsPerGame / avgKills;
                threat += (deathRatio - 1) * 4;
                target += (killRatio - 1) * 4 + (1 - deathRatio) * 2;
                if (deathRatio >= 1.08)
                    reasons.Add(($"против него вы умираете чаще: {kda.DeathsPerGame:F1} за игру (обычно {avgDeaths:F1})", true));
                if (killRatio >= 1.08)
                    reasons.Add(($"против него у вас больше убийств: {kda.KillsPerGame:F1} за игру (обычно {avgKills:F1})", false));
            }
            rated.Add((e, threat, target, reasons, onLane, laneScore));
        }

        var threats = rated.Where(r => r.Threat >= 0.6).OrderByDescending(r => r.Threat).Take(3)
            .Select(r => new PlanEnemy(r.Enemy, Pick(r.Reasons, threat: true), ThreatTips(me, r.Enemy, patch, r.OnLane && r.Lane < 0.47)))
            .ToList();
        var threatIds = threats.Select(t => t.Hero.Id).ToHashSet();
        var targets = rated.Where(r => r.Target >= 0.6 && !threatIds.Contains(r.Enemy.Id)).OrderByDescending(r => r.Target).Take(2)
            .Select(r => new PlanEnemy(r.Enemy, Pick(r.Reasons, threat: false), TargetTips(r.Enemy, r.OnLane && r.Lane > 0.53)))
            .ToList();

        string? laneAdvice = null;
        var laneRated = rated.Where(r => r.Lane is not null).ToList();
        if (laneRated.Count > 0)
        {
            var worst = laneRated.MinBy(r => r.Lane!.Value);
            var best = laneRated.MaxBy(r => r.Lane!.Value);
            if (worst.Lane <= 0.46)
                laneAdvice = $"Тяжёлая линия против {worst.Enemy.LocalizedName}: не размениваться, добивать осторожно, звать саппорта.";
            else if (best.Lane >= 0.54)
                laneAdvice = $"Линия в вашу пользу против {best.Enemy.LocalizedName}: давите с первых минут.";
        }

        return new GamePlan(me, position,
            patch.StartItems.TryGetValue((me.Id, position), out var start) ? start : [],
            laneAdvice, threats, targets, ItemTips(enemies, patch),
            $"STRATZ, {RankBrackets.Title(rank)}, патч {patch.PatchName}");
    }

    /// <summary>Причины угрозы — только отрицательные, причины цели — только положительные.</summary>
    private static List<string> Pick(List<(string Text, bool Bad)> reasons, bool threat) =>
        reasons.Where(r => r.Bad == threat).Select(r => r.Text).Take(2).ToList();

    private static (double Kills, double Deaths) AverageKda(int heroId, PatchData patch)
    {
        double games = 0, kills = 0, deaths = 0;
        foreach (var k in patch.Kda.Values)
        {
            if (k.HeroId != heroId) continue;
            games += k.Games; kills += k.KillsPerGame * k.Games; deaths += k.DeathsPerGame * k.Games;
        }
        return games > 0 ? (kills / games, deaths / games) : (0, 0);
    }

    private static List<string> ThreatTips(Hero me, Hero enemy, PatchData patch, bool hardLane)
    {
        var tips = new List<string>();
        var abilities = patch.AbilitiesOf(enemy.Id);
        var pierce = abilities.Where(a => a.PiercesBkb).Select(a => a.Name).Take(2).ToList();
        if (pierce.Count > 0) tips.Add($"{string.Join(" и ", pierce)} — сквозь BKB, она не спасёт");
        var invis = abilities.FirstOrDefault(a => a.Invisibility);
        if (invis is not null) tips.Add($"{invis.Name}: невидимость — держите Dust / Sentry Ward");
        if (enemy.HasRole(HeroRoleTags.Disabler) && !me.HasRole(HeroRoleTags.Escape))
            tips.Add("у него есть контроль, а у вас нет побега — не ходите по карте в одиночку");
        if (enemy.HasRole(HeroRoleTags.Initiator))
            tips.Add("начинает драки — прежде чем лезть, проверьте, где он");
        if (hardLane) tips.Add("на линии не размениваться, держаться ближе к своей вышке");
        return tips.Take(2).ToList();
    }

    private static List<string> TargetTips(Hero enemy, bool easyLane)
    {
        var tips = new List<string>();
        if (!enemy.HasRole(HeroRoleTags.Escape)) tips.Add("нет способностей для побега — ловите в контроль");
        if (!enemy.HasRole(HeroRoleTags.Durable) && enemy.HasRole(HeroRoleTags.Support)) tips.Add("хрупкий — начинайте драку с него");
        if (easyLane) tips.Add("давите его на линии, пока он не нафармился");
        return tips.Take(2).ToList();
    }

    private static List<string> ItemTips(IReadOnlyList<Hero> enemies, PatchData patch)
    {
        var tips = new List<string>();
        int magicHeroes = enemies.Count(e => patch.AbilitiesOf(e.Id).Count(a => a.DamageType == "Magical") >= 2);
        int physicalCores = enemies.Count(e => e.HasRole(HeroRoleTags.Carry) &&
                                               patch.AbilitiesOf(e.Id).Count(a => a.DamageType == "Magical") < 2);
        if (magicHeroes >= 3)
            tips.Add("Много магического урона — пригодятся BKB, Pipe of Insight, Glimmer Cape.");
        else if (physicalCores >= 2)
            tips.Add("Много физического урона — пригодятся броня и Ghost Scepter.");

        var invis = enemies.Where(e => patch.AbilitiesOf(e.Id).Any(a => a.Invisibility)).Select(e => e.LocalizedName).ToList();
        if (invis.Count > 0) tips.Add($"Невидимость у {string.Join(", ", invis)} — нужны Dust и Sentry Ward.");

        var pierce = enemies.SelectMany(e => patch.AbilitiesOf(e.Id).Where(a => a.PiercesBkb)).Select(a => a.Name).Distinct().Take(3).ToList();
        if (pierce.Count > 0) tips.Add($"Не полагайтесь только на BKB: {string.Join(", ", pierce)} проходят сквозь неё.");

        var strong = enemies.SelectMany(e => patch.AbilitiesOf(e.Id)
                .Where(a => a.Dispellable.StartsWith("Strong", StringComparison.OrdinalIgnoreCase)))
            .Select(a => a.Name).Distinct().Take(2).ToList();
        if (strong.Count > 0) tips.Add($"{string.Join(", ", strong)} снимаются только сильным диспелом — Manta и Eul's не помогут.");

        return tips.Take(4).ToList();
    }
}
