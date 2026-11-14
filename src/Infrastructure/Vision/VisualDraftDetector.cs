using DraftAssistant.Application.Abstractions;
using DraftAssistant.Domain.Draft;
using DraftAssistant.Infrastructure.Capture;

namespace DraftAssistant.Infrastructure.Vision;

/// <summary>
/// IDraftDetector: окно Dota → захват только области ROI → анализ кадра → наблюдение.
/// </summary>
public sealed class VisualDraftDetector(IScreenCaptureService capture, DraftFrameAnalyzer analyzer) : IDraftDetector
{
    public IReadOnlyList<SlotId> Slots => DraftLayout.StandardSlots;

    /// <summary>Последний полный анализ — для отладочного вывода.</summary>
    public FrameAnalysis? LastAnalysis { get; private set; }

    public DraftObservation? Observe()
    {
        var window = capture.FindGameWindow();
        if (window is null) return null;

        var now = DateTimeOffset.UtcNow;
        if (window.IsMinimized)
            return new DraftObservation(false, 0, [], ObservationIssue.None, now);

        if (!analyzer.IsCalibrated)
            return new DraftObservation(false, 0, [], ObservationIssue.LayoutNotCalibrated, now);

        int w = window.ClientRect.Width, h = window.ClientRect.Height;
        var region = analyzer.RequiredRegion(w, h);
        if (region.IsEmpty)
            return new DraftObservation(false, 0, [], ObservationIssue.LayoutNotCalibrated, now);

        var frame = capture.Capture(window, region);
        if (frame is null)
            return new DraftObservation(false, 0, [], ObservationIssue.None, now);

        using var mat = CvImage.ToBgrMat(frame);
        LastAnalysis = analyzer.Analyze(mat, region, w, h);
        return LastAnalysis.Observation;
    }
}
