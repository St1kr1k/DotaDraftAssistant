namespace DraftAssistant.Domain.Player;

/// <summary>Группа рангов, по которой берётся статистика (мета на разных рангах разная).</summary>
public enum RankBracket
{
    HeraldGuardian = 1,
    CrusaderArchon = 2,
    LegendAncient = 3,
    DivineImmortal = 4,
}

public static class RankBrackets
{
    public static IReadOnlyList<RankBracket> All { get; } =
        [RankBracket.HeraldGuardian, RankBracket.CrusaderArchon, RankBracket.LegendAncient, RankBracket.DivineImmortal];

    /// <summary>Бракеты OpenDota (1 Herald … 8 Immortal).</summary>
    public static IReadOnlyList<int> OpenDota(RankBracket rank) => rank switch
    {
        RankBracket.HeraldGuardian => [1, 2],
        RankBracket.CrusaderArchon => [3, 4],
        RankBracket.DivineImmortal => [7, 8],
        _ => [5, 6],
    };

    /// <summary>Имя в STRATZ API (RankBracketBasicEnum) — оно же часть имени файла данных.</summary>
    public static string Stratz(RankBracket rank) => rank switch
    {
        RankBracket.HeraldGuardian => "HERALD_GUARDIAN",
        RankBracket.CrusaderArchon => "CRUSADER_ARCHON",
        RankBracket.DivineImmortal => "DIVINE_IMMORTAL",
        _ => "LEGEND_ANCIENT",
    };

    public static string Title(RankBracket rank) => rank switch
    {
        RankBracket.HeraldGuardian => "Herald – Guardian",
        RankBracket.CrusaderArchon => "Crusader – Archon",
        RankBracket.DivineImmortal => "Divine – Immortal",
        _ => "Legend – Ancient",
    };
}
