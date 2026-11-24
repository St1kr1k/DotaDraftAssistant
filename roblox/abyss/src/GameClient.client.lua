-- Клиент «В Бездну»: интерфейс, барьер на лестнице, бои, находки, освещение по слоям.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local function R(name: string): RemoteEvent
	return Remotes:WaitForChild(name) :: RemoteEvent
end
local BuyStepR, BuyUpR, BuyRUpR, RollR = R("BuyStep"), R("BuyUp"), R("BuyRUp"), R("Roll")
local RebirthR, ToggleR, TeleportR, FightR, DigR = R("Rebirth"), R("Toggle"), R("Teleport"), R("Fight"), R("Dig")
local StateR, EventR = R("State"), R("Event")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

--------------------------------------------------------------------------------
-- Состояние
--------------------------------------------------------------------------------
local state: Config.Data = Config.newData()
local income = 0
local stateTime = os.clock()
local hasState = false
type FightInfo = { layer: number, hp: number, maxHp: number, timeLeft: number }
local fight: FightInfo? = nil

local function coinsNow(): number
	return state.coins + income * math.min(os.clock() - stateTime, 1.5)
end

--------------------------------------------------------------------------------
-- Утилиты интерфейса
--------------------------------------------------------------------------------
local BG = Color3.fromRGB(20, 17, 26)
local PANEL = Color3.fromRGB(32, 27, 40)
local CARD = Color3.fromRGB(44, 37, 54)
local CARD_DIM = Color3.fromRGB(34, 29, 42)
local ACCENT = Color3.fromRGB(255, 190, 80)
local GOOD = Color3.fromRGB(60, 180, 90)
local BAD = Color3.fromRGB(75, 68, 85)
local RED = Color3.fromRGB(230, 70, 70)
local PURPLE = Color3.fromRGB(190, 120, 255)
local CYAN = Color3.fromRGB(90, 210, 255)
local MUTED = Color3.fromRGB(185, 175, 195)
local WHITE = Color3.new(1, 1, 1)
local DARKTEXT = Color3.fromRGB(35, 25, 10)

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number?): any
	return new("UICorner", { CornerRadius = UDim.new(0, r or 12) })
end

local function stroke(color: Color3, thickness: number?, transparency: number?): any
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function label(props: { [string]: any }): TextLabel
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or WHITE
	return new("TextLabel", props)
end

local function button(props: { [string]: any }, children: { Instance }?): TextButton
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or WHITE
	props.AutoButtonColor = true
	return new("TextButton", props, children)
end

local function playSound(id: string, volume: number, pitch: number?)
	local s = new("Sound", { SoundId = id, Volume = volume, PlaybackSpeed = pitch or 1, Parent = SoundService })
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end
local SND_STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local SND_BUY = "rbxasset://sounds/button.wav"
local SND_PING = "rbxasset://sounds/electronicpingshort.wav"
local SND_WIN = "rbxasset://sounds/victory.wav"
local SND_HIT = "rbxasset://sounds/swordslash.wav"

local function pop(inst: GuiObject, from: number?)
	local sc = inst:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = inst })
	sc.Scale = from or 0.9
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

--------------------------------------------------------------------------------
-- Корень
--------------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "AbyssUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
local uiScale = new("UIScale", { Parent = gui })
local function updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		uiScale.Scale = math.clamp(math.min(cam.ViewportSize.Y / 950, cam.ViewportSize.X / 1500), 0.55, 1.15)
	end
end
updateScale()
local cam0 = workspace.CurrentCamera
if cam0 then
	cam0:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(480, 108),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.12,
	Parent = gui,
}, { corner(18), stroke(ACCENT, 2) })
local coinsLabel = label({
	Size = UDim2.new(1, -20, 0, 50),
	Position = UDim2.fromOffset(10, 4),
	Text = "💰 0",
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = ACCENT,
	Parent = hud,
})
local incomeLabel = label({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 54), Text = "", TextSize = 18, Parent = hud })
local depthLabel = label({
	Size = UDim2.new(1, -20, 0, 18),
	Position = UDim2.fromOffset(10, 76),
	Text = "",
	TextSize = 15,
	Font = Enum.Font.Gotham,
	TextColor3 = CYAN,
	Parent = hud,
})
local titleLabel = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 4),
	Size = UDim2.fromOffset(400, 22),
	Text = "",
	TextSize = 16,
	Font = Enum.Font.FredokaOne,
	TextStrokeTransparency = 0.3,
	Parent = hud,
})

--------------------------------------------------------------------------------
-- Нижняя панель: шаг вниз
--------------------------------------------------------------------------------
local bottom = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(440, 80),
	BackgroundTransparency = 1,
	Parent = gui,
})
local stepButton = button({
	Size = UDim2.new(1, -110, 1, 0),
	BackgroundColor3 = BAD,
	Text = "",
	Parent = bottom,
}, { corner(18), stroke(WHITE, 3) })
local stepTitle = label({
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.fromOffset(0, 6),
	Text = "⬇ ШАГ ВНИЗ",
	TextSize = 28,
	Font = Enum.Font.FredokaOne,
	Parent = stepButton,
})
local stepCostLabel = label({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 46), Text = "", TextSize = 18, Parent = stepButton })
local maxButton = button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, 100, 1, 0),
	BackgroundColor3 = PANEL,
	Text = "МАКС",
	TextSize = 20,
	Font = Enum.Font.FredokaOne,
	Parent = bottom,
}, { corner(18), stroke(ACCENT, 2) })

