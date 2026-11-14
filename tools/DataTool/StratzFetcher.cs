using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Infrastructure.Storage;

namespace DraftAssistant.DataTool;

/// <summary>
/// Общая статистика STRATZ (GraphQL) отдельно для каждой группы рангов (файлы *_LEGEND_ANCIENT.json и т.п.):
///   stratz_positions.json — игры и победы героя на каждой позиции (точные pos 1–5);
///   stratz_matchups.json  — героя против героя;
///   stratz_pairs.json     — героя вместе с героем;
///   stratz_lanes.json     — исходы линии против героя (победа / ничья / поражение на линии).
/// Личная статистика не запрашивается. Токен — только из переменной окружения STRATZ_TOKEN.
///
/// Перед сохранением проверяется смысл чисел: A против B и B против A должны давать в сумме ~100%.
/// Если проверка не проходит, этот вид данных не сохраняется (лучше без него, чем с перевёрнутыми числами).
/// </summary>
internal static class StratzFetcher
{
    private const string Url = "https://api.stratz.com/graphql";
    private const int HeroesPerRequest = 6;

    public static async Task<int> Run(Dictionary<string, string> o)
    {
        var token = Environment.GetEnvironmentVariable("STRATZ_TOKEN");
        if (string.IsNullOrWhiteSpace(token))
        {
            Console.WriteLine("STRATZ_TOKEN не задан — пропускаю STRATZ");
            return 0;
        }

        var dataDir = Path.GetFullPath(o.TryGetValue("out", out var d) ? d : "data");
        var patchDir = DataFiles.PatchDir(dataDir);
        Directory.CreateDirectory(patchDir);
        var heroIds = JsonHeroRepository.Load(dataDir).All.Select(h => h.Id).OrderBy(i => i).ToList();
        if (heroIds.Count == 0) throw new InvalidOperationException("нет списка героев — сначала fetch");

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(90) };
        http.DefaultRequestHeaders.Add("Authorization", $"Bearer {token}");
        http.DefaultRequestHeaders.UserAgent.ParseAdd("STRATZ_API");

