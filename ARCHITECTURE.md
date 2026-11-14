# Dota Draft Assistant — архитектура

> **USER DOES NOT ENTER THE DRAFT. APPLICATION OBSERVES THE DRAFT.**
> Пользователь вводит только свой профиль (позиция, main/comfort/avoid). Пики, баны, стороны и фаза драфта определяются по изображению экрана.

## 1. Выбор технологий

| Критерий | C# + WPF | C# + WinUI 3 | C# + Avalonia | C++ + Qt | Rust + Tauri | TS + Tauri |
|---|---|---|---|---|---|---|
| Overlay: прозрачность, topmost, click-through | ✅ `AllowsTransparency` + `WS_EX_TRANSPARENT`, давно отлажено | ⚠️ прозрачное окно без рамки делается через обходные пути | ⚠️ работает, но на Windows сложнее с click-through и DPI | ✅ | ⚠️ WebView2-окно, прозрачность и click-through через плагины | ⚠️ то же |
| Захват экрана (GDI / Windows.Graphics.Capture) | ✅ P/Invoke + CsWinRT | ✅ | ✅ (P/Invoke) | ✅ нативно | ✅ через crates `windows` | ❌ только через Rust-часть |
| Computer vision | ✅ OpenCvSharp (полный OpenCV) | ✅ | ✅ | ✅ нативный OpenCV | ⚠️ `opencv`-crate сложен в сборке | ❌ через Rust/WASM |
| Задержка / CPU | ✅ хватает с запасом (анализ 5–15 FPS малых ROI) | ✅ | ✅ | ✅ лучший | ✅ | ⚠️ WebView2 + IPC |
| Стабильность | ✅ зрелая платформа | ⚠️ моложе, есть регрессии | ✅ | ✅ | ⚠️ | ⚠️ |
| Простота разработки | ✅ | ⚠️ | ✅ | ❌ дольше всех | ⚠️ | ✅ UI, ❌ всё остальное |

**Решение: C# / .NET 8 + WPF + OpenCvSharp4.**
Приложение только под Windows, и WPF здесь самый проверенный способ сделать прозрачный click-through overlay с корректным DPI. .NET даёт прямой доступ к WinAPI, а OpenCvSharp — весь OpenCV без собственной нативной сборки. Производительности C# хватает с большим запасом: анализируются несколько маленьких ROI с частотой 8 FPS, а не 4K-кадры с частотой 144 FPS. C++/Qt был бы чуть быстрее, но заметно дороже в разработке. Domain и Application собраны как `net8.0` без зависимостей от Windows, поэтому их можно тестировать и переносить отдельно.

## 2. Слои

```
src/
  Domain/          чистая модель: Hero, DraftState, PlayerProfile, PatchData, ScoreComponent, интерфейсы evaluator'ов
  Application/     логика: DraftStateTracker, DraftStateMachine, evaluators, RecommendationService, DraftPipeline
  Infrastructure/  WinAPI-захват, OpenCV, распознавание, GSI, JSON-хранилища
  Presentation/    WPF overlay, настройки, калибровка (composition root — App.xaml.cs)
tools/DataTool     загрузка данных (OpenDota/Steam CDN), проверка разметки по скриншоту, добавление шаблонов
tools/prototype    Python-прототип распознавания для подбора порогов
tests/             xUnit
```

Зависимости направлены только внутрь: `Presentation → Infrastructure → Application → Domain`.

* `GdiScreenCaptureService` ничего не знает о героях и контрпиках.
* `CounterEvaluator` ничего не знает о координатах экрана (получает `DraftContext`).
* UI не вычисляет score: `OverlayViewModel` только форматирует готовый `DraftSnapshot`.
* Application видит "глаза" только через порт `IDraftDetector` → `DraftObservation`.

## 3. Pipeline

