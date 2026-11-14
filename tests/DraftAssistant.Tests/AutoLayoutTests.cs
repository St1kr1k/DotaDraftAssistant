using DraftAssistant.Domain.Draft;
using DraftAssistant.Domain.Heroes;
using DraftAssistant.Domain.Player;
using DraftAssistant.Infrastructure.Storage;
using DraftAssistant.Infrastructure.Vision;
using OpenCvSharp;

namespace DraftAssistant.Tests;

public class AutoLayoutTests
{
    // Пропорции сняты со скриншота драфта: шаг 0.0656·W, ширина полоски 0.057·W, линия на 0.065·H.
    private static Mat SyntheticTopBar(int width, int height, params int[] missing) => SyntheticTopBar(width, height, missing, []);

    /// <summary>У выбравших героя полоска не под портретом, а над ним (у края экрана) и сдвинута к центру.</summary>
    private static Mat SyntheticTopBar(int width, int height, int[] missing, int[] picked)
    {
        var img = new Mat((int)(height * PlayerBarGridDetector.SearchHeight), width, MatType.CV_8UC3, new Scalar(40, 35, 30));
        double pitch = width * 0.0656, barW = width * 0.057, y = height * 0.065;
        double firstLeft = width * 0.1448, firstRight = width * 0.6126;
        var colors = new[]
        {
            new Scalar(230, 110, 40), new Scalar(140, 230, 90), new Scalar(200, 60, 190), new Scalar(40, 210, 230), new Scalar(30, 120, 240),
            new Scalar(170, 120, 250), new Scalar(60, 190, 160), new Scalar(220, 210, 60), new Scalar(40, 140, 40), new Scalar(20, 80, 200),
        };
        for (int i = 0; i < 10; i++)
        {
            if (missing.Contains(i)) continue;
            double c = (i < 5 ? firstLeft : firstRight) + (i % 5) * pitch;
            int barH = Math.Max(3, height / 270);
            if (picked.Contains(i))
            {
                double top = y + barH / 2.0 - PlayerBarGridDetector.TopToBottomBars * pitch - barH / 2.0;
                double cx = c + (i < 5 ? -1 : 1) * PlayerBarGrid.Skew * pitch;
                Cv2.Rectangle(img, new Rect((int)(cx - barW / 2), (int)Math.Max(0, top), (int)barW, barH), colors[i], -1);
            }
            else
            {
                Cv2.Rectangle(img, new Rect((int)(c - barW / 2), (int)y, (int)barW, barH), colors[i], -1);
            }
        }
        return img;
    }

    [Theory]
    [InlineData(1920, 1080)]
    [InlineData(2560, 1440)]
    [InlineData(3840, 2160)]
    public void Finds_ten_slots_on_any_16x9_resolution(int w, int h)
    {
        using var top = SyntheticTopBar(w, h, missing: [3, 5]); // две полоски «не видны» — восстанавливаются по шагу
        var grid = PlayerBarGridDetector.Detect(top, w);
        Assert.NotNull(grid);
        Assert.Equal(8, grid!.DetectedBars);
        Assert.InRange(grid.Pitch, w * 0.0656 - 2, w * 0.0656 + 2);
        Assert.InRange(grid.RadiantCenters[3], w * 0.1448 + 3 * w * 0.0656 - 3, w * 0.1448 + 3 * w * 0.0656 + 3);
        Assert.InRange(grid.DireCenters[0], w * 0.6126 - 3, w * 0.6126 + 3);
        Assert.All(grid.RadiantCenters, c => Assert.True(c < w / 2.0));
        Assert.All(grid.DireCenters, c => Assert.True(c > w / 2.0));
    }

    [Theory]
    [InlineData(1920, 1080, new[] { 0, 1, 5, 9 })]
    [InlineData(2560, 1440, new[] { 0, 1, 2, 3, 5, 6, 7, 9 })]
    [InlineData(2560, 1440, new[] { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 })]
    public void Grid_stays_in_place_as_heroes_get_picked(int w, int h, int[] picked)
    {
        using var empty = SyntheticTopBar(w, h);
        using var during = SyntheticTopBar(w, h, [], picked);
        var g0 = PlayerBarGridDetector.Detect(empty, w)!;
        var g1 = PlayerBarGridDetector.Detect(during, w);
        Assert.NotNull(g1);
        Assert.InRange(g1!.BarY, g0.BarY - 3, g0.BarY + 3);
        for (int i = 0; i < 5; i++)
        {
            Assert.InRange(g1.RadiantCenters[i], g0.RadiantCenters[i] - 4, g0.RadiantCenters[i] + 4);
            Assert.InRange(g1.DireCenters[i], g0.DireCenters[i] - 4, g0.DireCenters[i] + 4);
        }
    }

