using System.IO;
using System.Windows;
using System.Windows.Threading;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Application.Recommendation;
using DraftAssistant.Application.Recommendation.Evaluators;
using DraftAssistant.Application.Roles;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Scoring;
using DraftAssistant.Infrastructure.Capture;
using DraftAssistant.Infrastructure.Gsi;
using DraftAssistant.Infrastructure.Recognition;
using DraftAssistant.Infrastructure.Storage;
using DraftAssistant.Infrastructure.Vision;
using DraftAssistant.Presentation.Calibration;
using DraftAssistant.Presentation.Interop;
using DraftAssistant.Presentation.Overlay;
using DraftAssistant.Presentation.Settings;
using DraftAssistant.Presentation.Updates;

namespace DraftAssistant.Presentation;

/// <summary>Composition root: здесь (и только здесь) слои соединяются друг с другом.</summary>
public partial class App : System.Windows.Application
{
    private const uint VK_D = 0x44, VK_O = 0x4F;

    private readonly CancellationTokenSource _cts = new();
    private IAppLog _log = NullLog.Instance;
    private ISettingsRepository _settingsRepo = null!;
    private AppSettings _settings = null!;
    private volatile PlayerProfile _profile = new();
    private JsonHeroRepository _heroes = null!;
    private GdiScreenCaptureService _capture = null!;
    private JsonLayoutStore _layout = null!;
    private HeroTemplateLibrary _templates = null!;
    private GsiListener? _gsi;
    private DraftPipeline _pipeline = null!;
    private OverlayViewModel _vm = null!;
    private OverlayWindow _overlay = null!;
    private HotkeyManager? _hotkeys;
    private DispatcherTimer? _positionTimer;
    private bool _interactive;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var userDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DotaDraftAssistant");
        var dataDir = Path.Combine(AppContext.BaseDirectory, "data");
        _log = new FileLog(userDir);
        DispatcherUnhandledException += (_, args) =>
        {
            _log.Error("UI exception", args.Exception);
            args.Handled = true;
        };

        _settingsRepo = new JsonSettingsRepository(userDir);
        _settings = _settingsRepo.LoadSettings();
        _profile = _settingsRepo.LoadProfile();

        try
        {
            _heroes = JsonHeroRepository.Load(dataDir);
        }
        catch (FileNotFoundException ex)
        {
            MessageBox.Show(
                $"{ex.Message}\n\nСкачайте данные героев и патча:\n  dotnet run --project tools/DataTool -- fetch\nи пересоберите приложение.",
                "Dota Draft Assistant", MessageBoxButton.OK, MessageBoxImage.Warning);
            Shutdown();
            return;
        }

        // --- Infrastructure: глаза ---
        _capture = new GdiScreenCaptureService();
        _layout = new JsonLayoutStore(userDir, dataDir);
        _templates = HeroTemplateLibrary.LoadFromDirectory(DataFiles.HeroesDir(dataDir), _heroes.All.Select(h => h.Id));
        _log.Info($"Templates loaded for {_templates.HeroCount}/{_heroes.All.Count} heroes");

        Func<RecognitionOptions> recOptions = () => _settings.Recognition;
        var recognizer = new CompositeHeroRecognizer(
            new TemplateHeroRecognizer(_templates, recOptions),
            new ColorHistogramHeroRecognizer(_templates, recOptions),
            recOptions);
        var analyzer = new DraftFrameAnalyzer(_layout, recognizer, new SlotEmptinessClassifier(recOptions), recOptions);
        var detector = new VisualDraftDetector(_capture, analyzer);

        if (_settings.Gsi.Enabled)
        {
            try
            {
                _gsi = new GsiListener(_settings.Gsi.Port, _log);
                _gsi.Start();
            }
            catch (Exception ex)
            {
                _log.Warn($"GSI listener не запущен: {ex.Message}");
                _gsi?.Dispose();
                _gsi = null;
            }
        }

        // --- Application: мозг ---
        var roles = new RoleTagPositionPrior();
        Func<ScoringOptions> scoring = () => _settings.Scoring;
        IHeroEvaluator[] evaluators =
        [
            new CounterEvaluator(scoring),
            new TeamNeedsSynergyEvaluator(),
            new MetaEvaluator(scoring),
            new RoleFitEvaluator(roles),
            new PlayerPreferenceEvaluator(scoring),
        ];
        var recommendations = new RecommendationService(_heroes, evaluators, () => _settings.Scoring.Weights);

