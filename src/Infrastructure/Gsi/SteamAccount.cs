using System.Text.RegularExpressions;

namespace DraftAssistant.Infrastructure.Gsi;

/// <summary>
/// Имя текущего пользователя Steam (его видно над слотом в драфте Dota).
/// Читается из Steam\config\loginusers.vdf — аккаунт с MostRecent = 1.
/// Это обычный конфиг Steam на диске, ни Steam, ни Dota не затрагиваются.
/// </summary>
public static partial class SteamAccount
{
    public static string? CurrentPersonaName()
    {
        foreach (var root in GsiInstaller.SteamRoots())
        {
            var path = Path.Combine(root, "config", "loginusers.vdf");
            if (!File.Exists(path)) continue;
            string text;
            try { text = File.ReadAllText(path); } catch (IOException) { continue; }

            string? fallback = null;
            foreach (Match user in UserBlock().Matches(text))
            {
                var body = user.Groups[1].Value;
                var name = Field(body, "PersonaName");
                if (name is null) continue;
                fallback ??= name;
                if (Field(body, "MostRecent") == "1") return name;
            }
            if (fallback is not null) return fallback;
        }
        return null;
    }

    private static string? Field(string body, string key)
    {
        var m = Regex.Match(body, $"\"{key}\"\\s+\"([^\"]*)\"", RegexOptions.IgnoreCase);
        return m.Success ? m.Groups[1].Value : null;
    }

    // "7656119...." { ... }  — блок одного аккаунта (без вложенных фигурных скобок).
    [GeneratedRegex("\"\\d{5,}\"\\s*\\{([^{}]*)\\}")]
    private static partial Regex UserBlock();
}
