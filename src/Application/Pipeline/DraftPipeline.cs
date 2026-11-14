using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Draft;
using DraftAssistant.Application.Recommendation;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Patch;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Roles;
using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Pipeline;

public enum PipelineStatus
{
    Starting,
    GameNotFound,
    LayoutNotCalibrated,
    Observing,
    Error,
}

public enum SideSource { None, Gsi, OwnHeroMatch, Manual }

public sealed record DraftSnapshot(
    PipelineStatus Status,
    string? StatusMessage,
    DraftState State,
    SideSource SideSource,
    IReadOnlyList<HeroRecommendation> Recommendations,
    IReadOnlyDictionary<int, PositionDistribution> EnemyRoles,
    PatchData Patch,
    double ScreenConfidence,
    /// <summary>Ваш герой уже выбран (по данным GSI). Окошко подсказок после этого скрывается.</summary>
    bool OwnHeroPicked);

/// <summary>
/// Склеивает слои: детектор → трекер → машина состояний → рекомендации → событие для UI.
/// Работает в фоне с ограниченной частотой анализа. Ничего не знает о WPF и о координатах.
/// </summary>
public sealed class DraftPipeline
{
    private readonly IDraftDetector _detector;
    private readonly IGameStateHintSource? _hints;
    private readonly IRecommendationService _recommendations;
    private readonly IRoleInferenceService _roles;
    private readonly IHeroRepository _heroes;
    private readonly IPatchDataProvider _patchProvider;
    private readonly Func<PlayerProfile> _profile;
    private readonly AppSettings _settings;
    private readonly IAppLog _log;
    private readonly DraftStateTracker _tracker;
    private readonly DraftStateMachine _machine;

    private PatchData _patch = PatchData.Empty;
    private volatile bool _recommendationsDirty = true;
    private volatile int _manualSide = -1; // -1 = авто
    private DraftSnapshot? _last;
    // Оценки всех героев до последнего изменения драфта и после него — для дельты "82 → 94".
    private IReadOnlyDictionary<int, double> _baselineScores = new Dictionary<int, double>();
    private IReadOnlyDictionary<int, double> _currentScores = new Dictionary<int, double>();

    public DraftPipeline(
        IDraftDetector detector,
        IGameStateHintSource? hints,
        IRecommendationService recommendations,
        IRoleInferenceService roles,
        IHeroRepository heroes,
        IPatchDataProvider patchProvider,
        Func<PlayerProfile> profile,
        AppSettings settings,
        IAppLog log)
    {
        _detector = detector;
        _hints = hints;
        _recommendations = recommendations;
        _roles = roles;
        _heroes = heroes;
        _patchProvider = patchProvider;
        _profile = profile;
        _settings = settings;
        _log = log;
        _tracker = new DraftStateTracker(detector.Slots, settings.Tracker);
        _machine = new DraftStateMachine(settings.StateMachine);
    }

    public event EventHandler<DraftSnapshot>? SnapshotUpdated;

    public DraftSnapshot? Last => _last;

    /// <summary>Профиль или веса изменились — пересчитать рекомендации на следующем кадре.</summary>
    public void InvalidateRecommendations() => _recommendationsDirty = true;

    /// <summary>Резервный вариант, если сторону нельзя определить автоматически. null = авто.</summary>
    public void SetManualSide(DraftSide? side)
    {
        _manualSide = side is null ? -1 : (int)side.Value;
        _recommendationsDirty = true;
    }

    public async Task RunAsync(CancellationToken ct)
    {
        _patch = _patchProvider.Load();
        _log.Info($"Patch data: {_patch.PatchName}, heroes={_patch.HeroStats.Count}, matchups={_patch.Matchups.Count}");

        var period = TimeSpan.FromMilliseconds(1000.0 / Math.Clamp(_settings.Pipeline.AnalysisFps, 1, 30));
        using var timer = new PeriodicTimer(period);
        do
        {
            try
            {
                Tick();
            }
            catch (Exception ex)
            {
                _log.Error("Pipeline tick failed", ex);
                Publish(_last?.State ?? DraftState.Initial(_detector.Slots), PipelineStatus.Error, ex.Message,
                        SideSource.None, 0, force: true);
            }
        }
        while (await timer.WaitForNextTickAsync(ct).ConfigureAwait(false));
    }