-- Блок стража (появляется вместо шага)
local bossRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -104),
	Size = UDim2.fromOffset(440, 46),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
local fightButton = button({ Size = UDim2.fromOffset(250, 46), BackgroundColor3 = RED, Text = "⚔ Сразиться", TextSize = 18, Font = Enum.Font.FredokaOne, Parent = bossRow }, { corner(12) })
local toBossButton = button({ Size = UDim2.fromOffset(170, 46), BackgroundColor3 = PANEL, Text = "🏃 К стражу", TextSize = 16, Parent = bossRow }, { corner(12), stroke(RED, 2) })
local bossHint = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -154),
	Size = UDim2.fromOffset(520, 22),
	Text = "",
	TextSize = 15,
	TextStrokeTransparency = 0.3,
	Visible = false,
	Parent = gui,
})

--------------------------------------------------------------------------------
-- Боковые кнопки
--------------------------------------------------------------------------------
local leftBar = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(70, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 8) }) })

local function sideButton(icon: string, caption: string, color: Color3?): TextButton
	local b = button({ Size = UDim2.fromOffset(70, 66), BackgroundColor3 = PANEL, Text = "", Parent = leftBar }, { corner(14), stroke(color or ACCENT, 1.5, 0.3) })
	label({ Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 4), Text = icon, TextSize = 28, Parent = b })
	label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 44), Text = caption, TextSize = 11, TextColor3 = MUTED, Parent = b })
	return b
end
local edgeButton = sideButton("🏃", "К краю")
local upButton = sideButton("⬆", "Наверх")
local digButton = sideButton("🦴", "Копать", CYAN)
local rollButton = sideButton("🎲", "Звание", PURPLE)
local menuButton = sideButton("📜", "Меню")

--------------------------------------------------------------------------------
-- Правая панель с вкладками
--------------------------------------------------------------------------------
local panel = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(400, 640),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.08,
	Parent = gui,
}, { corner(18), stroke(ACCENT, 2) })
local tabsBar = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 44), BackgroundTransparency = 1, Parent = panel }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
})
local content = new("Frame", { Position = UDim2.fromOffset(8, 58), Size = UDim2.new(1, -16, 1, -66), BackgroundTransparency = 1, ClipsDescendants = true, Parent = panel })

type Tab = { button: TextButton, page: Frame, badge: TextLabel }
local tabs: { [string]: Tab } = {}
local currentTab = "ups"
local function selectTab(id: string)
	currentTab = id
	for tid, t in pairs(tabs) do
		local on = tid == id
		t.page.Visible = on
		t.button.BackgroundColor3 = on and ACCENT or PANEL
		t.button.TextColor3 = on and DARKTEXT or WHITE
	end
end
local function addTab(id: string, title: string): Frame
	local b = button({ Size = UDim2.new(0.25, -5, 1, 0), BackgroundColor3 = PANEL, Text = title, TextSize = 14, Parent = tabsBar }, { corner(10) })
	local badge = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -6),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = RED,
		Text = "!",
		TextSize = 13,
		Visible = false,
		ZIndex = 3,
		Parent = b,
	})
	corner(10).Parent = badge
	local page = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = content })
	tabs[id] = { button = b, page = page, badge = badge }
	b.Activated:Connect(function()
		selectTab(id)
		playSound(SND_BUY, 0.2, 1.4)
	end)
	return page
end
local function scroller(parent: Instance, top: number): ScrollingFrame
	return new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }),
	})
end
local function sectionHeader(parent: Instance, text: string, order: number, color: Color3)
	label({ Size = UDim2.new(1, 0, 0, 26), Text = text, TextSize = 17, Font = Enum.Font.FredokaOne, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Parent = parent })
end

