using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using DraftAssistant.Application.Abstractions;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Infrastructure.Capture;
using OpenCvSharp;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>Что удалось прочитать текстом с экрана драфта.</summary>
public sealed record DraftTextInfo(
    IReadOnlyDictionary<SlotId, Position> Roles,
    DraftSide? AllySide,
    int? OwnSlotIndex,
    IReadOnlyCollection<int> BannedHeroes);

/// <summary>
/// Чтение текста встроенным распознаванием Windows (Windows.Media.Ocr):
///  * подписи ролей тиммейтов в рейтинге («Лёгкая», «Центр», …) → позиции союзников;
///  * у какой команды есть подписи ролей → ваша сторона (у противников их нет);
///  * ники → ваш слот (по имени игрока из GSI) → ваша позиция в этой катке;
///  * строки чата «Запрещён герой: …» → баны.
///
/// Если для языка нет OCR-пакета Windows, соответствующее чтение просто отключается.
/// </summary>
public sealed class DraftTextReader
{
    private readonly IHeroRepository _heroes;
    private readonly IAppLog _log;
    private readonly OcrEngine? _localized;
    private readonly OcrEngine? _latin;

    // Чат: левый верх и размер в долях UI-холста 16:9 (сняты со скриншота драфта).
    private static readonly NormalizedRect ChatArea = new(0.44, 0.80, 0.27, 0.17);

    public DraftTextReader(IHeroRepository heroes, IAppLog log)
    {
        _heroes = heroes;
        _log = log;
        _localized = Create("ru") ?? OcrEngine.TryCreateFromUserProfileLanguages();
        _latin = Create("en-US") ?? _localized;
        _log.Info($"OCR: роли/ники — {_localized?.RecognizerLanguage.LanguageTag ?? "нет"}, чат — {_latin?.RecognizerLanguage.LanguageTag ?? "нет"}");
    }

    public bool Available => _localized is not null;

    private static OcrEngine? Create(string tag)
    {
        try
        {
            var lang = new Language(tag);
            return OcrEngine.IsLanguageSupported(lang) ? OcrEngine.TryCreateFromLanguage(lang) : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <param name="top">Верх клиентской области (BGR), содержит полосу ролей и ников.</param>
    /// <param name="chat">Область чата (BGR) или null.</param>
    /// <param name="chatRectInClient">Где эта область чата находится (для отладки, не используется в разборе).</param>
    public DraftTextInfo Read(Mat top, PlayerBarGrid grid, Mat? chat, string? playerName)
    {
        var roles = new Dictionary<SlotId, Position>();
        DraftSide? allySide = null;
        int? ownSlot = null;

        if (_localized is not null)
        {
            int bestCount = 0;
            foreach (var side in new[] { DraftSide.Radiant, DraftSide.Dire })
            {
                var band = grid.TeamBand(side, PlayerBarGrid.RoleTop, PlayerBarGrid.RoleBottom);
                var words = Recognize(_localized, top, band);
                var centers = Enumerable.Range(0, 5).Select(i => grid.Center(side, i)).ToList();
                var perSlot = DraftTextParsing.AssignToSlots(words, centers, maxGap: 0);
                int count = 0;
                foreach (var (index, text) in perSlot)
                {
                    if (DraftTextParsing.ParseRole(text) is { } pos)
                    {
                        roles[new SlotId(side, SlotKind.Pick, index)] = pos;
                        count++;
                    }
                }
                // Подписи ролей есть только у своей команды.
                if (count >= 2 && count > bestCount) { bestCount = count; allySide = side; }
            }
            // Если подписи нашлись у обеих сторон (ошибка OCR) — оставляем только роли «своей».
            if (allySide is { } ally)
                foreach (var k in roles.Keys.Where(k => k.Side != ally).ToList()) roles.Remove(k);

            if (allySide is { } s && !string.IsNullOrWhiteSpace(playerName))
            {
                var band = grid.TeamBand(s, PlayerBarGrid.NameTop, PlayerBarGrid.NameBottom);
                var words = Recognize(_localized, top, band);
                var centers = Enumerable.Range(0, 5).Select(i => grid.Center(s, i)).ToList();
                foreach (var (index, text) in DraftTextParsing.AssignToSlots(words, centers, maxGap: grid.Pitch * 0.08))
                {
                    if (DraftTextParsing.NameMatches(text, playerName)) { ownSlot = index; break; }
                }
            }
        }

        var bans = new List<int>();
        if (_latin is not null && chat is not null)
        {
            foreach (var line in RecognizeLines(_latin, chat))
            {
                if (DraftTextParsing.ParseBanLine(line, _heroes) is { } hero) bans.Add(hero.Id);
            }
        }

        return new DraftTextInfo(roles, allySide, ownSlot, bans);
    }

    public static PixelRect ChatRect(int clientWidth, int clientHeight) =>
        UiCanvas.ToPixels(ChatArea, UiCanvas.Compute(clientWidth, clientHeight, CanvasAnchor.Center));

    private List<OcrWord> Recognize(OcrEngine engine, Mat image, PixelRect rect)
    {
        var words = new List<OcrWord>();
        using var crop = CvImage.Crop(image, rect);
        if (crop is null) return words;
        const double scale = 3.0; // мелкий текст OCR читает заметно лучше после увеличения
        var result = Run(engine, crop, scale);
        if (result is null) return words;
        foreach (var line in result.Lines)
        {
            foreach (var w in line.Words)
            {
                double left = rect.X + w.BoundingRect.X / scale;
                double right = rect.X + (w.BoundingRect.X + w.BoundingRect.Width) / scale;
                words.Add(new OcrWord(w.Text, (left + right) / 2, left, right));
            }
        }
        return words;
    }

    private IEnumerable<string> RecognizeLines(OcrEngine engine, Mat image)
    {
        var result = Run(engine, image, 2.0);
        return result is null ? [] : result.Lines.Select(l => l.Text).ToList();
    }

    private OcrResult? Run(OcrEngine engine, Mat bgr, double scale)
    {
        try
        {
            using var big = new Mat();
            Cv2.Resize(bgr, big, new OpenCvSharp.Size(0, 0), scale, scale, InterpolationFlags.Cubic);
            using var bgra = new Mat();
            Cv2.CvtColor(big, bgra, ColorConversionCodes.BGR2BGRA);
            int w = bgra.Width, h = bgra.Height;
            if (w > OcrEngine.MaxImageDimension || h > OcrEngine.MaxImageDimension) return null;

            var bytes = new byte[w * h * 4];
            for (int y = 0; y < h; y++) Marshal.Copy(bgra.Ptr(y), bytes, y * w * 4, w * 4);
            using var bitmap = SoftwareBitmap.CreateCopyFromBuffer(bytes.AsBuffer(), BitmapPixelFormat.Bgra8, w, h);
            return engine.RecognizeAsync(bitmap).AsTask().GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            _log.Warn($"OCR: {ex.Message}");
            return null;
        }
    }
}
