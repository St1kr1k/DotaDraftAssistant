using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using DraftAssistant.Infrastructure.Capture;
using DraftAssistant.Infrastructure.Vision;
using DraftAssistant.Presentation.Interop;
using Microsoft.Win32;

namespace DraftAssistant.Presentation.Calibration;

/// <summary>
/// Калибровка ROI по реальному кадру: пользователь обводит 1-й и 5-й слоты каждой стороны
/// и (опционально) статичный элемент экрана драфта. Окно ничего не вычисляет само —
/// нормализация и сохранение эталонов выполняются JsonLayoutStore.
/// </summary>
public partial class CalibrationWindow : Window
{
    private static readonly (string Text, Color Color)[] Steps =
    [
        ("1/5. Обведите ПЕРВЫЙ (крайний левый) слот героя Radiant", Colors.LimeGreen),
        ("2/5. Обведите ПЯТЫЙ слот героя Radiant (ближайший к центру)", Colors.LimeGreen),
        ("3/5. Обведите ПЕРВЫЙ слот героя Dire (ближайший к центру)", Colors.OrangeRed),
        ("4/5. Обведите ПЯТЫЙ (крайний правый) слот героя Dire", Colors.OrangeRed),
        ("5/5. Обведите статичный элемент, который есть ТОЛЬКО на экране драфта (без таймера и меняющихся цифр) — или пропустите", Colors.Gold),
    ];

    private readonly IScreenCaptureService _capture;
    private readonly JsonLayoutStore _store;
    private readonly List<PixelRect> _rects = [];
    private ImageFrame? _frame;
    private Point _start;
    private Rectangle? _rubber;
    private bool _signatureSkipped;

    public CalibrationWindow(IScreenCaptureService capture, JsonLayoutStore store)
    {
        InitializeComponent();
        _capture = capture;
        _store = store;
        SourceInitialized += (_, _) => NativeWindow.ExcludeFromCapture(this);
        UpdateInstruction();
    }

    public bool Saved { get; private set; }

    private void OnCaptureDota(object sender, RoutedEventArgs e)
    {
        var window = _capture.FindGameWindow();
        if (window is null) { MessageBox.Show(this, "Окно Dota 2 не найдено."); return; }
        var frame = _capture.Capture(window, new PixelRect(0, 0, window.ClientRect.Width, window.ClientRect.Height));
        if (frame is null) { MessageBox.Show(this, "Не удалось захватить окно (свёрнуто или exclusive fullscreen?)."); return; }
        SetFrame(frame);
    }

    private void OnOpenScreenshot(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Filter = "Изображения|*.png;*.jpg;*.jpeg;*.bmp" };
        if (dlg.ShowDialog(this) != true) return;

