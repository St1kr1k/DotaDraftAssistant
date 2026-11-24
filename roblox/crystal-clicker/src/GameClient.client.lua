-- Клиент: интерфейс, анимации, всплывающие числа.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClickRemote = Remotes:WaitForChild("Click") :: RemoteEvent
local BuyRemote = Remotes:WaitForChild("Buy") :: RemoteEvent
local RebirthRemote = Remotes:WaitForChild("Rebirth") :: RemoteEvent
local FeedbackRemote = Remotes:WaitForChild("Feedback") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local world = workspace:WaitForChild("CrystalWorld")
local crystal = world:WaitForChild("BigCrystal") :: BasePart
local core = crystal:WaitForChild("Core") :: BasePart

-- Цвета ------------------------------------------------------------------
local BG = Color3.fromRGB(24, 22, 38)
local CARD = Color3.fromRGB(38, 35, 60)
local ACCENT = Color3.fromRGB(70, 210, 255)
local GOOD = Color3.fromRGB(60, 200, 110)
local BAD = Color3.fromRGB(90, 85, 110)
local GOLD = Color3.fromRGB(255, 205, 60)

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

local function corner(r: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 12) })
end

local function stroke(color: Color3, thickness: number?)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props: { [string]: any })
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	return new("TextLabel", props)
end

-- Звуки (встроенные в клиент Roblox)
local function playSound(id: string, volume: number, pitch: number?)
	local s = new("Sound", { SoundId = id, Volume = volume, PlaybackSpeed = pitch or 1, Parent = SoundService })
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end
local SND_CLICK = "rbxasset://sounds/electronicpingshort.wav"
local SND_BUY = "rbxasset://sounds/button.wav"

-- Интерфейс --------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "CrystalUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Маленькие экраны: уменьшаем всё
local uiScale = new("UIScale", { Parent = gui })
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local h = cam.ViewportSize.Y
	uiScale.Scale = math.clamp(h / 900, 0.6, 1.2)
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- Верхняя панель: баланс
local top = new("Frame", {
	Name = "Top",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(420, 110),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(16), stroke(ACCENT, 2) })

local balanceLabel = label({
	Size = UDim2.new(1, -20, 0, 56),
	Position = UDim2.fromOffset(10, 6),
	Text = "💎 0",
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = ACCENT,
	Parent = top,
})
local rateLabel = label({
	Size = UDim2.new(1, -20, 0, 22),
	Position = UDim2.fromOffset(10, 60),
	Text = "",
	TextSize = 18,
	TextColor3 = Color3.fromRGB(210, 210, 230),
	Parent = top,
})
local multLabel = label({
	Size = UDim2.new(1, -20, 0, 20),
	Position = UDim2.fromOffset(10, 84),
	Text = "",
	TextSize = 15,
	TextColor3 = GOLD,
	Parent = top,
})

-- Кнопка «Добыть»
local mineButton = new("TextButton", {
	Name = "Mine",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(240, 78),
	BackgroundColor3 = ACCENT,
	Text = "⛏ ДОБЫТЬ",
	Font = Enum.Font.FredokaOne,
	TextSize = 36,
	TextColor3 = Color3.fromRGB(20, 30, 50),
	AutoButtonColor = true,
	Parent = gui,
}, { corner(20), stroke(Color3.new(1, 1, 1), 3) })

-- Магазин справа
local shop = new("Frame", {
	Name = "Shop",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(330, 560),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.1,
	Parent = gui,
}, { corner(16), stroke(ACCENT, 2) })

label({
	Size = UDim2.new(1, 0, 0, 40),
	Text = "🛒 Улучшения",
	TextSize = 24,
	Font = Enum.Font.FredokaOne,
	Parent = shop,
})

local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 44),
	Size = UDim2.new(1, -16, 1, -150),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = ACCENT,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = shop,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingRight = UDim.new(0, 8) }),
})

