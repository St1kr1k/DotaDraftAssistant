namespace DraftAssistant.Domain.Player;

public enum Position
{
    Carry = 1,
    Mid = 2,
    Offlane = 3,
    SoftSupport = 4,
    HardSupport = 5,
}

public enum HeroPreference
{
    Neutral = 0,
    Main,
    Comfort,
    /// <summary>Показывать, но со штрафом.</summary>
    SoftAvoid,
    /// <summary>Не показывать вообще.</summary>
    HardAvoid,
}

/// <summary>
/// Единственное, что пользователь вводит вручную. Драфт сюда не входит.
/// </summary>
public sealed class PlayerProfile
{
    public Position MyPosition { get; set; } = Position.Offlane;
    public Position? SecondaryPosition { get; set; }
    public Dictionary<int, HeroPreference> Preferences { get; set; } = new();

    /// <summary>Ник в Dota — запасной способ найти свой слот на экране драфта, если GSI не настроен.</summary>
    public string? Nickname { get; set; }

    public HeroPreference GetPreference(int heroId) =>
        Preferences.TryGetValue(heroId, out var p) ? p : HeroPreference.Neutral;

    public int? MainHeroId =>
        Preferences.Where(kv => kv.Value == HeroPreference.Main).Select(kv => (int?)kv.Key).FirstOrDefault();

    public PlayerProfile Clone() => new()
    {
        MyPosition = MyPosition,
        SecondaryPosition = SecondaryPosition,
        Nickname = Nickname,
        Preferences = new Dictionary<int, HeroPreference>(Preferences),
    };
}
