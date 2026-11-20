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
    /// <summary>Версия порогов распознавания: сохранённые пороги старой версии заменяются новыми.</summary>
    public const int CurrentVersion = 2;
    public int Version { get; set; }

    /// <summary>Ширина рабочего изображения слота; высота считается из пропорций слота.</summary>
    public int WorkWidth { get; set; } = 64;
    /// <summary>Во сколько раз арт героя в верхней панели драфта крупнее портрета из данных.</summary>
    public double PortraitZoom { get; set; } = 1.2;
    /// <summary>
    /// Минимальный контраст (СКО яркости) выбранного героя. Затемнённый портрет — это герой,
    /// на которого игрок только навёл курсор, а не пик.
    /// </summary>
    public double MinHeroStdDev { get; set; } = 25;
    /// <summary>Доля, отрезаемая с каждой стороны слота перед сравнением (рамки, неточность калибровки).</summary>
    public double InnerMargin { get; set; } = 0.1;
    /// <summary>
    /// Ниже этого итогового score герой не считается распознанным.
    /// Подобрано на кадрах реальных драфтов (2560×1440, с подписями рангов и без):
    /// у героев 0.68–0.94, у пустых слотов ≤ 0.50.
    /// </summary>
    public double MinScore { get; set; } = 0.58;
    /// <summary>Score, при котором составляющая уверенности по абсолютному значению = 1.</summary>
    public double StrongScore { get; set; } = 0.8;
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
    /// <summary>Версия набора весов. При обновлении приложения со сменой весов старые сохранённые настройки оценки сбрасываются.</summary>
    public const int CurrentVersion = 3;
    public int Version { get; set; }

    /// <summary>
    /// Веса раннего пика (о врагах почти ничего не известно): важнее ваша позиция, сила героя в патче
    /// и устойчивость к контрпику. Сумма — 100.
    /// </summary>
    public ScoringWeights WeightsEarly { get; set; } = new()
    {
        Weights = new()
        {
            [ScoreComponent.RoleFit] = 10,
            [ScoreComponent.Comfort] = 10,
            [ScoreComponent.Meta] = 20,
            [ScoreComponent.Safety] = 15,
            [ScoreComponent.Synergy] = 10,
            [ScoreComponent.Pairs] = 5,
            [ScoreComponent.Lane] = 15,
            [ScoreComponent.Counter] = 15,
        },
    };

    /// <summary>
    /// Веса позднего пика (враги известны): линия и вся вражеская команда весят вместе 55%,
    /// мета и ваши отметки — 15%. Сумма — 100.
    /// </summary>
    public ScoringWeights WeightsLate { get; set; } = new()
    {
        Weights = new()
        {
            [ScoreComponent.RoleFit] = 5,
            [ScoreComponent.Comfort] = 5,
            [ScoreComponent.Meta] = 10,
            [ScoreComponent.Safety] = 5,
            [ScoreComponent.Synergy] = 10,
            [ScoreComponent.Pairs] = 10,
            [ScoreComponent.Lane] = 25,
            [ScoreComponent.Counter] = 30,
        },
    };

    /// <summary>Задать вес компонента сразу для раннего и позднего пика.</summary>
    public void SetWeight(ScoreComponent component, double weight)
    {
        WeightsEarly.Weights[component] = weight;
        WeightsLate.Weights[component] = weight;
    }

    /// <summary>
    /// Герой не предлагается на позицию, если на ней проходит меньше этой доли его игр
    /// (защита от «WK мид»: редкие специалисты дают высокий винрейт на чужой роли).
    /// Работает, только когда есть статистика позиций.
    /// </summary>
    public double MinPositionShare { get; set; } = 0.15;

    /// <summary>Сглаживание винрейта: столько "виртуальных" игр с WR 50% добавляется к выборке.</summary>
    public int MetaPriorGames { get; set; } = 500;
    public int MatchupPriorGames { get; set; } = 40;
    public int PairPriorGames { get; set; } = 150;

    /// <summary>Отклонение WR, которое соответствует максимальной оценке компонента (±1).</summary>
    public double MetaFullScaleWinrateDelta { get; set; } = 0.06;
    public double CounterFullScaleWinrateDelta { get; set; } = 0.025;
    public double PairFullScaleWinrateDelta { get; set; } = 0.04;
    /// <summary>Отклонение доли выигранных линий для максимальной оценки линии.</summary>
    public double LaneFullScaleDelta { get; set; } = 0.08;

    public double MainHeroValue { get; set; } = 0.7;
    public double ComfortHeroValue { get; set; } = 0.4;
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
    /// <summary>После вашего пика показывать план на игру (стартовые предметы, опасные враги, лёгкие цели).</summary>
    public bool ShowPlan { get; set; } = true;
    /// <summary>Сколько секунд план остаётся на экране после конца драфта (Ctrl+Shift+O — скрыть раньше).</summary>
    public int PlanLingerSeconds { get; set; } = 90;
    /// <summary>
    /// Догадки о пиках соперников поверх их пустых слотов (по открытой статистике игроков на OpenDota).
    /// Выключено по умолчанию.
    /// </summary>
    public bool ShowEnemyPredictions { get; set; }
    /// <summary>Закрываться вместе с Dota 2 (если игра была запущена, пока работала программа).</summary>
    public bool ExitWithGame { get; set; } = true;
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
