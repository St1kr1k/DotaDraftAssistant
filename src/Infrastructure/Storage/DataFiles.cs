using System.Text.Json;
using System.Text.Json.Serialization;
using DraftAssistant.Domain.Heroes;

namespace DraftAssistant.Infrastructure.Storage;

/// <summary>Форматы локальных файлов данных (их пишет DataTool, читает приложение).</summary>
public static class DataFiles
{
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static string HeroesJson(string dataDir) => Path.Combine(dataDir, "heroes", "heroes.json");
    public static string HeroesDir(string dataDir) => Path.Combine(dataDir, "heroes");
    public static string PatchDir(string dataDir) => Path.Combine(dataDir, "patch");
}

public sealed class HeroDto
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string LocalizedName { get; set; } = "";
    public PrimaryAttribute PrimaryAttribute { get; set; }
    public AttackType AttackType { get; set; }
    public List<string> Roles { get; set; } = [];
    public List<string> Aliases { get; set; } = [];
}

public sealed class PatchMetaDto
{
    public string Patch { get; set; } = "unknown";
    public DateTimeOffset FetchedAt { get; set; }
    public string Source { get; set; } = "";
    public string MatchupSource { get; set; } = "";
    public string PositionSource { get; set; } = "";
    public string PairSource { get; set; } = "";
}

public sealed class ItemDto
{
    public int Id { get; set; }
    public string Key { get; set; } = "";
    public string Name { get; set; } = "";
    public int Cost { get; set; }
}

public sealed class AbilityDto
{
    public string Key { get; set; } = "";
    public string Name { get; set; } = "";
    public string DamageType { get; set; } = "";
    public bool PiercesBkb { get; set; }
    public string Dispellable { get; set; } = "";
    public bool Invisibility { get; set; }
}

public sealed class HeroAbilitiesDto
{
    public int HeroId { get; set; }
    public List<AbilityDto> Abilities { get; set; } = [];
}

/// <summary>Стартовая закупка: сколько игр (Games) из игр героя на позиции (PositionGames) брали Instance-й экземпляр предмета.</summary>
public sealed class StartItemDto
{
    public int HeroId { get; set; }
    public int Position { get; set; }
    public int ItemId { get; set; }
    public int Instance { get; set; }
    public int Games { get; set; }
    public int PositionGames { get; set; }
}

public sealed class LaneDto
{
    public int HeroId { get; set; }
    public int VsHeroId { get; set; }
    public int Games { get; set; }
    public int Wins { get; set; }
    public int Draws { get; set; }
    public int Losses { get; set; }
    public string Source { get; set; } = "";
}

/// <summary>Описание данных STRATZ (stratz_meta.json): пустая строка — этот вид данных не получен.</summary>
public sealed class StratzMetaDto
{
    public DateTimeOffset FetchedAt { get; set; }
    public string PositionSource { get; set; } = "";
    public string MatchupSource { get; set; } = "";
    public string PairSource { get; set; } = "";
    public string LaneSource { get; set; } = "";
    /// <summary>Текущая версия игры по STRATZ (например 7.41f), если винрейты взяты по патчу.</summary>
    public string GameVersion { get; set; } = "";
    /// <summary>Откуда винрейты героев (hero_stats.json): пусто — OpenDota.</summary>
    public string HeroStatsSource { get; set; } = "";
}

public sealed class HeroStatsDto
{
    public int HeroId { get; set; }
    public Dictionary<string, BracketDto> Brackets { get; set; } = new();
}

public sealed class BracketDto
{
    public int Picks { get; set; }
    public int Wins { get; set; }
}

public sealed class MatchupDto
{
    public int HeroId { get; set; }
    public int VsHeroId { get; set; }
    public int Games { get; set; }
    public int Wins { get; set; }
    /// <summary>Источник: "opendota", "stratz", … (пусто — opendota, старый формат).</summary>
    public string? Source { get; set; }
    /// <summary>Среднее за игру у HeroId в играх против VsHeroId (STRATZ), если известно.</summary>
    public double? KillsPerGame { get; set; }
    public double? DeathsPerGame { get; set; }
}

/// <summary>Игры героя на позиции 1..5 по одному источнику.</summary>
public sealed class PositionDto
{
    public int HeroId { get; set; }
    public int Position { get; set; }
    public int Games { get; set; }
    public int Wins { get; set; }
    public string Source { get; set; } = "";
}

/// <summary>Игры двух героев в одной команде по одному источнику.</summary>
public sealed class PairDto
{
    public int HeroId { get; set; }
    public int AllyId { get; set; }
    public int Games { get; set; }
    public int Wins { get; set; }
    public string Source { get; set; } = "";
}

/// <summary>
/// Описание пакета данных (patch/pack.json и data-meta.json в релизе «data»).
/// Пакет собирается в GitHub Actions по расписанию и скачивается приложением без выпуска новой версии.
/// </summary>
public sealed class PackMetaDto
{
    /// <summary>Патч, по которому собрана статистика.</summary>
    public string Patch { get; set; } = "unknown";
    /// <summary>Когда собран пакет: приложение берёт пакет, если он новее своих данных.</summary>
    public DateTimeOffset FetchedAt { get; set; }
    /// <summary>Когда этот патч впервые попал в пакет (свежий патч — данные обновляются чаще).</summary>
    public DateTimeOffset PatchSince { get; set; }
    /// <summary>Герои в пакете: если появились новые — нужны портреты (data-heroes.zip).</summary>
    public List<int> HeroIds { get; set; } = [];
}
