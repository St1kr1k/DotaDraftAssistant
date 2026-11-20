using System.IO.Compression;
using System.Text.Json;
using DraftAssistant.Application.Abstractions;

namespace DraftAssistant.Infrastructure.Storage;

/// <summary>
/// Скачанные пакеты данных: %APPDATA%\DotaDraftAssistant\data\&lt;время&gt;\{patch,heroes}.
///
/// Статистика патча (patch) и герои с портретами (heroes) выбираются независимо:
/// статистика — самая свежая (новее встроенной в программу), герои — только если в пакете появились новые
/// (иначе берутся встроенные: они проверены вместе с этой версией распознавания).
/// </summary>
public sealed class DataPackStore(string bundledRoot, string downloadsRoot, IAppLog log)
{
    public const string PackFile = "pack.json";

    public string BundledRoot => bundledRoot;
    public string DownloadsRoot => downloadsRoot;

    /// <summary>Папка (с подпапкой patch), из которой читать статистику.</summary>
    public string ResolvePatchRoot()
    {
        var bundled = FetchedAt(bundledRoot);
        foreach (var dir in Candidates())
            if (File.Exists(Path.Combine(DataFiles.PatchDir(dir), "meta.json")) && FetchedAt(dir) > bundled)
                return dir;
        return bundledRoot;
    }

    /// <summary>Папка (с подпапкой heroes), из которой читать героев и портреты.</summary>
    public string ResolveHeroesRoot()
    {
        var bundled = HeroIds(bundledRoot);
        foreach (var dir in Candidates())
        {
            var ids = HeroIds(dir);
            if (ids.Count > bundled.Count && ids.IsSupersetOf(bundled)) return dir;
        }
        return bundledRoot;
    }

    /// <summary>Когда собраны данные в папке: pack.json, а у старых сборок — meta.json.</summary>
    public static DateTimeOffset FetchedAt(string root)
    {
        var patch = DataFiles.PatchDir(root);
        return Read<PackMetaDto>(Path.Combine(patch, PackFile))?.FetchedAt
            ?? Read<PatchMetaDto>(Path.Combine(patch, "meta.json"))?.FetchedAt
            ?? DateTimeOffset.MinValue;
    }

    public static HashSet<int> HeroIds(string root) =>
        (Read<List<HeroDto>>(DataFiles.HeroesJson(root)) ?? []).Select(h => h.Id).ToHashSet();

    /// <summary>Убирает недокачанное и старые пакеты; используемые папки и два самых новых остаются.</summary>
    public void Cleanup(params string[] inUse)
    {
        if (!Directory.Exists(downloadsRoot)) return;
        var keep = new HashSet<string>(inUse.Select(Path.GetFullPath), StringComparer.OrdinalIgnoreCase);
        foreach (var dir in Candidates().Take(2)) keep.Add(Path.GetFullPath(dir));
        foreach (var dir in Directory.GetDirectories(downloadsRoot))
        {
            if (keep.Contains(Path.GetFullPath(dir))) continue;
            try { Directory.Delete(dir, recursive: true); }
            catch (Exception ex) { log.Warn($"Не удалось удалить старые данные {dir}: {ex.Message}"); }
        }
    }

    /// <summary>Распаковывает zip в новую папку пакета. Возвращает её путь.</summary>
    public string Install(IEnumerable<string> zips)
    {
        string name = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss");
        string target = Path.Combine(downloadsRoot, name);
        string temp = target + ".tmp";
        if (Directory.Exists(temp)) Directory.Delete(temp, recursive: true);
        Directory.CreateDirectory(temp);
        foreach (var zip in zips)
            ZipFile.ExtractToDirectory(zip, temp, overwriteFiles: true); // пути вне папки .NET не распакует
        if (Directory.Exists(target)) Directory.Delete(target, recursive: true);
        Directory.Move(temp, target);
        return target;
    }

    /// <summary>Готовые пакеты, новые первыми (имя папки — время установки).</summary>
    private IEnumerable<string> Candidates() =>
        Directory.Exists(downloadsRoot)
            ? Directory.GetDirectories(downloadsRoot)
                .Where(d => !d.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(d => Path.GetFileName(d), StringComparer.Ordinal)
            : [];

    internal static T? Read<T>(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), DataFiles.Json) : default; }
        catch (Exception) { return default; }
    }
}

