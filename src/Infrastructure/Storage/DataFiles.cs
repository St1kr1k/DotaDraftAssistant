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