        var decoder = BitmapDecoder.Create(new Uri(dlg.FileName), BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var converted = new FormatConvertedBitmap(decoder.Frames[0], PixelFormats.Bgra32, null, 0);
        int stride = converted.PixelWidth * 4;
        var pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);
        SetFrame(new ImageFrame(converted.PixelWidth, converted.PixelHeight, stride, pixels));
    }

    private void SetFrame(ImageFrame frame)
    {
        _frame = frame;
        // Bgr32 игнорирует альфа-канал (у BitBlt-кадров он не определён).
        var bmp = BitmapSource.Create(frame.Width, frame.Height, 96, 96, PixelFormats.Bgr32, null, frame.Bgra, frame.Stride);
        FrameImage.Source = bmp;
        Surface.Width = DrawCanvas.Width = frame.Width;
        Surface.Height = DrawCanvas.Height = frame.Height;
        OnReset(this, new RoutedEventArgs());
    }

    private void OnReset(object sender, RoutedEventArgs e)
    {
        _rects.Clear();
        _signatureSkipped = false;
        DrawCanvas.Children.Clear();
        UpdateInstruction();
    }

    private void OnSkip(object sender, RoutedEventArgs e)
    {
        if (_rects.Count != 4) return;
        _signatureSkipped = true;
        UpdateInstruction();
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (_frame is null || StepIndex >= Steps.Length) return;
        _start = e.GetPosition(DrawCanvas);
        _rubber = new Rectangle { Stroke = new SolidColorBrush(Steps[StepIndex].Color), StrokeThickness = 2 };
        Canvas.SetLeft(_rubber, _start.X);
        Canvas.SetTop(_rubber, _start.Y);
        DrawCanvas.Children.Add(_rubber);
        DrawCanvas.CaptureMouse();
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (_rubber is null) return;
        var p = e.GetPosition(DrawCanvas);
        Canvas.SetLeft(_rubber, Math.Min(p.X, _start.X));
        Canvas.SetTop(_rubber, Math.Min(p.Y, _start.Y));
        _rubber.Width = Math.Abs(p.X - _start.X);
        _rubber.Height = Math.Abs(p.Y - _start.Y);
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_rubber is null) return;
        DrawCanvas.ReleaseMouseCapture();
        var p = e.GetPosition(DrawCanvas);
        var rect = new PixelRect(
            (int)Math.Round(Math.Min(p.X, _start.X)), (int)Math.Round(Math.Min(p.Y, _start.Y)),
            (int)Math.Round(Math.Abs(p.X - _start.X)), (int)Math.Round(Math.Abs(p.Y - _start.Y)));
        _rubber = null;

        if (rect.Width < 6 || rect.Height < 6)
        {
            DrawCanvas.Children.RemoveAt(DrawCanvas.Children.Count - 1);
            return;
        }
        _rects.Add(rect);
        if (_rects.Count == 4) DrawInterpolatedPreview();
        UpdateInstruction();
    }

    /// <summary>После 4 прямоугольников показываем все 10 рассчитанных слотов, чтобы глазами проверить совпадение.</summary>
    private void DrawInterpolatedPreview()
    {
        void Draw(PixelRect first, PixelRect last, Color color)
        {
            int w = (first.Width + last.Width) / 2, h = (first.Height + last.Height) / 2;
            for (int i = 1; i < 4; i++)
            {
                double t = i / 4.0;
                var r = new Rectangle
                {
                    Width = w, Height = h, Stroke = new SolidColorBrush(color),
                    StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 3, 2 },
                };
                Canvas.SetLeft(r, first.X + t * (last.X - first.X));
                Canvas.SetTop(r, first.Y + t * (last.Y - first.Y));
                DrawCanvas.Children.Add(r);
            }
        }
        Draw(_rects[0], _rects[1], Colors.LimeGreen);
        Draw(_rects[2], _rects[3], Colors.OrangeRed);
    }

    private int StepIndex => _signatureSkipped ? Steps.Length : _rects.Count;

    private void UpdateInstruction()
    {
        if (_frame is null)
        {
            Instruction.Text = "Сначала захватите окно Dota 2 во время выбора героев или откройте скриншот экрана драфта.";
        }
        else if (StepIndex < Steps.Length)
        {
            Instruction.Text = Steps[StepIndex].Text;
        }
        else
        {
            Instruction.Text = "Готово. Проверьте пунктирные слоты и нажмите «Сохранить».";
        }
        SkipButton.IsEnabled = _frame is not null && _rects.Count == 4 && !_signatureSkipped;
        SaveButton.IsEnabled = _frame is not null && (_rects.Count == 5 || (_rects.Count == 4 && _signatureSkipped));
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        if (_frame is null) return;
        try
        {
            var layout = _store.SaveCalibration(
                _frame, _rects[0], _rects[1], _rects[2], _rects[3],
                _rects.Count == 5 ? _rects[4] : null,
                EmptySlotsBox.IsChecked == true);
            Saved = true;
            MessageBox.Show(this,
                $"Разметка сохранена ({layout.CalibratedOn}).\n{_store.LayoutPath}\n\n" +
                "Проверить распознавание на скриншоте: DataTool check-layout --screenshot <файл>",
                "Калибровка");
            DialogResult = true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Ошибка сохранения");
        }
    }
}
