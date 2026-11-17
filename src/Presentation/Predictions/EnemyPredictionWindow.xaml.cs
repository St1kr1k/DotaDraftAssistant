using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Media;
using DraftAssistant.Presentation.Interop;

namespace DraftAssistant.Presentation.Predictions;

/// <summary>Иконка-догадка поверх пустого слота соперника (координаты — в DIP внутри окна).</summary>
public sealed record PredictionTile(double Left, double Top, double Width, double Height, double Skew,
                                    ImageSource? Portrait, string Label, double LabelSize)
{
    public double HalfHeight => Height / 2;
}

/// <summary>
/// Прозрачное окно поверх верхней панели драфта: в пустых слотах соперников — их вероятные герои.
/// Мышь проходит в игру; окно скрыто от захвата экрана, чтобы распознавание не приняло иконки за пики.
/// </summary>
public partial class EnemyPredictionWindow : Window
{
    public EnemyPredictionWindow()
    {
        InitializeComponent();
        DataContext = this;
        SourceInitialized += (_, _) =>
        {
            NativeWindow.ExcludeFromCapture(this);
            NativeWindow.SetClickThrough(this, true);
        };
    }

    public ObservableCollection<PredictionTile> Tiles { get; } = [];

    /// <summary>Коэффициент физические пиксели → DIP для монитора окна.</summary>
    public double PixelsToDip => 1.0 / VisualTreeHelper.GetDpi(this).DpiScaleX;
}
