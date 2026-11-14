using System.Collections.ObjectModel;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Scoring;
using DraftAssistant.Presentation.Components;

namespace DraftAssistant.Presentation.Overlay;

public sealed record SlotItem(string Text, string Detail, bool IsUnknown);

public sealed record ComponentItem(string Label, int Value);

public sealed record ReasonItem(string Text, bool Positive);

public sealed class RecommendationItem
{
    public required int Rank { get; init; }
    public required string Name { get; init; }
    public required int Score { get; init; }
    public required string DeltaText { get; init; }
    public required bool HasDelta { get; init; }
    public required bool DeltaPositive { get; init; }
    public required IReadOnlyList<ComponentItem> Components { get; init; }
    public required IReadOnlyList<ReasonItem> Reasons { get; init; }
}

/// <summary>
/// Только отображение готового снимка pipeline. Никаких вычислений score —
/// числа и причины приходят из application-слоя.
/// </summary>
public sealed class OverlayViewModel : ObservableObject
{
    private readonly IHeroRepository _heroes;
    private string _status = "Запуск…";
    private string _versionText = "";
    private string _updateText = "";
    private string _phase = "";
    private string _roleText = "";
    private string _sideText = "";
    private bool _isInteractive;
    private bool _sideKnown;
    private bool _hasDraft;
    private bool _learnMode;
    private double _panelOpacity = 0.92;
    private string _firstGroupTitle = "ВРАГИ";
    private string _secondGroupTitle = "СОЮЗНИКИ";
    private (DraftSnapshot Snapshot, Position Position)? _last;

    public OverlayViewModel(IHeroRepository heroes) => _heroes = heroes;

    public string Status { get => _status; set => Set(ref _status, value); }
    public string VersionText { get => _versionText; set => Set(ref _versionText, value); }
    /// <summary>Сообщение об автообновлении (пусто — не показывается).</summary>
    public string UpdateText { get => _updateText; set { if (Set(ref _updateText, value)) Raise(nameof(HasUpdate)); } }
    public bool HasUpdate => !string.IsNullOrEmpty(_updateText);
    public string Phase { get => _phase; set => Set(ref _phase, value); }
    public string RoleText { get => _roleText; set => Set(ref _roleText, value); }
    public string SideText { get => _sideText; set => Set(ref _sideText, value); }
    public bool IsInteractive { get => _isInteractive; set => Set(ref _isInteractive, value); }
    public bool SideKnown { get => _sideKnown; set => Set(ref _sideKnown, value); }
    public bool HasDraft { get => _hasDraft; set => Set(ref _hasDraft, value); }
    public bool LearnMode
    {
        get => _learnMode;
        set { if (Set(ref _learnMode, value) && _last is { } l) Apply(l.Snapshot, l.Position); }
    }
    public double PanelOpacity { get => _panelOpacity; set => Set(ref _panelOpacity, Math.Clamp(value, 0.3, 1)); }
    public string FirstGroupTitle { get => _firstGroupTitle; set => Set(ref _firstGroupTitle, value); }
    public string SecondGroupTitle { get => _secondGroupTitle; set => Set(ref _secondGroupTitle, value); }

    public int ReasonsPerHero => LearnMode ? 8 : 3;

    public ObservableCollection<SlotItem> FirstGroup { get; } = [];
    public ObservableCollection<SlotItem> SecondGroup { get; } = [];
    public ObservableCollection<RecommendationItem> Recommendations { get; } = [];

