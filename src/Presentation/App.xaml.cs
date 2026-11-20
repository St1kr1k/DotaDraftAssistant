using System.IO;
using System.Windows;
using System.Windows.Threading;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Presentation.Predictions;
using DraftAssistant.Infrastructure.Players;
using DraftAssistant.Application.Prediction;
using DraftAssistant.Application.Plan;
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
    /// <summary>План на игру после вашего пика и до какого момента его показывать после конца драфта.</summary>
    private GamePlan? _plan;
    private VisualDraftDetector _detector = null!;
    private EnemyPredictionService _predictions = null!;
    private EnemyPredictionWindow _predictionWindow = null!;
    private HeroImages _images = null!;
    private IReadOnlyDictionary<int, string> _heroNames = new Dictionary<int, string>();
    private DateTimeOffset? _planUntil;
    private string? _steamName;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var userDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DotaDraftAssistant");
        var dataDir = Path.Combine(AppContext.BaseDirectory, "data");
        _log = new FileLog(userDir);
        // Свежая статистика меты скачивается отдельно от версий программы (релиз «data»):
        // герои/портреты и статистика берутся из самого подходящего пакета, а встроенные данные — запасной вариант.
        var packs = new DataPackStore(dataDir, Path.Combine(userDir, "data"), _log);
        var heroesDir = packs.ResolveHeroesRoot();
        var patchDir = packs.ResolvePatchRoot();
        packs.Cleanup(heroesDir, patchDir);
        if (heroesDir != dataDir || patchDir != dataDir)
            _log.Info($"Данные: герои из {heroesDir}, статистика из {patchDir}");
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
            heroes = JsonHeroRepository.Load(heroesDir);
        }
        catch (FileNotFoundException ex)
        {
            MessageBox.Show($"{ex.Message}\n\nПереустановите приложение или запустите DataTool fetch.",
                            "Dota Draft Assistant", MessageBoxButton.OK, MessageBoxImage.Warning);
            Shutdown();
            return;
        }
        var patchProvider = new LocalPatchDataProvider(patchDir, _log);
        var patch = patchProvider.Load(_profile.Current.Rank);

        // --- Infrastructure: «глаза» ---
        _capture = new GdiScreenCaptureService();
        _layout = new JsonLayoutStore(userDir, dataDir);
        _templates = HeroTemplateLibrary.LoadFromDirectory(DataFiles.HeroesDir(heroesDir), heroes.All.Select(h => h.Id),
                                                           _settings.Current.Recognition.PortraitZoom);
        _log.Info($"Templates loaded for {_templates.HeroCount}/{heroes.All.Count} heroes");

        Func<RecognitionOptions> rec = () => _settings.Current.Recognition;
        var recognizer = new CompositeHeroRecognizer(
            new TemplateHeroRecognizer(_templates, rec), new ColorHistogramHeroRecognizer(_templates, rec), rec);
        var analyzer = new DraftFrameAnalyzer(_layout, recognizer, new SlotEmptinessClassifier(rec), rec);
        // Ник из Steam: по нему на экране драфта находится ваш слот (без GSI и параметров запуска).
        try { _steamName = SteamAccount.CurrentPersonaName(); } catch (Exception) { _steamName = null; }
        _log.Info($"Steam persona: {_steamName ?? "не найден"}");
        var textReader = new DraftTextReader(heroes, _log);
        var debugDir = Path.Combine(userDir, "debug");
        var detector = new VisualDraftDetector(
            _capture, analyzer, textReader,
            playerName: () => _gsi?.Current?.PlayerName ?? _profile.Current.Nickname ?? _steamName,
            debugDirectory: debugDir,
            saveDebugFrames: () => _settings.Current.Recognition.SaveDebugFrames);

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
        var roles = new StatsRoleInference(() => _pipeline is { Patch.PatchName: not "unknown" } p ? p.Patch : patch, new RoleTagPositionPrior());
        Func<ScoringOptions> scoring = () => _settings.Current.Scoring;
        IHeroEvaluator[] evaluators =
        [
            new CounterEvaluator(scoring),
            new LaneEvaluator(roles, scoring),
            new TeamNeedsSynergyEvaluator(),
            new PairSynergyEvaluator(scoring),
            new MetaEvaluator(scoring),
            new SafetyEvaluator(),
            new RoleFitEvaluator(roles),
            new PlayerPreferenceEvaluator(scoring),
        ];
        var recommendations = new RecommendationService(heroes, evaluators, scoring, roles);
        _detector = detector;
        _heroNames = heroes.All.ToDictionary(h => h.Id, h => h.LocalizedName);
        _predictions = new EnemyPredictionService(new OpenDotaPlayerSource(), _log);
        _predictions.Updated += () => Dispatcher.InvokeAsync(UpdatePredictions);
        _pipeline = new DraftPipeline(detector, _gsi, recommendations, roles, heroes, patchProvider,
                                      () => _profile.Current, _settings.Current, _log, new GamePlanService(roles));
        _profile.Changed += (_, _) => _pipeline.InvalidateRecommendations();

        // --- Presentation ---
        var images = new HeroImages(DataFiles.HeroesDir(heroesDir));

        _images = images;
        _predictionWindow = new EnemyPredictionWindow();
        NativeWindow.Handle(_predictionWindow);
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

        _mainVm = new MainViewModel { VersionText = $"v{AppUpdater.CurrentVersion}", PatchText = MainViewModel.PatchLine(patch, $"v{AppUpdater.CurrentVersion}") };
        _main = new MainWindow(
            _mainVm,
            new HeroesPage(new HeroesViewModel(heroes, _profile, roles, patch, images)),
            new PositionPage(new PositionViewModel(_profile, heroes, roles)),
            new OverlayPage(overlayVm),
            new SetupPage(detector, _layout, _gsi, _settings, _profile, debugDir, OpenCalibration, _steamName));
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
        _positionTimer.Tick += (_, _) => { UpdatePopupVisibility(); PositionPopup(); UpdatePredictions(); ExitIfGameClosed(); };
        _positionTimer.Start();

        _ = Task.Run(() => _pipeline.RunAsync(_cts.Token));

        _updater = new AppUpdater(_log);
        _updater.StatusChanged += (text, ready) => Dispatcher.InvokeAsync(() =>
        {
            _mainVm.UpdateText = text;
            _mainVm.CanRestartToUpdate = ready;
        });
        _ = Task.Run(() => _updater.RunAsync(_cts.Token));

        // Мета: свежие данные подключаются без перезапуска (между драфтами), новые герои — после перезапуска.
        if (AppUpdater.RepoUrl is { } repoUrl)
        {
            var dataUpdater = new DataPackUpdater(packs, repoUrl, _log);
            dataUpdater.PatchDataUpdated += (dir, pack) =>
            {
                patchProvider.DataDir = dir;
                _pipeline.ReloadPatchData();
            };
            dataUpdater.NewHeroesDownloaded += _ => Dispatcher.InvokeAsync(() =>
            {
                _mainVm.UpdateText = "Скачаны новые герои — перезапустите программу, чтобы она их узнавала";
            });
            var heroIds = heroes.All.Select(h => h.Id).ToHashSet();
            _ = Task.Run(() => dataUpdater.RunAsync(patchDir, heroIds, _cts.Token));
        }

        // GSI ещё не настроен — сразу показываем раздел, где это делается в один клик.
        // GSI теперь не обязателен: свой слот находится по нику из Steam. Раздел «Настройка» открываем,
        // только если ник неизвестен совсем.
        if (_steamName is null && _profile.Current.Nickname is null && !GsiInstaller.Status(_settings.Current.Gsi.DotaPath).ConfigInstalled)
            _main.ShowPage("setup");
    }

    private void OnSnapshot(DraftSnapshot s)
    {
        _lastSnapshot = s;
        bool inDraft = s.State.Phase is DraftPhase.DraftDetected or DraftPhase.BanPhase or DraftPhase.PickPhase;

        if (s.Plan is not null)
        {
            _plan = s.Plan;
            _planUntil = null; // пока идёт драфт, план виден без ограничения по времени
        }
        else if (inDraft && !s.OwnHeroPicked)
        {
            _plan = null; // новый драфт — старый план больше не нужен
        }
        if (_plan is not null && !inDraft && _planUntil is null)
            _planUntil = DateTimeOffset.Now.AddSeconds(Math.Max(0, _settings.Current.Overlay.PlanLingerSeconds));

        _mainVm.Apply(s);
        _popupVm.ShowPlan(PlanVisible() ? _plan : null);
        _popupVm.Apply(s);
        UpdatePopupVisibility();
        UpdatePredictions();
    }

    /// <summary>
    /// Догадки о пиках соперников поверх их пустых слотов (если включено в настройках окошка).
    /// Иконка слота исчезает, как только соперник выбрал героя.
    /// </summary>
    private void UpdatePredictions()
    {
        var s = _lastSnapshot;
        bool inDraft = s is { DraftConfirmed: true } && s.State.Phase is DraftPhase.DraftDetected or DraftPhase.BanPhase or DraftPhase.PickPhase;
        var window = _capture.FindGameWindow();
        if (!_settings.Current.Overlay.ShowEnemyPredictions || _userHidden || s is null || !inDraft ||
            s.Status != PipelineStatus.Observing || _detector.CurrentGrid is not { } grid ||
            window is null || window.IsMinimized)
        {
            if (_predictionWindow.IsVisible) _predictionWindow.Hide();
            return;
        }

        var predictions = _predictions.Predict(s);
        if (predictions.Count == 0)
        {
            if (_predictionWindow.IsVisible) _predictionWindow.Hide();
            return;
        }

        var c = window.ClientRect;
        int height = grid.BarY + 2;
        NativeWindow.Place(_predictionWindow, c.X, c.Y, c.Width, height);
        if (!_predictionWindow.IsVisible) _predictionWindow.Show();

        double k = _predictionWindow.PixelsToDip;
        double skewDeg = Math.Atan(PlayerBarGrid.Skew / PlayerBarGridDetector.TopToBottomBars) * 180 / Math.PI;
        _predictionWindow.Tiles.Clear();
        foreach (var p in predictions)
        {
            bool radiant = p.Slot.Side == DraftSide.Radiant;
            double shift = PlayerBarGrid.Skew / 2 * grid.Pitch * (radiant ? -1 : 1);
            double w = grid.BarWidth, h = 0.48 * grid.Pitch;
            double left = grid.Center(p.Slot.Side, p.Slot.Index) - w / 2 + shift;
            double top = grid.BarY - 0.50 * grid.Pitch;
            string hero = _heroNames.GetValueOrDefault(p.HeroId, "?");
            _predictionWindow.Tiles.Add(new PredictionTile(
                left * k, top * k, w * k, h * k, radiant ? skewDeg : -skewDeg,
                _images.Portrait(p.HeroId, 256), $"вероятно {hero} · {p.Share:P0}", Math.Max(9, 0.075 * grid.Pitch * k)));
        }
    }

    private bool _gameSeen;
    private DateTimeOffset? _gameGoneSince;

    /// <summary>
    /// Dota закрылась — закрываемся и мы (скачанное обновление при этом установится само).
    /// Только если игра была запущена при работающей программе: запуск программы до игры её не закрывает.
    /// </summary>
    private void ExitIfGameClosed()
    {
        bool running;
        try
        {
            var found = System.Diagnostics.Process.GetProcessesByName("dota2");
            running = found.Length > 0;
            foreach (var p in found) p.Dispose();
        }
        catch (Exception) { return; }
        if (running) { _gameSeen = true; _gameGoneSince = null; return; }
        if (!_gameSeen || !_settings.Current.Overlay.ExitWithGame || _popup.IsMoveMode) return;
        _gameGoneSince ??= DateTimeOffset.Now;
        if (DateTimeOffset.Now - _gameGoneSince < TimeSpan.FromSeconds(10)) return;
        _log.Info("Dota 2 закрыта — программа закрывается вместе с ней");
        Shutdown();
    }

    /// <summary>План виден после вашего пика до конца драфта и ещё PlanLingerSeconds после него.</summary>
    private bool PlanVisible() =>
        _plan is not null && _settings.Current.Overlay.ShowPlan &&
        (_planUntil is null || DateTimeOffset.Now < _planUntil);

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
        else if (!_userHidden && PlanVisible())
        {
            if (!_popupVm.IsPlan) _popupVm.ShowPlan(_plan);
            show = true;
        }
        else if (_userHidden || _lastSnapshot is not { Status: PipelineStatus.Observing } s || !_popupVm.HasPicks)
        {
            show = false;
        }
        else
        {
            var phase = s.State.Phase;
            // Только подтверждённый драфт (есть бан или пик): цветные полоски игроков бывают и в лобби.
            bool inDraft = s.DraftConfirmed && phase is DraftPhase.DraftDetected or DraftPhase.BanPhase or DraftPhase.PickPhase;
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
        // Пока показан план, Ctrl+Shift+O просто закрывает его (подсказки в следующем драфте появятся как обычно).
        if (!_userHidden && PlanVisible())
        {
            _planUntil = DateTimeOffset.Now;
            _popupVm.ShowPlan(null);
            if (_lastSnapshot is not null) _popupVm.Apply(_lastSnapshot);
            UpdatePopupVisibility();
            return;
        }
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
