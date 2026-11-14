using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace DraftAssistant.Infrastructure.Gsi;

public sealed record GsiInstallStatus(bool DotaFound, bool ConfigInstalled, string? DotaPath, string? ConfigPath);

/// <summary>
/// Установка конфига Game State Integration в один клик.
/// Это штатный механизм Valve: файл в папке cfg/gamestate_integration, который Dota читает при запуске
/// и по которому сама отправляет данные на localhost. Клиент игры не изменяется.
/// Параметр запуска -gamestateintegration пользователь добавляет в Steam сам — приложение
/// не правит настройки Steam.
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

    public static GsiInstallStatus Status()
    {
        var dota = FindDotaGameDir();
        if (dota is null) return new GsiInstallStatus(false, false, null, null);
        var cfg = Path.Combine(dota, "cfg", "gamestate_integration", FileName);
        return new GsiInstallStatus(true, File.Exists(cfg), dota, cfg);
    }

    /// <summary>Кладёт конфиг в папку Dota. Возвращает путь к файлу.</summary>
    public static string Install(int port)
    {
        var dota = FindDotaGameDir() ?? throw new DirectoryNotFoundException("Папка Dota 2 не найдена в библиотеках Steam.");
        var dir = Path.Combine(dota, "cfg", "gamestate_integration");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, FileName);
        File.WriteAllText(path, ConfigText(port));
        return path;
    }

    /// <summary>…\steamapps\common\dota 2 beta\game\dota во всех библиотеках Steam.</summary>
    public static string? FindDotaGameDir()
    {
        foreach (var library in SteamLibraries())
        {
            var dir = Path.Combine(library, "steamapps", "common", "dota 2 beta", "game", "dota");
            if (Directory.Exists(dir)) return dir;
        }
        return null;
    }

    private static IEnumerable<string> SteamLibraries()
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
        roots.Add(@"C:\Program Files (x86)\Steam");

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in roots)
        {
            if (seen.Add(root)) yield return root;
            var vdf = Path.Combine(root, "steamapps", "libraryfolders.vdf");
            if (!File.Exists(vdf)) continue;
            string text;
            try { text = File.ReadAllText(vdf); } catch (IOException) { continue; }
            foreach (Match m in PathRegex().Matches(text))
            {
                var lib = m.Groups[1].Value.Replace(@"\\", @"\");
                if (seen.Add(lib)) yield return lib;
            }
        }
    }

    [GeneratedRegex("\"path\"\\s+\"([^\"]+)\"", RegexOptions.IgnoreCase)]
    private static partial Regex PathRegex();
}
