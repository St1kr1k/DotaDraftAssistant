using DraftAssistant.Domain.Draft;
using DraftAssistant.Infrastructure.Capture;
using OpenCvSharp;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>
/// Сетка из 10 слотов экрана драфта, найденная по цветным полоскам игроков
/// (стандартные цвета Dota под карточкой каждого игрока).
///
/// Вся геометрия выражена через шаг между слотами (Pitch) от линии полосок, поэтому она
/// не зависит от разрешения: интерфейс Dota масштабируется целиком, и пропорции сохраняются
/// на 1080p, 1440p и 4K. Это заменяет ручную калибровку.
/// </summary>
public sealed record PlayerBarGrid(
    int BarY,
    double Pitch,
    double BarWidth,
    IReadOnlyList<double> RadiantCenters,
    IReadOnlyList<double> DireCenters,
    int DetectedBars)
{
    // Смещения по вертикали от линии полосок, в долях шага (сняты со скриншота драфта).
    public const double PortraitTop = -0.53;
    public const double PortraitBottom = -0.17;
    public const double NameTop = 0.10;
    public const double NameBottom = 0.27;
    public const double RoleTop = 0.27;
    public const double RoleBottom = 0.47;

    public double Center(DraftSide side, int index) =>
        side == DraftSide.Radiant ? RadiantCenters[index] : DireCenters[index];

    private PixelRect Band(DraftSide side, int index, double top, double bottom, double widthFactor)
    {
        double c = Center(side, index);
        double w = widthFactor;
        int y0 = (int)Math.Round(BarY + top * Pitch), y1 = (int)Math.Round(BarY + bottom * Pitch);
        return new PixelRect((int)Math.Round(c - w / 2), Math.Max(0, y0), (int)Math.Round(w), Math.Max(1, y1 - Math.Max(0, y0)));
    }

    /// <summary>Карточка героя (над рангом игрока).</summary>
    public PixelRect Portrait(DraftSide side, int index) => Band(side, index, PortraitTop, PortraitBottom, BarWidth);

    /// <summary>Ник игрока.</summary>
    public PixelRect Name(DraftSide side, int index) => Band(side, index, NameTop, NameBottom, Pitch);

    /// <summary>Подпись роли (только у своей команды в рейтинге).</summary>
    public PixelRect Role(DraftSide side, int index) => Band(side, index, RoleTop, RoleBottom, Pitch);

    /// <summary>Полоса подписей (или ников) одной команды целиком — для распознавания текста одним проходом.</summary>
    public PixelRect TeamBand(DraftSide side, double top, double bottom)
    {
        var first = Band(side, 0, top, bottom, Pitch);
        var last = Band(side, 4, top, bottom, Pitch);
        return first.Union(last);
    }

    /// <summary>Нижняя граница всего, что нужно с верха экрана (для захвата).</summary>
    public int RequiredHeight => (int)Math.Ceiling(BarY + RoleBottom * Pitch) + 2;

    /// <summary>Тот же ли это экран (с точностью до пары пикселей) — чтобы не сбрасывать кэши без причины.</summary>
    public bool SameAs(PlayerBarGrid other) =>
        Math.Abs(BarY - other.BarY) <= 2 &&
        Math.Abs(Pitch - other.Pitch) <= 2 &&
        RadiantCenters.Zip(other.RadiantCenters).All(p => Math.Abs(p.First - p.Second) <= 2) &&
        DireCenters.Zip(other.DireCenters).All(p => Math.Abs(p.First - p.Second) <= 2);
}

public static class PlayerBarGridDetector
{
    /// <summary>Доля высоты экрана сверху, где ищутся полоски.</summary>
    public const double SearchHeight = 0.16;

