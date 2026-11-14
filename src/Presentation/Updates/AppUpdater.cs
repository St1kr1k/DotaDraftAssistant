using System.Reflection;
using DraftAssistant.Application.Abstractions;
using Velopack;
using Velopack.Sources;

namespace DraftAssistant.Presentation.Updates;

/// <summary>
/// Автообновление из GitHub Releases. Новая версия скачивается в фоне и применяется,
/// когда пользователь закроет приложение — посреди драфта ничего не перезапускается.
/// </summary>
internal sealed class AppUpdater(IAppLog log)
{
    public static string CurrentVersion =>
        Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "dev";

    private static string? RepoUrl =>
        Assembly.GetEntryAssembly()?
            .GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(a => a.Key == "UpdateRepoUrl")?.Value is { Length: > 0 } url ? url : null;

    /// <summary>Возвращает текст для overlay или null, если обновлений нет / проверка невозможна.</summary>
    public async Task<string?> CheckAndDownloadAsync()
    {
        var repo = RepoUrl;
        if (repo is null) return null; // локальная сборка — обновлять неоткуда

        try
        {
            var mgr = new UpdateManager(new GithubSource(repo, null, false));
            if (!mgr.IsInstalled) return null; // запущено не из установки (dotnet run, папка release)

            var update = await mgr.CheckForUpdatesAsync().ConfigureAwait(false);
            if (update is null) return null;

            var version = update.TargetFullRelease.Version.ToString();
            log.Info($"Найдено обновление {version}, загружаю");
            await mgr.DownloadUpdatesAsync(update).ConfigureAwait(false);

            // Применится после выхода из приложения, без перезапуска посреди драфта.
            mgr.WaitExitThenApplyUpdates(update.TargetFullRelease, silent: true, restart: false);
            return $"Обновление {version} загружено — установится после закрытия";
        }
        catch (Exception ex)
        {
            log.Warn($"Проверка обновлений не удалась: {ex.Message}");
            return null;
        }
    }
}
