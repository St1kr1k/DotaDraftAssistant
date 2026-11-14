using System.IO;
using System.Windows;
using System.Windows.Threading;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Application.Recommendation;
using DraftAssistant.Application.Recommendation.Evaluators;
using DraftAssistant.Application.Roles;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Scoring;
using DraftAssistant.Infrastructure.Capture;
using DraftAssistant.Infrastructure.Gsi;
using DraftAssistant.Infrastructure.Recognition;
using DraftAssistant.Infrastructure.Storage;
using DraftAssistant.Infrastructure.Vision;
using DraftAssistant.Presentation.Calibration;
using DraftAssistant.Presentation.Common;
using DraftAssistant.Presentation.Interop;
using DraftAssistant.Presentation.Main;
using DraftAssistant.Presentation.Pages;
using DraftAssistant.Presentation.Popup;
using DraftAssistant.Presentation.Updates;

namespace DraftAssistant.Presentation;

/// <summary>Composition root: здесь (и только здесь) слои соединяются друг с другом.</summary>
public partial class App : System.Windows.Application
{
    private const uint VK_D = 0x44, VK_O = 0x4F;

    private readonly CancellationTokenSource _cts = new();
    private IAppLog _log = NullLog.Instance;
    private SettingsStore _settings = null!;
    private ProfileStore _profile = null!;
    private GdiScreenCaptureService _capture = null!;
    private JsonLayoutStore _layout = null!;
    private HeroTemplateLibrary? _templates;
    private GsiListener? _gsi;
    private DraftPipeline _pipeline = null!;
    private AppUpdater _updater = null!;
    private PopupViewModel _popupVm = null!;
    private PopupWindow _popup = null!;
    private MainWindow _main = null!;
    private MainViewModel _mainVm = null!;
    private HotkeyManager? _hotkeys;
    private DispatcherTimer? _positionTimer;
    private DraftSnapshot? _lastSnapshot;
    private bool _userHidden;

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

        var settingsRepo = new JsonSettingsRepository(userDir);
        _settings = new SettingsStore(settingsRepo, settingsRepo.LoadSettings());
        _profile = new ProfileStore(settingsRepo, settingsRepo.LoadProfile());

        JsonHeroRepository heroes;
        try
        {
            heroes = JsonHeroRepository.Load(dataDir);
        }
        catch (FileNotFoundException ex)
        {
            MessageBox.Show($"{ex.Message}\n\nПереустановите приложение или запустите DataTool fetch.",
                            "Dota Draft Assistant", MessageBoxButton.OK, MessageBoxImage.Warning);
            Shutdown();
            return;
        }
        var patchProvider = new LocalPatchDataProvider(dataDir, _log);
        var patch = patchProvider.Load();

        // --- Infrastructure: «глаза» ---
        _capture = new GdiScreenCaptureService();
        _layout = new JsonLayoutStore(userDir, dataDir);
        _templates = HeroTemplateLibrary.LoadFromDirectory(DataFiles.HeroesDir(dataDir), heroes.All.Select(h => h.Id));
        _log.Info($"Templates loaded for {_templates.HeroCount}/{heroes.All.Count} heroes");

        Func<RecognitionOptions> rec = () => _settings.Current.Recognition;
        var recognizer = new CompositeHeroRecognizer(
            new TemplateHeroRecognizer(_templates, rec), new ColorHistogramHeroRecognizer(_templates, rec), rec);
        var analyzer = new DraftFrameAnalyzer(_layout, recognizer, new SlotEmptinessClassifier(rec), rec);
        var detector = new VisualDraftDetector(_capture, analyzer);

        if (_settings.Current.Gsi.Enabled)
        {
            try
            {
                _gsi = new GsiListener(_settings.Current.Gsi.Port, _log);
                _gsi.Start();
            }
            catch (Exception ex)
            {
                _log.Warn($"GSI listener не запущен: {ex.Message}");
                _gsi?.Dispose();
                _gsi = null;
            }
        }

        // --- Application: «мозг» ---
        var roles = new RoleTagPositionPrior();
        Func<ScoringOptions> scoring = () => _settings.Current.Scoring;
        IHeroEvaluator[] evaluators =
        [
            new CounterEvaluator(scoring),
            new TeamNeedsSynergyEvaluator(),
            new MetaEvaluator(scoring),
            new RoleFitEvaluator(roles),
            new PlayerPreferenceEvaluator(scoring),
        ];
        var recommendations = new RecommendationService(heroes, evaluators, () => _settings.Current.Scoring.Weights);
        _pipeline = new DraftPipeline(detector, _gsi, recommendations, roles, heroes, patchProvider,
                                      () => _profile.Current, _settings.Current, _log);
        _profile.Changed += (_, _) => _pipeline.InvalidateRecommendations();

        // --- Presentation ---
        var images = new HeroImages(DataFiles.HeroesDir(dataDir));

        _popupVm = new PopupViewModel(images);
        _popupVm.ApplySettings(_settings.Current.Overlay);
        _popup = new PopupWindow(_popupVm);
        _popup.Moved += (_, rect) => SavePopupPosition(rect);
        _settings.Changed += (_, _) =>
        {
            _popupVm.ApplySettings(_settings.Current.Overlay);
            UpdatePopupVisibility();
            PositionPopup();
        };
        // Окно создаётся сразу, чтобы горячие клавиши работали, даже пока оно скрыто.
        NativeWindow.Handle(_popup);

        var overlayVm = new OverlaySettingsViewModel(_settings);
        overlayVm.MoveModeRequested += (_, _) => ToggleMoveMode();

