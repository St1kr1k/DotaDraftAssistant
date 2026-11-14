using DraftAssistant.Application.Abstractions;
using DraftAssistant.Application.Configuration;
using DraftAssistant.Domain.Draft;

namespace DraftAssistant.Application.Draft;

/// <summary>
/// Превращает поток покадровых наблюдений в стабильное состояние слотов.
///
/// Frame → recognition → confidence → state comparison → state update.
///
/// Правила (anti-flickering):
///  * герой подтверждается только после N ПОДРЯД одинаковых уверенных наблюдений;
///  * последовательность X, Y, X сбрасывает счётчик — состояние не меняется;
///  * наблюдение с низкой уверенностью не считается героем;
///  * подтверждённый пик "липкий": для замены другим героем или очистки нужно намного больше кадров;
///  * один герой не может быть подтверждён в двух слотах одновременно.
/// </summary>
public sealed class DraftStateTracker
{
    private sealed class SlotTrack(SlotId id)
    {
        public SlotState Current = SlotState.Empty(id);
        public ObservedContent? CandidateKind;
        public int? CandidateHero;
        public int CandidateCount;
        public double CandidateConfidenceSum;
    }

    private readonly TrackerOptions _options;
    private readonly IReadOnlyList<SlotId> _slotOrder;
    private readonly Dictionary<SlotId, SlotTrack> _tracks;

    public DraftStateTracker(IEnumerable<SlotId> slots, TrackerOptions options)
    {
        _options = options;
        _slotOrder = slots.ToList();
        _tracks = _slotOrder.ToDictionary(s => s, s => new SlotTrack(s));
    }

    public IReadOnlyList<SlotState> Slots => _slotOrder.Select(s => _tracks[s].Current).ToList();

    public void Reset()
    {
        foreach (var id in _slotOrder) _tracks[id] = new SlotTrack(id);
    }

    /// <summary>Обработать наблюдения одного кадра. Возвращает true, если состояние слотов изменилось.</summary>
    public bool Update(IReadOnlyList<SlotObservation> observations)
    {
        bool changed = false;
        foreach (var obs in observations)
        {
            if (!_tracks.TryGetValue(obs.Slot, out var track)) continue;
            changed |= UpdateSlot(track, Normalize(obs));
        }
        return changed;
    }

    private SlotObservation Normalize(SlotObservation obs)
    {
        if (obs.Content != ObservedContent.Hero) return obs;

        // Неуверенное распознавание — это не "герой", а "что-то непонятное".
        if (obs.HeroId is null || obs.Confidence < _options.MinConfidence)
            return obs with { Content = ObservedContent.Unknown, HeroId = null };

        // Герой уже подтверждён в другом слоте — это почти наверняка ошибка распознавания.
        bool elsewhere = _tracks.Values.Any(t =>
            t.Current.Id != obs.Slot &&
            t.Current.Status == SlotStatus.Confirmed &&
            t.Current.HeroId == obs.HeroId);
        return elsewhere ? obs with { Content = ObservedContent.Unknown, HeroId = null } : obs;
    }

    private bool UpdateSlot(SlotTrack t, SlotObservation obs)
    {
        if (t.CandidateKind == obs.Content && t.CandidateHero == obs.HeroId)
        {
            t.CandidateCount++;
            t.CandidateConfidenceSum += obs.Confidence;
        }
        else
        {
            t.CandidateKind = obs.Content;
            t.CandidateHero = obs.HeroId;
            t.CandidateCount = 1;
            t.CandidateConfidenceSum = obs.Confidence;
        }

        double avgConfidence = t.CandidateConfidenceSum / t.CandidateCount;
        var cur = t.Current;
        SlotState? next = null;

        switch (obs.Content)
        {
            case ObservedContent.Hero:
                if (cur.Status == SlotStatus.Confirmed && cur.HeroId == obs.HeroId)
                {
                    // Тот же герой: обновляем уверенность без генерации события (UI не дёргается).
                    t.Current = cur with { Confidence = Math.Max(cur.Confidence, avgConfidence) };
                }
                else if (cur.Status == SlotStatus.Confirmed)
                {
                    if (t.CandidateCount >= _options.ReplaceConfirmedFrames)
                        next = new SlotState(cur.Id, SlotStatus.Confirmed, obs.HeroId, avgConfidence);
                }
                else if (t.CandidateCount >= _options.ConfirmFrames)
                {
                    next = new SlotState(cur.Id, SlotStatus.Confirmed, obs.HeroId, avgConfidence);
                }
                break;

            case ObservedContent.Empty:
                if (cur.Status == SlotStatus.Confirmed)
                {
                    if (t.CandidateCount >= _options.ClearConfirmedFrames) next = SlotState.Empty(cur.Id);
                }
                else if (cur.Status == SlotStatus.Unknown && t.CandidateCount >= _options.ConfirmFrames)
                {
                    next = SlotState.Empty(cur.Id);
                }
                break;

            case ObservedContent.Unknown:
                // Неуверенное наблюдение никогда не перетирает подтверждённого героя.
                if (cur.Status == SlotStatus.Empty && t.CandidateCount >= _options.UnknownFrames)
                    next = new SlotState(cur.Id, SlotStatus.Unknown, null, avgConfidence);
                break;
        }

        if (next is null || next == cur) return false;
        t.Current = next;
        return true;
    }
}
