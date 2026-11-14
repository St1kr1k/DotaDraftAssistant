using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace DraftAssistant.Infrastructure.Gsi;

public sealed record GsiInstallStatus(bool DotaFound, bool ConfigInstalled, string? DotaPath, string? ConfigPath);

/// <summary>
/// Установка конфига Game State Integration в один клик.
/// Это штатный механизм Valve: файл в папке cfg/gamestate_integration, который Dota читает при запуске
/// и по которому сама отправляет данные на localhost. Клиент игры не изменяется.
///
/// Папка Dota ищется так (первое найденное):
///   1. путь, выбранный пользователем вручную;
///   2. запущенный процесс dota2.exe (точнее всего — это именно та Dota, в которую играют);
///   3. библиотека Steam, где есть appmanifest_570.acf (Dota 2) и game\bin\win64\dota2.exe.
/// </summary>
public static partial class GsiInstaller
{
    public const string LaunchOption = "-gamestateintegration";
    private const string FileName = "gamestate_integration_draftassistant.cfg";

    public static string ConfigText(int port) => $$"""
        "Dota Draft Assistant"
        {
            "uri"           "http://localhost:{{port}}/"
            "timeout"       "5.0"
            "buffer"        "0.1"
            "throttle"      "0.5"
            "heartbeat"     "10.0"
            "data"
            {
                "provider"  "1"
                "map"       "1"
                "player"    "1"
                "hero"      "1"
            }
        }
        """;

    public static GsiInstallStatus Status(string? manualDotaDir = null)
    {
        var dota = FindDotaGameDir(manualDotaDir);
        if (dota is null) return new GsiInstallStatus(false, false, null, null);
        var cfg = Path.Combine(dota, "cfg", "gamestate_integration", FileName);
        return new GsiInstallStatus(true, File.Exists(cfg), dota, cfg);
    }

    /// <summary>Кладёт конфиг в папку Dota и убирает наш файл из других (ошибочно найденных) копий. Возвращает путь.</summary>
    public static string Install(int port, string? manualDotaDir = null)
    {
        var dota = FindDotaGameDir(manualDotaDir)
                   ?? throw new DirectoryNotFoundException("Папка Dota 2 не найдена. Запустите Dota или укажите папку вручную.");
        var dir = Path.Combine(dota, "cfg", "gamestate_integration");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, FileName);
        File.WriteAllText(path, ConfigText(port));

        foreach (var other in CandidateGameDirs().Where(d => !SamePath(d, dota)))
        {
            var stray = Path.Combine(other, "cfg", "gamestate_integration", FileName);
            try { if (File.Exists(stray)) File.Delete(stray); } catch (Exception) { }
        }
        return path;
    }

    /// <summary>
    /// Пользователь может указать любую папку внутри Dota (корень «dota 2 beta», game, game\dota) —
    /// приводим к …\game\dota.
    /// </summary>
    public static string? NormalizeManualDir(string? chosen)
    {
        if (string.IsNullOrWhiteSpace(chosen) || !Directory.Exists(chosen)) return null;
        foreach (var candidate in new[]
                 {
                     chosen,
                     Path.Combine(chosen, "dota"),
                     Path.Combine(chosen, "game", "dota"),
                     Path.Combine(chosen, "dota 2 beta", "game", "dota"),
                     Path.Combine(chosen, "steamapps", "common", "dota 2 beta", "game", "dota"),
                 })
        {
            if (IsDotaGameDir(candidate)) return Path.GetFullPath(candidate);
        }
        return null;
    }

    public static string? FindDotaGameDir(string? manualDotaDir = null)
    {
        if (NormalizeManualDir(manualDotaDir) is { } manual) return manual;
        if (FromRunningProcess() is { } running) return running;
        return CandidateGameDirs().FirstOrDefault();
    }

    private static bool IsDotaGameDir(string dir) =>
        Directory.Exists(Path.Combine(dir, "cfg")) &&
        File.Exists(Path.Combine(dir, "..", "bin", "win64", "dota2.exe"));

    private static string? FromRunningProcess()
    {
        foreach (var p in Process.GetProcessesByName("dota2"))
        {
            try
            {
                var exe = p.MainModule?.FileName;
                if (exe is null) continue;
                // …\dota 2 beta\game\bin\win64\dota2.exe → …\dota 2 beta\game\dota
                var dir = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(exe)!, "..", "..", "dota"));
                if (IsDotaGameDir(dir)) return dir;
            }
            catch (Exception)
            {
                // нет доступа к процессу — пробуем другие способы
            }
            finally
            {
                p.Dispose();
            }
        }
        return null;
    }

    /// <summary>Папки …\game\dota во всех библиотеках Steam, сначала те, где Dota реально установлена.</summary>
    private static IEnumerable<string> CandidateGameDirs()
    {
        var withManifest = new List<string>();
        var others = new List<string>();
        foreach (var library in SteamLibraries())
        {
            var dir = Path.Combine(library, "steamapps", "common", "dota 2 beta", "game", "dota");
            if (!IsDotaGameDir(dir)) continue;
            if (File.Exists(Path.Combine(library, "steamapps", "appmanifest_570.acf"))) withManifest.Add(dir);
            else others.Add(dir);
        }
        return withManifest.Concat(others);
    }

    /// <summary>Каталоги установки Steam (из реестра).</summary>
    public static IEnumerable<string> SteamRoots()
    {
        var roots = new List<string>();
        foreach (var (hive, key, value) in new[]
                 {
                     (Registry.CurrentUser, @"Software\Valve\Steam", "SteamPath"),
                     (Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
                     (Registry.LocalMachine, @"SOFTWARE\Valve\Steam", "InstallPath"),
                 })
        {
            try
            {
                if (hive.OpenSubKey(key)?.GetValue(value) is string p && Directory.Exists(p))
                    roots.Add(Path.GetFullPath(p.Replace('/', '\\')));
            }
            catch (Exception) { }
        }
        return roots.Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static IEnumerable<string> SteamLibraries()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in SteamRoots())
        {
            if (seen.Add(root)) yield return root;
            var vdf = Path.Combine(root, "steamapps", "libraryfolders.vdf");
            if (!File.Exists(vdf)) continue;
            string text;
            try { text = File.ReadAllText(vdf); } catch (IOException) { continue; }
            foreach (Match m in PathRegex().Matches(text))
            {
                var lib = m.Groups[1].Value.Replace(@"\\", @"\");
                if (Directory.Exists(lib) && seen.Add(lib)) yield return lib;
            }
        }
    }

    private static bool SamePath(string a, string b) =>
        string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

    [GeneratedRegex("\"path\"\\s+\"([^\"]+)\"", RegexOptions.IgnoreCase)]
    private static partial Regex PathRegex();
}
