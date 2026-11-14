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

/// <summary>
/// LocalPatchDataProvider: читает data/patch/*.json и объединяет источники.
///
/// Источники (OpenDota, STRATZ, …) берут одни и те же матчи Dota, поэтому игры не складываются:
/// винрейт и доля позиции считаются как среднее, взвешенное по надёжности источника и размеру его выборки.
/// Agreement показывает, согласны ли источники; при расхождении компонент оценки получает меньшую уверенность.
/// </summary>
public sealed class LocalPatchDataProvider(string dataDir, IAppLog log) : IPatchDataProvider
{
    /// <summary>Насколько доверяем источнику (позиции у STRATZ точные, у OpenDota — разделение линий по ролям героя).</summary>
    private static double Reliability(string? source) => (source ?? "opendota").ToLowerInvariant() switch
    {
        var s when s.StartsWith("stratz") => 1.0,
        "opendota-lanes" => 0.6,
        _ => 0.8,
    };

    public PatchData Load(RankBracket rank)
    {
        var dir = DataFiles.PatchDir(dataDir);
        // Данные STRATZ лежат по группам рангов: stratz_matchups_LEGEND_ANCIENT.json и т.д.
        // Старые файлы без ранга (Legend–Immortal) используются, если файла для ранга нет.
        string S(string kind)
        {
            var ranked = $"stratz_{kind}_{RankBrackets.Stratz(rank)}.json";
            return File.Exists(Path.Combine(dir, ranked)) ? ranked : $"stratz_{kind}.json";
        }
        try
        {
            var meta = Read<PatchMetaDto>(Path.Combine(dir, "meta.json")) ?? new PatchMetaDto();
            var stratz = Read<StratzMetaDto>(Path.Combine(dir, "stratz_meta.json")) ?? new StratzMetaDto();
            var stats = Read<List<HeroStatsDto>>(Path.Combine(dir, "hero_stats.json")) ?? [];
            // Один вид данных из нескольких источников: файлы читаются вместе и объединяются ниже.
            var matchups = ReadAll<MatchupDto>(dir, "matchups.json", S("matchups"));
            var positions = ReadAll<PositionDto>(dir, "positions.json", S("positions"));
            var pairs = ReadAll<PairDto>(dir, "pairs.json", S("pairs"));
            var lanes = ReadAll<LaneDto>(dir, S("lanes"));
            // Строки без источника — из старых файлов OpenDota.
            foreach (var m in matchups.Where(m => string.IsNullOrEmpty(m.Source))) m.Source = "opendota";

            return new PatchData
            {
                PatchName = meta.Patch,
                Rank = rank,
                FetchedAt = meta.FetchedAt,
                Source = meta.Source,
                MatchupSource = Join(meta.MatchupSource, stratz.MatchupSource),
                PositionSource = Join(meta.PositionSource, stratz.PositionSource),
                PairSource = Join(meta.PairSource, stratz.PairSource),
                LaneSource = Join("", stratz.LaneSource),
                Lanes = lanes.GroupBy(l => (l.HeroId, l.VsHeroId)).ToDictionary(g => g.Key, g =>
                {
                    var l = g.First();
                    return new LaneStats(l.HeroId, l.VsHeroId, l.Games, l.Wins, l.Draws, l.Losses);
                }),
                HeroStats = stats.ToDictionary(
                    s => s.HeroId,
                    s => new HeroPatchStats(s.HeroId, s.Brackets
                        .Where(b => int.TryParse(b.Key, out _))
                        .ToDictionary(b => int.Parse(b.Key), b => new BracketStats(b.Value.Picks, b.Value.Wins)))),
                Matchups = MergeMatchups(matchups),
                Positions = MergePositions(positions),
                Pairs = pairs.GroupBy(p => (p.HeroId, p.AllyId))
                    .ToDictionary(g => g.Key, g =>
                    {
                        var (games, wins, _) = Merge(g.Select(x => (x.Games, x.Wins, (string?)x.Source)));
                        return new PairStats(g.Key.HeroId, g.Key.AllyId, games, wins);
                    }),
            };
        }
        catch (Exception ex)
        {
            log.Error("Не удалось загрузить данные патча — рекомендации будут без Meta/Counter", ex);
            return PatchData.Empty;
        }
    }

