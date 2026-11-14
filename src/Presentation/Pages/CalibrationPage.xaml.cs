using System.Windows;
using System.Windows.Controls;
using DraftAssistant.Infrastructure.Vision;

namespace DraftAssistant.Presentation.Pages;

public partial class CalibrationPage : UserControl
{
    private readonly JsonLayoutStore _layout;
    private readonly Func<bool> _openCalibration;

    /// <param name="openCalibration">Открывает окно калибровки; возвращает true, если разметка сохранена.</param>
    public CalibrationPage(JsonLayoutStore layout, Func<bool> openCalibration)
    {
        InitializeComponent();
        _layout = layout;
        _openCalibration = openCalibration;
        Loaded += (_, _) => Refresh();
    }

    private void Refresh()
    {
        var l = _layout.Current;
        if (l.Calibrated)
        {
            StatusText.Text = "Откалибровано";
            DetailText.Text = $"{l.CalibratedOn} · сигнатура экрана драфта: {(l.SignatureImage is null ? "нет (драфт заметен с первого пика)" : "есть")}";
        }
        else
        {
            StatusText.Text = "Не откалибровано";
            DetailText.Text = "Пока калибровки нет, приложение не видит пики на экране.";
        }
    }

    private void OnOpen(object sender, RoutedEventArgs e)
    {
        _openCalibration();
        Refresh();
    }
}
