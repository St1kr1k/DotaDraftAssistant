using DraftAssistant.Domain.Draft;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>
/// Разметка ROI экрана драфта (DraftArea → AllySlots / EnemySlots / BanSlots / Signature).
/// Хранится в JSON, координаты нормализованы относительно UI-холста (см. UiCanvas).
/// </summary>
public sealed class DraftLayout
{
    public int Version { get; set; } = 1;

    /// <summary>false — координаты приблизительные, распознавание слотов не запускается.</summary>
    public bool Calibrated { get; set; }

    public CanvasAnchor Anchor { get; set; } = CanvasAnchor.TopCenter;

    public List<NormalizedRect> RadiantPicks { get; set; } = [];
    public List<NormalizedRect> DirePicks { get; set; } = [];
    public List<NormalizedRect> RadiantBans { get; set; } = [];
    public List<NormalizedRect> DireBans { get; set; } = [];

    /// <summary>Статичный элемент, присутствующий только на экране драфта.</summary>
    public NormalizedRect? SignatureRegion { get; set; }

    /// <summary>Имя PNG-файла эталона сигнатуры (рядом с layout.json).</summary>
    public string? SignatureImage { get; set; }

    /// <summary>Имя PNG-файла эталона пустого слота (рядом с layout.json).</summary>
    public string? EmptySlotImage { get; set; }

    public string? CalibratedOn { get; set; }

    public IEnumerable<(SlotId Id, NormalizedRect Rect)> AllSlots()
    {
        for (int i = 0; i < RadiantPicks.Count; i++) yield return (new SlotId(DraftSide.Radiant, SlotKind.Pick, i), RadiantPicks[i]);
        for (int i = 0; i < DirePicks.Count; i++) yield return (new SlotId(DraftSide.Dire, SlotKind.Pick, i), DirePicks[i]);
        for (int i = 0; i < RadiantBans.Count; i++) yield return (new SlotId(DraftSide.Radiant, SlotKind.Ban, i), RadiantBans[i]);
        for (int i = 0; i < DireBans.Count; i++) yield return (new SlotId(DraftSide.Dire, SlotKind.Ban, i), DireBans[i]);
    }

    public const int PicksPerSide = 5;
    public const int MaxBansPerSide = 7; // Captains Mode

    /// <summary>
    /// Фиксированный набор слотов pipeline: 5+5 пиков и до 7+7 банов.
    /// Неразмеченные слоты просто никогда не наблюдаются и остаются пустыми,
    /// поэтому перекалибровка не требует перезапуска трекера.
    /// </summary>
    public static IReadOnlyList<SlotId> StandardSlots { get; } =
        new[] { DraftSide.Radiant, DraftSide.Dire }
            .SelectMany(side =>
                Enumerable.Range(0, PicksPerSide).Select(i => new SlotId(side, SlotKind.Pick, i))
                .Concat(Enumerable.Range(0, MaxBansPerSide).Select(i => new SlotId(side, SlotKind.Ban, i))))
            .ToList();

    /// <summary>Пропорции слота (ширина / высота) — по первому пику.</summary>
    public double SlotAspect(PixelRectSize canvas)
    {
        var r = RadiantPicks.FirstOrDefault() ?? DirePicks.FirstOrDefault();
        if (r is null || r.Height <= 0) return 16.0 / 9.0;
        return r.Width * canvas.Width / (r.Height * canvas.Height);
    }
}

public readonly record struct PixelRectSize(int Width, int Height);
