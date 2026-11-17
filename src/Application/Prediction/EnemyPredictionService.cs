using System.Collections.Concurrent;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Domain.Draft;

namespace DraftAssistant.Application.Prediction;

/// <summary>Догадка: кого, вероятно, возьмёт соперник в этом слоте (по его открытым матчам).</summary>
public sealed record SlotPrediction(SlotId Slot, string Nickname, int HeroId, double Share, int Games);

/// <summary>
/// Для соперников, которые ещё не выбрали героя: ищет игрока по нику в открытой статистике
/// и берёт его самого частого героя из ещё доступных. Это догадка, а не знание:
/// профиль может быть скрыт, ник — совпасть с чужим.
/// </summary>
public sealed class EnemyPredictionService(IPlayerHeroSource source, IAppLog log)
{
    private readonly ConcurrentDictionary<string, Task<PlayerHeroes?>> _lookups = new();

    /// <summary>Пришёл ответ по какому-то игроку — стоит пересчитать догадки.</summary>
    public event Action? Updated;

    public IReadOnlyList<SlotPrediction> Predict(DraftSnapshot s)
    {
        if (s.State.MySide is not { } mySide) return [];
        var enemySide = mySide.Opposite();
        var unavailable = s.State.UnavailableHeroes;
        var used = new HashSet<int>();
        var result = new List<SlotPrediction>();

        foreach (var (slot, name) in s.PlayerNames.Where(kv => kv.Key.Side == enemySide && kv.Key.Kind == SlotKind.Pick)
                                                  .OrderBy(kv => kv.Key.Index))
        {
            var state = s.State.Slots.FirstOrDefault(x => x.Id == slot);
            if (state is { Status: SlotStatus.Confirmed }) continue; // уже выбрал — догадка не нужна

            var task = Lookup(name);
            if (!task.IsCompletedSuccessfully || task.Result is not { } player || player.TotalGames <= 0) continue;

            var pick = player.Heroes.FirstOrDefault(h => !unavailable.Contains(h.HeroId) && !used.Contains(h.HeroId));
            if (pick.Games <= 0) continue;
            used.Add(pick.HeroId);
            result.Add(new SlotPrediction(slot, name, pick.HeroId, (double)pick.Games / player.TotalGames, player.TotalGames));
        }
        return result;
    }

    private Task<PlayerHeroes?> Lookup(string nickname)
    {
        var key = nickname.Trim().ToLowerInvariant();
        return _lookups.GetOrAdd(key, _ =>
        {
            var t = Run(nickname);
            t.ContinueWith(_ => Updated?.Invoke(), TaskScheduler.Default);
            return t;
        });
    }

    private async Task<PlayerHeroes?> Run(string nickname)
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            var p = await source.FindAsync(nickname, cts.Token).ConfigureAwait(false);
            log.Info(p is null
                ? $"Игрок «{nickname}»: не найден или профиль скрыт"
                : $"Игрок «{nickname}» → {p.PersonaName} (#{p.AccountId}), {p.TotalGames} игр, чаще всего: {string.Join(", ", p.Heroes.Take(3).Select(h => h.HeroId))}");
            return p;
        }
        catch (Exception ex)
        {
            log.Warn($"Поиск игрока «{nickname}» не удался: {ex.Message}");
            return null;
        }
    }
}
