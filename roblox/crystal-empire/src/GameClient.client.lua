-- Клиент «Кристальной империи»: интерфейс, анимации, бонусы.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local function R(name: string): RemoteEvent
	return Remotes:WaitForChild(name) :: RemoteEvent
end
local ClickR, BuyGenR, BuyUpR, BuyAllUpsR, BuyPUpR = R("Click"), R("BuyGen"), R("BuyUp"), R("BuyAllUps"), R("BuyPUp")
local RebirthR, ClaimGoldenR, ToggleAutoR, GoHomeR = R("Rebirth"), R("ClaimGolden"), R("ToggleAuto"), R("GoHome")
local StateR, EventR = R("State"), R("Event")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

--------------------------------------------------------------------------------
-- Состояние (приходит с сервера)
--------------------------------------------------------------------------------
local state: Config.Data = Config.newData()
local perSec = 0
local clickValue = 1
local frenzyLeft = 0
local stormLeft = 0
local stateTime = os.clock()
local hasState = false

local function mult(): number
	return frenzyLeft > 0 and Config.FrenzyMult or 1
end

-- Плавный счётчик: прибавляем доход между снимками сервера
local function crystalsNow(): number
	return state.crystals + perSec * mult() * math.min(os.clock() - stateTime, 1.5)
end

--------------------------------------------------------------------------------
-- Утилиты интерфейса
--------------------------------------------------------------------------------
local BG = Color3.fromRGB(22, 20, 36)
local PANEL = Color3.fromRGB(30, 27, 48)
local CARD = Color3.fromRGB(42, 38, 66)
local CARD_DIM = Color3.fromRGB(34, 31, 52)
local ACCENT = Color3.fromRGB(70, 210, 255)
local GOOD = Color3.fromRGB(50, 190, 100)
local BAD = Color3.fromRGB(80, 76, 100)
local GOLD = Color3.fromRGB(255, 205, 60)
local PINK = Color3.fromRGB(255, 100, 200)
local MUTED = Color3.fromRGB(180, 178, 205)
local WHITE = Color3.new(1, 1, 1)

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
local SND_CLICK = "rbxasset://sounds/electronicpingshort.wav"
local SND_BUY = "rbxasset://sounds/button.wav"
local SND_WIN = "rbxasset://sounds/victory.wav"

local function pop(inst: GuiObject, scaleFrom: number?)
	local sc = inst:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = inst })
	sc.Scale = scaleFrom or 0.9
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

--------------------------------------------------------------------------------
-- Корневой ScreenGui
--------------------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "EmpireUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

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
-- HUD сверху
--------------------------------------------------------------------------------
local hud = new("Frame", {
	Name = "HUD",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(460, 104),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.12,
	Parent = gui,
}, { corner(18), stroke(ACCENT, 2) })

local balanceLabel = label({
	Size = UDim2.new(1, -20, 0, 54),
	Position = UDim2.fromOffset(10, 4),
	Text = "💎 0",
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = ACCENT,
	Parent = hud,
})
local rateLabel = label({
	Size = UDim2.new(1, -20, 0, 22),
	Position = UDim2.fromOffset(10, 56),
	Text = "",
	TextSize = 19,
	Parent = hud,
})
local bonusLabel = label({
	Size = UDim2.new(1, -20, 0, 20),
	Position = UDim2.fromOffset(10, 80),
	Text = "",
	TextSize = 15,
	Font = Enum.Font.Gotham,
	TextColor3 = GOLD,
	Parent = hud,
})

-- Полоски активных бонусов
local boostFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 118),
	Size = UDim2.fromOffset(460, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

local function makeBoostBar(color: Color3): (Frame, Frame, TextLabel)
	local bar = new("Frame", {
		Size = UDim2.fromOffset(380, 30),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = boostFrame,
	}, { corner(10), stroke(color, 2) })
	local fill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.45,
		Parent = bar,
	}, { corner(10) })
	local t = label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 17, Font = Enum.Font.FredokaOne, ZIndex = 2, Parent = bar })
	return bar, fill, t
end
local frenzyBar, frenzyFill, frenzyText = makeBoostBar(GOLD)
local stormBar, stormFill, stormText = makeBoostBar(PINK)
local frenzyMax, stormMax = 30, 15

--------------------------------------------------------------------------------
-- Кнопки слева
--------------------------------------------------------------------------------
local leftBar = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(64, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 8) }) })

local function sideButton(icon: string, caption: string): TextButton
	local b = button({
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = PANEL,
		Text = "",
		Parent = leftBar,
	}, { corner(14), stroke(ACCENT, 1.5, 0.3) })
	label({ Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 4), Text = icon, TextSize = 28, Parent = b })
	label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 42), Text = caption, TextSize = 11, TextColor3 = MUTED, Parent = b })
	return b