--------------------------------------------------------------------------------
-- Вкладка «Улучшения»
--------------------------------------------------------------------------------
local upsPage = addTab("ups", "⬆ Улучш.")
local upsList = scroller(upsPage, 0)
type UpCard = { u: Config.Upgrade, frame: Frame, lvl: TextLabel, buy: TextButton, lock: TextLabel }
local upCards: { UpCard } = {}
local TREES = { { "coins", "💰 Монеты", ACCENT }, { "luck", "🍀 Удача", GOOD }, { "power", "⚔ Сила", RED } }
local order = 0
for _, tree in ipairs(TREES) do
	order += 1
	sectionHeader(upsList, tree[2], order, tree[3])
	for _, u in ipairs(Config.Upgrades) do
		if u.tree == tree[1] then
			order += 1
			local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = CARD, LayoutOrder = order, Parent = upsList }, { corner(12) })
			new("Frame", { Size = UDim2.fromOffset(5, 46), Position = UDim2.fromOffset(8, 10), BackgroundColor3 = tree[3], Parent = frame }, { corner(3) })
			label({ Position = UDim2.fromOffset(20, 6), Size = UDim2.new(1, -150, 0, 22), Text = u.name, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
			label({
				Position = UDim2.fromOffset(20, 28),
				Size = UDim2.new(1, -150, 0, 18),
				Text = u.desc,
				TextSize = 12,
				TextWrapped = true,
				Font = Enum.Font.Gotham,
				TextColor3 = MUTED,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
			local lvl = label({ Position = UDim2.fromOffset(20, 46), Size = UDim2.new(1, -150, 0, 14), Text = "", TextSize = 11, Font = Enum.Font.Gotham, TextColor3 = tree[3], TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
			local buy = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(116, 46), BackgroundColor3 = BAD, Text = "", TextSize = 15, Parent = frame }, { corner(10) })
			local lock = label({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 0.25,
				BackgroundColor3 = Color3.new(0, 0, 0),
				Text = string.format("🔒 Победи %d страж%s", u.needBoss, u.needBoss == 1 and "а" or "ей"),
				TextSize = 15,
				ZIndex = 3,
				Visible = false,
				Parent = frame,
			})
			corner(12).Parent = lock
			buy.Activated:Connect(function()
				BuyUpR:FireServer(u.id, 1)
				pop(buy, 0.9)
			end)
			table.insert(upCards, { u = u, frame = frame, lvl = lvl, buy = buy, lock = lock })
		end
	end
end

--------------------------------------------------------------------------------
-- Вкладка «Коллекция»
--------------------------------------------------------------------------------
local colPage = addTab("col", "🦴 Находки")
local colList = scroller(colPage, 0)
local colSummary = label({
	Size = UDim2.new(1, 0, 0, 54),
	Text = "",
	TextSize = 14,
	TextWrapped = true,
	Font = Enum.Font.Gotham,
	TextColor3 = MUTED,
	LayoutOrder = 0,
	Parent = colList,
})
type RelicCell = { relic: Config.Relic, frame: Frame, name: TextLabel, info: TextLabel }
local relicCells: { RelicCell } = {}
local layerHeaders: { [number]: TextLabel } = {}
for L, layer in ipairs(Config.Layers) do
	local header = label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = string.format("Слой %d · %s", L, layer.name),
		TextSize = 15,
		Font = Enum.Font.FredokaOne,
		TextColor3 = layer.glow,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = L * 2 - 1,
		Parent = colList,
	})
	layerHeaders[L] = header
	local grid = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = L * 2, Parent = colList }, {
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 50), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, relic in ipairs(Config.RelicsByLayer[L]) do
		local frame = new("Frame", { BackgroundColor3 = CARD_DIM, LayoutOrder = i, Parent = grid }, { corner(10), stroke(relic.rarity.color, 1.5, 0.6) })
		local name = label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 20), Text = "???", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = MUTED, Parent = frame })
		local info = label({ Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 22), Text = relic.rarity.name, TextSize = 11, TextWrapped = true, Font = Enum.Font.Gotham, TextColor3 = relic.rarity.color, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
		table.insert(relicCells, { relic = relic, frame = frame, name = name, info = info })
	end
end

--------------------------------------------------------------------------------
-- Вкладка «Звания»
--------------------------------------------------------------------------------
local titlePage = addTab("titles", "🎖 Звания")
local titleList = scroller(titlePage, 0)
local titleHeader = new("Frame", { Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = CARD, LayoutOrder = 0, Parent = titleList }, { corner(12), stroke(PURPLE, 1.5, 0.3) })
local titleCurrent = label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 28), Text = "", TextSize = 20, Font = Enum.Font.FredokaOne, TextXAlignment = Enum.TextXAlignment.Left, Parent = titleHeader })
local titleInfo = label({ Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 20), Text = "", TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Parent = titleHeader })
local rollBig = button({ Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 0, 48), BackgroundColor3 = PURPLE, Text = "🎲 Крутить", TextSize = 18, Font = Enum.Font.FredokaOne, Parent = titleHeader }, { corner(12) })
rollBig.Activated:Connect(function()
	RollR:FireServer()
	pop(rollBig, 0.9)
end)
type TitleRow = { t: Config.Title, frame: Frame, owned: TextLabel }
local titleRows: { TitleRow } = {}
for i, t in ipairs(Config.Titles) do
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = CARD_DIM, LayoutOrder = i, Parent = titleList }, { corner(10) })
	label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.5, 0, 1, 0), Text = t.name, TextSize = 15, TextColor3 = t.color, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	label({ Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.22, 0, 1, 0), Text = Config.formatChance(t.chance), TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = MUTED, Parent = frame })
	local owned = label({ Position = UDim2.new(0.72, 0, 0, 0), Size = UDim2.new(0.28, -8, 1, 0), Text = "×" .. tostring(t.mult), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Parent = frame })
	table.insert(titleRows, { t = t, frame = frame, owned = owned })
end