-- Перерождение (низ магазина)
local rebirthButton = new("TextButton", {
	Name = "Rebirth",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -16, 0, 92),
	BackgroundColor3 = BAD,
	Text = "",
	AutoButtonColor = true,
	Parent = shop,
}, { corner(12), stroke(GOLD, 2) })
local rebirthTitle = label({
	Size = UDim2.new(1, -12, 0, 30),
	Position = UDim2.fromOffset(6, 4),
	Text = "🔁 ПЕРЕРОЖДЕНИЕ",
	TextSize = 22,
	Font = Enum.Font.FredokaOne,
	TextColor3 = GOLD,
	Parent = rebirthButton,
})
local rebirthInfo = label({
	Size = UDim2.new(1, -12, 0, 52),
	Position = UDim2.fromOffset(6, 34),
	Text = "",
	TextSize = 14,
	TextWrapped = true,
	Font = Enum.Font.Gotham,
	Parent = rebirthButton,
})
local _ = rebirthTitle

-- Кнопка скрыть/показать магазин (для телефонов)
local toggle = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(130, 40),
	BackgroundColor3 = CARD,
	Text = "Скрыть магазин",
	TextSize = 15,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = gui,
}, { corner(10), stroke(ACCENT, 1) })
toggle.Activated:Connect(function()
	shop.Visible = not shop.Visible
	toggle.Text = shop.Visible and "Скрыть магазин" or "🛒 Магазин"
end)

-- Сообщения по центру
local toast = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 130),
	Size = UDim2.fromOffset(600, 44),
	BackgroundColor3 = BG,
	BackgroundTransparency = 1,
	TextTransparency = 1,
	TextSize = 22,
	Font = Enum.Font.FredokaOne,
	TextColor3 = GOLD,
	Parent = gui,
})
corner(12).Parent = toast