    private static Dictionary<(int Hero, int Vs), MatchupStats> MergeMatchups(List<MatchupDto> rows) =>
        rows.GroupBy(m => (m.HeroId, m.VsHeroId))
            .ToDictionary(g => g.Key, g =>
            {
                var (games, wins, agreement) = Merge(g.Select(x => (x.Games, x.Wins, (string?)x.Source)));
                return new MatchupStats(g.Key.HeroId, g.Key.VsHeroId, games, wins, agreement);
            });

    private static Dictionary<(int Hero, Position Position), PositionStats> MergePositions(List<PositionDto> rows)
    {
        // Доля позиции считается внутри каждого источника (игры на позиции / все игры героя в этом источнике).
        var totals = rows.GroupBy(r => (r.HeroId, r.Source)).ToDictionary(g => g.Key, g => g.Sum(r => r.Games));
        var result = new Dictionary<(int, Position), PositionStats>();
        foreach (var g in rows.Where(r => r.Position is >= 1 and <= 5).GroupBy(r => (r.HeroId, Pos: (Position)r.Position)))
        {
            double wShare = 0, share = 0;
            foreach (var r in g)
            {
                int total = totals.GetValueOrDefault((r.HeroId, r.Source));
                if (total <= 0) continue;
                double w = Reliability(r.Source) * total / (total + 300.0);
                share += w * r.Games / total;
                wShare += w;
            }
            var (games, wins, agreement) = Merge(g.Select(x => (x.Games, x.Wins, (string?)x.Source)));
            result[(g.Key.HeroId, g.Key.Pos)] = new PositionStats(
                g.Key.HeroId, g.Key.Pos, games, wins,
                wShare > 0 ? share / wShare : 0,
                agreement,
                string.Join("+", g.Select(x => x.Source).Distinct()));
        }
        return result;
    }

    /// <summary>
    /// Объединение строк разных источников по одной сущности.
    /// Games — максимум по источникам (не сумма: матчи общие), Wins — по взвешенному винрейту.
    /// Agreement: один источник — его надёжность; несколько — 1, уменьшается при расхождении винрейтов (5% разницы → 0.4).
    /// </summary>
    internal static (int Games, int Wins, double Agreement) Merge(IEnumerable<(int Games, int Wins, string? Source)> rows)
    {
        var list = rows.Where(r => r.Games > 0).ToList();
        if (list.Count == 0) return (0, 0, 0);
        if (list.Count == 1) return (list[0].Games, list[0].Wins, Reliability(list[0].Source));

        double wSum = 0, wrSum = 0;
        foreach (var r in list)
        {
            double w = Reliability(r.Source) * r.Games / (r.Games + 300.0);
            wrSum += w * r.Wins / r.Games;
            wSum += w;
        }
        double wr = wrSum / wSum;
        double spread = list.Max(r => (double)r.Wins / r.Games) - list.Min(r => (double)r.Wins / r.Games);
        double agreement = 1 - Math.Clamp(spread / 0.05, 0, 1) * 0.6;
        int games = list.Max(r => r.Games);
        return (games, (int)Math.Round(wr * games), agreement);
    }

    private static string Join(params string?[] sources)
    {
        var parts = sources.Where(s => !string.IsNullOrWhiteSpace(s)).ToList();
        return parts.Count > 0 ? string.Join(" + ", parts) : "none";
    }

    private static List<T> ReadAll<T>(string dir, params string[] files) =>
        files.SelectMany(f => Read<List<T>>(Path.Combine(dir, f)) ?? []).ToList();

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