```
Dota 2 window ─► GdiScreenCaptureService.FindGameWindow()            (процесс dota2.exe → самое крупное видимое окно)
              ─► DraftFrameAnalyzer.RequiredRegion()                  (объединение всех ROI → захватывается только эта полоса)
              ─► GdiScreenCaptureService.Capture(region)              (BitBlt, BGRA)
              ─► DraftFrameAnalyzer.Analyze()
                    ├─ сигнатура экрана драфта (NCC с эталоном)       → DraftScreenVisible
                    └─ для каждого слота:
                         кэш миниатюры 16×9 (слот не изменился → результат из кэша)
                         SlotEmptinessClassifier                      → Empty
                         CompositeHeroRecognizer (template + histogram) → Hero(id, confidence) | Unknown(confidence)
              ─► DraftObservation (кадр)
              ─► DraftStateTracker (temporal confirmation)            → SlotState[] (стабильное)
              ─► DraftStateMachine (+ подсказка GSI)                  → DraftPhase
              ─► определение стороны (GSI team → свой герой из GSI → ручной выбор)
              ─► DraftState
              ─► RecommendationService (evaluators × веса из конфигурации)
              ─► DraftSnapshot ─► OverlayViewModel ─► WPF
```

Пересчёт выполняется только при изменении подтверждённого состояния, а не на каждом кадре.

## 4. Ключевые решения

### Захват
MVP использует GDI `BitBlt` с экранного DC. В Borderless Fullscreen игра композитится через DWM, и регион ~1920×120 захватывается примерно за миллисекунду. Собственные окна приложения исключены из захвата через `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)`, иначе overlay попадал бы в кадр. Ограничение: окна, перекрывающие Dota, попадают в кадр. Следующий шаг — реализация `IScreenCaptureService` через Windows.Graphics.Capture (захват конкретного окна); остальные слои при этом не меняются.

### ROI и разрешения
ROI задаются в долях **UI-холста**: это наибольшая область 16:9 внутри окна (`UiCanvas`). 16:9-разрешения (1080p / 1440p / 4K) совпадают с окном целиком; на 21:9 холст центрирован, на 16:10 прижат к верху. Координаты не захардкожены: их задаёт калибровка по реальному кадру (обвести 1-й и 5-й слоты каждой стороны, промежуточные интерполируются), и они сохраняются в `layout.json`. Поведение UI Dota на нестандартных соотношениях сторон — это предположение. Поэтому разметка всегда сохраняется относительно холста конкретного пользователя, а `DataTool check-layout` показывает результат на скриншоте.

### Распознавание
`IHeroRecognizer` → `TemplateHeroRecognizer` (центральная часть слота ищется внутри шаблона через `TM_CCOEFF_NORMED`; метод устойчив к яркости, контрасту и сдвигу калибровки, работает и на обесцвеченных банах) + `ColorHistogramHeroRecognizer` (Hue/Sat-гистограммы) → `CompositeHeroRecognizer` (взвешенное слияние). Уверенность складывается из абсолютного score и отрыва от второго кандидата. Если два героя похожи, уверенность низкая, и выводится `Unknown (xx%)`. Шаблоны готовятся лениво под фактический размер слота, поэтому распознавание не привязано к разрешению. Собственные вырезки слотов (`DataTool add-template`) добавляются как дополнительные шаблоны героя. OCR (`Windows.Media.Ocr`) и feature matching подключаются в Composite как дополнительные методы.

Пороги подобраны на прототипе (`tools/prototype`): у посторонних изображений лучший score ≤ 0.63, у героев ≥ 0.84 → `MinScore = 0.60`. При масштабе, сильно отличающемся от шаблона, распознаватель отвечает `Unknown`, а не выдаёт ошибочного героя.

### Anti-flickering
`DraftStateTracker`:
- герой подтверждается после N подряд одинаковых уверенных кадров;
- последовательность X → Y → X не меняет состояние;
- подтверждённый пик "липкий": замена — 8 кадров, очистка — 40;
- неуверенный кадр никогда не перезаписывает подтверждённого героя;
- один герой не может стоять в двух слотах.

### Машина состояний
`IDLE → DRAFT_DETECTED → BAN_PHASE → PICK_PHASE → DRAFT_COMPLETED → IDLE`. Переходы определяются фактами: виден ли экран драфта, сколько пиков и банов подтверждено, что сообщает GSI. Гистерезис считается в кадрах, а не в секундах драфта.

### GSI (официальный Valve Game State Integration)
Это не чтение памяти, а штатный механизм: Dota сама отправляет JSON на `localhost`. Пики соперников игроку GSI **не** отдаёт, поэтому главный источник драфта — зрение. GSI надёжно сообщает фазу игры, сторону игрока и его собственного героя. Это используется для машины состояний и для определения "союзники/враги". Если GSI не настроен, сторона берётся по ручному переключателю в overlay. Это единственное, что пользователь может указать сам, и только как запасной вариант.

