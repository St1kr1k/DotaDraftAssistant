using System.Globalization;
using System.Text;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>Слово, распознанное OCR, с горизонтальным центром в координатах клиентской области.</summary>
public sealed record OcrWord(string Text, double CenterX, double Left, double Right);

/// <summary>
/// Разбор текста экрана драфта. Чистые функции без OCR — покрываются тестами.
/// </summary>
public static class DraftTextParsing
{
    /// <summary>
    /// Подпись роли → позиция. Русский и английский клиент.
    /// «Полная поддержка» / «Hard Support» = 5, «Поддержка» / «Support» = 4,
    /// «Лёгкая» / «Safe» = 1, «Центр» / «Mid» = 2, «Сложная» / «Off» = 3.
    /// </summary>
    public static Position? ParseRole(string text)
    {
        var t = Normalize(text);
        if (t.Length == 0) return null;
        if (t.Contains("полн") || t.Contains("hard")) return Position.HardSupport;
        if (t.Contains("поддерж") || t.Contains("support") || t.Contains("soft")) return Position.SoftSupport;
        if (t.Contains("легк") || t.Contains("safe")) return Position.Carry;
        if (t.Contains("центр") || t.Contains("mid")) return Position.Mid;
        if (t.Contains("сложн") || t.Contains("off")) return Position.Offlane;
        return null;
    }

    /// <summary>
    /// Склеивает соседние слова в фразы (разрыв больше <paramref name="maxGap"/> — новая фраза)
    /// и раскладывает фразы по слотам по ближайшему центру.
    /// </summary>
    public static Dictionary<int, string> AssignToSlots(IEnumerable<OcrWord> words, IReadOnlyList<double> slotCenters, double maxGap)
    {
        var ordered = words.Where(w => w.Text.Trim().Length > 0).OrderBy(w => w.Left).ToList();
        var phrases = new List<(string Text, double Left, double Right)>();
        foreach (var w in ordered)
        {
            if (phrases.Count > 0 && w.Left - phrases[^1].Right <= maxGap)
            {
                var last = phrases[^1];
                phrases[^1] = (last.Text + " " + w.Text, last.Left, Math.Max(last.Right, w.Right));
            }
            else
            {
                phrases.Add((w.Text, w.Left, w.Right));
            }
        }

        var result = new Dictionary<int, string>();
        foreach (var (text, left, right) in phrases)
        {
            double c = (left + right) / 2;
            int best = 0;
            for (int i = 1; i < slotCenters.Count; i++)
                if (Math.Abs(slotCenters[i] - c) < Math.Abs(slotCenters[best] - c)) best = i;
            result[best] = result.TryGetValue(best, out var prev) ? prev + " " + text : text;
        }
        return result;
    }

    /// <summary>
    /// Строка чата о бане («Запрещён герой: Batrider.» / «… banned …: Pudge») → герой.
    /// Имена героев в чате всегда английские, поэтому сравнение идёт с LocalizedName и алиасами.
    /// </summary>
    public static Hero? ParseBanLine(string line, IHeroRepository heroes)
    {
        var lower = line.ToLowerInvariant();
        if (!lower.Contains("запрещ") && !lower.Contains("ban")) return null;
        int colon = line.LastIndexOf(':');
        if (colon < 0 || colon == line.Length - 1) return null;
        var name = NormalizeName(line[(colon + 1)..]);
        if (name.Length < 2) return null;
        return heroes.All.FirstOrDefault(h => NormalizeName(h.LocalizedName) == name)
               ?? heroes.All.FirstOrDefault(h => h.Aliases.Any(a => NormalizeName(a) == name))
               ?? heroes.All.FirstOrDefault(h => name.Length >= 5 && NormalizeName(h.LocalizedName).StartsWith(name));
    }

    /// <summary>
    /// Совпадает ли ник из верхней панели (может быть обрезан «…») с именем игрока из GSI.
    /// </summary>
    public static bool NameMatches(string onScreen, string playerName)
    {
        var a = NormalizeName(onScreen);
        var b = NormalizeName(playerName);
        if (a.Length < 3 || b.Length < 3) return false;
        return a == b || b.StartsWith(a) || a.StartsWith(b) || (a.Length >= 5 && b.Contains(a));
    }

    private static string Normalize(string s) =>
        s.ToLowerInvariant().Replace('ё', 'е').Trim();

    /// <summary>Только буквы и цифры, нижний регистр, ё → е; убирает тег гильдии в квадратных скобках.</summary>
    public static string NormalizeName(string s)
    {
        int bracket = s.IndexOf('[');
        if (bracket > 0) s = s[..bracket];
        var sb = new StringBuilder(s.Length);
        foreach (var ch in s.Normalize(NormalizationForm.FormC))
        {
            if (char.IsLetterOrDigit(ch)) sb.Append(char.ToLower(ch, CultureInfo.InvariantCulture) == 'ё' ? 'е' : char.ToLower(ch, CultureInfo.InvariantCulture));
        }
        return sb.ToString();
    }
}
