using System.Collections.ObjectModel;
using System.Windows.Media;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Application.Plan;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Player;
using DraftAssistant.Domain.Scoring;
using DraftAssistant.Presentation.Common;
using DraftAssistant.Presentation.Components;
using DraftAssistant.Presentation.Pages;

namespace DraftAssistant.Presentation.Popup;

public sealed record PopupReason(string Text, bool Positive);

public sealed record PopupPlanEnemy(string Name, ImageSource? Portrait, IReadOnlyList<string> Reasons, IReadOnlyList<string> Tips);

public sealed record PopupPick(string Name, int Score, ImageSource? Portrait, bool IsFirst, IReadOnlyList<PopupReason> Reasons);

/// <summary>Окошко в игре: только готовые данные из pipeline, никаких расчётов.</summary>
public sealed class PopupViewModel : ObservableObject
{
    private readonly HeroImages _images;
    private string _header = "ТОП-3";
    private string _phaseText = "";
    private bool _isMoveMode;
    private bool _showReasons = true;
    private double _scale = 1;
    private Brush _background = Brushes.Black;

    public PopupViewModel(HeroImages images) => _images = images;

    public ObservableCollection<PopupPick> Picks { get; } = [];

    // --- План после пика ---
    private bool _isPlan;
    private string _startItems = "";
    private string? _laneAdvice;
    private string _planBasis = "";
    public bool IsPlan { get => _isPlan; private set { if (Set(ref _isPlan, value)) Raise(nameof(IsPicks)); } }
    public bool IsPicks => !IsPlan;
    public string StartItems { get => _startItems; private set => Set(ref _startItems, value); }
    public bool HasStartItems => StartItems.Length > 0;
    public string? LaneAdvice { get => _laneAdvice; private set => Set(ref _laneAdvice, value); }
    public bool HasLaneAdvice => !string.IsNullOrEmpty(LaneAdvice);
    public string PlanBasis { get => _planBasis; private set => Set(ref _planBasis, value); }
    public ObservableCollection<PopupPlanEnemy> Threats { get; } = [];
    public ObservableCollection<PopupPlanEnemy> Targets { get; } = [];
    public ObservableCollection<string> ItemTips { get; } = [];
    public bool HasThreats => Threats.Count > 0;
    public bool HasTargets => Targets.Count > 0;
    public bool HasItemTips => ItemTips.Count > 0;

    /// <summary>Показать план (null — вернуться к топ-3).</summary>
    public void ShowPlan(GamePlan? plan)
    {
        IsPlan = plan is not null;
        if (plan is null) return;

        Header = $"ПЛАН · {plan.MyHero.LocalizedName.ToUpperInvariant()} · POS {(int)plan.Position}";
        PhaseText = "";
        StartItems = string.Join(" · ", plan.StartItems.Take(7).Select(i => i.Count > 1 ? $"{i.Name} ×{i.Count}" : i.Name));
        LaneAdvice = plan.LaneAdvice;
        PlanBasis = plan.Basis;

        Fill(Threats, plan.Threats);
        Fill(Targets, plan.Targets);
        ItemTips.Clear();
        foreach (var t in plan.ItemTips) ItemTips.Add(t);

        Raise(nameof(HasStartItems)); Raise(nameof(HasLaneAdvice));
        Raise(nameof(HasThreats)); Raise(nameof(HasTargets)); Raise(nameof(HasItemTips));
    }

    private void Fill(ObservableCollection<PopupPlanEnemy> target, IReadOnlyList<PlanEnemy> source)
    {
        target.Clear();
        foreach (var e in source)
            target.Add(new PopupPlanEnemy(e.Hero.LocalizedName, _images.Portrait(e.Hero.Id, 120),
                e.Reasons.Select(Capitalize).ToList(), e.Tips.Select(t => "→ " + t).ToList()));
    }

    private static string Capitalize(string s) => s.Length == 0 ? s : char.ToUpper(s[0]) + s[1..];

    public string Header { get => _header; set => Set(ref _header, value); }
    public string PhaseText { get => _phaseText; set => Set(ref _phaseText, value); }
    public bool IsMoveMode { get => _isMoveMode; set => Set(ref _isMoveMode, value); }
    public bool ShowReasons { get => _showReasons; set => Set(ref _showReasons, value); }
    public double Scale { get => _scale; set => Set(ref _scale, value); }
    public Brush Background { get => _background; set => Set(ref _background, value); }
    public bool HasPicks => Picks.Count > 0;

    public void ApplySettings(OverlayOptions o)
    {
        ShowReasons = o.ShowReasons;
        Scale = OverlaySettingsViewModel.ScaleOf(o.Size);
        var bg = new SolidColorBrush(Color.FromArgb((byte)Math.Round(Math.Clamp(o.Opacity, 0.4, 1) * 255), 9, 9, 11));
        bg.Freeze();
        Background = bg;
    }

    public void Apply(DraftSnapshot s)
    {
        if (IsPlan) return; // пока показан план, топ-3 не перерисовываем
        Header = s.PositionFromDraft
            ? $"ТОП-3 · POS {(int)s.EffectivePosition} · из драфта"
            : $"ТОП-3 · POS {(int)s.EffectivePosition}";
        PhaseText = s.State.Phase switch
        {
            DraftPhase.PickPhase => $"пики · {s.State.ConfirmedPickCount}/{s.State.TotalPickSlots}",
            DraftPhase.BanPhase => "баны",
            DraftPhase.DraftDetected => "драфт",
            DraftPhase.Completed => "драфт завершён",
            _ => "",
        };

        Picks.Clear();
        int i = 0;
        foreach (var r in s.Recommendations.Take(3))
        {
            Picks.Add(new PopupPick(
                r.Hero.LocalizedName,
                (int)Math.Round(r.Score),
                _images.Portrait(r.Hero.Id, 220),
                i++ == 0,
                r.Reasons.Take(2).Select(ToReason).ToList()));
        }
        Raise(nameof(HasPicks));
    }

    /// <summary>Формулировка зависит от уверенности: предположение не выдаётся за факт.</summary>
    private static PopupReason ToReason(Reason reason)
    {
        string prefix = reason.Confidence switch
        {
            >= 0.75 => "",
            >= 0.45 => "вероятно, ",
            _ => "возможно, ",
        };
        string text = prefix + reason.Text;
        text = char.ToUpper(text[0]) + text[1..];
        return new PopupReason(text, reason.Polarity == ReasonPolarity.Positive);
    }
}
