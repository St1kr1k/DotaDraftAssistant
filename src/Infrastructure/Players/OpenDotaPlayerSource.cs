using System.Net.Http.Json;
using System.Text.Json.Nodes;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Infrastructure.Vision;

namespace DraftAssistant.Infrastructure.Players;

/// <summary>
/// Открытая статистика игрока на OpenDota: поиск по нику и самые частые герои за последние 90 дней.
/// Только публичные данные (игроки со скрытой историей матчей не находятся). Ключ не нужен.
/// </summary>
public sealed class OpenDotaPlayerSource : IPlayerHeroSource, IDisposable
{
    private const string Api = "https://api.opendota.com/api";
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(15) };

    public OpenDotaPlayerSource() => _http.DefaultRequestHeaders.UserAgent.ParseAdd("DotaDraftAssistant");

    public async Task<PlayerHeroes?> FindAsync(string nickname, CancellationToken ct)
    {
        // Ник с экрана может быть обрезан («лапаухий[50…») — ищем по началу без тега и многоточия.
        var query = nickname.Split('[')[0].TrimEnd('.', '…', ' ');
        if (DraftTextParsing.NormalizeName(query).Length < 3) return null;

        var found = await _http.GetFromJsonAsync<JsonArray>($"{Api}/search?q={Uri.EscapeDataString(query)}", ct).ConfigureAwait(false);
        if (found is null) return null;

        // Из совпадающих по нику — тот, кто играл последним (он сейчас в этой катке).
        var best = found.OfType<JsonObject>()
            .Select(o => (Id: Long(o["account_id"]), Name: o["personaname"]?.ToString() ?? "", Last: Date(o["last_match_time"])))
            .Where(c => c.Id > 0 && DraftTextParsing.NameMatches(nickname, c.Name))
            .OrderByDescending(c => c.Last)
            .FirstOrDefault();
        if (best.Id <= 0 || best.Last < DateTimeOffset.UtcNow.AddDays(-30)) return null;

        var heroes = await _http.GetFromJsonAsync<JsonArray>($"{Api}/players/{best.Id}/heroes?date=90", ct).ConfigureAwait(false);
        if (heroes is null) return null;
        var list = heroes.OfType<JsonObject>()
            .Select(h => (HeroId: (int)Long(h["hero_id"]), Games: (int)Long(h["games"])))
            .Where(h => h.HeroId > 0 && h.Games > 0)
            .OrderByDescending(h => h.Games)
            .ToList();
        int total = list.Sum(h => h.Games);
        return total == 0 ? null : new PlayerHeroes(best.Id, best.Name, list, total);
    }

    private static long Long(JsonNode? n) => n switch
    {
        JsonValue v when v.TryGetValue<long>(out var l) => l,
        JsonValue v when v.TryGetValue<int>(out var i) => i,
        JsonValue v when v.TryGetValue<string>(out var s) && long.TryParse(s, out var p) => p,
        _ => 0,
    };

    private static DateTimeOffset Date(JsonNode? n) =>
        n is JsonValue v && v.TryGetValue<string>(out var s) && DateTimeOffset.TryParse(s, out var d) ? d : DateTimeOffset.MinValue;

    public void Dispose() => _http.Dispose();
}
