using System.Text.Json;
using System.Text.Json.Serialization;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Infrastructure.Storage;

public sealed class JsonHeroRepository : IHeroRepository
{
    private readonly Dictionary<int, Hero> _byId;
    private readonly Dictionary<string, Hero> _byName;

    private JsonHeroRepository(IReadOnlyList<Hero> heroes)
    {
        All = heroes.OrderBy(h => h.LocalizedName, StringComparer.OrdinalIgnoreCase).ToList();
        _byId = heroes.ToDictionary(h => h.Id);
        _byName = new Dictionary<string, Hero>(StringComparer.OrdinalIgnoreCase);
        foreach (var h in heroes)
        {
            _byName[h.Name] = h;
            foreach (var a in h.Aliases) _byName.TryAdd(a, h);
        }
    }

    public IReadOnlyList<Hero> All { get; }
    public Hero? Find(int heroId) => _byId.GetValueOrDefault(heroId);
    public Hero? FindByName(string internalName) => _byName.GetValueOrDefault(internalName);

    /// <exception cref="FileNotFoundException">Данные героев ещё не скачаны DataTool'ом.</exception>
    public static JsonHeroRepository Load(string dataDir)
    {
        var path = DataFiles.HeroesJson(dataDir);
        if (!File.Exists(path))
            throw new FileNotFoundException("Нет данных героев. Запустите: DataTool fetch", path);
        var dtos = JsonSerializer.Deserialize<List<HeroDto>>(File.ReadAllText(path), DataFiles.Json) ?? [];
        return FromHeroes(dtos.Select(d => new Hero(d.Id, d.Name, d.LocalizedName, d.PrimaryAttribute, d.AttackType, d.Roles, d.Aliases)));
    }

    public static JsonHeroRepository FromHeroes(IEnumerable<Hero> heroes) => new(heroes.ToList());
}

/// <summary>LocalPatchDataProvider: читает data/patch/*.json. RemotePatchDataProvider может реализовать тот же интерфейс.</summary>
public sealed class LocalPatchDataProvider(string dataDir, IAppLog log) : IPatchDataProvider
{
    public PatchData Load()
    {
        var dir = DataFiles.PatchDir(dataDir);
        try
        {
            var meta = Read<PatchMetaDto>(Path.Combine(dir, "meta.json")) ?? new PatchMetaDto();
            var stats = Read<List<HeroStatsDto>>(Path.Combine(dir, "hero_stats.json")) ?? [];
            var matchups = Read<List<MatchupDto>>(Path.Combine(dir, "matchups.json")) ?? [];

            return new PatchData
            {
                PatchName = meta.Patch,
                FetchedAt = meta.FetchedAt,
                Source = meta.Source,
                MatchupSource = meta.MatchupSource,
                HeroStats = stats.ToDictionary(
                    s => s.HeroId,
                    s => new HeroPatchStats(s.HeroId, s.Brackets
                        .Where(b => int.TryParse(b.Key, out _))
                        .ToDictionary(b => int.Parse(b.Key), b => new BracketStats(b.Value.Picks, b.Value.Wins)))),
                Matchups = matchups
                    .GroupBy(m => (m.HeroId, m.VsHeroId))
                    .ToDictionary(g => g.Key, g => new MatchupStats(g.Key.HeroId, g.Key.VsHeroId, g.Sum(x => x.Games), g.Sum(x => x.Wins))),
            };
        }
        catch (Exception ex)
        {
            log.Error("Не удалось загрузить данные патча — рекомендации будут без Meta/Counter", ex);
            return PatchData.Empty;
        }
    }

    private static T? Read<T>(string path) =>
        File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), DataFiles.Json) : default;
}

/// <summary>settings.json и profile.json в %APPDATA%\DotaDraftAssistant.</summary>
public sealed class JsonSettingsRepository(string userDirectory) : ISettingsRepository
{
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private string SettingsPath => Path.Combine(userDirectory, "settings.json");
    private string ProfilePath => Path.Combine(userDirectory, "profile.json");

    public AppSettings LoadSettings()
    {
        var s = Read<AppSettings>(SettingsPath);
        if (s is not null) return s;
        s = new AppSettings();
        SaveSettings(s); // создаём файл с дефолтами, чтобы веса можно было править руками
        return s;
    }

    public void SaveSettings(AppSettings settings) => Write(SettingsPath, settings);

    public PlayerProfile LoadProfile() => Read<PlayerProfile>(ProfilePath) ?? new PlayerProfile();

    public void SaveProfile(PlayerProfile profile) => Write(ProfilePath, profile);

    private static T? Read<T>(string path)
    {
        if (!File.Exists(path)) return default;
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(path), Json); }
        catch (JsonException) { return default; }
    }

    private void Write<T>(string path, T value)
    {
        Directory.CreateDirectory(userDirectory);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(value, Json));
        File.Move(tmp, path, overwrite: true);
    }
}

public sealed class FileLog : IAppLog
{
    private readonly string _path;
    private readonly object _gate = new();

    public FileLog(string userDirectory)
    {
        Directory.CreateDirectory(userDirectory);
        _path = Path.Combine(userDirectory, "draft-assistant.log");
        if (File.Exists(_path) && new FileInfo(_path).Length > 5_000_000) File.Delete(_path);
    }

    public void Info(string message) => Write("INFO", message);
    public void Warn(string message) => Write("WARN", message);
    public void Error(string message, Exception? ex = null) => Write("ERROR", ex is null ? message : $"{message}: {ex}");

    private void Write(string level, string message)
    {
        lock (_gate)
        {
            try { File.AppendAllText(_path, $"{DateTimeOffset.Now:HH:mm:ss.fff} {level} {message}{Environment.NewLine}"); }
            catch (IOException) { }
        }
    }
}
