using DraftAssistant.Domain.Scoring;

namespace DraftAssistant.Application.Configuration;

/// <summary>Все настраиваемые параметры. Сериализуются в settings.json.</summary>
public sealed class AppSettings
{
    public PipelineOptions Pipeline { get; set; } = new();
    public TrackerOptions Tracker { get; set; } = new();
    public StateMachineOptions StateMachine { get; set; } = new();
    public RecognitionOptions Recognition { get; set; } = new();
    public ScoringOptions Scoring { get; set; } = new();
    public OverlayOptions Overlay { get; set; } = new();
    public GsiOptions Gsi { get; set; } = new();
}

public sealed class PipelineOptions
{
    /// <summary>Частота анализа кадров (не частота рендера Dota).</summary>
    public double AnalysisFps { get; set; } = 8;
    public int RecommendationCount { get; set; } = 5;
}

public sealed class TrackerOptions
{
    /// <summary>Сколько последовательных кадров нужно, чтобы подтвердить героя в пустом слоте.</summary>
    public int ConfirmFrames { get; set; } = 3;
    /// <summary>Минимальная уверенность распознавания, чтобы кадр засчитался как "герой".</summary>
    public double MinConfidence { get; set; } = 0.6;
    /// <summary>Сколько кадров нужно, чтобы заменить УЖЕ подтверждённого героя другим.</summary>
    public int ReplaceConfirmedFrames { get; set; } = 8;
    /// <summary>Сколько кадров "пусто" нужно, чтобы снять подтверждённый пик (пики почти не откатываются).</summary>
    public int ClearConfirmedFrames { get; set; } = 40;
    /// <summary>Сколько кадров нераспознанного содержимого нужно, чтобы показать "Unknown".</summary>
    public int UnknownFrames { get; set; } = 3;
}

public sealed class StateMachineOptions
{
    /// <summary>Кадров с видимым экраном драфта до перехода Idle → DraftDetected.</summary>
    public int EnterFrames { get; set; } = 3;
    /// <summary>Кадров без экрана драфта до возврата в Idle.</summary>
    public int ExitFrames { get; set; } = 24;
}

public sealed class RecognitionOptions
{
    /// <summary>Ширина рабочего изображения слота; высота считается из пропорций слота.</summary>
    public int WorkWidth { get; set; } = 64;
    /// <summary>Доля, отрезаемая с каждой стороны слота перед сравнением (рамки, неточность калибровки).</summary>
    public double InnerMargin { get; set; } = 0.1;
    /// <summary>
    /// Ниже этого итогового score герой не считается распознанным.
    /// Подобрано на прототипе (tools/prototype): у "чужих" изображений лучший score ≤ 0.63,
    /// у героев ≥ 0.84. На реальных кадрах проверяется через DataTool check-layout.
    /// </summary>
    public double MinScore { get; set; } = 0.60;
    /// <summary>Score, при котором составляющая уверенности по абсолютному значению = 1.</summary>
    public double StrongScore { get; set; } = 0.85;
    /// <summary>Отрыв лучшего кандидата от второго, при котором составляющая уверенности по отрыву = 1.</summary>
    public double GoodMargin { get; set; } = 0.15;
    public double TemplateWeight { get; set; } = 0.75;
    public double HistogramWeight { get; set; } = 0.25;
    /// <summary>Порог похожести на эталон пустого слота.</summary>
    public double EmptySlotThreshold { get; set; } = 0.85;
    /// <summary>Если эталона пустого слота нет: слот с СКО яркости ниже порога считается пустым.</summary>
    public double EmptySlotMaxStdDev { get; set; } = 12;
    /// <summary>Порог совпадения сигнатуры экрана драфта.</summary>
    public double SignatureThreshold { get; set; } = 0.75;
    /// <summary>Сохранять пару кадров каждого драфта локально (для разбора ошибок распознавания).</summary>
    public bool SaveDebugFrames { get; set; } = true;
    /// <summary>Средняя разница миниатюр, ниже которой слот считается неизменившимся (результат берётся из кэша).</summary>
    public double UnchangedSlotThreshold { get; set; } = 3.0;
}

public sealed class ScoringOptions
{
    public ScoringWeights Weights { get; set; } = new()
    {
        Weights = new()
        {
            [ScoreComponent.Counter] = 0.25,
            [ScoreComponent.Synergy] = 0.20,
            [ScoreComponent.Meta] = 0.15,
            [ScoreComponent.RoleFit] = 0.15,
            [ScoreComponent.Comfort] = 0.10,
            // Lane / Composition / Strategic появятся вместе со своими evaluator'ами.
        },
    };

    /// <summary>Бракеты для мета-статистики (1 Herald ... 8 Immortal).</summary>
    public List<int> MetaBrackets { get; set; } = [5, 6, 7, 8];

    /// <summary>Сглаживание винрейта: столько "виртуальных" игр с WR 50% добавляется к выборке.</summary>
    public int MetaPriorGames { get; set; } = 500;
    public int MatchupPriorGames { get; set; } = 40;

    /// <summary>Отклонение WR, которое соответствует максимальной оценке компонента (±1).</summary>
    public double MetaFullScaleWinrateDelta { get; set; } = 0.05;
    public double CounterFullScaleWinrateDelta { get; set; } = 0.04;

    public double MainHeroValue { get; set; } = 1.0;
    public double ComfortHeroValue { get; set; } = 0.6;
    public double SoftAvoidValue { get; set; } = -1.0;
}

public enum PopupShowMode
{
    /// <summary>Во время пиков, пока вы не выбрали героя.</summary>
    UntilMyPick,
    /// <summary>Весь драфт, включая баны и после вашего пика.</summary>
    WholeDraft,
}

public enum PopupSize { Small, Medium, Large }

public sealed class OverlayOptions
{
    public double Opacity { get; set; } = 0.94;
    /// <summary>Отступ окошка от правого края окна Dota по умолчанию (доля ширины).</summary>
    public double RightMargin { get; set; } = 0.0125;
    /// <summary>Отступ окошка от верха окна Dota по умолчанию (доля высоты).</summary>
    public double TopOffset { get; set; } = 0.11;
    /// <summary>Сохранённое положение левого верхнего угла (доли окна Dota). -1 = по умолчанию, справа сверху.</summary>
    public double PositionX { get; set; } = -1;
    public double PositionY { get; set; } = -1;
    public PopupShowMode ShowMode { get; set; } = PopupShowMode.UntilMyPick;
    public PopupSize Size { get; set; } = PopupSize.Medium;
    public bool ShowReasons { get; set; } = true;
}

public sealed class GsiOptions
{
    public bool Enabled { get; set; } = true;
    public int Port { get; set; } = 53000;
    /// <summary>Через сколько секунд без сообщений подсказка GSI считается устаревшей.</summary>
    public int StaleAfterSeconds { get; set; } = 30;
    /// <summary>Папка Dota, выбранная вручную (если автоматически нашлась не та).</summary>
    public string? DotaPath { get; set; }
}