    /// <summary>Один шаг pipeline. Публичный — для тестов и отладочных инструментов.</summary>
    public void Tick()
    {
        var observation = _detector.Observe();
        if (observation is null)
        {
            Publish(_last?.State ?? DraftState.Initial(_detector.Slots), PipelineStatus.GameNotFound,
                    "Окно Dota 2 не найдено", _last?.SideSource ?? SideSource.None, 0);
            return;
        }

        var hint = FreshHint();
        var external = hint?.State ?? ExternalGameState.Unknown;

        bool slotsChanged = false;
        if (observation.DraftScreenVisible && _machine.Phase != DraftPhase.Completed)
            slotsChanged = _tracker.Update(observation.Slots);

        var slots = _tracker.Slots;
        int picks = slots.Count(s => s.Id.Kind == SlotKind.Pick && s.Status == SlotStatus.Confirmed);
        int bans = slots.Count(s => s.Id.Kind == SlotKind.Ban && s.Status == SlotStatus.Confirmed);
        int totalPicks = slots.Count(s => s.Id.Kind == SlotKind.Pick);

        var transition = _machine.Update(observation.DraftScreenVisible, external, picks, totalPicks, bans);
        if (transition is { From: DraftPhase.Idle, To: DraftPhase.DraftDetected })
        {
            _log.Info("Draft detected — новый драфт, состояние сброшено");
            _tracker.Reset();
            _baselineScores = new Dictionary<int, double>();
            _currentScores = new Dictionary<int, double>();
            if (observation.DraftScreenVisible) _tracker.Update(observation.Slots);
            slots = _tracker.Slots;
        }
        if (transition is not null) _log.Info($"Phase {transition.From} → {transition.To}");

        var (side, sideSource) = ResolveSide(hint, slots);
        var state = new DraftState(_machine.Phase, slots, side, observation.Timestamp);

        var status = observation.Issue == ObservationIssue.LayoutNotCalibrated
            ? PipelineStatus.LayoutNotCalibrated
            : PipelineStatus.Observing;
        string? message = status == PipelineStatus.LayoutNotCalibrated
            ? "Разметка экрана драфта не откалибрована (Ctrl+Shift+D → Калибровка)"
            : null;

        bool sideChanged = _last?.State.MySide != side;
        bool ownPickedChanged = _last is not null && _last.OwnHeroPicked != (hint?.OwnHeroId is not null);
        bool changed = slotsChanged || transition is not null || sideChanged || _recommendationsDirty
                       || _last?.Status != status || ownPickedChanged;
        if (changed)
            Publish(state, status, message, sideSource, observation.ScreenConfidence, force: true);
    }

    private GameStateHint? FreshHint()
    {
        var h = _hints?.Current;
        if (h is null) return null;
        return DateTimeOffset.UtcNow - h.ReceivedAt > TimeSpan.FromSeconds(_settings.Gsi.StaleAfterSeconds) ? null : h;
    }

    private (DraftSide? Side, SideSource Source) ResolveSide(GameStateHint? hint, IReadOnlyList<SlotState> slots)
    {
        if (_manualSide >= 0) return ((DraftSide)_manualSide, SideSource.Manual);
        if (hint?.Team is { } team) return (team, SideSource.Gsi);
        if (hint?.OwnHeroId is { } own)
        {
            var slot = slots.FirstOrDefault(s => s.Id.Kind == SlotKind.Pick && s.Status == SlotStatus.Confirmed && s.HeroId == own);
            if (slot is not null) return (slot.Id.Side, SideSource.OwnHeroMatch);
        }
        // Сохраняем ранее определённую сторону до конца драфта.
        if (_last?.State.MySide is { } prev && _machine.Phase != DraftPhase.Idle) return (prev, _last.SideSource);
        return (null, SideSource.None);
    }

    private void Publish(DraftState state, PipelineStatus status, string? message, SideSource sideSource,
                         double screenConfidence, bool force = false)
    {
        if (!force && _last is not null && _last.Status == status && _last.StatusMessage == message) return;

        IReadOnlyList<HeroRecommendation> recs = _last?.Recommendations ?? [];
        bool draftChanged = _last is null || !SameDraft(_last.State, state);
        if ((_recommendationsDirty || draftChanged) && status != PipelineStatus.GameNotFound)
        {
            // Дельта считается относительно состояния ДО последнего изменения драфта,
            // а не относительно предыдущего пересчёта (иначе "82 → 94" исчезало бы сразу).
            if (draftChanged) _baselineScores = _currentScores;
            var all = _recommendations.Recommend(state, _profile(), _patch, int.MaxValue, _baselineScores);
            _currentScores = all.ToDictionary(r => r.Hero.Id, r => r.Score);
            recs = all.Take(_settings.Pipeline.RecommendationCount).ToList();
            _recommendationsDirty = false;
        }

        var enemyRoles = state.EnemyPicks
            .Select(_heroes.Find).OfType<Hero>()
            .ToDictionary(h => h.Id, h => _roles.Infer(h));

        bool ownPicked = FreshHint()?.OwnHeroId is not null;
        _last = new DraftSnapshot(status, message, state, sideSource, recs, enemyRoles, _patch, screenConfidence, ownPicked);
        SnapshotUpdated?.Invoke(this, _last);
    }

    private static bool SameDraft(DraftState a, DraftState b) =>
        a.MySide == b.MySide &&
        a.Phase == b.Phase &&
        a.Slots.Select(s => (s.Id, s.Status, s.HeroId)).SequenceEqual(b.Slots.Select(s => (s.Id, s.Status, s.HeroId)));
}