        _pipeline = new DraftPipeline(
            detector, _gsi, recommendations, roles, _heroes,
            new LocalPatchDataProvider(dataDir, _log),
            () => _profile, _settings, _log);

        // --- Presentation ---
        _vm = new OverlayViewModel(_heroes)
        {
            VersionText = $"v{AppUpdater.CurrentVersion}",
            PanelOpacity = _settings.Overlay.Opacity,
            LearnMode = _settings.Overlay.LearnMode,
        };
        _overlay = new OverlayWindow(_vm);
        _overlay.SettingsRequested += (_, _) => OpenSettings();
        _overlay.CalibrationRequested += (_, _) => OpenCalibration();
        _overlay.ExitRequested += (_, _) => Shutdown();
        _overlay.SideOverrideChanged += (_, side) => _pipeline.SetManualSide(side);
        _overlay.Show();

        _hotkeys = new HotkeyManager(_overlay);
        if (!_hotkeys.Register(HotkeyManager.MOD_CONTROL | HotkeyManager.MOD_SHIFT, VK_D, ToggleInteractive))
            _log.Warn("Ctrl+Shift+D уже занят другим приложением");
        if (!_hotkeys.Register(HotkeyManager.MOD_CONTROL | HotkeyManager.MOD_SHIFT, VK_O, ToggleVisibility))
            _log.Warn("Ctrl+Shift+O уже занят другим приложением");

        _pipeline.SnapshotUpdated += (_, snapshot) =>
            Dispatcher.InvokeAsync(() => _vm.Apply(snapshot, _profile.MyPosition));

        _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _positionTimer.Tick += (_, _) => PositionOverlay();
        _positionTimer.Start();
        PositionOverlay();

        _ = Task.Run(() => _pipeline.RunAsync(_cts.Token));

        // Автообновление в фоне: скачивается сейчас, ставится после закрытия приложения.
        _ = Task.Run(async () =>
        {
            var text = await new AppUpdater(_log).CheckAndDownloadAsync();
            if (text is not null) await Dispatcher.InvokeAsync(() => _vm.UpdateText = text);
        });

        // Первый запуск: сразу предлагаем заполнить профиль.
        if (_profile.Preferences.Count == 0 && !File.Exists(Path.Combine(userDir, "profile.json")))
            Dispatcher.InvokeAsync(OpenSettings, DispatcherPriority.ApplicationIdle);
    }

    private void ToggleInteractive()
    {
        _interactive = !_interactive;
        _overlay.SetInteractive(_interactive);
    }

    private void ToggleVisibility()
    {
        if (_overlay.IsVisible) _overlay.Hide();
        else _overlay.Show();
    }

    /// <summary>Overlay прилипает к правому краю окна Dota (физические пиксели).</summary>
    private void PositionOverlay()
    {
        var window = _capture.FindGameWindow();
        if (window is null || window.IsMinimized) return;
        var source = PresentationSource.FromVisual(_overlay);
        double scale = source?.CompositionTarget?.TransformToDevice.M11 ?? 1.0;
        int overlayWidthPx = (int)Math.Round(_overlay.ActualWidth * scale);
        int x = window.ClientRect.Right - overlayWidthPx - (int)(window.ClientRect.Width * _settings.Overlay.RightMargin);
        int y = window.ClientRect.Y + (int)(window.ClientRect.Height * _settings.Overlay.TopOffset);
        NativeWindow.MoveTo(_overlay, x, y);
    }

    private void OpenSettings()
    {
        var dlg = new SettingsWindow(_heroes, _profile.Clone());
        if (dlg.ShowDialog() == true && dlg.Result is { } profile)
        {
            _profile = profile;
            _settingsRepo.SaveProfile(profile);
            _pipeline.InvalidateRecommendations();
            if (_pipeline.Last is { } last) _vm.Apply(last, profile.MyPosition);
        }
    }

    private void OpenCalibration()
    {
        var dlg = new CalibrationWindow(_capture, _layout);
        dlg.ShowDialog();
        if (dlg.Saved) _pipeline.InvalidateRecommendations();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _cts.Cancel();
        _positionTimer?.Stop();
        _hotkeys?.Dispose();
        _gsi?.Dispose();
        if (_settings is not null)
        {
            _settings.Overlay.Opacity = _vm?.PanelOpacity ?? _settings.Overlay.Opacity;
            _settings.Overlay.LearnMode = _vm?.LearnMode ?? false;
            _settingsRepo?.SaveSettings(_settings);
        }
        base.OnExit(e);
    }
}