--------------------------------------------------------------------------------
-- Вкладка «Перерождение»
--------------------------------------------------------------------------------
local rebPage = addTab("reb", "🔁 Перерожд.")
local rebList = scroller(rebPage, 0)
local rebHeader = new("Frame", { Size = UDim2.new(1, 0, 0, 236), BackgroundColor3 = CARD, LayoutOrder = 0, Parent = rebList }, { corner(12), stroke(CYAN, 1.5, 0.3) })
local tokensLabel = label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 30), Text = "", TextSize = 21, Font = Enum.Font.FredokaOne, TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Left, Parent = rebHeader })
local rebInfo = label({
	Position = UDim2.fromOffset(12, 40),
	Size = UDim2.new(1, -24, 0, 70),
	Text = "",
	TextSize = 13,
	TextWrapped = true,
	Font = Enum.Font.Gotham,
	TextColor3 = MUTED,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = rebHeader,
})
local rebButton = button({ Position = UDim2.fromOffset(12, 114), Size = UDim2.new(1, -24, 0, 48), BackgroundColor3 = BAD, Text = "", TextSize = 18, Font = Enum.Font.FredokaOne, Parent = rebHeader }, { corner(12) })
local autoStepToggle = button({ Position = UDim2.fromOffset(12, 168), Size = UDim2.new(1, -24, 0, 28), BackgroundColor3 = PANEL, Text = "", TextSize = 13, Visible = false, Parent = rebHeader }, { corner(8) })
local autoDigToggle = button({ Position = UDim2.fromOffset(12, 200), Size = UDim2.new(1, -24, 0, 28), BackgroundColor3 = PANEL, Text = "", TextSize = 13, Visible = false, Parent = rebHeader }, { corner(8) })
autoStepToggle.Activated:Connect(function()
	ToggleR:FireServer("autoStep")
end)
autoDigToggle.Activated:Connect(function()
	ToggleR:FireServer("autoDig")
end)
local confirmUntil = 0
rebButton.Activated:Connect(function()
	if Config.tokensOnRebirth(state) < 1 then
		return
	end
	if os.clock() < confirmUntil then
		confirmUntil = 0
		RebirthR:FireServer()
	else
		confirmUntil = os.clock() + 3
		rebButton.Text = "Точно? Нажми ещё раз"
		pop(rebButton, 0.9)
	end
end)
type RCard = { r: Config.RebirthUp, lvl: TextLabel, buy: TextButton }
local rCards: { RCard } = {}
for i, r in ipairs(Config.RebirthUps) do
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = CARD, LayoutOrder = i, Parent = rebList }, { corner(12) })
	label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -140, 0, 22), Text = "💠 " .. r.name, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	label({
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -140, 0, 26),
		Text = r.desc,
		TextSize = 12,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	local lvl = label({ Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -140, 0, 14), Text = "", TextSize = 11, Font = Enum.Font.Gotham, TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local buy = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(112, 46), BackgroundColor3 = BAD, Text = "", TextSize = 15, Parent = frame }, { corner(10) })
	buy.Activated:Connect(function()
		BuyRUpR:FireServer(r.id)
		pop(buy, 0.9)
	end)
	table.insert(rCards, { r = r, lvl = lvl, buy = buy })
end

selectTab("ups")

--------------------------------------------------------------------------------
-- Бой: полоса здоровья стража
--------------------------------------------------------------------------------
local fightFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 148),
	Size = UDim2.fromOffset(480, 64),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.1,
	Visible = false,
	Parent = gui,
}, { corner(14), stroke(RED, 2) })
local fightName = label({ Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 22), Text = "", TextSize = 17, Font = Enum.Font.FredokaOne, TextColor3 = RED, Parent = fightFrame })
local hpBg = new("Frame", { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 24), BackgroundColor3 = Color3.fromRGB(40, 15, 15), Parent = fightFrame }, { corner(8) })
local hpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED, Parent = hpBg }, { corner(8) })
local hpText = label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 14, ZIndex = 2, Parent = hpBg })

--------------------------------------------------------------------------------
-- Сообщения и окна
--------------------------------------------------------------------------------
local toastHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 222),
	Size = UDim2.fromOffset(520, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

local function toast(text: string, color: Color3?)
	local t = label({
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = BG,
		Text = "  " .. text .. "  ",
		TextSize = 18,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color or ACCENT,
		Parent = toastHolder,
	})
	corner(12).Parent = t
	stroke(color or ACCENT, 1.5, 0.3).Parent = t
	pop(t, 0.7)
	task.delay(3.5, function()
		local info = TweenInfo.new(0.5)
		TweenService:Create(t, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		local st = t:FindFirstChildOfClass("UIStroke")
		if st then
			TweenService:Create(st, info, { Transparency = 1 }):Play()
		end
		task.wait(0.5)
		t:Destroy()
	end)
	local labels = {}
	for _, c in ipairs(toastHolder:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if #labels > 5 then
		labels[1]:Destroy()
	end
end

local function modal(title: string, body: string, buttonText: string, color: Color3?)
	local shade = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 50, Parent = gui })
	local box = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 300),
		BackgroundColor3 = BG,
		ZIndex = 51,
		Parent = shade,
	}, { corner(20), stroke(color or ACCENT, 3) })
	label({ Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 40), Text = title, TextSize = 28, Font = Enum.Font.FredokaOne, TextColor3 = color or ACCENT, ZIndex = 52, Parent = box })
	label({ Position = UDim2.fromOffset(24, 64), Size = UDim2.new(1, -48, 0, 150), Text = body, TextSize = 17, TextWrapped = true, Font = Enum.Font.Gotham, ZIndex = 52, Parent = box })
	local ok = button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(220, 52),
		BackgroundColor3 = GOOD,
		Text = buttonText,
		TextSize = 20,
		Font = Enum.Font.FredokaOne,
		ZIndex = 52,
		Parent = box,
	}, { corner(14) })
	pop(box, 0.6)
	ok.Activated:Connect(function()
		shade:Destroy()
	end)