end
local homeButton = sideButton("🏠", "Домой")
local shopButton = sideButton("🛒", "Магазин")

--------------------------------------------------------------------------------
-- Кнопка добычи
--------------------------------------------------------------------------------
local mineButton = button({
	Name = "Mine",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.fromOffset(210, 66),
	BackgroundColor3 = ACCENT,
	Text = "⛏ ДОБЫТЬ",
	Font = Enum.Font.FredokaOne,
	TextSize = 30,
	TextColor3 = Color3.fromRGB(15, 25, 45),
	Parent = gui,
}, { corner(18), stroke(WHITE, 3) })
local mineSub = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -88),
	Size = UDim2.fromOffset(300, 20),
	Text = "",
	TextSize = 15,
	TextStrokeTransparency = 0.4,
	Parent = gui,
})

--------------------------------------------------------------------------------
-- Магазин (правая панель с вкладками)
--------------------------------------------------------------------------------
local shop = new("Frame", {
	Name = "Shop",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(400, 640),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.08,
	Parent = gui,
}, { corner(18), stroke(ACCENT, 2) })

local tabsBar = new("Frame", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(1, -16, 0, 44),
	BackgroundTransparency = 1,
	Parent = shop,
}, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
})

local content = new("Frame", {
	Position = UDim2.fromOffset(8, 58),
	Size = UDim2.new(1, -16, 1, -66),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = shop,
})

type Tab = { button: TextButton, page: Frame, badge: TextLabel }
local tabs: { [string]: Tab } = {}
local currentTab = "gens"

local function selectTab(id: string)
	currentTab = id
	for tid, t in pairs(tabs) do
		local on = tid == id
		t.page.Visible = on
		t.button.BackgroundColor3 = on and ACCENT or PANEL
		t.button.TextColor3 = on and Color3.fromRGB(15, 25, 45) or WHITE
	end
end

local function addTab(id: string, title: string): Frame
	local b = button({
		Size = UDim2.new(0.25, -5, 1, 0),
		BackgroundColor3 = PANEL,
		Text = title,
		TextSize = 15,
		Parent = tabsBar,
	}, { corner(10) })
	local badge = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -6),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = PINK,
		Text = "!",
		TextSize = 14,
		Visible = false,
		ZIndex = 3,
		Parent = b,
	})
	corner(11).Parent = badge
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

local function progressBar(parent: Instance, pos: UDim2, size: UDim2, color: Color3): (Frame, Frame)
	local bg = new("Frame", { Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(20, 18, 32), Parent = parent }, { corner(4) })
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, Parent = bg }, { corner(4) })
	return bg, fill
end

--------------------------------------------------------------------------------
-- Вкладка «Генераторы»
--------------------------------------------------------------------------------
local gensPage = addTab("gens", "⚙ Добыча")
local buyMode: any = 1
local modeButtons: { [any]: TextButton } = {}
local modeBar = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = gensPage }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
})
for _, m in ipairs({ 1, 10, 100, "max" } :: { any }) do
	local b = button({
		Size = UDim2.new(0.25, -5, 1, 0),
		BackgroundColor3 = PANEL,
		Text = m == "max" and "МАКС" or ("×" .. tostring(m)),
		TextSize = 15,
		Parent = modeBar,
	}, { corner(8) })
	modeButtons[m] = b
	b.Activated:Connect(function()
		buyMode = m
		for mm, bb in pairs(modeButtons) do
			bb.BackgroundColor3 = mm == buyMode and GOLD or PANEL
			bb.TextColor3 = mm == buyMode and Color3.fromRGB(40, 30, 10) or WHITE
		end
	end)
end
modeButtons[1].BackgroundColor3 = GOLD
modeButtons[1].TextColor3 = Color3.fromRGB(40, 30, 10)

local gensList = scroller(gensPage, 40)

type GenCard = {
	gen: Config.Generator,
	frame: Frame,
	title: TextLabel,
	info: TextLabel,
	fill: Frame,
	milestone: TextLabel,
	buy: TextButton,
	buyTop: TextLabel,
	buyCost: TextLabel,
}
local genCards: { GenCard } = {}