local toastToken = 0
local function showToast(text: string)
	toastToken += 1
	local my = toastToken
	toast.Text = text
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.2
	task.delay(3.5, function()
		if my ~= toastToken then
			return
		end
		TweenService:Create(toast, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	end)
end

-- Карточки улучшений
type Card = { frame: Frame, level: TextLabel, button: TextButton, up: any }
local cards: { Card } = {}

for i, up in ipairs(Config.Upgrades) do
	local frame = new("Frame", {
		Name = up.id,
		LayoutOrder = i,
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = CARD,
		Parent = list,
	}, { corner(10) })
	new("Frame", {
		Size = UDim2.fromOffset(6, 54),
		Position = UDim2.fromOffset(8, 10),
		BackgroundColor3 = up.color,
		BorderSizePixel = 0,
		Parent = frame,
	}, { corner(3) })
	label({
		Position = UDim2.fromOffset(22, 6),
		Size = UDim2.new(1, -130, 0, 24),
		Text = up.name,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	label({
		Position = UDim2.fromOffset(22, 30),
		Size = UDim2.new(1, -130, 0, 18),
		Text = up.desc,
		TextSize = 14,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(190, 190, 215),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local level = label({
		Position = UDim2.fromOffset(22, 50),
		Size = UDim2.new(1, -130, 0, 18),
		Text = "Ур. 0",
		TextSize = 13,
		Font = Enum.Font.Gotham,
		TextColor3 = ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local button = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(100, 50),
		BackgroundColor3 = BAD,
		Text = "💎 10",
		TextSize = 17,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	}, { corner(10) })
	button.Activated:Connect(function()
		BuyRemote:FireServer(up.id)
	end)
	table.insert(cards, { frame = frame, level = level, button = button, up = up })
end

-- Обновление чисел ------------------------------------------------------
local function attr(name: string): number
	return tonumber(player:GetAttribute(name)) or 0
end

local function refresh()
	local crystals = attr("Crystals")
	local rebirths = attr("Rebirths")
	balanceLabel.Text = "💎 " .. Config.format(crystals)
	rateLabel.Text = string.format("⛏ %s за клик   ⚙ %s/сек", Config.format(attr("PerClick")), Config.format(attr("PerSecond")))
	local crit = attr("Crit")
	local mult = Config.getMultiplier(rebirths)
	local parts = {}
	if mult > 1 then
		table.insert(parts, "✨ Множитель ×" .. tostring(mult))
	end
	if crit > 0 then
		table.insert(parts, string.format("🍀 Крит %d%%", math.floor(crit * 100 + 0.5)))
	end
	multLabel.Text = table.concat(parts, "    ")

	for _, card in ipairs(cards) do
		local lvl = attr("Lvl_" .. card.up.id)
		card.level.Text = "Ур. " .. lvl
		if card.up.maxLevel and lvl >= card.up.maxLevel then
			card.button.Text = "МАКС"
			card.button.BackgroundColor3 = GOLD
			card.button.TextColor3 = Color3.fromRGB(40, 30, 10)
		else
			local cost = Config.getCost(card.up, lvl)
			card.button.Text = "💎 " .. Config.format(cost)
			card.button.BackgroundColor3 = crystals >= cost and GOOD or BAD
			card.button.TextColor3 = Color3.new(1, 1, 1)
		end
	end

	local rcost = Config.getRebirthCost(rebirths)
	local canRebirth = crystals >= rcost
	rebirthButton.BackgroundColor3 = canRebirth and Color3.fromRGB(150, 110, 20) or BAD
	rebirthInfo.Text = string.format(
		"Нужно 💎 %s. Сбросит кристаллы и улучшения, но навсегда даст ×%s ко всей добыче.",
		Config.format(rcost),
		tostring(Config.getMultiplier(rebirths + 1))
	)
end

player.AttributeChanged:Connect(refresh)
refresh()

-- Клики ------------------------------------------------------------------
local function mine()
	ClickRemote:FireServer()
end
mineButton.Activated:Connect(function()
	mine()
	mineButton.Size = UDim2.fromOffset(225, 72)
	TweenService:Create(mineButton, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(240, 78) }):Play()
end)

rebirthButton.Activated:Connect(function()
	if attr("Crystals") < Config.getRebirthCost(attr("Rebirths")) then
		showToast("Пока не хватает кристаллов для перерождения")
		return
	end
	RebirthRemote:FireServer()
end)

-- Анимация кристалла (только у себя на экране) ---------------------------
local basePos = crystal.Position
local tilt = CFrame.Angles(math.rad(45), 0, math.rad(35.264))
local pulse = 0
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	pulse = math.max(0, pulse - dt * 4)
	local bob = math.sin(t * 1.5) * 0.6
	local cf = CFrame.new(basePos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * 0.6, 0) * tilt
	crystal.CFrame = cf
	core.CFrame = cf
	local s = 8 * (1 + pulse * 0.12)
	crystal.Size = Vector3.new(s, s, s)
end)

-- Всплывающие числа над кристаллом
local function popNumber(amount: number, isCrit: boolean)
	local bb = new("BillboardGui", {
		Size = UDim2.fromOffset(isCrit and 260 or 160, isCrit and 70 or 44),
		StudsOffsetWorldSpace = Vector3.new(math.random(-40, 40) / 10, math.random(20, 50) / 10, math.random(-20, 20) / 10),
		AlwaysOnTop = true,
		Adornee = crystal,
		Parent = playerGui,
	})
	local txt = label({
		Size = UDim2.fromScale(1, 1),
		Text = (isCrit and "КРИТ! +" or "+") .. Config.format(amount),
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = isCrit and GOLD or Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		Parent = bb,
	})
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(txt, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1, function()
		bb:Destroy()
	end)
end

FeedbackRemote.OnClientEvent:Connect(function(kind: string, a: any, b: any)
	if kind == "click" then
		pulse = 1
		popNumber(a, b)
		playSound(SND_CLICK, b and 0.6 or 0.25, b and 0.8 or (1 + math.random() * 0.3))
	elseif kind == "bought" then
		playSound(SND_BUY, 0.5)
		local up = Config.ById[a]
		if up then
			showToast("Куплено: " .. up.name)
		end
	elseif kind == "message" then
		playSound(SND_BUY, 0.5, 0.8)
		showToast(tostring(a))
	end
end)

showToast("Добро пожаловать в Кристальный кликер!")
