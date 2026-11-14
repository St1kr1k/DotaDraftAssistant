using DraftAssistant.Infrastructure.Capture;
using DraftAssistant.Infrastructure.Vision;

namespace DraftAssistant.Tests;

public class UiCanvasTests
{
    [Theory]
    [InlineData(1920, 1080, 0, 0, 1920, 1080)]
    [InlineData(2560, 1440, 0, 0, 2560, 1440)]
    [InlineData(3840, 2160, 0, 0, 3840, 2160)]
    [InlineData(3440, 1440, 440, 0, 2560, 1440)]   // 21:9 — поля по бокам
    [InlineData(1920, 1200, 0, 0, 1920, 1080)]     // 16:10 — прижато к верху
    public void Canvas_is_largest_16x9_area(int w, int h, int x, int y, int cw, int ch)
    {
        Assert.Equal(new PixelRect(x, y, cw, ch), UiCanvas.Compute(w, h));
    }

    [Fact]
    public void Same_normalized_rect_scales_across_16x9_resolutions()
    {
        var r = new NormalizedRect(0.38, 0.01, 0.04, 0.04);
        var a = UiCanvas.ToPixels(r, UiCanvas.Compute(1920, 1080));
        var b = UiCanvas.ToPixels(r, UiCanvas.Compute(3840, 2160));
        // Допуск ±1 px на округление.
        Assert.InRange(b.X, a.X * 2 - 1, a.X * 2 + 1);
        Assert.InRange(b.Width, a.Width * 2 - 1, a.Width * 2 + 1);
    }

    [Fact]
    public void Ultrawide_keeps_centered_ui_in_place()
    {
        var r = new NormalizedRect(0.5, 0.0, 0.05, 0.05);
        var px = UiCanvas.ToPixels(r, UiCanvas.Compute(3440, 1440));
        Assert.Equal(3440 / 2, px.X);
    }

    [Fact]
    public void Normalize_roundtrip()
    {
        var canvas = UiCanvas.Compute(2560, 1440);
        var original = new PixelRect(812, 6, 98, 55);
        var back = UiCanvas.ToPixels(UiCanvas.ToNormalized(original, canvas), canvas);
        Assert.Equal(original, back);
    }

    [Fact]
    public void Interpolation_spreads_slots_evenly()
    {
        var slots = JsonLayoutStore.Interpolate(new PixelRect(100, 10, 50, 30), new PixelRect(500, 10, 50, 30), 5).ToList();
        Assert.Equal(new[] { 100, 200, 300, 400, 500 }, slots.Select(s => s.X));
    }
}