for i, gen in ipairs(Config.Generators) do
	local frame = new("Frame", {
		Name = gen.id,
		LayoutOrder = i,
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = CARD,
		Visible = false,
		Parent = gensList,
	}, { corner(12) })
	new("Frame", { Size = UDim2.fromOffset(6, 72), Position = UDim2.fromOffset(8, 10), BackgroundColor3 = gen.color, Parent = frame }, { corner(3) })
	label({ Position = UDim2.fromOffset(20, 8), Size = UDim2.fromOffset(34, 34), Text = gen.icon, TextSize = 26, Parent = frame })
	local title = label({
		Position = UDim2.fromOffset(56, 8),
		Size = UDim2.new(1, -186, 0, 22),
		Text = gen.name,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	local info = label({
		Position = UDim2.fromOffset(56, 30),
		Size = UDim2.new(1, -186, 0, 18),
		Text = "",
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local _, fill = progressBar(frame, UDim2.fromOffset(20, 58), UDim2.new(1, -150, 0, 10), gen.color)
	local milestone = label({
		Position = UDim2.fromOffset(20, 70),
		Size = UDim2.new(1, -150, 0, 16),
		Text = "",
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local buy = button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(116, 70),
		BackgroundColor3 = BAD,
		Text = "",
		Parent = frame,
	}, { corner(12) })
	local buyTop = label({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 8), Text = "Купить", TextSize = 16, Parent = buy })
	local buyCost = label({ Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 36), Text = "", TextSize = 15, TextScaled = false, Parent = buy })
	buy.Activated:Connect(function()
		BuyGenR:FireServer(gen.id, buyMode)
		pop(buy, 0.92)
	end)
	table.insert(genCards, {
		gen = gen,
		frame = frame,
		title = title,
		info = info,
		fill = fill,
		milestone = milestone,
		buy = buy,
		buyTop = buyTop,
		buyCost = buyCost,
	})
end

--------------------------------------------------------------------------------
-- Вкладка «Улучшения»
--------------------------------------------------------------------------------
local upsPage = addTab("ups", "⬆ Улучш.")
local buyAll = button({
	Size = UDim2.new(1, -10, 0, 38),
	BackgroundColor3 = GOOD,
	Text = "Купить все доступные",
	TextSize = 16,
	Parent = upsPage,
}, { corner(10) })
buyAll.Activated:Connect(function()
	BuyAllUpsR:FireServer()
end)
local upsList = scroller(upsPage, 46)
local upsEmpty = label({
	Size = UDim2.new(1, 0, 0, 60),
	Text = "Новые улучшения появятся, когда прокачаешь генераторы (уровни 10, 25, 50…) или накопишь больше кристаллов.",
	TextWrapped = true,
	TextSize = 14,
	Font = Enum.Font.Gotham,
	TextColor3 = MUTED,
	LayoutOrder = 100000,
	Parent = upsList,
})

type UpCard = { up: Config.Upgrade, frame: Frame, buy: TextButton }
local upCards: { [string]: UpCard } = {}

local function makeUpCard(up: Config.Upgrade): UpCard
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = CARD, Parent = upsList }, { corner(12) })
	new("Frame", { Size = UDim2.fromOffset(6, 46), Position = UDim2.fromOffset(8, 10), BackgroundColor3 = up.color, Parent = frame }, { corner(3) })
	label({
		Position = UDim2.fromOffset(22, 8),
		Size = UDim2.new(1, -150, 0, 22),
		Text = up.name,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	label({
		Position = UDim2.fromOffset(22, 30),
		Size = UDim2.new(1, -150, 0, 30),
		Text = up.desc,
		TextSize = 12,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	local buy = button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(112, 46),
		BackgroundColor3 = BAD,
		Text = "💎 " .. Config.format(up.cost),
		TextSize = 15,
		Parent = frame,
	}, { corner(10) })
	buy.Activated:Connect(function()
		BuyUpR:FireServer(up.id)
		pop(buy, 0.9)
	end)
	return { up = up, frame = frame, buy = buy }
end

--------------------------------------------------------------------------------
-- Вкладка «Звёзды» (перерождение)
--------------------------------------------------------------------------------
local starPage = addTab("stars", "✨ Звёзды")
local starList = scroller(starPage, 0)

local starHeader = new("Frame", { Size = UDim2.new(1, 0, 0, 230), BackgroundColor3 = CARD, LayoutOrder = 0, Parent = starList }, {
	corner(12),
	stroke(GOLD, 1.5, 0.3),
})
local dustLabel = label({
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 32),
	Text = "✨ 0 звёздной пыли",
	TextSize = 22,
	Font = Enum.Font.FredokaOne,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = starHeader,
})
local dustInfo = label({
	Position = UDim2.fromOffset(12, 40),
	Size = UDim2.new(1, -24, 0, 54),
	Text = "",
	TextSize = 13,
	TextWrapped = true,
	Font = Enum.Font.Gotham,
	TextColor3 = MUTED,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = starHeader,
})
local _, dustFill = progressBar(starHeader, UDim2.fromOffset(12, 100), UDim2.new(1, -24, 0, 12), GOLD)
local dustNext = label({
	Position = UDim2.fromOffset(12, 114),
	Size = UDim2.new(1, -24, 0, 18),
	Text = "",
	TextSize = 12,
	Font = Enum.Font.Gotham,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = starHeader,
})
local rebirthButton = button({
	Position = UDim2.fromOffset(12, 138),
	Size = UDim2.new(1, -24, 0, 50),
	BackgroundColor3 = BAD,
	Text = "🔁 ПЕРЕРОДИТЬСЯ",
	TextSize = 19,
	Font = Enum.Font.FredokaOne,
	Parent = starHeader,
}, { corner(12) })
local autoToggle = button({
	Position = UDim2.fromOffset(12, 194),
	Size = UDim2.new(1, -24, 0, 28),
	BackgroundColor3 = PANEL,
	Text = "",
	TextSize = 13,
	Visible = false,
	Parent = starHeader,
}, { corner(8) })
autoToggle.Activated:Connect(function()
	ToggleAutoR:FireServer()
end)

local confirmUntil = 0
rebirthButton.Activated:Connect(function()
	if Config.dustOnRebirth(state) < 1 then
		return
	end
	if os.clock() < confirmUntil then
		confirmUntil = 0
		RebirthR:FireServer()
	else
		confirmUntil = os.clock() + 3
		rebirthButton.Text = "Точно? Нажми ещё раз"
		pop(rebirthButton, 0.9)
	end
end)

type PCard = { p: Config.PrestigeUp, frame: Frame, lvl: TextLabel, buy: TextButton }
local pCards: { PCard } = {}
for i, p in ipairs(Config.PrestigeUps) do
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = CARD, LayoutOrder = i, Parent = starList }, { corner(12) })
	label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -140, 0, 22),
		Text = "✨ " .. p.name,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	label({
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -140, 0, 26),
		Text = p.desc,
		TextSize = 12,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	local lvl = label({
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -140, 0, 14),
		Text = "",
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local buy = button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(112, 46),
		BackgroundColor3 = BAD,
		Text = "",
		TextSize = 15,
		Parent = frame,
	}, { corner(10) })
	buy.Activated:Connect(function()
		BuyPUpR:FireServer(p.id)
		pop(buy, 0.9)
	end)
	table.insert(pCards, { p = p, frame = frame, lvl = lvl, buy = buy })
