namespace DraftAssistant.Domain.Heroes;

public enum PrimaryAttribute { Unknown, Strength, Agility, Intelligence, Universal }

public enum AttackType { Unknown, Melee, Ranged }

/// <summary>
/// Герой как доменная сущность. Изображения для распознавания сюда намеренно не входят —
/// они живут в infrastructure (data/heroes/{id}/...).
/// </summary>
public sealed record Hero(
    int Id,
    string Name,
    string LocalizedName,
    PrimaryAttribute PrimaryAttribute,
    AttackType AttackType,
    IReadOnlyList<string> Roles,
    IReadOnlyList<string> Aliases)
{
    public bool HasRole(string role) =>
        Roles.Any(r => string.Equals(r, role, StringComparison.OrdinalIgnoreCase));

    public override string ToString() => LocalizedName;
}

/// <summary>Теги ролей в том виде, в котором их отдаёт OpenDota / Valve.</summary>
public static class HeroRoleTags
{
    public const string Carry = "Carry";
    public const string Support = "Support";
    public const string Nuker = "Nuker";
    public const string Disabler = "Disabler";
    public const string Jungler = "Jungler";
    public const string Durable = "Durable";
    public const string Escape = "Escape";
    public const string Pusher = "Pusher";
    public const string Initiator = "Initiator";
}

public interface IHeroRepository
{
    IReadOnlyList<Hero> All { get; }
    Hero? Find(int heroId);
    Hero? FindByName(string internalName);
}
