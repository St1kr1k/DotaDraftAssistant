using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Infrastructure.Capture;
using DraftAssistant.Infrastructure.Recognition;
using DraftAssistant.Infrastructure.Storage;
using DraftAssistant.Infrastructure.Vision;
using OpenCvSharp;

namespace DraftAssistant.DataTool;

/// <summary>
///   DataTool fetch        [--out data] [--api-key KEY] [--no-matchups] [--delay-ms 1100]
///   DataTool check-layout --screenshot shot.png [--data data] [--user-dir DIR] [--out debug] [--player НИК]
///   DataTool add-template --screenshot shot.png --slot Radiant-Pick-1 --hero "Axe" [--data data] [--user-dir DIR]
/// </summary>
internal static class Program
{
    private const string OpenDota = "https://api.opendota.com/api";
    private const string SteamCdn = "https://cdn.cloudflare.steamstatic.com";

    private static async Task<int> Main(string[] args)
    {
        if (args.Length == 0) return Usage();
        var opts = ParseOptions(args.Skip(1));
        try
        {
            return args[0] switch
            {
                "fetch" => await Fetch(opts),
                "check-layout" => CheckLayout(opts),
                "add-template" => AddTemplate(opts),
                _ => Usage(),
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Ошибка: {ex.Message}");
            return 1;
        }
    }

    private static int Usage()
    {
        Console.WriteLine("""
            DataTool fetch        [--out data] [--api-key KEY] [--no-matchups] [--delay-ms 1100]
                Скачивает героев, портреты, статистику патча и матчапы с OpenDota / Steam CDN.
            DataTool check-layout --screenshot shot.png [--data data] [--user-dir DIR] [--out debug]
                Прогоняет разметку и распознавание по скриншоту, сохраняет картинку с ROI и вырезки слотов.
            DataTool add-template --screenshot shot.png --slot Radiant-Pick-1 --hero "Axe" [--data data] [--user-dir DIR]
                Сохраняет вырезку слота как дополнительный шаблон героя (повышает точность на вашем экране).
            """);
        return 2;
    }

    private static Dictionary<string, string> ParseOptions(IEnumerable<string> args)
    {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string? key = null;
        foreach (var a in args)
        {
            if (a.StartsWith("--")) { key = a[2..]; d[key] = "true"; }
            else if (key is not null) { d[key] = a; key = null; }
        }
        return d;
    }

    private static string Opt(Dictionary<string, string> o, string key, string fallback) =>
        o.TryGetValue(key, out var v) ? v : fallback;

    private static string DefaultUserDir() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DotaDraftAssistant");

    // ------------------------------------------------------------------ fetch

    private static async Task<int> Fetch(Dictionary<string, string> o)
    {
        var dataDir = Path.GetFullPath(Opt(o, "out", "data"));
        var apiKey = o.GetValueOrDefault("api-key");
        int delay = int.Parse(Opt(o, "delay-ms", apiKey is null ? "1500" : "100"));
        string Q(string url) => apiKey is null ? url : $"{url}{(url.Contains('?') ? '&' : '?')}api_key={apiKey}";

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("DotaDraftAssistant-DataTool/0.1");

        Console.WriteLine("Герои…");
        var heroesJson = await GetJson<JsonObject>(http, Q($"{OpenDota}/constants/heroes"))
                         ?? throw new InvalidOperationException("пустой ответ constants/heroes");
        var heroes = new List<HeroDto>();
        Directory.CreateDirectory(DataFiles.HeroesDir(dataDir));

        foreach (var (_, node) in heroesJson)
        {
            if (node is not JsonObject h) continue;
            int id = h["id"]!.GetValue<int>();
            string name = h["name"]!.GetValue<string>();
            string shortName = name.Replace("npc_dota_hero_", "");
            heroes.Add(new HeroDto
            {
                Id = id,
                Name = name,
                LocalizedName = h["localized_name"]?.GetValue<string>() ?? shortName,
                PrimaryAttribute = (h["primary_attr"]?.GetValue<string>()) switch
                {
                    "str" => PrimaryAttribute.Strength,
                    "agi" => PrimaryAttribute.Agility,
                    "int" => PrimaryAttribute.Intelligence,
                    "all" => PrimaryAttribute.Universal,
                    _ => PrimaryAttribute.Unknown,
                },
                AttackType = (h["attack_type"]?.GetValue<string>()) switch
                {
                    "Melee" => AttackType.Melee,
                    "Ranged" => AttackType.Ranged,
                    _ => AttackType.Unknown,
                },
                Roles = h["roles"] is JsonArray roles ? roles.Select(r => r!.GetValue<string>()).ToList() : [],
                Aliases = [shortName],
            });

            var heroDir = Path.Combine(DataFiles.HeroesDir(dataDir), id.ToString());
            Directory.CreateDirectory(Path.Combine(heroDir, "templates"));
            await Download(http, ImageUrl(h["img"]?.GetValue<string>(), $"/apps/dota2/images/dota_react/heroes/{shortName}.png"), Path.Combine(heroDir, "portrait.png"));
            await Download(http, ImageUrl(h["icon"]?.GetValue<string>(), $"/apps/dota2/images/dota_react/heroes/icons/{shortName}.png"), Path.Combine(heroDir, "icon.png"));
        }
        heroes = heroes.OrderBy(h => h.Id).ToList();
        await File.WriteAllTextAsync(DataFiles.HeroesJson(dataDir), JsonSerializer.Serialize(heroes, DataFiles.Json));
        Console.WriteLine($"  {heroes.Count} героев");

        Console.WriteLine("Патч и статистика…");
        var patchDir = DataFiles.PatchDir(dataDir);
        Directory.CreateDirectory(patchDir);
        var patches = await GetJson<JsonArray>(http, Q($"{OpenDota}/constants/patch"));
        string patchName = patches?.LastOrDefault()?["name"]?.GetValue<string>() ?? "unknown";

        var statsJson = await GetJson<JsonArray>(http, Q($"{OpenDota}/heroStats")) ?? new JsonArray();
        var stats = statsJson.OfType<JsonObject>().Select(s => new HeroStatsDto
        {
            HeroId = s["id"]!.GetValue<int>(),
            Brackets = Enumerable.Range(1, 8).ToDictionary(
                b => b.ToString(),
                b => new BracketDto
                {
                    Picks = s[$"{b}_pick"]?.GetValue<int>() ?? 0,
                    Wins = s[$"{b}_win"]?.GetValue<int>() ?? 0,
                }),
        }).ToList();
        await File.WriteAllTextAsync(Path.Combine(patchDir, "hero_stats.json"), JsonSerializer.Serialize(stats, DataFiles.Json));

        var matchups = new List<MatchupDto>();
        int failedMatchups = 0;
        if (!o.ContainsKey("no-matchups"))
        {
            Console.WriteLine($"Матчапы ({heroes.Count} запросов, пауза {delay} мс)…");
            foreach (var hero in heroes)
            {
                JsonArray arr;
                try
                {
                    arr = await GetJson<JsonArray>(http, Q($"{OpenDota}/heroes/{hero.Id}/matchups")) ?? new JsonArray();
                }
                catch (HttpRequestException ex)
                {
                    // Матчапы одного героя не должны ронять весь релиз: без них Counter честно будет нейтральным.
                    Console.Error.WriteLine($"\n  матчапы {hero.LocalizedName} пропущены: {ex.Message}");
                    failedMatchups++;
                    continue;
                }
                matchups.AddRange(arr.OfType<JsonObject>().Select(m => new MatchupDto
                {
                    HeroId = hero.Id,
                    VsHeroId = m["hero_id"]!.GetValue<int>(),
                    Games = m["games_played"]!.GetValue<int>(),
                    Wins = m["wins"]!.GetValue<int>(),
                    Source = "opendota",
                }));
                Console.Write('.');
                await Task.Delay(delay);
            }
            Console.WriteLine();
            await File.WriteAllTextAsync(Path.Combine(patchDir, "matchups.json"), JsonSerializer.Serialize(matchups, DataFiles.Json));
            if (failedMatchups > heroes.Count / 4)
                throw new InvalidOperationException($"слишком много пропущенных матчапов: {failedMatchups}");
        }

        // Позиции по линиям (OpenDota /scenarios/laneRoles): лёгкая/мид/сложная.
        // Лёгкая линия делится на pos 1 и pos 5, сложная — на pos 3 и pos 4 по тому,
        // насколько герой «саппорт» по ролям Valve. Это приближение — STRATZ даёт позиции точно.
        var positions = new List<PositionDto>();
        if (!o.ContainsKey("no-positions"))
        {
            Console.WriteLine($"Позиции по линиям ({heroes.Count} запросов)…");
            var prior = new DraftAssistant.Application.Roles.RoleTagPositionPrior();
            foreach (var hero in heroes)
            {
                JsonArray arr;
                try
                {
                    arr = await GetJson<JsonArray>(http, Q($"{OpenDota}/scenarios/laneRoles?hero_id={hero.Id}")) ?? new JsonArray();
                }
                catch (HttpRequestException ex)
                {
                    Console.Error.WriteLine($"\n  позиции {hero.LocalizedName} пропущены: {ex.Message}");
                    continue;
                }
                var byLane = arr.OfType<JsonObject>()
                    .GroupBy(r => Num(r["lane_role"]))
                    .ToDictionary(g => g.Key, g => (Games: g.Sum(r => Num(r["games"])), Wins: g.Sum(r => Num(r["wins"]))));

                var domainHero = new Hero(hero.Id, hero.Name, hero.LocalizedName, hero.PrimaryAttribute, hero.AttackType, hero.Roles, hero.Aliases);
                var d = prior.Infer(domainHero);
                double supportSafe = d[DraftAssistant.Domain.Player.Position.HardSupport] /
                                     Math.Max(1e-6, d[DraftAssistant.Domain.Player.Position.HardSupport] + d[DraftAssistant.Domain.Player.Position.Carry]);
                double supportOff = d[DraftAssistant.Domain.Player.Position.SoftSupport] /
                                    Math.Max(1e-6, d[DraftAssistant.Domain.Player.Position.SoftSupport] + d[DraftAssistant.Domain.Player.Position.Offlane]);

                void Add(int pos, (int Games, int Wins) lane, double fraction)
                {
                    int g = (int)Math.Round(lane.Games * fraction), w = (int)Math.Round(lane.Wins * fraction);
                    if (g > 0) positions.Add(new PositionDto { HeroId = hero.Id, Position = pos, Games = g, Wins = w, Source = "opendota-lanes" });
                }
                if (byLane.TryGetValue(1, out var safe)) { Add(1, safe, 1 - supportSafe); Add(5, safe, supportSafe); }
                if (byLane.TryGetValue(2, out var mid)) Add(2, mid, 1);
                if (byLane.TryGetValue(3, out var off)) { Add(3, off, 1 - supportOff); Add(4, off, supportOff); }
                Console.Write('.');
                await Task.Delay(delay);
            }
            Console.WriteLine();
            await File.WriteAllTextAsync(Path.Combine(patchDir, "positions.json"), JsonSerializer.Serialize(positions, DataFiles.Json));
        }

        var meta = new PatchMetaDto
        {
            Patch = patchName,
            FetchedAt = DateTimeOffset.UtcNow,
            Source = "OpenDota heroStats (публичные матчи по бракетам)",
            MatchupSource = "OpenDota /heroes/{id}/matchups",
            PositionSource = positions.Count > 0 ? "OpenDota /scenarios/laneRoles (pos 1/5 и 3/4 разделены по ролям героя)" : "",
        };
        await File.WriteAllTextAsync(Path.Combine(patchDir, "meta.json"), JsonSerializer.Serialize(meta, DataFiles.Json));
        Console.WriteLine($"Готово: {dataDir} (патч {patchName}, матчапов {matchups.Count})");
        return 0;
    }

    /// <summary>
    /// GET JSON с повторами: на 429 (лимит OpenDota) и 5xx ждём Retry-After или нарастающую паузу.
    /// </summary>
    private static async Task<T?> GetJson<T>(HttpClient http, string url)
    {
        for (int attempt = 1; ; attempt++)
        {
            HttpResponseMessage response;
            try
            {
                response = await http.GetAsync(url);
            }
            catch (TaskCanceledException) when (attempt < 4)
            {
                // Таймаут: OpenDota перегружен — подождать и повторить.
                Console.Error.WriteLine($"\n  таймаут, повтор через {15 * attempt} с…");
                await Task.Delay(TimeSpan.FromSeconds(15 * attempt));
                continue;
            }
            catch (TaskCanceledException ex)
            {
                throw new HttpRequestException($"таймаут ({url.Split('?')[0]})", ex);
            }
            using var _ = response;
            int code = (int)response.StatusCode;
            if (response.IsSuccessStatusCode)
                return await response.Content.ReadFromJsonAsync<T>();

            bool retryable = code == 429 || code >= 500;
            if (!retryable || attempt >= 6)
                throw new HttpRequestException($"{code} {response.ReasonPhrase} ({url.Split('?')[0]})", null, response.StatusCode);

            var wait = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(20 * attempt);
            Console.Error.WriteLine($"\n  {code}, повтор через {wait.TotalSeconds:0} с…");
            await Task.Delay(wait);
        }
    }

    /// <summary>Число из JSON, где OpenDota иногда отдаёт числа строками.</summary>
    private static int Num(JsonNode? n)
    {
        if (n is null) return 0;
        if (n is JsonValue v)
        {
            if (v.TryGetValue<int>(out var i)) return i;
            if (v.TryGetValue<long>(out var l)) return (int)l;
            if (v.TryGetValue<double>(out var d)) return (int)d;
            if (v.TryGetValue<string>(out var s) && int.TryParse(s, out var p)) return p;
        }
        return 0;
    }

    private static string ImageUrl(string? path, string fallback)
    {
        var p = string.IsNullOrEmpty(path) ? fallback : path;
        p = p.Split('?')[0];
        return p.StartsWith("http") ? p : SteamCdn + p;
    }

    private static async Task Download(HttpClient http, string url, string path)
    {
        if (File.Exists(path)) return;
        try
        {
            var bytes = await http.GetByteArrayAsync(url);
            await File.WriteAllBytesAsync(path, bytes);
        }
        catch (HttpRequestException ex)
        {
            Console.Error.WriteLine($"  не скачано {url}: {ex.Message}");
        }
    }

    // ------------------------------------------------------------------ check-layout

    private sealed record Toolkit(JsonHeroRepository Heroes, JsonLayoutStore Layout, DraftFrameAnalyzer Analyzer, HeroTemplateLibrary Templates, string DataDir);

    private static Toolkit BuildToolkit(Dictionary<string, string> o)
    {
        var dataDir = Path.GetFullPath(Opt(o, "data", "data"));
        var userDir = Opt(o, "user-dir", DefaultUserDir());
        var heroes = JsonHeroRepository.Load(dataDir);
        var settings = new JsonSettingsRepository(userDir).LoadSettings();
        var layout = new JsonLayoutStore(userDir, dataDir);
        var templates = HeroTemplateLibrary.LoadFromDirectory(DataFiles.HeroesDir(dataDir), heroes.All.Select(h => h.Id));
        Func<RecognitionOptions> rec = () => settings.Recognition;
        var recognizer = new CompositeHeroRecognizer(
            new TemplateHeroRecognizer(templates, rec), new ColorHistogramHeroRecognizer(templates, rec), rec);
        var analyzer = new DraftFrameAnalyzer(layout, recognizer, new SlotEmptinessClassifier(rec), rec);
        return new Toolkit(heroes, layout, analyzer, templates, dataDir);
    }

    private static int CheckLayout(Dictionary<string, string> o)
    {
        var shot = o.GetValueOrDefault("screenshot") ?? throw new ArgumentException("--screenshot обязателен");
        var outDir = Path.GetFullPath(Opt(o, "out", "debug"));
        Directory.CreateDirectory(outDir);
        var tk = BuildToolkit(o);

        using var img = Cv2.ImRead(shot, ImreadModes.Color);
        if (img.Empty()) throw new ArgumentException($"не удалось открыть {shot}");
        Console.WriteLine($"Скриншот {img.Width}x{img.Height}, шаблонов героев: {tk.Templates.HeroCount}");

        var sw = System.Diagnostics.Stopwatch.StartNew();
        FrameAnalysis analysis;
        if (tk.Analyzer.IsCalibrated)
        {
            Console.WriteLine($"Режим: ручная калибровка ({tk.Layout.LayoutPath})");
            analysis = tk.Analyzer.Analyze(img, new PixelRect(0, 0, img.Width, img.Height), img.Width, img.Height, useCache: false);
        }
        else
        {
            using var top = new Mat(img, new Rect(0, 0, img.Width, (int)(img.Height * PlayerBarGridDetector.SearchHeight)));
            var grid = PlayerBarGridDetector.Detect(top, img.Width);
            if (grid is null)
            {
                Console.WriteLine("Режим: автоматический — сетка слотов НЕ найдена (это не экран драфта или интерфейс отличается).");
                return 1;
            }
            Console.WriteLine($"Режим: автоматический — сетка найдена: полоски на y={grid.BarY}, шаг {grid.Pitch:0.0}px, найдено полосок {grid.DetectedBars}/10");
            analysis = tk.Analyzer.AnalyzeGrid(img, new PixelRect(0, 0, img.Width, img.Height), grid, useCache: false);

            var reader = new DraftTextReader(tk.Heroes, new ConsoleLog());
            if (reader.Available)
            {
                using var chat = CvImage.Crop(img, DraftTextReader.ChatRect(img.Width, img.Height));
                var text = reader.Read(img, grid, chat, o.GetValueOrDefault("player"));
                Console.WriteLine($"Ваша сторона (по подписям ролей): {text.AllySide?.ToString() ?? "не определена"}");
                foreach (var (slot, pos) in text.Roles.OrderBy(r => r.Key.Index))
                    Console.WriteLine($"  роль {slot}: pos {(int)pos}");
                if (text.OwnSlotIndex is { } own) Console.WriteLine($"Ваш слот: {own + 1}");
                Console.WriteLine($"Баны из чата: {string.Join(", ", text.BannedHeroes.Select(id => tk.Heroes.Find(id)?.LocalizedName))}");
            }
            else
            {
                Console.WriteLine("OCR Windows недоступен — роли и баны не читаются.");
            }
        }
        sw.Stop();
        Console.WriteLine($"Экран драфта: {(analysis.Observation.DraftScreenVisible ? "ДА" : "нет")} (score {analysis.SignatureScore:0.00}); анализ {sw.ElapsedMilliseconds} мс");

        using var annotated = img.Clone();
        foreach (var s in analysis.Slots)
        {
            string Name(int id) => tk.Heroes.Find(id)?.LocalizedName ?? $"#{id}";
            var obs = s.Observation;
            string label = obs.Content switch
            {
                DraftAssistant.Application.Abstractions.ObservedContent.Empty => "empty",
                DraftAssistant.Application.Abstractions.ObservedContent.Hero => $"{Name(obs.HeroId!.Value)} {obs.Confidence:P0}",
                _ => $"unknown {obs.Confidence:P0}",
            };
            string top = s.Recognition is null ? "" :
                string.Join(" | ", s.Recognition.Candidates.Take(3).Select(c => $"{Name(c.HeroId)} {c.Score:0.000}"));
            Console.WriteLine($"  {s.Slot,-18} {label,-28} {top}");

            var r = new Rect(s.RectInClient.X, s.RectInClient.Y, s.RectInClient.Width, s.RectInClient.Height);
            var color = obs.Content switch
            {
                DraftAssistant.Application.Abstractions.ObservedContent.Hero => Scalar.LimeGreen,
                DraftAssistant.Application.Abstractions.ObservedContent.Empty => Scalar.Gray,
                _ => Scalar.Red,
            };
            Cv2.Rectangle(annotated, r, color, 2);
            Cv2.PutText(annotated, label, new OpenCvSharp.Point(r.X, r.Bottom + 14), HersheyFonts.HersheySimplex, 0.45, color, 1);

            using var crop = CvImage.Crop(img, s.RectInClient);
            if (crop is not null) Cv2.ImWrite(Path.Combine(outDir, $"{s.Slot}.png"), crop);
        }

        var outPath = Path.Combine(outDir, "annotated.png");
        Cv2.ImWrite(outPath, annotated);
        Console.WriteLine($"Сохранено: {outPath}");
        return 0;
    }

    private sealed class ConsoleLog : DraftAssistant.Application.Abstractions.IAppLog
    {
        public void Info(string message) => Console.WriteLine(message);
        public void Warn(string message) => Console.WriteLine($"WARN {message}");
        public void Error(string message, Exception? ex = null) => Console.WriteLine($"ERROR {message} {ex?.Message}");
    }

    // ------------------------------------------------------------------ add-template

    private static int AddTemplate(Dictionary<string, string> o)
    {
        var shot = o.GetValueOrDefault("screenshot") ?? throw new ArgumentException("--screenshot обязателен");
        var slotName = o.GetValueOrDefault("slot") ?? throw new ArgumentException("--slot обязателен (например Radiant-Pick-1)");
        var heroName = o.GetValueOrDefault("hero") ?? throw new ArgumentException("--hero обязателен");
        var tk = BuildToolkit(o);

        var hero = tk.Heroes.All.FirstOrDefault(h =>
                       string.Equals(h.LocalizedName, heroName, StringComparison.OrdinalIgnoreCase) ||
                       h.Aliases.Contains(heroName, StringComparer.OrdinalIgnoreCase))
                   ?? throw new ArgumentException($"герой '{heroName}' не найден");

        using var img = Cv2.ImRead(shot, ImreadModes.Color);
        if (img.Empty()) throw new ArgumentException($"не удалось открыть {shot}");
        PixelRect rect;
        if (tk.Analyzer.IsCalibrated)
        {
            var layout = tk.Layout.Current;
            var canvas = UiCanvas.Compute(img.Width, img.Height, layout.Anchor);
            var slot = layout.AllSlots().FirstOrDefault(s => string.Equals(s.Id.ToString(), slotName, StringComparison.OrdinalIgnoreCase));
            if (slot.Rect is null) throw new ArgumentException($"слот '{slotName}' не размечен");
            rect = UiCanvas.ToPixels(slot.Rect, canvas);
        }
        else
        {
            using var top = new Mat(img, new Rect(0, 0, img.Width, (int)(img.Height * PlayerBarGridDetector.SearchHeight)));
            var grid = PlayerBarGridDetector.Detect(top, img.Width) ?? throw new InvalidOperationException("сетка слотов не найдена на скриншоте");
            var id = DraftLayout.StandardSlots.Cast<DraftAssistant.Domain.Draft.SlotId?>()
                .FirstOrDefault(s => string.Equals(s.ToString(), slotName, StringComparison.OrdinalIgnoreCase));
            if (id is not { Kind: DraftAssistant.Domain.Draft.SlotKind.Pick } sid)
                throw new ArgumentException($"слот '{slotName}' не найден (пример: Radiant-Pick-1)");
            rect = grid.Portrait(sid.Side, sid.Index);
        }

        using var crop = CvImage.Crop(img, rect) ?? throw new InvalidOperationException("слот вне изображения");
        var dir = Path.Combine(DataFiles.HeroesDir(tk.DataDir), hero.Id.ToString(), "templates");
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, $"{DateTime.Now:yyyyMMdd_HHmmss}_{slotName}.png");
        Cv2.ImWrite(path, crop);
        Console.WriteLine($"Шаблон {hero.LocalizedName} сохранён: {path}");
        return 0;
    }
}
