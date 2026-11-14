using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Player;
using DraftAssistant.Infrastructure.Vision;

namespace DraftAssistant.Presentation.Common;

/// <summary>Текущий профиль: читают pipeline и страницы, меняют только страницы. Каждое изменение сохраняется сразу.</summary>
public sealed class ProfileStore(ISettingsRepository repo, PlayerProfile initial)
{
    private volatile PlayerProfile _current = initial;

    public PlayerProfile Current => _current;

    public event EventHandler? Changed;

    public void Update(Action<PlayerProfile> change)
    {
        var next = _current.Clone();
        change(next);
        _current = next;
        repo.SaveProfile(next);
        Changed?.Invoke(this, EventArgs.Empty);
    }
}

/// <summary>Настройки приложения: общий объект + сохранение по запросу.</summary>
public sealed class SettingsStore(ISettingsRepository repo, AppSettings settings)
{
    public AppSettings Current { get; } = settings;

    public event EventHandler? Changed;

    public void Save()
    {
        repo.SaveSettings(Current);
        Changed?.Invoke(this, EventArgs.Empty);
    }
}

/// <summary>Портреты героев из data/heroes/{id}/portrait.png, загружаются один раз и кэшируются.</summary>
public sealed class HeroImages(string heroesDirectory)
{
    private readonly Dictionary<(int, int), ImageSource?> _cache = new();

    private readonly Dictionary<(int, int), ImageSource?> _tiles = new();

    /// <summary>
    /// Портрет, обрезанный под плитку с соотношением <paramref name="aspect"/> так, чтобы герой
    /// (лицо, а не фон или плечо) был в центре.
    /// </summary>
    public ImageSource? Tile(int heroId, double aspect)
    {
        var key = (heroId, (int)Math.Round(aspect * 100));
        if (_tiles.TryGetValue(key, out var cached)) return cached;

        ImageSource? result = null;
        var path = Path.Combine(heroesDirectory, heroId.ToString(), "portrait.png");
        if (Portrait(heroId, 0) is BitmapSource full)
        {
            try
            {
                int w = full.PixelWidth, h = full.PixelHeight;
                int window = Math.Min(w, (int)Math.Round(h * aspect));
                double center = PortraitFocus.FindCenterX(path, aspect);
                int x = Math.Clamp((int)Math.Round(center * w - window / 2.0), 0, w - window);
                var crop = new CroppedBitmap(full, new System.Windows.Int32Rect(x, 0, window, h));
                crop.Freeze();
                result = crop;
            }
            catch (Exception)
            {
                result = full;
            }
        }
        _tiles[key] = result;
        return result;
    }

    /// <param name="decodeWidth">Ширина декодирования; 0 — исходный размер.</param>
    public ImageSource? Portrait(int heroId, int decodeWidth = 256)
    {
        var key = (heroId, decodeWidth);
        if (_cache.TryGetValue(key, out var cached)) return cached;

        ImageSource? image = null;
        var path = Path.Combine(heroesDirectory, heroId.ToString(), "portrait.png");
        if (File.Exists(path))
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.UriSource = new Uri(path, UriKind.Absolute);
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                if (decodeWidth > 0) bmp.DecodePixelWidth = decodeWidth;
                bmp.EndInit();
                bmp.Freeze();
                image = bmp;
            }
            catch (Exception)
            {
                image = null;
            }
        }
        _cache[key] = image;
        return image;
    }
}
