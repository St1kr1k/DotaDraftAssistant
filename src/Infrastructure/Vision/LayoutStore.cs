using System.Text.Json;
using System.Text.Json.Serialization;
using DraftAssistant.Infrastructure.Capture;
using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Vision;

public interface ILayoutProvider
{
    DraftLayout Current { get; }
    /// <summary>Эталон сигнатуры экрана драфта (BGR), если откалиброван.</summary>
    Mat? Signature { get; }
    /// <summary>Эталон пустого слота (BGR), если сохранён.</summary>
    Mat? EmptySlot { get; }
    /// <summary>Увеличивается при каждом сохранении — потребители сбрасывают кэши.</summary>
    int Revision { get; }
}

/// <summary>
/// layout.json + PNG-эталоны в %APPDATA%\DotaDraftAssistant\layout.
/// Если пользовательской разметки нет — берётся data/layout.default.json (Calibrated = false).
/// </summary>
public sealed class JsonLayoutStore : ILayoutProvider, IDisposable
{
    public static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly string _dir;
    private readonly string _defaultPath;
    private readonly object _gate = new();
    private DraftLayout _layout = new();
    private Mat? _signature;
    private Mat? _empty;

    public JsonLayoutStore(string userDirectory, string dataDirectory)
    {
        _dir = Path.Combine(userDirectory, "layout");
        _defaultPath = Path.Combine(dataDirectory, "layout.default.json");
        Reload();
    }

    public DraftLayout Current { get { lock (_gate) return _layout; } }
    public Mat? Signature { get { lock (_gate) return _signature; } }
    public Mat? EmptySlot { get { lock (_gate) return _empty; } }
    public int Revision { get; private set; }

    public string LayoutPath => Path.Combine(_dir, "layout.json");

    public void Reload()
    {
        var path = File.Exists(LayoutPath) ? LayoutPath : _defaultPath;
        var layout = File.Exists(path)
            ? JsonSerializer.Deserialize<DraftLayout>(File.ReadAllText(path), Json) ?? new DraftLayout()
            : new DraftLayout();

        Mat? signature = LoadImage(layout.SignatureImage);
        Mat? empty = LoadImage(layout.EmptySlotImage);
        lock (_gate)
        {
            // Старые Mat не освобождаем явно: их может прямо сейчас использовать поток анализа.
            // Их освободит финализатор после того, как ссылки исчезнут.
            _layout = layout;
            _signature = signature;
            _empty = empty;
            Revision++;
        }
    }

    private Mat? LoadImage(string? name)
    {
        if (string.IsNullOrEmpty(name)) return null;
        var p = Path.Combine(_dir, name);
        if (!File.Exists(p)) return null;
        var m = Cv2.ImRead(p, ImreadModes.Color);
        if (!m.Empty()) return m;
        m.Dispose();
        return null;
    }

    /// <summary>
    /// Сохранить калибровку. Прямоугольники — в пикселях клиентской области кадра <paramref name="frame"/>.
    /// Слоты 2..4 интерполируются между 1-м и 5-м (слоты на экране драфта равномерно распределены).
    /// </summary>
    public DraftLayout SaveCalibration(
        ImageFrame frame,
        PixelRect radiantFirst, PixelRect radiantLast,
        PixelRect direFirst, PixelRect direLast,
        PixelRect? signature,
        bool slotsAreEmpty,
        CanvasAnchor anchor = CanvasAnchor.TopCenter)
    {
        Directory.CreateDirectory(_dir);
        var canvas = UiCanvas.Compute(frame.Width, frame.Height, anchor);
        using var image = CvImage.ToBgrMat(frame);

        var layout = new DraftLayout
        {
            Calibrated = true,
            Anchor = anchor,
            RadiantPicks = Interpolate(radiantFirst, radiantLast, DraftLayout.PicksPerSide).Select(r => UiCanvas.ToNormalized(r, canvas)).ToList(),
            DirePicks = Interpolate(direFirst, direLast, DraftLayout.PicksPerSide).Select(r => UiCanvas.ToNormalized(r, canvas)).ToList(),
            CalibratedOn = $"{frame.Width}x{frame.Height} @ {DateTimeOffset.Now:yyyy-MM-dd HH:mm}",
        };

        if (signature is { } sig)
        {
            using var crop = CvImage.Crop(image, sig);
            if (crop is not null)
            {
                Cv2.ImWrite(Path.Combine(_dir, "signature.png"), crop);
                layout.SignatureRegion = UiCanvas.ToNormalized(sig, canvas);
                layout.SignatureImage = "signature.png";
            }
        }

        if (slotsAreEmpty)
        {
            using var crop = CvImage.Crop(image, radiantFirst);
            if (crop is not null)
            {
                Cv2.ImWrite(Path.Combine(_dir, "empty_slot.png"), crop);
                layout.EmptySlotImage = "empty_slot.png";
            }
        }

        File.WriteAllText(LayoutPath, JsonSerializer.Serialize(layout, Json));
        Reload();
        return layout;
    }

    /// <summary>Удалить ручную калибровку и вернуться к автоматическому поиску слотов.</summary>
    public void ResetToAutomatic()
    {
        if (File.Exists(LayoutPath)) File.Delete(LayoutPath);
        Reload();
    }

    public bool HasManualCalibration => File.Exists(LayoutPath) && Current.Calibrated;

    internal static IEnumerable<PixelRect> Interpolate(PixelRect first, PixelRect last, int count)
    {
        int w = (first.Width + last.Width) / 2, h = (first.Height + last.Height) / 2;
        for (int i = 0; i < count; i++)
        {
            double t = count == 1 ? 0 : (double)i / (count - 1);
            yield return new PixelRect(
                (int)Math.Round(first.X + t * (last.X - first.X)),
                (int)Math.Round(first.Y + t * (last.Y - first.Y)),
                w, h);
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _signature?.Dispose();
            _empty?.Dispose();
        }
    }
}