    public void Apply(DraftSnapshot s, Position myPosition)
    {
        _last = (s, myPosition);
        Status = s.Status switch
        {
            PipelineStatus.GameNotFound => "Dota 2 не найдена",
            PipelineStatus.LayoutNotCalibrated => s.StatusMessage ?? "Нужна калибровка",
            PipelineStatus.Error => $"Ошибка: {s.StatusMessage}",
            PipelineStatus.Observing => $"Наблюдение · патч {s.Patch.PatchName}",
            _ => "Запуск…",
        };

        Phase = s.State.Phase switch
        {
            DraftPhase.Idle => "ожидание драфта",
            DraftPhase.DraftDetected => "драфт обнаружен",
            DraftPhase.BanPhase => "баны",
            DraftPhase.PickPhase => $"пики · осталось {s.State.RemainingPickSlots}",
            DraftPhase.Completed => "драфт завершён",
            _ => "",
        };

        RoleText = $"POS {(int)myPosition}";
        HasDraft = s.State.Phase != DraftPhase.Idle || s.State.ConfirmedPickCount > 0;

        var mySide = s.State.MySide;
        SideKnown = mySide is not null;
        string sideSource = s.SideSource switch
        {
            SideSource.Gsi => "GSI",
            SideSource.OwnHeroMatch => "по вашему герою",
            SideSource.Manual => "вручную",
            _ => "?",
        };
        SideText = mySide is { } side ? $"{side} ({sideSource})" : "сторона не определена";

        // Если сторона известна — показываем ВРАГИ/СОЮЗНИКИ, иначе честно RADIANT/DIRE.
        var first = mySide?.Opposite() ?? DraftSide.Radiant;
        var second = mySide ?? DraftSide.Dire;
        FirstGroupTitle = mySide is null ? "RADIANT" : "ВРАГИ";
        SecondGroupTitle = mySide is null ? "DIRE" : "СОЮЗНИКИ";

        Replace(FirstGroup, Slots(s, first, showRoles: mySide is not null));
        Replace(SecondGroup, Slots(s, second, showRoles: false));
        Replace(Recommendations, s.Recommendations.Select((r, i) => ToItem(r, i + 1, ReasonsPerHero)));
    }

    private IEnumerable<SlotItem> Slots(DraftSnapshot s, DraftSide side, bool showRoles)
    {
        foreach (var slot in s.State.SlotsOf(side, SlotKind.Pick))
        {
            switch (slot.Status)
            {
                case SlotStatus.Confirmed when slot.HeroId is { } id:
                    var name = _heroes.Find(id)?.LocalizedName ?? $"#{id}";
                    string detail = "";
                    if (showRoles && s.EnemyRoles.TryGetValue(id, out var dist))
                    {
                        var top = dist.Ordered.First();
                        detail = $"~pos {(int)top.Position} {top.Probability:P0}";
                    }
                    yield return new SlotItem(name, detail, false);
                    break;
                case SlotStatus.Unknown:
                    yield return new SlotItem($"Unknown ({slot.Confidence:P0})", "", true);
                    break;
            }
        }
    }

    private static RecommendationItem ToItem(HeroRecommendation r, int rank, int reasonCount)
    {
        int Comp(ScoreComponent c) => r.Components.TryGetValue(c, out var cs) ? cs.Display : 50;
        double delta = r.Delta ?? 0;
        return new RecommendationItem
        {
            Rank = rank,
            Name = r.Hero.LocalizedName,
            Score = (int)Math.Round(r.Score),
            HasDelta = Math.Abs(delta) >= 1,
            DeltaPositive = delta > 0,
            DeltaText = r.PreviousScore is { } p ? $"{p:0} → {r.Score:0}" : "",
            Components =
            [
                new("Counter", Comp(ScoreComponent.Counter)),
                new("Synergy", Comp(ScoreComponent.Synergy)),
                new("Meta", Comp(ScoreComponent.Meta)),
                new("Role", Comp(ScoreComponent.RoleFit)),
                new("Comfort", Comp(ScoreComponent.Comfort)),
            ],
            Reasons = r.Reasons.Take(reasonCount).Select(ToReason).ToList(),
        };
    }

    /// <summary>Формулировка зависит от уверенности аргумента: не выдаём предположение за факт.</summary>
    private static ReasonItem ToReason(Reason reason)
    {
        string prefix = reason.Confidence switch
        {
            >= 0.75 => "",
            >= 0.45 => "вероятно, ",
            _ => "возможно, ",
        };
        bool positive = reason.Polarity == ReasonPolarity.Positive;
        return new ReasonItem($"{(positive ? "+" : "−")} {prefix}{reason.Text}", positive);
    }

    private static void Replace<T>(ObservableCollection<T> target, IEnumerable<T> items)
    {
        target.Clear();
        foreach (var i in items) target.Add(i);
    }
}
