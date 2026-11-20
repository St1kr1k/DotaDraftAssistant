using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Draft;
using DraftAssistant.Application.Recommendation;
using DraftAssistant.Application.Plan;
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

public enum SideSource { None, Gsi, Screen, OwnHeroMatch, Manual }

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
    bool OwnHeroPicked,
    /// <summary>Позиция, под которую считаются рекомендации.</summary>
    Position EffectivePosition,
    /// <summary>true — позиция прочитана с экрана драфта (рейтинг), false — взята из профиля.</summary>
    bool PositionFromDraft)
{
    /// <summary>План на игру после вашего пика (null — герой ещё не выбран или не определён).</summary>
    public GamePlan? Plan { get; init; }

    /// <summary>Ники игроков под слотами, прочитанные с экрана драфта.</summary>
    public IReadOnlyDictionary<SlotId, string> PlayerNames { get; init; } = new Dictionary<SlotId, string>();
}

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
    private readonly GamePlanService? _plans;
    private GamePlan? _plan;
    private string? _draftId;
    private readonly Dictionary<SlotId, string> _playerNames = new();
    private int? _mySlotCandidate;
    private readonly Dictionary<SlotId, int?> _loggedSlots = new();
    private DraftSide? _loggedSide;
    private int? _loggedMySlot;
    private int _framesSaved;
    private int _framesPicks = -1;
    private string _planKey = "";
    private readonly Func<PlayerProfile> _profile;
    private readonly AppSettings _settings;
    private readonly IAppLog _log;
    private readonly DraftStateTracker _tracker;
    private readonly DraftStateMachine _machine;

    private PatchData _patch = PatchData.Empty;
    private volatile bool _recommendationsDirty = true;
    private volatile bool _patchReloadPending;
    private volatile int _manualSide = -1; // -1 = авто
    private DraftSnapshot? _last;

    // Прочитанное с экрана за текущий драфт (сбрасывается при новом драфте).
    private readonly Dictionary<SlotId, Position> _positions = new();
    private readonly HashSet<int> _chatBans = new();
    private DraftSide? _screenAllySide;
    private int? _mySlot;
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
        IAppLog log,
        GamePlanService? plans = null)
    {
        _plans = plans;
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

    /// <summary>Подключены другие данные патча (смена ранга или свежие данные меты).</summary>
    public event EventHandler<PatchData>? PatchDataChanged;

    public DraftSnapshot? Last => _last;

    /// <summary>Данные патча, по которым сейчас считаются рекомендации (для ранга пользователя).</summary>
    public PatchData Patch => _patch;

    /// <summary>
    /// Скачаны свежие данные меты — перечитать их. Подключаются вне драфта (пока никто не выбрал героя),
    /// чтобы оценки не менялись посреди пиков.
    /// </summary>
    public void ReloadPatchData() => _patchReloadPending = true;

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
        _patch = _patchProvider.Load(_profile().Rank);
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

        // Во время самой игры полоска героев сверху похожа на экран драфта. Это не драфт, если:
        // GSI говорит, что идёт игра, или «драфт» появился сразу почти со всеми выбранными героями.
        if (observation.DraftScreenVisible)
        {
            int rawPicks = observation.Slots.Count(s => s.Slot.Kind == SlotKind.Pick && s.Content == ObservedContent.Hero);
            bool inGame = external == ExternalGameState.InGame
                          || (_machine.Phase == DraftPhase.Idle && (rawPicks >= 8 || external == ExternalGameState.PostDraft));
            if (inGame) observation = observation with { DraftScreenVisible = false };
        }

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
            _draftId = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            _playerNames.Clear();
            _loggedSlots.Clear();
            _loggedSide = null;
            _loggedMySlot = null;
            _framesSaved = 0;
            _framesPicks = -1;
            _log.Info($"Draft detected — новый драфт {_draftId}, состояние сброшено");
            _tracker.Reset();
            _positions.Clear();
            _chatBans.Clear();
            _screenAllySide = null;
            _mySlot = null;
            _mySlotCandidate = null;
            _baselineScores = new Dictionary<int, double>();
            _currentScores = new Dictionary<int, double>();
            if (observation.DraftScreenVisible) _tracker.Update(observation.Slots);
            slots = _tracker.Slots;
        }
        if (transition is not null) _log.Info($"Phase {transition.From} → {transition.To}");

        bool textChanged = observation.DraftScreenVisible && _machine.Phase != DraftPhase.Idle && MergeText(observation);

        var (side, sideSource) = ResolveSide(hint, slots);
        var state = new DraftState(_machine.Phase, slots, side, observation.Timestamp)
        {
            Positions = new Dictionary<SlotId, Position>(_positions),
            ExtraBans = new HashSet<int>(_chatBans),
            MySlotIndex = _mySlot,
        };

        var status = observation.Issue == ObservationIssue.LayoutNotCalibrated
            ? PipelineStatus.LayoutNotCalibrated
            : PipelineStatus.Observing;
        string? message = status == PipelineStatus.LayoutNotCalibrated
            ? "Разметка экрана драфта не откалибрована (Ctrl+Shift+D → Калибровка)"
            : null;

        LogDraftChanges(state, sideSource, hint, slotsChanged || transition is not null);

        bool sideChanged = _last?.State.MySide != side;
        bool ownPickedChanged = _last is not null && _last.OwnHeroPicked != OwnHeroPicked(state, hint);
        bool changed = slotsChanged || transition is not null || sideChanged || _recommendationsDirty
                       || _last?.Status != status || ownPickedChanged || textChanged;
        if (changed)
            Publish(state, status, message, sideSource, observation.ScreenConfidence, force: true);
    }

    /// <summary>
    /// Подробный лог драфта: какие герои распознаны, какая сторона и откуда, какой слот ваш.
    /// Плюс кадр экрана на каждом новом пике (если включено сохранение кадров) — по ним видно,
    /// где распознавание ошиблось.
    /// </summary>
    private void LogDraftChanges(DraftState state, SideSource sideSource, GameStateHint? hint, bool slotsMaybeChanged)
    {
        if (_machine.Phase == DraftPhase.Idle || _draftId is null) return;

        if (slotsMaybeChanged)
        {
            foreach (var s in state.Slots.Where(s => s.Status == SlotStatus.Confirmed))
            {
                if (_loggedSlots.TryGetValue(s.Id, out var prev) && prev == s.HeroId) continue;
                _loggedSlots[s.Id] = s.HeroId;
                var name = s.HeroId is { } id ? _heroes.Find(id)?.LocalizedName ?? $"#{id}" : "?";
                _log.Info($"Слот {s.Id}: {name} ({s.Confidence:F2})");
            }
            int picks = state.Slots.Count(s => s.Id.Kind == SlotKind.Pick && s.Status == SlotStatus.Confirmed);
            if (picks != _framesPicks)
            {
                _framesPicks = picks;
                if (_framesSaved++ < 14) _detector.SaveDebugFrame(_draftId, $"picks{picks}");
            }
        }
        if (state.MySide != _loggedSide)
        {
            _loggedSide = state.MySide;
            _log.Info($"Сторона: {state.MySide?.ToString() ?? "не определена"} (источник: {sideSource}; GSI: {(hint is null ? "нет" : $"{hint.State}, team={hint.Team}, hero={hint.OwnHeroId}")})");
        }
        if (state.MySlotIndex != _loggedMySlot)
        {
            _loggedMySlot = state.MySlotIndex;
            _log.Info($"Мой слот: {state.MySlotIndex?.ToString() ?? "не найден"}; позиций прочитано: {state.Positions.Count}");
        }
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
        // Подписи ролей в рейтинге видны только у своей команды.
        if (_screenAllySide is { } screen) return (screen, SideSource.Screen);
        if (hint?.OwnHeroId is { } own)
        {
            var slot = slots.FirstOrDefault(s => s.Id.Kind == SlotKind.Pick && s.Status == SlotStatus.Confirmed && s.HeroId == own);
            if (slot is not null) return (slot.Id.Side, SideSource.OwnHeroMatch);
        }
        // Сохраняем ранее определённую сторону до конца драфта.
        if (_last?.State.MySide is { } prev && _machine.Phase != DraftPhase.Idle) return (prev, _last.SideSource);
        return (null, SideSource.None);
    }

    /// <summary>
    /// Вы уже выбрали героя? По GSI (если настроен) или по экрану: в вашем слоте (найден по нику)
    /// появился подтверждённый герой. Параметр запуска для этого не нужен.
    /// </summary>
    private static bool OwnHeroPicked(DraftState state, GameStateHint? hint)
    {
        if (hint?.OwnHeroId is not null) return true;
        if (state.MySide is { } side && state.MySlotIndex is { } slot)
        {
            var mine = state.Slots.FirstOrDefault(s => s.Id == new SlotId(side, SlotKind.Pick, slot));
            return mine is { Status: SlotStatus.Confirmed };
        }
        return false;
    }

    /// <summary>Добавляет роли, баны, сторону и свой слот, прочитанные с экрана. true — что-то изменилось.</summary>
    private bool MergeText(DraftObservation o)
    {
        bool changed = false;
        if (o.Roles is { } roles)
        {
            foreach (var (slot, pos) in roles)
            {
                if (_positions.TryGetValue(slot, out var old) && old == pos) continue;
                _positions[slot] = pos;
                changed = true;
            }
        }
        if (o.BannedHeroes is { } bans)
            foreach (var b in bans)
                if (_chatBans.Add(b))
                {
                    changed = true;
                    _log.Info($"Бан из чата: {_heroes.Find(b)?.LocalizedName ?? b.ToString()}");
                }
        if (o.AllySide is { } ally && _screenAllySide != ally) { _screenAllySide = ally; changed = true; }
        if (o.OwnSlotIndex is { } own && _mySlot != own)
        {
            // Свой слот меняем, только если новое прочтение повторилось дважды подряд (OCR ников иногда ошибается).
            if (_mySlot is null || _mySlotCandidate == own) { _mySlot = own; _mySlotCandidate = null; changed = true; }
            else _mySlotCandidate = own;
        }
        else if (o.OwnSlotIndex == _mySlot) _mySlotCandidate = null;
        if (o.PlayerNames is { } names)
        {
            foreach (var (slot, name) in names)
            {
                // Более длинное прочтение ника надёжнее (OCR иногда теряет часть букв).
                if (_playerNames.TryGetValue(slot, out var old) && old.Length >= name.Length) continue;
                _playerNames[slot] = name;
                changed = true;
            }
        }
        return changed;
    }

    /// <summary>
    /// Позиция для рекомендаций: в рейтинге — та, что подписана под вашим ником в этом драфте;
    /// иначе — из профиля.
    /// </summary>
    private (Position Position, bool FromDraft) EffectivePosition(DraftState state)
    {
        if (state.MySide is { } side && state.MySlotIndex is { } slot &&
            state.Positions.TryGetValue(new SlotId(side, SlotKind.Pick, slot), out var pos))
            return (pos, true);
        return (_profile().MyPosition, false);
    }

    private void Publish(DraftState state, PipelineStatus status, string? message, SideSource sideSource,
                         double screenConfidence, bool force = false)
    {
        if (!force && _last is not null && _last.Status == status && _last.StatusMessage == message) return;

        var (position, fromDraft) = EffectivePosition(state);
        var profile = _profile();
        bool reload = _patchReloadPending && state.ConfirmedPickCount == 0;
        if (profile.Rank != _patch.Rank || reload)
        {
            // Пользователь сменил ранг — статистика другой группы рангов; или скачаны свежие данные меты.
            if (reload) _patchReloadPending = false;
            _patch = _patchProvider.Load(profile.Rank);
            _recommendationsDirty = true;
            _log.Info($"Patch data {_patch.PatchName} ({_patch.FetchedAt:u}) для ранга {profile.Rank}: matchups={_patch.Matchups.Count}, positions={_patch.Positions.Count}");
            PatchDataChanged?.Invoke(this, _patch);
        }
        if (profile.MyPosition != position)
        {
            profile = profile.Clone();
            profile.MyPosition = position;
        }

        IReadOnlyList<HeroRecommendation> recs = _last?.Recommendations ?? [];
        bool draftChanged = _last is null || !SameDraft(_last.State, state);
        if ((_recommendationsDirty || draftChanged) && status != PipelineStatus.GameNotFound)
        {
            // Дельта считается относительно состояния ДО последнего изменения драфта,
            // а не относительно предыдущего пересчёта (иначе "82 → 94" исчезало бы сразу).
            if (draftChanged) _baselineScores = _currentScores;
            var all = _recommendations.Recommend(state, profile, _patch, int.MaxValue, _baselineScores);
            _currentScores = all.ToDictionary(r => r.Hero.Id, r => r.Score);
            recs = all.Take(_settings.Pipeline.RecommendationCount).ToList();
            _recommendationsDirty = false;
            if (state.Phase != DraftPhase.Idle)
                _log.Info($"Рекомендации (pos {(int)position}, союзников {state.AllyPicks.Count}, врагов {state.EnemyPicks.Count}): " +
                          string.Join(", ", recs.Take(3).Select(r => $"{r.Hero.LocalizedName} {r.Score:F0}")));
        }

        var enemyRoles = state.EnemyPicks
            .Select(_heroes.Find).OfType<Hero>()
            .ToDictionary(h => h.Id, h => _roles.Infer(h));

        bool ownPicked = OwnHeroPicked(state, FreshHint());
        var plan = ownPicked ? BuildPlan(state, position, profile) : null;
        _last = new DraftSnapshot(status, message, state, sideSource, recs, enemyRoles, _patch, screenConfidence, ownPicked,
                                  position, fromDraft) { Plan = plan, PlayerNames = new Dictionary<SlotId, string>(_playerNames) };
        SnapshotUpdated?.Invoke(this, _last);
    }

    /// <summary>План пересчитывается, только когда меняются ваш герой, позиция, ранг или враги.</summary>
    private GamePlan? BuildPlan(DraftState state, Position position, PlayerProfile profile)
    {
        if (_plans is null) return null;
        int? myHeroId = FreshHint()?.OwnHeroId;
        if (myHeroId is null && state.MySide is { } side && state.MySlotIndex is { } slot)
            myHeroId = state.Slots.FirstOrDefault(s => s.Id == new SlotId(side, SlotKind.Pick, slot) && s.Status == SlotStatus.Confirmed)?.HeroId;
        if (myHeroId is null || _heroes.Find(myHeroId.Value) is not { } me) return null;

        var enemies = state.EnemyPicks.Select(_heroes.Find).OfType<Hero>().ToList();
        string key = $"{me.Id}|{position}|{profile.Rank}|{string.Join(",", enemies.Select(e => e.Id).Order())}|{_patch.GetHashCode()}";
        if (key != _planKey)
        {
            try
            {
                _plan = _plans.Build(me, position, enemies, _patch, profile.Rank);
                _planKey = key;
                _log.Info($"План: {me.LocalizedName}, pos {(int)position}; старт: " +
                          (_plan.StartItems.Count == 0 ? $"нет данных (в данных старт есть для {_patch.StartItems.Count} пар герой/позиция)"
                                                       : string.Join(", ", _plan.StartItems.Select(i => i.Name))) +
                          $"; опасны: {string.Join(", ", _plan.Threats.Select(t => t.Hero.LocalizedName))}" +
                          $"; цели: {string.Join(", ", _plan.Targets.Select(t => t.Hero.LocalizedName))}");
            }
            catch (Exception ex)
            {
                _log.Error("Не удалось построить план на игру", ex);
                _plan = null;
            }
        }
        return _plan;
    }

    private static bool SameDraft(DraftState a, DraftState b) =>
        a.MySide == b.MySide &&
        a.Phase == b.Phase &&
        a.MySlotIndex == b.MySlotIndex &&
        a.ExtraBans.SetEquals(b.ExtraBans) &&
        a.Positions.Count == b.Positions.Count &&
        a.Positions.All(kv => b.Positions.TryGetValue(kv.Key, out var v) && v == kv.Value) &&
        a.Slots.Select(s => (s.Id, s.Status, s.HeroId)).SequenceEqual(b.Slots.Select(s => (s.Id, s.Status, s.HeroId)));
}