    [Fact]
    public void Geometry_scales_with_resolution()
    {
        using var a = SyntheticTopBar(1920, 1080);
        using var b = SyntheticTopBar(3840, 2160);
        var ga = PlayerBarGridDetector.Detect(a, 1920)!;
        var gb = PlayerBarGridDetector.Detect(b, 3840)!;
        var pa = ga.Portrait(DraftSide.Dire, 2);
        var pb = gb.Portrait(DraftSide.Dire, 2);
        Assert.InRange(pb.X, pa.X * 2 - 4, pa.X * 2 + 4);
        Assert.InRange(pb.Width, pa.Width * 2 - 4, pa.Width * 2 + 4);
    }

    [Fact]
    public void Plain_screen_is_not_a_draft()
    {
        using var flat = new Mat(170, 1920, MatType.CV_8UC3, new Scalar(30, 30, 30));
        Assert.Null(PlayerBarGridDetector.Detect(flat, 1920));
    }

    [Theory]
    [InlineData("Лёгкая", Position.Carry)]
    [InlineData("Центр", Position.Mid)]
    [InlineData("Сложная", Position.Offlane)]
    [InlineData("Поддержка", Position.SoftSupport)]
    [InlineData("Полная поддержка", Position.HardSupport)]
    [InlineData("Hard Support", Position.HardSupport)]
    [InlineData("Soft Support", Position.SoftSupport)]
    [InlineData("Safe Lane", Position.Carry)]
    public void Parses_role_labels(string text, Position expected) =>
        Assert.Equal(expected, DraftTextParsing.ParseRole(text));

    [Fact]
    public void Words_are_assigned_to_nearest_slots()
    {
        double[] centers = [100, 200, 300, 400, 500];
        var words = new[]
        {
            new OcrWord("Лёгкая", 100, 80, 120),
            new OcrWord("Центр", 201, 185, 217),
            new OcrWord("Полная", 285, 262, 308),
            new OcrWord("поддержка", 330, 310, 350),
            new OcrWord("Поддержка", 402, 375, 429),
            new OcrWord("Сложная", 498, 470, 526),
        };
        var slots = DraftTextParsing.AssignToSlots(words, centers, maxGap: 0);
        Assert.Equal(Position.Carry, DraftTextParsing.ParseRole(slots[0]));
        Assert.Equal(Position.Mid, DraftTextParsing.ParseRole(slots[1]));
        Assert.Equal(Position.HardSupport, DraftTextParsing.ParseRole(slots[2]));
        Assert.Equal(Position.SoftSupport, DraftTextParsing.ParseRole(slots[3]));
        Assert.Equal(Position.Offlane, DraftTextParsing.ParseRole(slots[4]));
    }

    [Fact]
    public void Parses_ban_lines_from_chat()
    {
        var heroes = JsonHeroRepository.FromHeroes(
        [
            new Hero(65, "npc_dota_hero_batrider", "Batrider", PrimaryAttribute.Universal, AttackType.Ranged, [], ["batrider"]),
            new Hero(46, "npc_dota_hero_templar_assassin", "Templar Assassin", PrimaryAttribute.Agility, AttackType.Ranged, [], ["templar_assassin"]),
        ]);
        Assert.Equal(65, DraftTextParsing.ParseBanLine("Запрещён герой: Batrider.", heroes)?.Id);
        Assert.Equal(46, DraftTextParsing.ParseBanLine("Запрещен герой: Templar Assassin.", heroes)?.Id);
        Assert.Null(DraftTextParsing.ParseBanLine("pycl: давай мид", heroes));
    }

    [Theory]
    [InlineData("splu s otkritim...", "splu s otkritim rtom", true)]
    [InlineData("Левое яйцо [5O5AT]", "Левое яйцо", true)]
    [InlineData("Kruge", "pycl", false)]
    public void Matches_truncated_nicknames(string onScreen, string player, bool expected) =>
        Assert.Equal(expected, DraftTextParsing.NameMatches(onScreen, player));
}