end

--------------------------------------------------------------------------------
-- Вкладка «Награды» (достижения и статистика)
--------------------------------------------------------------------------------
local achPage = addTab("ach", "🏆 Награды")
local achList = scroller(achPage, 0)
local statsCard = new("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = CARD, LayoutOrder = 0, Parent = achList }, { corner(12) })
local statsText = label({
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 1, -16),
	Text = "",
	TextSize = 14,
	Font = Enum.Font.Gotham,
	TextWrapped = true,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = statsCard,
})

local achGrid = new("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	Parent = achList,
}, {
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 54), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
type ACard = { a: Config.Achievement, frame: Frame, title: TextLabel }
local aCards: { ACard } = {}
for i, a in ipairs(Config.Achievements) do
	local frame = new("Frame", { BackgroundColor3 = CARD_DIM, LayoutOrder = i, Parent = achGrid }, { corner(10) })
	local title = label({
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 20),
		Text = "🔒 " .. a.name,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = MUTED,
		Parent = frame,
	})
	label({
		Position = UDim2.fromOffset(8, 24),
		Size = UDim2.new(1, -16, 0, 26),
		Text = a.desc,
		TextSize = 11,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	table.insert(aCards, { a = a, frame = frame, title = title })
end

selectTab("gens")

shopButton.Activated:Connect(function()
	shop.Visible = not shop.Visible
	if shop.Visible then
		pop(shop, 0.95)
	end
end)
homeButton.Activated:Connect(function()
	GoHomeR:FireServer()
end)

--------------------------------------------------------------------------------
-- Всплывающие сообщения
--------------------------------------------------------------------------------
local toastHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 200),
	Size = UDim2.fromOffset(520, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

local function toast(text: string, color: Color3?)
	local t = label({
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = BG,
		Text = "  " .. text .. "  ",
		TextSize = 19,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color or GOLD,
		Parent = toastHolder,
	})
	corner(12).Parent = t
	stroke(color or GOLD, 1.5, 0.3).Parent = t
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
	if #toastHolder:GetChildren() > 5 then
		for _, c in ipairs(toastHolder:GetChildren()) do
			if c:IsA("TextLabel") then
				c:Destroy()
				break
			end
		end
	end
end

-- Модальное окно (оффлайн-доход, приветствие, перерождение)
local function modal(title: string, body: string, buttonText: string)
	local shade = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex = 50,
		Parent = gui,
	})
	local box = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 290),
		BackgroundColor3 = BG,
		ZIndex = 51,
		Parent = shade,
	}, { corner(20), stroke(GOLD, 3) })
	label({
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 40),
		Text = title,
		TextSize = 28,
		Font = Enum.Font.FredokaOne,
		TextColor3 = GOLD,
		ZIndex = 52,
		Parent = box,
	})
	label({
		Position = UDim2.fromOffset(24, 64),
		Size = UDim2.new(1, -48, 0, 140),
		Text = body,
		TextSize = 17,
		TextWrapped = true,
		Font = Enum.Font.Gotham,
		ZIndex = 52,
		Parent = box,
	})
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

