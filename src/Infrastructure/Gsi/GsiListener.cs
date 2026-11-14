using System.Net;
using System.Text.Json;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Domain.Draft;

namespace DraftAssistant.Infrastructure.Gsi;

/// <summary>
/// Приёмник официального Valve Game State Integration (Dota сама POST'ит JSON на localhost).
///
/// GSI НЕ даёт игроку пики соперников — поэтому основной источник драфта остаётся визуальным.
/// Но он надёжно сообщает фазу игры (выбор героев / стратегия / игра), сторону игрока и
/// его собственного героя. Это дополнительный сигнал для машины состояний и определения стороны.
/// Это не чтение памяти и не модификация клиента: конфиг GSI — штатный механизм Valve.
/// </summary>
public sealed class GsiListener : IGameStateHintSource, IDisposable
{
    private readonly HttpListener _listener = new();
    private readonly IAppLog _log;
    private readonly CancellationTokenSource _cts = new();
    private volatile GameStateHint? _current;

    public GsiListener(int port, IAppLog log)
    {
        _log = log;
        _listener.Prefixes.Add($"http://localhost:{port}/");
    }

    public GameStateHint? Current => _current;

    public void Start()
    {
        _listener.Start();
        _ = Task.Run(LoopAsync);
        _log.Info($"GSI listener started: {string.Join(", ", _listener.Prefixes)}");
    }

    private async Task LoopAsync()
    {
        while (!_cts.IsCancellationRequested && _listener.IsListening)
        {
            HttpListenerContext ctx;
            try
            {
                ctx = await _listener.GetContextAsync().ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                if (_cts.IsCancellationRequested || !_listener.IsListening) return;
                _log.Warn($"GSI: {ex.Message}");
                continue;
            }

            try
            {
                using var reader = new StreamReader(ctx.Request.InputStream, ctx.Request.ContentEncoding);
                var body = await reader.ReadToEndAsync().ConfigureAwait(false);
                var hint = Parse(body, DateTimeOffset.UtcNow);
                if (hint is not null) _current = hint;
                ctx.Response.StatusCode = 200;
            }
            catch (Exception ex)
            {
                _log.Warn($"GSI parse error: {ex.Message}");
                ctx.Response.StatusCode = 400;
            }
            finally
            {
                ctx.Response.Close();
            }
        }
    }

    /// <summary>Разбор payload GSI. Публичный и статический — покрывается тестами без сети.</summary>
    public static GameStateHint? Parse(string json, DateTimeOffset receivedAt)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object) return null;

        var state = ExternalGameState.Unknown;
        if (root.TryGetProperty("map", out var map) && map.ValueKind == JsonValueKind.Object &&
            map.TryGetProperty("game_state", out var gs) && gs.ValueKind == JsonValueKind.String)
        {
            state = MapGameState(gs.GetString());
        }

        DraftSide? team = null;
        string? playerName = null;
        if (root.TryGetProperty("player", out var pl) && pl.ValueKind == JsonValueKind.Object &&
            pl.TryGetProperty("name", out var pn) && pn.ValueKind == JsonValueKind.String)
        {
            playerName = pn.GetString();
        }
        if (root.TryGetProperty("player", out var player) && player.ValueKind == JsonValueKind.Object &&
            player.TryGetProperty("team_name", out var tn) && tn.ValueKind == JsonValueKind.String)
        {
            team = tn.GetString()?.ToLowerInvariant() switch
            {
                "radiant" => DraftSide.Radiant,
                "dire" => DraftSide.Dire,
                _ => null,
            };
        }

        int? heroId = null;
        if (root.TryGetProperty("hero", out var hero) && hero.ValueKind == JsonValueKind.Object &&
            hero.TryGetProperty("id", out var hid) && hid.ValueKind == JsonValueKind.Number &&
            hid.TryGetInt32(out var id) && id > 0)
        {
            heroId = id;
        }

        return new GameStateHint(state, team, heroId, receivedAt, playerName);
    }

    public static ExternalGameState MapGameState(string? s) => s switch
    {
        "DOTA_GAMERULES_STATE_HERO_SELECTION" => ExternalGameState.HeroSelection,
        "DOTA_GAMERULES_STATE_STRATEGY_TIME" or
        "DOTA_GAMERULES_STATE_TEAM_SHOWCASE" or
        "DOTA_GAMERULES_STATE_WAIT_FOR_MAP_TO_LOAD" => ExternalGameState.PostDraft,
        "DOTA_GAMERULES_STATE_PRE_GAME" or
        "DOTA_GAMERULES_STATE_GAME_IN_PROGRESS" or
        "DOTA_GAMERULES_STATE_POST_GAME" => ExternalGameState.InGame,
        _ => ExternalGameState.Unknown,
    };

    public void Dispose()
    {
        _cts.Cancel();
        try { _listener.Stop(); _listener.Close(); } catch (ObjectDisposedException) { }
        _cts.Dispose();
    }
}
