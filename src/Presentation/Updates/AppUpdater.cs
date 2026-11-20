using System.Reflection;
using DraftAssistant.Application.Abstractions;
using Velopack;
using Velopack.Sources;

namespace DraftAssistant.Presentation.Updates;

/// <summary>
/// Автообновление из GitHub Releases (Velopack).
///
/// 1. При запуске и затем каждые 3 часа приложение спрашивает GitHub, есть ли версия новее.
/// 2. Если есть — в фоне скачивает только разницу (дельту) или полный пакет.
/// 3. Устанавливается обновление, когда пользователь закрывает приложение (посреди драфта ничего
///    не перезапускается), либо сразу — кнопкой «Перезапустить и обновить».
/// </summary>
public sealed class AppUpdater(IAppLog log)
{
    private UpdateManager? _manager;
    private UpdateInfo? _ready;

    public static string CurrentVersion =>
        Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "dev";

    public static string? RepoUrl =>
        Assembly.GetEntryAssembly()?
            .GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == "UpdateRepoUrl")?.Value is { Length: > 0 } url ? url : null;

    /// <summary>Текст статуса для интерфейса.</summary>
    public event Action<string, bool>? StatusChanged; // (текст, готово к установке)

    public async Task RunAsync(CancellationToken ct)
    {
        var repo = RepoUrl;
        if (repo is null) { StatusChanged?.Invoke("Обновления: локальная сборка", false); return; }

        try
        {
            _manager = new UpdateManager(new GithubSource(repo, null, false));
            if (!_manager.IsInstalled) { StatusChanged?.Invoke("Обновления: запущено не из установки", false); return; }
        }
        catch (Exception ex)
        {
            log.Warn($"Velopack: {ex.Message}");
            StatusChanged?.Invoke("Обновления недоступны", false);
            return;
        }

        while (!ct.IsCancellationRequested && _ready is null)
        {
            await CheckOnceAsync().ConfigureAwait(false);
            if (_ready is not null) break;
            try { await Task.Delay(TimeSpan.FromHours(3), ct).ConfigureAwait(false); }
            catch (TaskCanceledException) { return; }
        }
    }

    private async Task CheckOnceAsync()
    {
        try
        {
            StatusChanged?.Invoke("Обновления: проверка…", false);
            var update = await _manager!.CheckForUpdatesAsync().ConfigureAwait(false);
            if (update is null)
            {
                StatusChanged?.Invoke("Последняя версия", false);
                return;
            }

            var version = update.TargetFullRelease.Version.ToString();
            log.Info($"Найдено обновление {version}, загружаю");
            await _manager.DownloadUpdatesAsync(update, p => StatusChanged?.Invoke($"Загрузка {version}: {p}%", false)).ConfigureAwait(false);

            // Если пользователь просто закроет приложение — обновление установится само.
            _manager.WaitExitThenApplyUpdates(update.TargetFullRelease, silent: true, restart: false);
            _ready = update;
            StatusChanged?.Invoke($"Версия {version} скачана — установится при закрытии", true);
        }
        catch (Exception ex)
        {
            log.Warn($"Проверка обновлений не удалась: {ex.Message}");
            StatusChanged?.Invoke("Обновления: нет связи с GitHub", false);
        }
    }

    /// <summary>Установить скачанное обновление прямо сейчас и перезапустить приложение.</summary>
    public void RestartAndApply()
    {
        if (_manager is null || _ready is null) return;
        _manager.ApplyUpdatesAndRestart(_ready.TargetFullRelease);
    }
}