--------------------------------------------------------------------------------
-- Мой кристалл и анимации
--------------------------------------------------------------------------------
local plotsFolder = workspace:WaitForChild("Empire"):WaitForChild("Plots")
local myCrystal: BasePart? = nil
local pulse = 0

local function findMyCrystal()
	local idx = player:GetAttribute("Plot")
	if typeof(idx) ~= "number" then
		return
	end
	local plot = plotsFolder:FindFirstChild("Plot" .. idx)
	if plot then
		myCrystal = plot:FindFirstChild("Crystal") :: BasePart?
	end
end
player:GetAttributeChangedSignal("Plot"):Connect(findMyCrystal)
findMyCrystal()

type Spinner = { part: BasePart, core: BasePart?, base: Vector3, phase: number }
local spinners: { Spinner } = {}
local function collectSpinners()
	table.clear(spinners)
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		local c = plot:FindFirstChild("Crystal")
		if c and c:IsA("BasePart") then
			local base = c:GetAttribute("BasePos")
			if typeof(base) == "Vector3" then
				table.insert(spinners, {
					part = c,
					core = c:FindFirstChild("Core") :: BasePart?,
					base = base,
					phase = #spinners * 0.7,
				})
			end
		end
	end
end
collectSpinners()
plotsFolder.ChildAdded:Connect(collectSpinners)

local tilt = CFrame.Angles(math.rad(45), 0, math.rad(35.264))
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	pulse = math.max(0, pulse - dt * 5)
	local speed = frenzyLeft > 0 and 2.2 or 0.6
	for _, s in ipairs(spinners) do
		local bob = math.sin(t * 1.5 + s.phase) * 0.7
		local cf = CFrame.new(s.base + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * speed + s.phase, 0) * tilt
		s.part.CFrame = cf
		if s.core then
			s.core.CFrame = cf
		end
		if s.part == myCrystal then
			local sz = 9 * (1 + pulse * 0.1)
			s.part.Size = Vector3.new(sz, sz, sz)
		end
	end
end)

