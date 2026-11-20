using DraftAssistant.Domain.Patch;
using System.Windows.Media;
using DraftAssistant.Application.Pipeline;
using DraftAssistant.Presentation.Components;

namespace DraftAssistant.Presentation.Main;

/// <summary>Статус в левом нижнем углу главного окна: игра, патч, версия, обновления.</summary>
public sealed class MainViewModel : ObservableObject
{
    private static readonly Brush Ok = Frozen("#4ADE80");
    private static readonly Brush Warn = Frozen("#F2C14E");
    private static readonly Brush Off = Frozen("#6E6E76");

    private string _gameText = "Ищу Dota 2…";
    private Brush _gameDot = Off;
    private string _patchText = "";
    private string _updateText = "Обновления: проверка…";
    private bool _canRestartToUpdate;

    public string VersionText { get; init; } = "";
    public string GameText { get => _gameText; set => Set(ref _gameText, value); }
    public Brush GameDot { get => _gameDot; set => Set(ref _gameDot, value); }
    public string PatchText { get => _patchText; set => Set(ref _patchText, value); }
    public string UpdateText { get => _updateText; set => Set(ref _updateText, value); }
    public bool CanRestartToUpdate { get => _canRestartToUpdate; set => Set(ref _canRestartToUpdate, value); }

    public void Apply(DraftSnapshot s)
    {
        (GameText, GameDot) = s.Status switch
        {
            PipelineStatus.GameNotFound => ("Dota 2 не запущена", Off),
            PipelineStatus.LayoutNotCalibrated => ("Нужна калибровка", Warn),
            PipelineStatus.Error => ("Ошибка анализа", Warn),
            _ => ("Dota 2 найдена", Ok),
        };
        PatchText = PatchLine(s.Patch, VersionText);
    }

    /// <summary>«Патч 7.40 · данные от 20.11 · v1.0.50».</summary>
    public static string PatchLine(PatchData patch, string version) =>
        patch.FetchedAt > DateTimeOffset.MinValue.AddYears(1)
            ? $"Патч {patch.PatchName} · данные от {patch.FetchedAt.ToLocalTime():dd.MM} · {version}"
            : $"Патч {patch.PatchName} · {version}";

    private static Brush Frozen(string hex)
    {
        var b = (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;
        b.Freeze();
        return b;
    }
}