        var meta = new StratzMetaDto { FetchedAt = DateTimeOffset.UtcNow };
        foreach (var rank in RankBrackets.All)
        {
            Console.WriteLine($"--- {RankBrackets.Title(rank)} ---");
            await FetchBracket(http, heroIds, patchDir, RankBrackets.Stratz(rank), meta);
        }
        await Save(patchDir, "stratz_meta.json", meta);
        return 0;
    }

    private static async Task FetchBracket(HttpClient http, List<int> heroIds, string patchDir, string bracket, StratzMetaDto meta)
    {
        string Brackets = $"[{bracket}]";
        string F(string kind) => $"stratz_{kind}_{bracket}.json";

        // 1. Позиции — один запрос на всех героев.
        try
        {
            var data = await Query(http, $$"""
                { heroStats { stats(bracketBasicIds: {{Brackets}}, groupByPosition: true) { heroId position matchCount winCount } } }
                """);
            var rows = (data?["heroStats"]?["stats"] as JsonArray ?? [])
                .OfType<JsonObject>()
                .Select(r => (Hero: Int(r["heroId"]), Pos: PositionOf(r["position"]), Games: Int(r["matchCount"]), Wins: Int(r["winCount"])))
                .Where(r => r.Pos is >= 1 and <= 5 && r.Games > 0)
                .GroupBy(r => (r.Hero, r.Pos))
                .Select(g => new PositionDto { HeroId = g.Key.Hero, Position = g.Key.Pos, Games = g.Sum(x => x.Games), Wins = g.Sum(x => x.Wins), Source = "stratz" })
                .ToList();
            Console.WriteLine($"STRATZ позиции: {rows.Count} строк, героев {rows.Select(r => r.HeroId).Distinct().Count()}");
            if (rows.Select(r => r.HeroId).Distinct().Count() >= heroIds.Count / 2)
            {
                await Save(patchDir, F("positions"), rows);
                meta.PositionSource = "STRATZ (позиции 1–5, по рангам)";
            }
        }
        catch (Exception ex) { Console.Error.WriteLine($"STRATZ позиции не получены: {ex.Message}"); }

        // 2. С кем / против кого и 3. исходы линий — пачками героев в одном запросе (алиасы GraphQL).
        var matchups = new List<MatchupDto>();
        var pairs = new List<PairDto>();
        var lanes = new List<LaneDto>();
        foreach (var chunk in heroIds.Chunk(HeroesPerRequest))
        {
            var sb = new StringBuilder("{ heroStats {");
            foreach (var id in chunk)
            {
                sb.Append($" m{id}: matchUp(heroId: {id}, bracketBasicIds: {Brackets}, take: 200) {{ heroId vs {{ heroId1 heroId2 matchCount winCount }} with {{ heroId1 heroId2 matchCount winCount }} }}");
                sb.Append($" l{id}: laneOutcome(heroId: {id}, isWith: false, bracketBasicIds: {Brackets}) {{ heroId1 heroId2 matchCount winCount drawCount lossCount }}");
            }
            sb.Append(" } }");

            JsonNode? data;
            try { data = await Query(http, sb.ToString()); }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"\n  STRATZ пачка {chunk[0]}…{chunk[^1]} пропущена: {ex.Message}");
                continue;
            }
            var hs = data?["heroStats"];
            foreach (var id in chunk)
            {
                foreach (var dryad in (hs?[$"m{id}"] as JsonArray ?? []).OfType<JsonObject>())
                {
                    foreach (var v in (dryad["vs"] as JsonArray ?? []).OfType<JsonObject>())
                        if (Int(v["heroId1"]) == id && Int(v["matchCount"]) > 0)
                            matchups.Add(new MatchupDto { HeroId = id, VsHeroId = Int(v["heroId2"]), Games = Int(v["matchCount"]), Wins = Int(v["winCount"]), Source = "stratz" });
                    foreach (var w in (dryad["with"] as JsonArray ?? []).OfType<JsonObject>())
                        if (Int(w["heroId1"]) == id && Int(w["matchCount"]) > 0)
                            pairs.Add(new PairDto { HeroId = id, AllyId = Int(w["heroId2"]), Games = Int(w["matchCount"]), Wins = Int(w["winCount"]), Source = "stratz" });
                }
                foreach (var l in (hs?[$"l{id}"] as JsonArray ?? []).OfType<JsonObject>())
                {
                    int vs = Int(l["heroId2"]);
                    // Исход линии известен не во всех играх: считаем только игры с исходом.
                    int decided = Int(l["winCount"]) + Int(l["drawCount"]) + Int(l["lossCount"]);
                    if (Int(l["heroId1"]) != id || vs == id || decided <= 0) continue;
                    lanes.Add(new LaneDto
                    {
                        HeroId = id, VsHeroId = vs, Games = decided,
                        Wins = Int(l["winCount"]), Draws = Int(l["drawCount"]), Losses = Int(l["lossCount"]), Source = "stratz",
                    });
                }
            }
            Console.Write('.');
            await Task.Delay(1200);
        }
        Console.WriteLine();
        Console.WriteLine($"STRATZ: матчапов {matchups.Count}, пар {pairs.Count}, линий {lanes.Count}");

        // Сводим дубли (на случай нескольких недель/строк) и проверяем смысл чисел.
        matchups = matchups.GroupBy(m => (m.HeroId, m.VsHeroId))
            .Select(g => new MatchupDto { HeroId = g.Key.HeroId, VsHeroId = g.Key.VsHeroId, Games = g.Sum(x => x.Games), Wins = g.Sum(x => x.Wins), Source = "stratz" }).ToList();
        lanes = lanes.GroupBy(m => (m.HeroId, m.VsHeroId))
            .Select(g => new LaneDto { HeroId = g.Key.HeroId, VsHeroId = g.Key.VsHeroId, Games = g.Sum(x => x.Games), Wins = g.Sum(x => x.Wins), Draws = g.Sum(x => x.Draws), Losses = g.Sum(x => x.Losses), Source = "stratz" }).ToList();
        pairs = pairs.GroupBy(m => (m.HeroId, m.AllyId))
            .Select(g => new PairDto { HeroId = g.Key.HeroId, AllyId = g.Key.AllyId, Games = g.Sum(x => x.Games), Wins = g.Sum(x => x.Wins), Source = "stratz" }).ToList();

        double mSym = Symmetry(matchups.ToDictionary(m => (m.HeroId, m.VsHeroId), m => (double)m.Wins / m.Games));
        Console.WriteLine($"Проверка матчапов: WR(A,B)+WR(B,A) в среднем {mSym:F3} (должно быть ~1)");
        if (matchups.Count > 1000 && Math.Abs(mSym - 1) < 0.05)
        {
            await Save(patchDir, F("matchups"), matchups);
            meta.MatchupSource = "STRATZ (по рангам)";
        }

        double lSym = Symmetry(lanes.ToDictionary(l => (l.HeroId, l.VsHeroId), l => (l.Wins + 0.5 * l.Draws) / l.Games));
        Console.WriteLine($"Проверка линий: среднее {lSym:F3} (должно быть ~1)");
        if (lanes.Count > 1000 && Math.Abs(lSym - 1) < 0.08)
        {
            await Save(patchDir, F("lanes"), lanes);
            meta.LaneSource = "STRATZ исходы линий (по рангам)";
        }

        // Для пар симметрия другая: A с B и B с A — одни и те же игры, винрейты должны совпадать.
        var pairWr = pairs.ToDictionary(p => (p.HeroId, p.AllyId), p => (double)p.Wins / p.Games);
        var pairDiffs = pairWr.Where(kv => pairWr.ContainsKey((kv.Key.AllyId, kv.Key.HeroId)))
            .Select(kv => Math.Abs(kv.Value - pairWr[(kv.Key.AllyId, kv.Key.HeroId)])).ToList();
        double pDiff = pairDiffs.Count > 0 ? pairDiffs.Average() : 1;
        Console.WriteLine($"Проверка пар: |WR(A+B)−WR(B+A)| в среднем {pDiff:F3} (должно быть ~0)");
        if (pairs.Count > 1000 && pDiff < 0.03)
        {
            await Save(patchDir, F("pairs"), pairs);
            meta.PairSource = "STRATZ связки (по рангам)";
        }
    }

    private static double Symmetry(Dictionary<(int, int), double> wr)
    {
        var sums = wr.Where(kv => kv.Key.Item1 < kv.Key.Item2 && wr.ContainsKey((kv.Key.Item2, kv.Key.Item1)))
            .Select(kv => kv.Value + wr[(kv.Key.Item2, kv.Key.Item1)]).ToList();
        return sums.Count > 0 ? sums.Average() : 0;
    }

    private static async Task<JsonNode?> Query(HttpClient http, string query)
    {
        for (int attempt = 1; ; attempt++)
        {
            using var response = await http.PostAsJsonAsync(Url, new { query });
            var body = await response.Content.ReadAsStringAsync();
            if ((int)response.StatusCode == 429 && attempt < 5)
            {
                Console.Error.WriteLine($"\n  STRATZ 429, пауза {10 * attempt} с");
                await Task.Delay(TimeSpan.FromSeconds(10 * attempt));
                continue;
            }
            if (!response.IsSuccessStatusCode)
                throw new HttpRequestException($"{(int)response.StatusCode}: {body[..Math.Min(300, body.Length)]}");

            var json = JsonNode.Parse(body);
            if (json?["errors"] is JsonArray { Count: > 0 } errors)
                throw new InvalidOperationException("GraphQL: " + errors.ToJsonString()[..Math.Min(500, errors.ToJsonString().Length)]);
            return json?["data"];
        }
    }

    private static int PositionOf(JsonNode? n) => n?.GetValue<string>() switch
    {
        "POSITION_1" => 1, "POSITION_2" => 2, "POSITION_3" => 3, "POSITION_4" => 4, "POSITION_5" => 5, _ => 0,
    };

    private static int Int(JsonNode? n)
    {
        if (n is not JsonValue v) return 0;
        if (v.TryGetValue<int>(out var i)) return i;
        if (v.TryGetValue<long>(out var l)) return (int)l;
        if (v.TryGetValue<double>(out var d)) return (int)d;
        if (v.TryGetValue<decimal>(out var m)) return (int)m;
        return v.TryGetValue<string>(out var s) && int.TryParse(s, out var p) ? p : 0;
    }

    private static Task Save<T>(string dir, string file, T value) =>
        File.WriteAllTextAsync(Path.Combine(dir, file), JsonSerializer.Serialize(value, DataFiles.Json));
}