    /// <param name="topBgr">Верхняя часть клиентской области (BGR), начиная с y = 0.</param>
    /// <param name="clientWidth">Ширина клиентской области (topBgr должен быть той же ширины).</param>
    public static PlayerBarGrid? Detect(Mat topBgr, int clientWidth)
    {
        int W = topBgr.Width, H = topBgr.Height;
        if (W < 400 || H < 20) return null;

        using var hsv = new Mat();
        Cv2.CvtColor(topBgr, hsv, ColorConversionCodes.BGR2HSV);
        using var sat = new Mat();
        using var val = new Mat();
        Cv2.ExtractChannel(hsv, sat, 1);
        Cv2.ExtractChannel(hsv, val, 2);
        using var satMask = new Mat();
        using var valMask = new Mat();
        Cv2.Threshold(sat, satMask, 90, 255, ThresholdTypes.Binary);
        Cv2.Threshold(val, valMask, 90, 255, ThresholdTypes.Binary);
        using var mask = new Mat();
        Cv2.BitwiseAnd(satMask, valMask, mask);

        // 1. Строка с наибольшим числом насыщенных пикселей — линия полосок.
        int bestY = -1, bestCount = 0;
        for (int y = 0; y < H; y++)
        {
            using var row = mask.Row(y);
            int c = Cv2.CountNonZero(row);
            if (c > bestCount) { bestCount = c; bestY = y; }
        }
        if (bestY < 0 || bestCount < W * 0.12) return null;

        // 2. Горизонтальные отрезки в полосе ±2 px.
        int y0 = Math.Max(0, bestY - 2), y1 = Math.Min(H, bestY + 3);
        using var band = new Mat(mask, new Rect(0, y0, W, y1 - y0));
        using var colMax = new Mat();
        Cv2.Reduce(band, colMax, ReduceDimension.Row, ReduceTypes.Max, MatType.CV_8U);
        var on = new bool[W];
        for (int x = 0; x < W; x++) on[x] = colMax.At<byte>(0, x) > 0;

        var centers = new List<double>();
        var widths = new List<double>();
        for (int x = 0; x < W;)
        {
            if (!on[x]) { x++; continue; }
            int s = x;
            while (x < W && on[x]) x++;
            if (x - s >= W * 0.015) { centers.Add((s + x) / 2.0); widths.Add(x - s); }
        }
        if (centers.Count < 6) return null;

        // 3. Шаг между слотами: медиана соседних расстояний правдоподобной величины.
        var diffs = centers.Zip(centers.Skip(1), (a, b) => b - a).Where(d => d > W * 0.05 && d < W * 0.085).OrderBy(d => d).ToList();
        if (diffs.Count == 0) return null;
        double pitch = diffs[diffs.Count / 2];
        double mid = W / 2.0;

        // 4. Подгонка сетки из 5 слотов на каждую сторону (пропущенные полоски восстанавливаются по шагу).
        //    Если крайняя полоска не видна, сдвинутые варианты дают одинаковое число совпадений —
        //    тогда выбираем пару сеток, симметричную относительно центра экрана (часы драфта посередине).
        var leftCandidates = Candidates(centers.Where(c => c < mid).ToList(), pitch).Where(g => g.Grid[^1] < mid).ToList();
        var rightCandidates = Candidates(centers.Where(c => c > mid).ToList(), pitch).Where(g => g.Grid[0] > mid).ToList();
        if (leftCandidates.Count == 0 || rightCandidates.Count == 0) return null;

        (int Hits, double[] Grid) bestLeft = default, bestRight = default;
        int bestHits = -1;
        double bestAsym = double.MaxValue;
        foreach (var l in leftCandidates)
        {
            foreach (var r in rightCandidates)
            {
                int hits = l.Hits + r.Hits;
                double asym = Math.Abs(l.Grid[^1] + r.Grid[0] - W);
                if (hits > bestHits || (hits == bestHits && asym < bestAsym))
                {
                    bestHits = hits; bestAsym = asym; bestLeft = l; bestRight = r;
                }
            }
        }
        if (bestHits < 7) return null;

        widths.Sort();
        double barWidth = Math.Min(widths[widths.Count / 2], pitch * 0.95);
        return new PlayerBarGrid(bestY, pitch, barWidth, bestLeft.Grid, bestRight.Grid, bestHits);
    }

    private static List<(int Hits, double[] Grid)> Candidates(List<double> cs, double pitch)
    {
        var result = new List<(int Hits, double[] Grid)>();
        foreach (var c in cs)
        {
            for (int k = 0; k < 5; k++)
            {
                double start = c - k * pitch;
                var grid = Enumerable.Range(0, 5).Select(i => start + i * pitch).ToArray();
                int hits = grid.Count(g => cs.Any(x => Math.Abs(g - x) < 0.25 * pitch));
                result.Add((hits, grid));
            }
        }
        return result;
    }
}