/// <summary>
/// Подтягивает свежую статистику меты без обновления программы.
///
/// GitHub Actions по расписанию собирает пакет данных (чаще всего — в первые дни нового патча)
/// и кладёт его в релиз «data». Приложение при запуске и затем каждые 3 часа сравнивает его
/// с текущими данными и, если пакет новее, скачивает и подключает его.
/// </summary>
public sealed class DataPackUpdater(DataPackStore store, string repoUrl, IAppLog log)
{
    public const string MetaAsset = "data-meta.json";
    public const string PatchAsset = "data-patch.zip";
    public const string HeroesAsset = "data-heroes.zip";

    private static readonly HttpClient Http = CreateHttp();

    /// <summary>Скачана свежая статистика: (папка с patch, описание пакета).</summary>
    public event Action<string, PackMetaDto>? PatchDataUpdated;

    /// <summary>Скачаны портреты новых героев — подключатся после перезапуска.</summary>
    public event Action<string>? NewHeroesDownloaded;

    /// <param name="currentPatchRoot">Откуда сейчас читается статистика.</param>
    /// <param name="currentHeroIds">Какие герои известны программе сейчас.</param>
    public async Task RunAsync(string currentPatchRoot, IReadOnlySet<int> currentHeroIds, CancellationToken ct)
    {
        var known = new HashSet<int>(currentHeroIds);
        bool heroesDownloaded = false;
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var remote = await GetMeta(ct).ConfigureAwait(false);
                if (remote is not null)
                {
                    var current = DataPackStore.FetchedAt(currentPatchRoot);
                    bool newerStats = remote.FetchedAt > current;
                    bool newHeroes = !heroesDownloaded && remote.HeroIds.Count > 0 && !remote.HeroIds.All(known.Contains);
                    if (newerStats || newHeroes)
                    {
                        var zips = new List<string>();
                        if (newerStats) zips.Add(await Download(PatchAsset, ct).ConfigureAwait(false));
                        if (newHeroes) zips.Add(await Download(HeroesAsset, ct).ConfigureAwait(false));
                        var dir = store.Install(zips);
                        foreach (var z in zips) TryDelete(z);

                        if (newerStats)
                        {
                            if (DataPackStore.FetchedAt(dir) <= current)
                                log.Warn("Пакет данных скачан, но он не новее текущего — пропущен");
                            else
                            {
                                currentPatchRoot = dir;
                                log.Info($"Свежие данные меты: патч {remote.Patch}, собраны {remote.FetchedAt:u}");
                                PatchDataUpdated?.Invoke(dir, remote);
                            }
                        }
                        if (newHeroes)
                        {
                            heroesDownloaded = true;
                            log.Info($"Скачаны данные новых героев: {string.Join(", ", remote.HeroIds.Where(id => !known.Contains(id)))}");
                            NewHeroesDownloaded?.Invoke(dir);
                        }
                        store.Cleanup(currentPatchRoot, dir);
                    }
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { return; }
            catch (Exception ex)
            {
                log.Warn($"Обновление данных меты не удалось: {ex.Message}");
            }

            try { await Task.Delay(TimeSpan.FromHours(3), ct).ConfigureAwait(false); }
            catch (TaskCanceledException) { return; }
        }
    }

    private string AssetUrl(string asset) => $"{repoUrl.TrimEnd('/')}/releases/download/data/{asset}";

    private async Task<PackMetaDto?> GetMeta(CancellationToken ct)
    {
        using var resp = await Http.GetAsync(AssetUrl(MetaAsset), ct).ConfigureAwait(false);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return null; // пакетов ещё нет
        resp.EnsureSuccessStatusCode();
        var json = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        return JsonSerializer.Deserialize<PackMetaDto>(json, DataFiles.Json);
    }

    private async Task<string> Download(string asset, CancellationToken ct)
    {
        var path = Path.Combine(Path.GetTempPath(), $"dda_{Guid.NewGuid():N}_{asset}");
        using var resp = await Http.GetAsync(AssetUrl(asset), HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        await using (var file = File.Create(path))
            await resp.Content.CopyToAsync(file, ct).ConfigureAwait(false);
        return path;
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (Exception) { /* временный файл — не страшно */ }
    }

    private static HttpClient CreateHttp()
    {
        var http = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("DotaDraftAssistant");
        return http;
    }
}