### Scoring
`DraftScore = 50 + 50 · Σ(wᵢ · valueᵢ · confidenceᵢ) / Σwᵢ`. Каждый компонент даёт `value ∈ [-1; 1]`, `confidence ∈ [0; 1]` и список `Reason`, у каждого из которых есть источник (`Evidence`) и уверенность. Веса задаются в `settings.json`. Comfort ограничен своим весом и не может перебить плохой объективный драфт; это закреплено тестом. Компонент с низкой уверенностью стягивается к нейтральному значению.

| Компонент | MVP-реализация | Основа |
|---|---|---|
| Counter | средний сглаженный WR-перевес против всех выбранных врагов | матчапы OpenDota |
| Synergy | "чего не хватает команде" (инициация, фронтлайн, контроль, маг. урон, пуш) + анти-синергия | теги ролей |
| Meta | сглаженный WR в выбранных бракетах | heroStats OpenDota |
| RoleFit | вероятность позиции пользователя | эвристика по тегам (честно помечена) |
| Comfort | main / comfort / soft avoid; hard avoid отфильтрован | профиль |

## 5. Безопасность
Приложение не вызывает `OpenProcess`/`ReadProcessMemory`, не инжектит DLL, не использует `SendInput`, не меняет файлы клиента и не отправляет в игру команды или клики. Горячие клавиши только слушаются (`RegisterHotKey`). Источники данных: пиксели экрана, официальный GSI, публичные API OpenDota и Steam CDN.
Valve может менять правила для сторонних overlay. Перед публичным распространением стоит сверить актуальную позицию Valve по вспомогательным инструментам.

## 6. Что сделано в vertical slice и что дальше

| Фаза | Статус |
|---|---|
| 1 Window detection + capture | ✅ GDI, поиск по процессу, DPI-aware |
| 2 ROI + draft area | ✅ UI-холст, калибровка в приложении, сигнатура экрана драфта |
| 3 Hero recognition | ✅ template + histogram + composite, кэш неизменившихся слотов |
| 4 Draft state tracking | ✅ трекер + машина состояний + GSI |
| 5 Overlay | ✅ click-through, Ctrl+Shift+D интерактив, Ctrl+Shift+O скрыть, настройки, калибровка |
| 6 Role inference | 🟡 эвристика по тегам → заменить статистикой позиций (Stratz API) + назначение ролей по команде |
| 7 Counterpick | 🟡 матчапы → добавить lane / teamfight / scaling-факторы из данных способностей |
| 8 Synergy | 🟡 теги → парная синергия (duo WR) + данные способностей |
| 9 Meta | ✅ базово (WR по бракетам) |
| 10 Player preferences | ✅ |
| 11 Recommendation engine | 🟡 Lane / Composition / Strategic evaluator'ы |
| 12 Performance | 🟡 Windows.Graphics.Capture, профилирование |
| 13 Testing | 🟡 юнит-тесты есть; нужен набор реальных скриншотов с разметкой как регрессионный тест распознавания |

### Educational-модуль (раздел 31) — как встраивается
Модель уже готова к этому: у каждого `Reason` есть `Component`, `Confidence` и `Evidence`, а overlay выбирает формулировку по уверенности ("сильно" / "вероятно" / "возможно"). Learn mode показывает больше аргументов, дельта "82 → 94" считается относительно состояния до последнего пика. Дальше:
1. `HeroAbilityData` — структурированные данные способностей (тип урона, dispel, disable, break, BKB-pierce, радиус, КД). Источник — `npc_abilities` из файлов игры через dotaconstants, а не свободный текст.
2. `AbilityInteraction` — база известных взаимодействий `{source, target, type, strength, explanation, conditions}`, которая пополняется вручную или полуавтоматически. Каждое объяснение строится **только** из записей базы. Если записи нет, механического объяснения тоже нет, и остаётся статистика. Ничего не выдумывается.
3. `AbilityInteractionAnalyzer` — новый `IHeroEvaluator`, который выдаёт `Reason` с `Evidence = "взаимодействие X ↔ Y"`.
4. "Why not?" и "A vs B" — `IRecommendationService.Evaluate(heroId, …)` уже возвращает полную разбивку для любого героя, поэтому нужен только UI.
5. Game plan — шаблоны по фазам игры, которые заполняются из Reason'ов текущего драфта.