        _mainVm = new MainViewModel { VersionText = $"v{AppUpdater.CurrentVersion}", PatchText = $"Патч {patch.PatchName} · v{AppUpdater.CurrentVersion}" };
        _main = new MainWindow(
            _mainVm,
            new HeroesPage(new HeroesViewModel(heroes, _profile, roles, patch, images)),
            new PositionPage(new PositionViewModel(_profile, heroes, roles)),
            new OverlayPage(overlayVm),
            new CalibrationPage(_layout, OpenCalibration));
        _main.Closed += (_, _) => Shutdown();
        _main.RestartToUpdateRequested += (_, _) => _updater.RestartAndApply();
        _main.Show();

        _hotkeys = new HotkeyManager(_popup);
        if (!_hotkeys.Register(HotkeyManager.MOD_CONTROL | HotkeyManager.MOD_SHIFT, VK_D, ToggleMoveMode))
            _log.Warn("Ctrl+Shift+D уже занят другим приложением");
        if (!_hotkeys.Register(HotkeyManager.MOD_CONTROL | HotkeyManager.MOD_SHIFT, VK_O, ToggleUserHidden))
            _log.Warn("Ctrl+Shift+O уже занят другим приложением");

        _pipeline.SnapshotUpdated += (_, snapshot) => Dispatcher.InvokeAsync(() => OnSnapshot(snapshot));

        _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _positionTimer.Tick += (_, _) => PositionPopup();
        _positionTimer.Start();

        _ = Task.Run(() => _pipeline.RunAsync(_cts.Token));

        _updater = new AppUpdater(_log);
        _updater.StatusChanged += (text, ready) => Dispatcher.InvokeAsync(() =>
        {
            _mainVm.UpdateText = text;
            _mainVm.CanRestartToUpdate = ready;
        });
        _ = Task.Run(() => _updater.RunAsync(_cts.Token));

        // Первый запуск без калибровки — сразу показываем, что нужно сделать.
        if (!_layout.Current.Calibrated) _main.ShowPage("calibration");
    }

    private void OnSnapshot(DraftSnapshot s)
    {
        _lastSnapshot = s;
        _mainVm.Apply(s);
        _popupVm.Apply(s, _profile.Current.MyPosition);
        UpdatePopupVisibility();
    }

    /// <summary>
    /// Окошко видно во время драфта (по настройке — до вашего пика или весь драфт).
    /// В режиме перемещения видно всегда, чтобы его можно было поставить на место.
    /// </summary>
    private void UpdatePopupVisibility()
    {
        bool show;
        if (_popup.IsMoveMode)
        {
            show = true;
        }
        else if (_userHidden || _lastSnapshot is not { Status: PipelineStatus.Observing } s || !_popupVm.HasPicks)
        {
            show = false;
        }
        else
        {
            var phase = s.State.Phase;
            bool inDraft = phase is DraftPhase.DraftDetected or DraftPhase.BanPhase or DraftPhase.PickPhase;
            show = _settings.Current.Overlay.ShowMode == PopupShowMode.WholeDraft
                ? inDraft
                : inDraft && !s.OwnHeroPicked;
        }

        if (show && !_popup.IsVisible) { _popup.Show(); PositionPopup(); }
        else if (!show && _popup.IsVisible) _popup.Hide();
    }

    private void ToggleMoveMode()
    {
        _popup.SetMoveMode(!_popup.IsMoveMode);
        UpdatePopupVisibility();
        PositionPopup();
    }

    private void ToggleUserHidden()
    {
        _userHidden = !_userHidden;
        UpdatePopupVisibility();
    }

    /// <summary>Положение окошка — в долях окна Dota, поэтому переживает смену разрешения.</summary>
    private void PositionPopup()
    {
        if (!_popup.IsVisible || _popup.IsMoveMode) return;
        var window = _capture.FindGameWindow();
        if (window is null || window.IsMinimized) return;

        var o = _settings.Current.Overlay;
        var c = window.ClientRect;
        var size = NativeWindow.GetRect(_popup);
        int x, y;
        if (o.PositionX < 0 || o.PositionY < 0)
        {
            x = c.Right - size.Width - (int)(c.Width * o.RightMargin);
            y = c.Y + (int)(c.Height * o.TopOffset);
        }
        else
        {
            x = c.X + (int)(c.Width * o.PositionX);
            y = c.Y + (int)(c.Height * o.PositionY);
        }
        x = Math.Clamp(x, c.X, Math.Max(c.X, c.Right - size.Width));
        y = Math.Clamp(y, c.Y, Math.Max(c.Y, c.Bottom - size.Height));
        NativeWindow.MoveTo(_popup, x, y);
    }

    private void SavePopupPosition(NativeWindow.ScreenRect rect)
    {
        var window = _capture.FindGameWindow();
        if (window is null || window.ClientRect.IsEmpty) return;
        var c = window.ClientRect;
        _settings.Current.Overlay.PositionX = Math.Clamp((rect.Left - c.X) / (double)c.Width, 0, 1);
        _settings.Current.Overlay.PositionY = Math.Clamp((rect.Top - c.Y) / (double)c.Height, 0, 1);
        _settings.Save();
    }

    private bool OpenCalibration()
    {
        var dlg = new CalibrationWindow(_capture, _layout) { Owner = _main };
        dlg.ShowDialog();
        if (dlg.Saved) _pipeline.InvalidateRecommendations();
        return dlg.Saved;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _cts.Cancel();
        _positionTimer?.Stop();
        _hotkeys?.Dispose();
        _gsi?.Dispose();
        _settings?.Save();
        base.OnExit(e);
    }
}