end

-- Карточка находки
local relicQueue = 0
local function showRelic(relic: Config.Relic, shiny: boolean, isNew: boolean)
	relicQueue += 1
	local slot = relicQueue
	local color = relic.rarity.color
	local card = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(320, 150),
		BackgroundColor3 = BG,
		ZIndex = 30,
		Parent = gui,
	}, { corner(18), stroke(shiny and WHITE or color, shiny and 4 or 3) })
	label({ Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 22), Text = isNew and "✨ НОВАЯ НАХОДКА ✨" or "Находка", TextSize = 15, TextColor3 = MUTED, ZIndex = 31, Parent = card })
	label({ Position = UDim2.fromOffset(10, 34), Size = UDim2.new(1, -20, 0, 40), Text = (shiny and "🌟 " or "🦴 ") .. relic.name, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = color, ZIndex = 31, Parent = card })
	label({
		Position = UDim2.fromOffset(10, 78),
		Size = UDim2.new(1, -20, 0, 22),
		Text = relic.rarity.name .. (shiny and " · СИЯЮЩАЯ ×" .. Config.SHINY_MULT or ""),
		TextSize = 16,
		TextColor3 = shiny and Color3.fromRGB(255, 255, 180) or color,
		ZIndex = 31,
		Parent = card,
	})
	local entry = state.relics[relic.id]
	local bonus = entry and Config.relicBonus(relic, entry) or 0
	label({ Position = UDim2.fromOffset(10, 106), Size = UDim2.new(1, -20, 0, 30), Text = string.format("Бонус к доходу: +%d%%", math.floor(bonus * 100 + 0.5)), TextSize = 14, Font = Enum.Font.Gotham, ZIndex = 31, Parent = card })
	pop(card, 0.4)
	if relic.rarityIndex >= 4 or shiny then
		playSound(SND_WIN, 0.6, shiny and 1.3 or 1)
	else
		playSound(SND_PING, 0.4, 1.2)
	end
	task.delay(isNew and 2.2 or 1.3, function()
		TweenService:Create(card, TweenInfo.new(0.3), { Position = UDim2.fromScale(0.5, 0.3), BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.35)
		card:Destroy()
		if relicQueue == slot then
			relicQueue = 0
		end
	end)
end

--------------------------------------------------------------------------------
-- Личный барьер на лестнице (виден и непроходим только для тебя)
--------------------------------------------------------------------------------
local barrier = new("Part", {
	Name = "MyBarrier",
	Anchored = true,
	CanCollide = true,
	CastShadow = false,
	Material = Enum.Material.ForceField,
	Color = ACCENT,
	Transparency = 0.2,
	Size = Vector3.new(Config.PIT_OUTER - Config.PIT_INNER + 2, 14, 0.6),
})
local barrierBB = new("BillboardGui", { Size = UDim2.fromOffset(240, 44), StudsOffsetWorldSpace = Vector3.new(0, 2, 0), AlwaysOnTop = false, LightInfluence = 0, MaxDistance = 60, Adornee = barrier, Parent = barrier })
local barrierText = label({ Size = UDim2.fromScale(1, 1), Text = "", TextScaled = true, Font = Enum.Font.FredokaOne, TextStrokeTransparency = 0.2, Parent = barrierBB })
local barrierStep = -1
local function placeBarrier()
	local s = state.step
	if s >= Config.MAX_STEP then
		barrier.Parent = nil
		return
	end
	if s == barrierStep and barrier.Parent then
		return
	end
	barrierStep = s
	local a = (Config.stepAngle(s) + Config.stepAngle(s + 1)) / 2
	local y = Config.stepPosition(s).Y + 6
	barrier.CFrame = CFrame.new(math.cos(a) * Config.STEP_RADIUS, y, math.sin(a) * Config.STEP_RADIUS) * CFrame.Angles(0, -a, 0)
	barrier.Parent = workspace
end

--------------------------------------------------------------------------------
-- Освещение по глубине
--------------------------------------------------------------------------------
local tint = Lighting:WaitForChild("DepthTint", 10) :: ColorCorrectionEffect?
local surfaceAmbient = Lighting.Ambient
local surfaceOutdoor = Lighting.OutdoorAmbient
local surfaceBrightness = Lighting.Brightness
local currentLayerShown = 0
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local y = cam.CFrame.Position.Y
	local depth = (Config.SURFACE_Y - y) / Config.STEP_DROP
	local inPit = depth > 3 and Vector3.new(cam.CFrame.Position.X, 0, cam.CFrame.Position.Z).Magnitude < 40
	local layer = inPit and Config.layerOfStep(math.max(1, math.floor(depth))) or 0
	if layer ~= currentLayerShown then
		currentLayerShown = layer
		local info = TweenInfo.new(1.2)
		if layer == 0 then
			TweenService:Create(Lighting, info, { Ambient = surfaceAmbient, OutdoorAmbient = surfaceOutdoor, Brightness = surfaceBrightness }):Play()
			if tint then
				TweenService:Create(tint, info, { TintColor = WHITE, Brightness = 0 }):Play()
			end
		else
			local L = Config.Layers[layer]
			local dark = math.clamp(layer / #Config.Layers, 0, 1)
			TweenService:Create(Lighting, info, {
				Ambient = L.glow:Lerp(Color3.new(0, 0, 0), 0.55 + dark * 0.3),
				OutdoorAmbient = L.wall:Lerp(Color3.new(0, 0, 0), 0.4 + dark * 0.4),
				Brightness = math.max(0.3, 1.4 - dark),
			}):Play()
			if tint then
				TweenService:Create(tint, info, { TintColor = WHITE:Lerp(L.glow, 0.25), Brightness = -0.03 * layer }):Play()
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Кнопки
--------------------------------------------------------------------------------
stepButton.Activated:Connect(function()
	BuyStepR:FireServer(1)
	pop(stepButton, 0.94)
end)
maxButton.Activated:Connect(function()
	BuyStepR:FireServer("max")
	pop(maxButton, 0.9)
end)
fightButton.Activated:Connect(function()
	FightR:FireServer()
end)
toBossButton.Activated:Connect(function()
	TeleportR:FireServer("boss")
end)
edgeButton.Activated:Connect(function()
	TeleportR:FireServer("edge")
end)
upButton.Activated:Connect(function()
	TeleportR:FireServer("surface")
end)
digButton.Activated:Connect(function()
	DigR:FireServer()
	pop(digButton, 0.9)
end)
rollButton.Activated:Connect(function()
	RollR:FireServer()
	pop(rollButton, 0.9)
end)
menuButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		pop(panel, 0.95)
	end
end)

--------------------------------------------------------------------------------
-- Обновление интерфейса
--------------------------------------------------------------------------------
local function updateUI()
	if not hasState then
		return
	end
	local coins = coinsNow()
	local d = state
	coinsLabel.Text = "💰 " .. Config.format(coins)
	incomeLabel.Text = string.format("+%s/с   ·   🍀 удача ×%s", Config.format(income), Config.format(Config.luck(d)))
	local layer = Config.Layers[Config.layerOfStep(math.max(d.step, 1))]
	depthLabel.Text = string.format("⬇ Ступень %d / %d  ·  %s  ·  бонус глубины ×%s", d.step, Config.MAX_STEP, d.step > 0 and layer.name or "поверхность", Config.format(Config.depthMult(d)))
	local title = d.title and Config.TitleById[d.title]
	if title then
		titleLabel.Text = string.format("🎖 %s  (доход ×%s)", title.name, tostring(title.mult))
		titleLabel.TextColor3 = title.color
	else
		titleLabel.Text = "🎖 Без звания — крути на алтаре или кнопкой 🎲"
		titleLabel.TextColor3 = MUTED
	end

	-- Шаг / страж
	local canStep, why = Config.canBuyStep(d)
	local nextLayer = d.bosses + 1
	local atBoss = not canStep and d.step < Config.MAX_STEP and nextLayer <= #Config.Layers
	if canStep then
		local cost = Config.stepCost(d, d.step + 1)
		stepTitle.Text = "⬇ ШАГ ВНИЗ"
		stepCostLabel.Text = "💰 " .. Config.format(cost)
		stepButton.BackgroundColor3 = coins >= cost and GOOD or BAD
	elseif atBoss then
		stepTitle.Text = "⚔ СТРАЖ"
		stepCostLabel.Text = Config.Layers[nextLayer].boss
		stepButton.BackgroundColor3 = RED
	else
		stepTitle.Text = "🏁 ДНО"
		stepCostLabel.Text = why or ""
		stepButton.BackgroundColor3 = ACCENT
	end
	bossRow.Visible = atBoss and fight == nil
	bossHint.Visible = atBoss and fight == nil
	if atBoss then
		local hp = Config.bossHP(nextLayer)
		local total = Config.damagePerSec(d) * Config.fightDuration(d)
		local pct = math.floor(math.min(total / hp, 9.99) * 100)
		bossHint.Text = string.format(
			"Твой урон за бой ≈ %s из ❤ %s (%d%%)%s",
			Config.format(total),
			Config.format(hp),
			pct,
			pct < 100 and " — качай «Силу»" or " — можно побеждать!"
		)
		bossHint.TextColor3 = pct < 100 and Color3.fromRGB(255, 160, 140) or Color3.fromRGB(150, 255, 160)
		fightButton.Text = string.format("⚔ Сразиться: %s", Config.Layers[nextLayer].boss)
	end

	-- Барьер
	placeBarrier()
	if canStep then
		barrierText.Text = "💰 " .. Config.format(Config.stepCost(d, d.step + 1))
		barrierText.TextColor3 = ACCENT
		barrier.Color = ACCENT
	elseif atBoss then
		barrierText.Text = "⚔ Победи стража"
		barrierText.TextColor3 = RED
		barrier.Color = RED
	end

	-- Бой
	local f = fight
	fightFrame.Visible = f ~= nil
	if f then
		fightName.Text = string.format("⚔ %s — %d с", Config.Layers[f.layer].boss, math.ceil(f.timeLeft))
		hpFill.Size = UDim2.fromScale(math.clamp(f.hp / f.maxHp, 0, 1), 1)
		hpText.Text = "❤ " .. Config.format(math.max(0, f.hp)) .. " / " .. Config.format(f.maxHp)
	end

	-- Улучшения
	local anyUp = false
	for _, card in ipairs(upCards) do
		local u = card.u
		local lvl = Config.lvl(d, u.id)
		local locked = d.bosses < u.needBoss
		card.lock.Visible = locked
		card.lvl.Text = string.format("Уровень %d/%d", lvl, u.maxLevel)
		if lvl >= u.maxLevel then
			card.buy.Text = "МАКС"
			card.buy.BackgroundColor3 = ACCENT
			card.buy.TextColor3 = DARKTEXT
		else
			local cost = Config.upCost(u, lvl)
			card.buy.Text = "💰 " .. Config.format(cost)
			local can = not locked and coins >= cost
			card.buy.BackgroundColor3 = can and GOOD or BAD
			card.buy.TextColor3 = WHITE
			anyUp = anyUp or can
		end
	end
	tabs.ups.badge.Visible = anyUp and currentTab ~= "ups"

	-- Коллекция
	local found = 0
	for _, cell in ipairs(relicCells) do
		local e = d.relics[cell.relic.id]
		if e and e.n > 0 then
			found += 1
			cell.name.Text = (e.s > 0 and "🌟 " or "") .. cell.relic.name
			cell.name.TextColor3 = cell.relic.rarity.color
			cell.info.Text = string.format("×%d%s · +%d%%", e.n, e.s > 0 and (" (сияющих " .. e.s .. ")") or "", math.floor(Config.relicBonus(cell.relic, e) * 100 + 0.5))
			cell.frame.BackgroundColor3 = CARD
		else
			cell.name.Text = "???"
			cell.name.TextColor3 = MUTED
			cell.info.Text = cell.relic.rarity.name
			cell.frame.BackgroundColor3 = CARD_DIM
		end
	end
	colSummary.Text = string.format(
		"Найдено %d из %d. Все находки вместе: доход ×%s.\nРаскоп каждого слоя — на его 25-й ступени (кнопка 🦴 копает на самом глубоком). Находки сохраняются после перерождения.",
		found,
		#Config.Relics,
		Config.format(Config.relicMult(d))
	)

	-- Звания
	local rollCost = Config.titleRollCost(d)
	titleCurrent.Text = title and ("🎖 " .. title.name .. "  ×" .. tostring(title.mult)) or "🎖 Без звания"
	titleCurrent.TextColor3 = title and title.color or MUTED
	titleInfo.Text = string.format("Бросков: %d · удача ×%s делит знаменатель шанса", d.rolls, Config.format(Config.luck(d)))
	rollBig.Text = "🎲 Крутить — 💰 " .. Config.format(rollCost)
	rollBig.BackgroundColor3 = coins >= rollCost and PURPLE or BAD
	for _, row in ipairs(titleRows) do
		local n = d.titles[row.t.id] or 0
		row.frame.BackgroundColor3 = n > 0 and CARD or CARD_DIM
		row.owned.Text = (n > 0 and ("✓" .. n .. "  ") or "") .. "×" .. tostring(row.t.mult)
		row.owned.TextColor3 = n > 0 and row.t.color or MUTED
	end

	-- Перерождение
	local gain = Config.tokensOnRebirth(d)
	tokensLabel.Text = string.format("💠 %d осколков", d.tokens)
	rebInfo.Text = string.format(
		"Получено всего: %d → доход +%d%% навсегда.\nПерерождение открывается после %d-го стража. Сбрасывает монеты, ступени, стражей и улучшения. Находки, звания и осколки остаются.",
		d.tokensEver,
		math.floor(d.tokensEver * Config.TOKEN_BONUS * 100 + 0.5),
		Config.REBIRTH_NEED_BOSSES
	)
	if os.clock() >= confirmUntil then
		if gain >= 1 then
			rebButton.Text = string.format("🔁 Переродиться: +%d 💠", gain)
		else
			rebButton.Text = string.format("🔒 Победи %d стражей", Config.REBIRTH_NEED_BOSSES)
		end
	end
	rebButton.BackgroundColor3 = gain >= 1 and Color3.fromRGB(40, 140, 170) or BAD
	autoStepToggle.Visible = Config.rlvl(d, "r_autostep") >= 1
	autoStepToggle.Text = d.autoStep and "🦶 Автоспуск: ВКЛ" or "🦶 Автоспуск: ВЫКЛ"
	autoStepToggle.BackgroundColor3 = d.autoStep and Color3.fromRGB(40, 110, 70) or PANEL
	autoDigToggle.Visible = Config.rlvl(d, "r_autodig") >= 1
	autoDigToggle.Text = d.autoDig and "🐾 Крот-помощник: ВКЛ" or "🐾 Крот-помощник: ВЫКЛ"
	autoDigToggle.BackgroundColor3 = d.autoDig and Color3.fromRGB(40, 110, 70) or PANEL
	local anyR = false
	for _, card in ipairs(rCards) do
		local lvl = Config.rlvl(d, card.r.id)
		card.lvl.Text = string.format("Уровень %d/%d", lvl, card.r.maxLevel)
		if lvl >= card.r.maxLevel then
			card.buy.Text = "МАКС"
			card.buy.BackgroundColor3 = ACCENT
			card.buy.TextColor3 = DARKTEXT
		else
			local cost = Config.rupCost(card.r, lvl)
			card.buy.Text = "💠 " .. cost
			local can = d.tokens >= cost
			card.buy.BackgroundColor3 = can and GOOD or BAD
			card.buy.TextColor3 = WHITE
			anyR = anyR or can
		end
	end
	tabs.reb.badge.Visible = (anyR or gain >= math.max(5, d.tokensEver)) and currentTab ~= "reb"
end

task.spawn(function()
	while true do
		updateUI()
		task.wait(0.1)
	end
end)
RunService.Heartbeat:Connect(function(dt)
	if hasState then
		coinsLabel.Text = "💰 " .. Config.format(coinsNow())
	end
	local f = fight
	if f then
		f.timeLeft = math.max(0, f.timeLeft - dt)
	end
end)

--------------------------------------------------------------------------------
-- Сеть
--------------------------------------------------------------------------------
local lastStep = -1
StateR.OnClientEvent:Connect(function(s: any)
	state.coins = s.coins
	state.totalCoins = s.totalCoins
	state.step = s.step
	state.bestStep = s.bestStep
	state.bosses = s.bosses
	state.ups = s.ups or {}
	state.relics = s.relics or {}
	state.titles = s.titles or {}
	state.title = s.title
	state.tokens = s.tokens
	state.tokensEver = s.tokensEver
	state.rebirths = s.rebirths
	state.rups = s.rups or {}
	state.digs = s.digs
	state.rolls = s.rolls
	state.playTime = s.playTime
	state.autoStep = s.autoStep
	state.autoDig = s.autoDig
	income = s.income
	fight = s.fight
	stateTime = os.clock()
	if lastStep >= 0 and s.step > lastStep then
		playSound(SND_STEP, 0.4, 0.9 + math.random() * 0.2)
	end
	lastStep = s.step
	hasState = true
end)

EventR.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, dd: any)
	if kind == "bossReached" then
		local L = Config.Layers[a]
		toast("⚔ Путь преграждает " .. L.boss .. "!", RED)
		playSound(SND_HIT, 0.5, 0.7)
	elseif kind == "newLayer" then
		local L = Config.Layers[a]
		toast(string.format("🌋 Новый слой: %s", L.name), L.glow)
		playSound(SND_WIN, 0.4, 1.1)
	elseif kind == "digUnlocked" then
		toast("🦴 Открыт раскоп: " .. Config.Layers[a].name, CYAN)
	elseif kind == "fightStart" then
		playSound(SND_HIT, 0.6)
		toast("⚔ Бой начался!", RED)
	elseif kind == "fightWon" then
		playSound(SND_WIN, 0.7)
		modal(
			"⚔ Победа!",
			string.format("%s повержен!\nНаграда: 💰 %s\n\nПуть в следующий слой открыт.", Config.Layers[a].boss, Config.format(b)),
			"Глубже!",
			RED
		)
	elseif kind == "fightLost" then
		playSound(SND_HIT, 0.5, 0.6)
		toast(string.format("Страж выстоял (осталось %d%% здоровья). Прокачай «Силу» и попробуй снова", math.floor(b * 100 + 0.5)), RED)
	elseif kind == "relic" then
		local relic = Config.RelicById[a]
		if relic then
			if dd and not c and relic.rarityIndex < 3 and not b then
				-- автокопание обычных повторок не отвлекает
				return
			end
			showRelic(relic, b, c)
		end
	elseif kind == "title" then
		local t = Config.TitleById[a]
		if t then
			if b then
				playSound(SND_WIN, 0.6, 1.2)
				toast(string.format("🎖 Новое звание: %s (%s) — доход ×%s!", t.name, Config.formatChance(t.chance), tostring(t.mult)), t.color)
			else
				playSound(SND_PING, 0.3, 0.9)
				toast(string.format("🎲 %s (%s)", t.name, Config.formatChance(t.chance)), t.color)
			end
		end
	elseif kind == "upgraded" then
		local u = Config.UpById[a]
		playSound(SND_BUY, 0.4)
		if u then
			toast("⬆ " .. u.name .. " — ур. " .. Config.lvl(state, u.id) + b, ACCENT)
		end
	elseif kind == "rebirth" then
		playSound(SND_WIN, 0.7)
		modal("🔁 Перерождение!", string.format("Получено 💠 %d осколков.\nДоход вырос навсегда. Загляни во вкладку «Перерожд.» — там улучшения за осколки.", a), "Снова вниз!", CYAN)
		selectTab("reb")
	elseif kind == "offline" then
		modal("С возвращением!", string.format("Пока тебя не было (%s), монеты капали сами:\n\n💰 %s", Config.formatTime(b), Config.format(a)), "Забрать")
	elseif kind == "welcome" then
		modal(
			"⬇ В Бездну",
			"Монеты капают сами. Покупай ступени и спускайся — чем глубже, тем больше доход.\n\nКаждый слой стережёт страж, копай находки на раскопах, крути звания на алтаре и перерождайся ради осколков.",
			"Вниз!"
		)
	elseif kind == "message" then
		toast(tostring(a), ACCENT)
	end
end)
