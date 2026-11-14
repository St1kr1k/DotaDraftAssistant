using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Infrastructure.Gsi;
using DraftAssistant.Infrastructure.Vision;
using DraftAssistant.Presentation.Common;

namespace DraftAssistant.Presentation.Pages;

/// <summary>Раздел «Настройка»: автоопределение экрана, GSI в один клик, ник, отладочные кадры.</summary>
public partial class SetupPage : UserControl
{
    private static readonly Brush Ok = Frozen("#4ADE80");
    private static readonly Brush Warn = Frozen("#F2C14E");
    private static readonly Brush Off = Frozen("#6E6E76");

    private readonly VisualDraftDetector _detector;
    private readonly JsonLayoutStore _layout;
    private readonly IGameStateHintSource? _gsi;
    private readonly SettingsStore _settings;
    private readonly ProfileStore _profile;
    private readonly string _debugDir;
    private readonly Func<bool> _openCalibration;
    private readonly string? _steamName;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(2) };
    private bool _loading;

    public SetupPage(VisualDraftDetector detector, JsonLayoutStore layout, IGameStateHintSource? gsi,
                     SettingsStore settings, ProfileStore profile, string debugDir, Func<bool> openCalibration, string? steamName)
    {
        InitializeComponent();
        _detector = detector;
        _layout = layout;
        _gsi = gsi;
        _settings = settings;
        _profile = profile;
        _debugDir = debugDir;
        _openCalibration = openCalibration;
        _steamName = steamName;

        Loaded += (_, _) =>
        {
            _loading = true;
            NicknameBox.Text = _profile.Current.Nickname ?? "";
            DebugFramesBox.IsChecked = _settings.Current.Recognition.SaveDebugFrames;
            InstallDirText.Text = $"Программа: {InstallDir}";
            SettingsDirText.Text = $"Настройки, профиль и лог: {SettingsDir}";
            _loading = false;
            Refresh();
            _timer.Start();
        };
        Unloaded += (_, _) => _timer.Stop();
        _timer.Tick += (_, _) => Refresh();
    }

    private void Refresh()
    {
        // Экран
        if (_layout.HasManualCalibration)
        {
            ScreenDot.Fill = Warn;
            ScreenTitle.Text = "Ручная калибровка";
            ScreenDetail.Text = $"Используется сохранённая разметка ({_layout.Current.CalibratedOn}). Автоматический поиск отключён.";
            ResetManualButton.Visibility = Visibility.Visible;
        }
        else
        {
            ResetManualButton.Visibility = Visibility.Collapsed;
            ScreenTitle.Text = "Автоматически";
            if (_detector.LastAutoResolution is { } res)
            {
                ScreenDot.Fill = Ok;
                ScreenDetail.Text = $"Экран драфта найден сам на {res}. Калибровка не нужна: слоты, роли тиммейтов и баны читаются с экрана.";
            }
            else
            {
                ScreenDot.Fill = Off;
                ScreenDetail.Text = "Слоты героев найдутся сами в начале драфта на любом экране 16:9 (1080p, 2K, 4K). Калибровать ничего не нужно.";
            }
        }

        // Ник
        var nick = _profile.Current.Nickname;
        if (nick is not null) { NickDot.Fill = Ok; NickTitle.Text = $"{nick} (указан вручную)"; }
        else if (_steamName is not null) { NickDot.Fill = Ok; NickTitle.Text = $"{_steamName} (из Steam)"; }
        else { NickDot.Fill = Warn; NickTitle.Text = "Ник не найден — впишите его ниже"; }

        // GSI
        var status = GsiInstaller.Status(_settings.Current.Gsi.DotaPath);
        DotaPathText.Text = status.DotaPath is { } dp ? $"Папка Dota: {dp}" : "Папка Dota не найдена. Запустите Dota или укажите папку вручную.";
        bool receiving = _gsi?.Current is { } h && DateTimeOffset.UtcNow - h.ReceivedAt < TimeSpan.FromSeconds(60);
        if (receiving)
        {
            GsiDot.Fill = Ok;
            GsiTitle.Text = "Работает — Dota присылает данные";
        }
        else if (status.ConfigInstalled)
        {
            GsiDot.Fill = Warn;
            GsiTitle.Text = "Настроено, ждём данные от Dota";
        }
        else if (!status.DotaFound)
        {
            GsiDot.Fill = Off;
            GsiTitle.Text = "Не настроено — Dota не найдена";
        }
        else
        {
            GsiDot.Fill = Off;
            GsiTitle.Text = "Не настроено (необязательно)";
        }
        InstallGsiButton.Content = status.ConfigInstalled ? "Переустановить" : "Настроить в один клик";
        InstallGsiButton.IsEnabled = status.DotaFound;
    }

    private void OnInstallGsi(object sender, RoutedEventArgs e)
    {
        try
        {
            var path = GsiInstaller.Install(_settings.Current.Gsi.Port, _settings.Current.Gsi.DotaPath);
            GsiInstallResult.Text = $"Готово: {path}";
        }
        catch (Exception ex)
        {
            GsiInstallResult.Text = $"Не получилось: {ex.Message}";
        }
        Refresh();
    }

    private void OnChooseDotaFolder(object sender, RoutedEventArgs e)
    {
        var dlg = new Microsoft.Win32.OpenFolderDialog { Title = "Папка Dota 2 (например, G:\\SteamLibrary\\steamapps\\common\\dota 2 beta)" };
        if (dlg.ShowDialog(Window.GetWindow(this)) != true) return;
        var dir = GsiInstaller.NormalizeManualDir(dlg.FolderName);
        if (dir is null)
        {
            GsiInstallResult.Text = "В этой папке не найдена Dota 2. Выберите папку «dota 2 beta».";
            return;
        }
        _settings.Current.Gsi.DotaPath = dir;
        _settings.Save();
        GsiInstallResult.Text = $"Папка Dota: {dir}";
        Refresh();
    }

    private void OnCopyLaunchOption(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(GsiInstaller.LaunchOption); } catch (Exception) { }
    }

    private void OnNicknameChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        var nick = NicknameBox.Text.Trim();
        if (nick == (_profile.Current.Nickname ?? "")) return;
        _profile.Update(p => p.Nickname = nick.Length == 0 ? null : nick);
    }

    private void OnDebugFramesChanged(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _settings.Current.Recognition.SaveDebugFrames = DebugFramesBox.IsChecked == true;
        _settings.Save();
    }

    /// <summary>Папка установки: при установке через Velopack exe лежит в …\DotaDraftAssistant\current.</summary>
    private static string InstallDir
    {
        get
        {
            var dir = AppContext.BaseDirectory.TrimEnd('\\');
            return string.Equals(Path.GetFileName(dir), "current", StringComparison.OrdinalIgnoreCase)
                ? Path.GetDirectoryName(dir) ?? dir
                : dir;
        }
    }

    private string SettingsDir => Path.GetDirectoryName(_debugDir) ?? _debugDir;

    private void OnOpenInstallDir(object sender, RoutedEventArgs e) => OpenFolder(InstallDir);

    private void OnOpenSettingsDir(object sender, RoutedEventArgs e) => OpenFolder(SettingsDir);

    private static void OpenFolder(string dir)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true }); } catch (Exception) { }
    }

    private void OnOpenDebugFolder(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(_debugDir);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{_debugDir}\"") { UseShellExecute = true });
    }

    private void OnResetManual(object sender, RoutedEventArgs e)
    {
        _layout.ResetToAutomatic();
        Refresh();
    }

    private void OnManualCalibration(object sender, RoutedEventArgs e)
    {
        _openCalibration();
        Refresh();
    }

    private static Brush Frozen(string hex)
    {
        var b = (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;
        b.Freeze();
        return b;
    }
}