local function popNumber(amount: number, color: Color3, big: boolean)
	local adornee = myCrystal
	if not adornee then
		return
	end
	local bb = new("BillboardGui", {
		Size = UDim2.fromOffset(big and 260 or 170, big and 64 or 44),
		StudsOffsetWorldSpace = Vector3.new(math.random(-50, 50) / 10, math.random(10, 50) / 10, math.random(-30, 30) / 10),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = adornee,
		Parent = playerGui,
	})
	local txt = label({
		Size = UDim2.fromScale(1, 1),
		Text = "+" .. Config.format(amount),
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
		Parent = bb,
	})
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(txt, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1, function()
		bb:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Клики
--------------------------------------------------------------------------------
mineButton.Activated:Connect(function()
	ClickR:FireServer()
	pop(mineButton, 0.9)
end)

--------------------------------------------------------------------------------
-- Сверкающий кристалл (ловить мышкой/пальцем)
--------------------------------------------------------------------------------
local function spawnGolden(token: string, lifetime: number)
	local size = 96
	local g = button({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(math.random(18, 62) / 100, math.random(28, 72) / 100),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.1,
		Text = "💎",
		TextSize = 54,
		ZIndex = 40,
		Parent = gui,
	}, { corner(size // 2), stroke(WHITE, 4) })
	local glow = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(140, 22),
		Text = "Лови!",
		TextSize = 18,
		Font = Enum.Font.FredokaOne,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.2,
		ZIndex = 40,
		Parent = g,
	})
	local _ = glow
	pop(g, 0.2)
	playSound(SND_CLICK, 0.5, 1.6)
	local alive = true
	task.spawn(function()
		local start = os.clock()
		while alive and g.Parent do
			local t = os.clock() - start
			g.Rotation = math.sin(t * 3) * 15
			local sc = g:FindFirstChildOfClass("UIScale")
			if sc and t > 0.3 then
				sc.Scale = 1 + math.sin(t * 6) * 0.08
			end
			if t > lifetime then
				break
			end
			if t > lifetime - 3 then
				g.BackgroundTransparency = 0.1 + (t - (lifetime - 3)) / 3 * 0.8
			end
			RunService.RenderStepped:Wait()
		end
		if alive then
			alive = false
			g:Destroy()
		end
	end)
	g.Activated:Connect(function()
		if not alive then
			return
		end
		alive = false
		ClaimGoldenR:FireServer(token)
		g:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Обновление интерфейса
--------------------------------------------------------------------------------
local upsKey = ""

local function rebuildUpgrades()
	local available = {}
	for _, up in ipairs(Config.Upgrades) do
		if Config.isUpgradeUnlocked(state, up) then
			table.insert(available, up)
		end
	end
	table.sort(available, function(a, b)
		return a.cost < b.cost
	end)
	local keyParts = {}
	for _, up in ipairs(available) do
		table.insert(keyParts, up.id)
	end
	local key = table.concat(keyParts, ",")
	if key == upsKey then
		return
	end
	upsKey = key
	local keep: { [string]: boolean } = {}
	for i, up in ipairs(available) do
		keep[up.id] = true
		local card = upCards[up.id]
		if not card then
			card = makeUpCard(up)
			upCards[up.id] = card
		end
		card.frame.LayoutOrder = i
	end
	for id, card in pairs(upCards) do
		if not keep[id] then
			card.frame:Destroy()
			upCards[id] = nil
		end
	end
	upsEmpty.Visible = #available == 0
end

local function updateUI()
	if not hasState then
		return
	end
	local bank = crystalsNow()
	local m = mult()
	balanceLabel.Text = "💎 " .. Config.format(bank)
	rateLabel.Text = string.format("⚙ %s/сек", Config.format(perSec * m))
	rateLabel.TextColor3 = m > 1 and GOLD or WHITE

	local parts = {}
	local g = Config.globalMult(state)
	if g > 1.001 then
		table.insert(parts, "✨ Бонусы ×" .. Config.format(g))
	end
	local achCount = Config.countKeys(state.ach)
	if achCount > 0 then
		table.insert(parts, string.format("🏆 %d/%d", achCount, #Config.Achievements))
	end
	if state.dust > 0 then
		table.insert(parts, "✨ " .. Config.format(state.dust) .. " пыли")
	end
	bonusLabel.Text = table.concat(parts, "    ")

	local clickNow = clickValue * m * (stormLeft > 0 and Config.ClickStormMult or 1)
	mineSub.Text = "+" .. Config.format(clickNow) .. " за клик"
	mineSub.TextColor3 = stormLeft > 0 and PINK or WHITE

	-- Бонусы
	frenzyBar.Visible = frenzyLeft > 0
	if frenzyLeft > 0 then
		frenzyFill.Size = UDim2.fromScale(math.clamp(frenzyLeft / frenzyMax, 0, 1), 1)
		frenzyText.Text = string.format("🔥 Лихорадка: добыча ×%d — %d с", Config.FrenzyMult, math.ceil(frenzyLeft))
	end
	stormBar.Visible = stormLeft > 0
	if stormLeft > 0 then
		stormFill.Size = UDim2.fromScale(math.clamp(stormLeft / stormMax, 0, 1), 1)
		stormText.Text = string.format("⚡ Клик-шторм: клик ×%d — %d с", Config.ClickStormMult, math.ceil(stormLeft))
	end

	-- Генераторы: показываем купленные и два следующих
	local shownLocked = 0
	local anyAffordable = false
	for _, card in ipairs(genCards) do
		local gen = card.gen
		local lvl = state.gens[gen.id] or 0
		local visible = lvl > 0 or shownLocked < 2
		if lvl == 0 then
			shownLocked += 1
		end
		card.frame.Visible = visible
		if visible then
			local prod = Config.genProduction(state, gen, g) * m
			if lvl > 0 then
				card.title.Text = string.format("%s  ·  ур. %d", gen.name, lvl)
				local share = perSec > 0 and prod / (perSec * m) * 100 or 0
				card.info.Text = string.format("+%s/с  (%d%% дохода)", Config.format(prod), math.floor(share + 0.5))
			else
				card.title.Text = gen.name
				local one = gen.baseProd * Config.genUpgradeMult(state, gen.id) * g
				card.info.Text = string.format("Даёт +%s/с за уровень", Config.format(one))
			end
			local nextM, prevM = Config.nextMilestone(lvl)
			if nextM then
				card.fill.Size = UDim2.fromScale(math.clamp((lvl - prevM) / (nextM - prevM), 0, 1), 1)
				card.milestone.Text = string.format("На ур. %d — добыча ×2 (ещё %d)", nextM, nextM - lvl)
			else
				card.fill.Size = UDim2.fromScale(1, 1)
				card.milestone.Text = "Все рубежи пройдены!"
			end

			local n: number
			if buyMode == "max" then
				n = math.max(1, Config.maxAffordable(state, gen, bank))
			else
				n = buyMode :: number
			end
			local cost = Config.genCost(state, gen, n)
			local can = bank >= cost
			if buyMode == "max" or buyMode ~= 1 then
				-- можно купить меньше, чем выбрано: покупка «сколько хватает»
				local k = Config.maxAffordable(state, gen, bank, if buyMode == "max" then nil else buyMode :: number)
				if k > 0 then
					n = k
					cost = Config.genCost(state, gen, k)
					can = true
				end
			end
			card.buyTop.Text = n > 1 and ("Купить ×" .. n) or "Купить"
			card.buyCost.Text = "💎 " .. Config.format(cost)
			card.buy.BackgroundColor3 = can and GOOD or BAD
			anyAffordable = anyAffordable or can
		end
	end
	tabs.gens.badge.Visible = anyAffordable and currentTab ~= "gens"

	-- Улучшения
	rebuildUpgrades()
	local anyUp = false
	for _, card in pairs(upCards) do
		local can = bank >= card.up.cost
		card.buy.BackgroundColor3 = can and GOOD or BAD
		anyUp = anyUp or can
	end
	tabs.ups.badge.Visible = anyUp and currentTab ~= "ups"
	buyAll.Visible = anyUp
	buyAll.BackgroundColor3 = GOOD

	-- Звёзды
	local gain = Config.dustOnRebirth(state)
	dustLabel.Text = string.format("✨ %s звёздной пыли", Config.format(state.dust))
	dustInfo.Text = string.format(
		"Получено всего: %s → +%d%% к добыче навсегда. Перерождение сбросит кристаллы, генераторы и улучшения; пыль, звёздные улучшения и награды останутся.",
		Config.format(state.dustEver),
		math.floor(state.dustEver * Config.DustPerBonus * 100 + 0.5)
	)
	local nextNeed = Config.runTotalForDust(state, gain + 1)
	local prevNeed = gain > 0 and Config.runTotalForDust(state, gain) or 0
	dustFill.Size = UDim2.fromScale(math.clamp((state.runTotal - prevNeed) / math.max(1, nextNeed - prevNeed), 0, 1), 1)
	dustNext.Text = string.format("До следующей пыли: добыть ещё 💎 %s", Config.format(math.max(0, nextNeed - state.runTotal)))
	if os.clock() >= confirmUntil then
		rebirthButton.Text = gain >= 1 and string.format("🔁 ПЕРЕРОДИТЬСЯ: +%s ✨", Config.format(gain)) or "🔁 Нужно ещё добыть"
	end
	rebirthButton.BackgroundColor3 = gain >= 1 and Color3.fromRGB(170, 120, 20) or BAD
	local hasAuto = Config.pupLevel(state, "auto") >= 1
	autoToggle.Visible = hasAuto
	autoToggle.Text = state.autobuy and "🤖 Прораб: ВКЛ (нажми, чтобы выключить)" or "🤖 Прораб: ВЫКЛ (нажми, чтобы включить)"
	autoToggle.BackgroundColor3 = state.autobuy and Color3.fromRGB(40, 110, 70) or PANEL
	local anyP = false
	for _, card in ipairs(pCards) do
		local lvl = Config.pupLevel(state, card.p.id)
		if lvl >= card.p.maxLevel then
			card.lvl.Text = string.format("Уровень %d/%d", lvl, card.p.maxLevel)
			card.buy.Text = "МАКС"
			card.buy.BackgroundColor3 = GOLD
			card.buy.TextColor3 = Color3.fromRGB(40, 30, 10)
		else
			local cost = Config.pupCost(card.p, lvl)
			card.lvl.Text = string.format("Уровень %d/%d", lvl, card.p.maxLevel)
			card.buy.Text = "✨ " .. Config.format(cost)
			local can = state.dust >= cost
			card.buy.BackgroundColor3 = can and GOOD or BAD
			card.buy.TextColor3 = WHITE
			anyP = anyP or can
		end
	end
	tabs.stars.badge.Visible = (anyP or gain >= math.max(5, state.dustEver)) and currentTab ~= "stars"

	-- Награды
	statsText.Text = string.format(
		"<b>Статистика</b>\nДобыто за всё время: 💎 %s\nЗа этот забег: 💎 %s\nВ игре: %s\nКликов: %s · Сверкающих: %d · Перерождений: %d\nДостижения: %d из %d → +%d%% к добыче",
		Config.format(state.allTotal),
		Config.format(state.runTotal),
		Config.formatTime(state.playTime),
		Config.format(state.clicks),
		state.goldens,
		state.rebirths,
		achCount,
		#Config.Achievements,
		math.floor(achCount * Config.AchievementBonus * 100 + 0.5)
	)
	for _, card in ipairs(aCards) do
		local done = state.ach[card.a.id] == true
		card.frame.BackgroundColor3 = done and Color3.fromRGB(70, 60, 25) or CARD_DIM
		card.title.Text = (done and "🏆 " or "🔒 ") .. card.a.name
		card.title.TextColor3 = done and GOLD or MUTED
	end
end

task.spawn(function()
	while true do
		updateUI()
		task.wait(0.1)
	end
end)

-- Счётчики бонусов тикают и между снимками
RunService.Heartbeat:Connect(function(dt)
	frenzyLeft = math.max(0, frenzyLeft - dt)
	stormLeft = math.max(0, stormLeft - dt)
	if hasState then
		balanceLabel.Text = "💎 " .. Config.format(crystalsNow())
	end
end)

--------------------------------------------------------------------------------
-- Сеть
--------------------------------------------------------------------------------
StateR.OnClientEvent:Connect(function(s: any)
	state.crystals = s.crystals
	state.runTotal = s.runTotal
	state.allTotal = s.allTotal
	state.dust = s.dust
	state.dustEver = s.dustEver
	state.rebirths = s.rebirths
	state.gens = s.gens or {}
	state.ups = s.ups or {}
	state.pups = s.pups or {}
	state.ach = s.ach or {}
	state.clicks = s.clicks
	state.goldens = s.goldens
	state.playTime = s.playTime
	state.autobuy = s.autobuy
	perSec = s.perSec
	clickValue = s.clickValue
	frenzyLeft = s.frenzyLeft
	stormLeft = s.stormLeft
	stateTime = os.clock()
	hasState = true
	if not myCrystal then
		findMyCrystal()
	end
end)

EventR.OnClientEvent:Connect(function(kind: string, a: any, b: any)
	if kind == "click" then
		pulse = 1
		popNumber(a, stormLeft > 0 and PINK or WHITE, stormLeft > 0)
		playSound(SND_CLICK, 0.2, 1 + math.random() * 0.3)
	elseif kind == "bought" then
		local up = Config.UpById[a]
		playSound(SND_BUY, 0.5)
		if up then
			toast("⬆ " .. up.name, ACCENT)
		end
	elseif kind == "milestone" then
		local gen = Config.GenById[a]
		playSound(SND_BUY, 0.6, 1.3)
		if gen then
			toast(string.format("%s %s: уровень %d — добыча ×2!", gen.icon, gen.name, b), GOLD)
		end
	elseif kind == "achievement" then
		local ach = Config.AchById[a]
		playSound(SND_WIN, 0.35, 1.2)
		if ach then
			toast("🏆 Достижение: " .. ach.name, GOLD)
		end
	elseif kind == "goldenSpawn" then
		spawnGolden(a, b)
	elseif kind == "golden" then
		playSound(SND_WIN, 0.5)
		if a == "lucky" then
			toast("💎 Удача! +" .. Config.format(b), GOLD)
			popNumber(b, GOLD, true)
		elseif a == "frenzy" then
			frenzyMax = b
			frenzyLeft = b
			toast(string.format("🔥 Лихорадка! Вся добыча ×%d на %d с", Config.FrenzyMult, b), GOLD)
		elseif a == "storm" then
			stormMax = b
			stormLeft = b
			toast(string.format("⚡ Клик-шторм! Клики ×%d на %d с — жми!", Config.ClickStormMult, b), PINK)
		end
	elseif kind == "rebirth" then
		playSound(SND_WIN, 0.6)
		modal(
			"🔁 Перерождение!",
			string.format(
				"Ты получил ✨ %s звёздной пыли.\nТеперь вся добыча навсегда больше. Загляни во вкладку «Звёзды» — там улучшения за пыль.",
				Config.format(a)
			),
			"Вперёд!"
		)
		selectTab("stars")
	elseif kind == "offline" then
		modal(
			"С возвращением!",
			string.format("Пока тебя не было (%s), твоя империя добыла:\n\n💎 %s", Config.formatTime(b), Config.format(a)),
			"Забрать"
		)
	elseif kind == "welcome" then
		modal(
			"💎 Кристальная империя",
			"Строй генераторы — они добывают кристаллы сами, даже когда ты не в игре.\n\nПокупай улучшения, лови сверкающие кристаллы и перерождайся ради звёздной пыли!",
			"Играть"
		)
	elseif kind == "message" then
		toast(tostring(a), ACCENT)
	end
end)
