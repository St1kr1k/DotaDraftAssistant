-- Весь интерфейс игры, создаётся кодом.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local Format = require(Shared.Format)
local FishBuilder = require(Shared.FishBuilder)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer

local UI = {}
UI.Callbacks = {} :: { [string]: (...any) -> () }
UI.AutoCast = false

local gui: ScreenGui
local scaled = {} :: { UIScale }
local spinning = {} :: { { vp: ViewportFrame, model: Model, cf: CFrame } }
local rainbowGradients = {} :: { UIGradient }

-- ===== Палитра =====
local C = {
	Panel = Color3.fromRGB(55, 150, 255),
	Panel2 = Color3.fromRGB(28, 88, 200),
	Stroke = Color3.fromRGB(12, 12, 18),
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(80, 220, 100),
	Green2 = Color3.fromRGB(35, 160, 70),
	Blue = Color3.fromRGB(70, 180, 255),
	Blue2 = Color3.fromRGB(30, 110, 220),
	Orange = Color3.fromRGB(255, 170, 60),
	Orange2 = Color3.fromRGB(235, 110, 30),
	Red = Color3.fromRGB(255, 90, 90),
	Red2 = Color3.fromRGB(200, 45, 60),
	Gold = Color3.fromRGB(255, 220, 70),
	Gold2 = Color3.fromRGB(235, 160, 20),
	Purple = Color3.fromRGB(190, 110, 255),
	Purple2 = Color3.fromRGB(120, 60, 220),
	Gray = Color3.fromRGB(150, 155, 170),
	Gray2 = Color3.fromRGB(95, 100, 115),
}

-- ===== Конструктор =====
local function new(class: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 12) })
end

local function stroke(th: number?, color: Color3?)
	return new("UIStroke", { Thickness = th or 3, Color = color or C.Stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function grad(c1: Color3, c2: Color3, rot: number?)
	return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rot or 90 })
end

local function text(props: { [string]: any }): TextLabel
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = C.White,
		TextScaled = true,
		Text = "",
	})
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "StrokeThickness" and k ~= "MaxText" then
			(t :: any)[k] = v
		end
	end
	new("UIStroke", { Thickness = props.StrokeThickness or 2.5, Color = C.Stroke, LineJoinMode = Enum.LineJoinMode.Round, Parent = t })
	new("UITextSizeConstraint", { MaxTextSize = props.MaxText or 60, Parent = t })
	t.Parent = props.Parent
	return t
end

local function scaleable(obj: GuiObject)
	local s = new("UIScale", { Parent = obj })
	table.insert(scaled, s)
	return s
end

local function panel(props: { [string]: any }): Frame
	local f = new("Frame", { BackgroundColor3 = C.Panel, BorderSizePixel = 0 })
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Corner" then
			(f :: any)[k] = v
		end
	end
	corner(props.Corner or 16).Parent = f
	stroke(3.5).Parent = f
	grad(C.White, Color3.fromRGB(185, 200, 235)).Parent = f
	f.Parent = props.Parent
	return f
end

local function button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local c1, c2 = props.C1 or C.Green, props.C2 or C.Green2
	local b = new("TextButton", {
		BackgroundColor3 = C.White,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
	})
	corner(props.Corner or 12).Parent = b
	stroke(3.5).Parent = b
	local g = grad(c1, c2)
	g.Parent = b
	local us = new("UIScale", { Parent = b })
	local label = text({
		Text = props.Text or "",
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromOffset(5, 3),
		MaxText = props.MaxText or 32,
		ZIndex = props.ZIndex,
		Font = Enum.Font.LuckiestGuy,
		StrokeThickness = 3,
		Parent = b,
	})
	label.Name = "Label"
	b.MouseEnter:Connect(function()
		TweenService:Create(us, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(us, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(us, TweenInfo.new(0.06), { Scale = 0.93 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(us, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	if onClick then
		b.Activated:Connect(onClick)
	end
	b:SetAttribute("C1", c1)
	return b
end

local function setButtonColors(b: TextButton, c1: Color3, c2: Color3)
	local g = b:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(c1, c2)
	end
end

local function rarityGradient(label: TextLabel, rarity: number)
	if rarity == GameData.RarityIndex.Secret then
		local g = new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 120)),
				ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 200, 255)),
				ColorSequenceKeypoint.new(0.8, Color3.fromRGB(190, 100, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
			}),
			Parent = label,
		})
		table.insert(rainbowGradients, g)
	elseif rarity == GameData.RarityIndex.Mythic then
		new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 40, 80)), Rotation = 90, Parent = label })
	end
end

-- 3D-превью рыбы
local function fishViewport(parent: Instance, fishId: string, mutation: string, silhouette: boolean, spin: boolean, props: { [string]: any }?): ViewportFrame
	local vp = new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 175, 190),
		LightColor = Color3.fromRGB(255, 255, 250),
		LightDirection = Vector3.new(-0.6, -1, -0.4),
	})
	if props then
		for k, v in pairs(props) do
			(vp :: any)[k] = v
		end
	end
	if silhouette then
		vp.ImageColor3 = Color3.fromRGB(0, 0, 0)
		vp.ImageTransparency = 0.25
	end
	local model = FishBuilder.Build(fishId, mutation, 2, { static = true })
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	local cf, size = model:GetBoundingBox()
	local center = cf.Position
	model:PivotTo(CFrame.new(-center) * model:GetPivot())
	model.Parent = vp
	local cam = new("Camera", { FieldOfView = 30, Parent = vp })
	local dist = size.Magnitude * 1.65
	cam.CFrame = CFrame.lookAt(Vector3.new(dist * 0.82, dist * 0.22, -dist * 0.5), Vector3.zero)
	vp.CurrentCamera = cam
	vp.Parent = parent
	if spin then
		table.insert(spinning, { vp = vp, model = model, cf = model:GetPivot() })
	end
	return vp
end

-- ===== Тосты (уведомления) =====
local toastList: Frame

function UI.Toast(msg: string, color: Color3?, duration: number?)
	if not toastList then
		return
	end
	local f = panel({ Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.Panel2, Parent = toastList, BackgroundTransparency = 0.05 })
	f.LayoutOrder = -math.floor(os.clock() * 100)
	local t = text({ Text = msg, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextColor3 = color or C.White, MaxText = 22, Parent = f })
	t.TextXAlignment = Enum.TextXAlignment.Left
	local us = new("UIScale", { Scale = 0.6, Parent = f })
	TweenService:Create(us, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(duration or 3.5, function()
		local tw = TweenService:Create(us, TweenInfo.new(0.2), { Scale = 0 })
		tw:Play()
		tw.Completed:Wait()
		f:Destroy()
	end)
	local children = toastList:GetChildren()
	local count = 0
	for _, c in ipairs(children) do
		if c:IsA("Frame") then
			count += 1
		end
	end
	if count > 5 then
		local oldest, oldestOrder = nil, -math.huge
		for _, c in ipairs(children) do
			if c:IsA("Frame") and c.LayoutOrder > oldestOrder then
				oldest, oldestOrder = c, c.LayoutOrder
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
end

-- ===== Покупки за Robux =====
local function buy(kind: string, key: string, id: number)
	if id == 0 then
		if RunService:IsStudio() then
			local ok = Remotes.Get("DevGrant"):InvokeServer(key)
			UI.Toast(ok and ("🧪 Studio test: got " .. key) or "Test grant failed", C.Gold)
		else
			UI.Toast("This item is not set up yet", C.Red)
		end
		return
	end
	if kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end
UI.Buy = buy

local function nextTrainingPass()
	for _, p in ipairs(Config.TrainingPasses) do
		if not ClientState.HasPass(p.Key) then
			return p
		end
	end
	return nil
end
UI.NextTrainingPass = nextTrainingPass

-- ===== Окна =====
local windowHolder: Frame
local currentWindow: Frame? = nil
local currentName: string? = nil
local renderers = {} :: { [string]: (Frame) -> () }

local function closeWindow()
	if currentWindow then
		local w = currentWindow
		currentWindow = nil
		currentName = nil
		local us = w:FindFirstChild("PopScale") :: UIScale
		local tw = TweenService:Create(us, TweenInfo.new(0.15), { Scale = 0.5 })
		tw:Play()
		tw.Completed:Connect(function()
			w:Destroy()
		end)
	end
end
UI.CloseWindow = closeWindow

local function openWindow(name: string, title: string, c1: Color3, c2: Color3)
	if currentName == name then
		closeWindow()
		return
	end
	if currentWindow then
		currentWindow:Destroy()
		currentWindow = nil
	end
	local w = panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 450),
		BackgroundColor3 = C.Panel,
		Parent = windowHolder,
	})
	local pop = new("UIScale", { Name = "PopScale", Scale = 0.5, Parent = w })
	TweenService:Create(pop, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local header = new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.White, BorderSizePixel = 0, Parent = w })
	corner(14).Parent = header
	grad(c1, c2).Parent = header
	text({ Text = title, Size = UDim2.new(1, -120, 0, 44), Position = UDim2.fromOffset(18, 6), MaxText = 38, Font = Enum.Font.LuckiestGuy, StrokeThickness = 3.5, TextXAlignment = Enum.TextXAlignment.Left, Parent = header })
	button({ Text = "X", Size = UDim2.fromOffset(46, 46), Position = UDim2.new(1, -52, 0, 5), C1 = C.Red, C2 = C.Red2 }, closeWindow).Parent = header
	local body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -24, 1, -76), Parent = w })
	currentWindow = w
	currentName = name
	renderers[name](body)
end

local function rerenderWindow()
	if currentWindow and currentName and renderers[currentName] then
		local body = currentWindow:FindFirstChild("Body") :: Frame
		local scroll = body:FindFirstChildWhichIsA("ScrollingFrame", true)
		local pos = scroll and scroll.CanvasPosition
		for _, c in ipairs(body:GetChildren()) do
			c:Destroy()
		end
		renderers[currentName](body)
		local newScroll = body:FindFirstChildWhichIsA("ScrollingFrame", true)
		if newScroll and pos then
			newScroll.CanvasPosition = pos
		end
	end
end

local function scroller(parent: Instance, size: UDim2, pos: UDim2?): ScrollingFrame
	return new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = size,
		Position = pos or UDim2.new(),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.White,
		Parent = parent,
	})
end

-- Магазин наживок + расширение аквариума
renderers.Shop = function(body: Frame)
	local data = ClientState.Data
	if not data then
		return
	end
	local cash = ClientState.Cash()
	-- аквариум
	local tank = panel({ Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = C.Panel2, Parent = body })
	text({ Text = "🐠 Aquarium: " .. #data.Fish .. "/" .. data.Capacity .. " fish", Size = UDim2.new(0.6, 0, 0, 34), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26, Parent = tank })
	text({ Text = "Upgrade: +" .. Config.SlotsPerUpgrade .. " slots", Size = UDim2.new(0.6, 0, 0, 22), Position = UDim2.fromOffset(12, 40), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gray, MaxText = 18, Parent = tank })
	if data.TankLevel >= Config.MaxTankUpgrades then
		button({ Text = "MAX", Size = UDim2.fromOffset(190, 52), Position = UDim2.new(1, -200, 0, 9), C1 = C.Gray, C2 = C.Gray2 }).Parent = tank
	else
		local cost = Config.TankUpgradeCost(data.TankLevel)
		local can = cash >= cost
		button({ Text = Format.Money(cost), Size = UDim2.fromOffset(190, 52), Position = UDim2.new(1, -200, 0, 9), C1 = can and C.Green or C.Gray, C2 = can and C.Green2 or C.Gray2 }, function()
			local res = Remotes.Get("UpgradeTank"):InvokeServer()
			if res and not res.ok then
				UI.Toast(res.msg, C.Red)
			else
				UI.Toast("🐠 Aquarium upgraded!", C.Green)
			end
		end).Parent = tank
	end
	-- спортзал
	local gearPanel = panel({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 78), BackgroundColor3 = C.Panel2, Parent = body })
	local curGear = GameData.Gear[data.Gear or 1]
	local nextGear = GameData.Gear[(data.Gear or 1) + 1]
	text({ Text = "🏋️ " .. curGear.Id .. "  (x" .. curGear.Mult .. " 💪)", Size = UDim2.new(0.6, 0, 0, 34), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = curGear.Color, MaxText = 26, Parent = gearPanel })
	text({ Text = nextGear and ("Next: " .. nextGear.Id .. " — x" .. nextGear.Mult .. " power per pull-up") or "Best gear owned!", Size = UDim2.new(0.6, 0, 0, 22), Position = UDim2.fromOffset(12, 40), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gray, MaxText = 18, Parent = gearPanel })
	if nextGear then
		local can = cash >= nextGear.Price
		button({ Text = Format.Money(nextGear.Price), Size = UDim2.fromOffset(190, 52), Position = UDim2.new(1, -200, 0, 9), C1 = can and C.Green or C.Gray, C2 = can and C.Green2 or C.Gray2 }, function()
			local res = Remotes.Get("BuyGear"):InvokeServer()
			if res and not res.ok then
				UI.Toast(res.msg, C.Red)
			elseif res then
				UI.Toast("🏋️ Got " .. tostring(res.name) .. "!", C.Green)
			end
		end).Parent = gearPanel
	else
		button({ Text = "MAX", Size = UDim2.fromOffset(190, 52), Position = UDim2.new(1, -200, 0, 9), C1 = C.Gray, C2 = C.Gray2 }).Parent = gearPanel
	end
	-- наживки
	local list = scroller(body, UDim2.new(1, 0, 1, -158), UDim2.fromOffset(0, 158))
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	new("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = list })
	for i, bait in ipairs(GameData.Baits) do
		local row = panel({ Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.Panel2, LayoutOrder = i, Parent = list })
		local dot = new("Frame", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(12, 12), BackgroundColor3 = bait.Color, Parent = row })
		corner(20).Parent = dot
		stroke(3).Parent = dot
		text({ Text = bait.Name, Size = UDim2.new(0.45, 0, 0, 32), Position = UDim2.fromOffset(64, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26, Parent = row })
		text({ Text = "🍀 x" .. bait.Luck .. " Luck", Size = UDim2.new(0.45, 0, 0, 22), Position = UDim2.fromOffset(64, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Green, MaxText = 18, Parent = row })
		local owned = data.Baits[bait.Id]
		local equipped = data.Bait == bait.Id
		local label, c1, c2
		if equipped then
			label, c1, c2 = "EQUIPPED", C.Gray, C.Gray2
		elseif owned then
			label, c1, c2 = "EQUIP", C.Blue, C.Blue2
		else
			local can = cash >= bait.Price
			label, c1, c2 = Format.Money(bait.Price), can and C.Green or C.Gray, can and C.Green2 or C.Gray2
		end
		button({ Text = label, Size = UDim2.fromOffset(170, 48), Position = UDim2.new(1, -180, 0, 8), C1 = c1, C2 = c2 }, function()
			if equipped then
				return
			end
			local res = Remotes.Get("BuyBait"):InvokeServer(bait.Id)
			if res and not res.ok then
				UI.Toast(res.msg, C.Red)
			elseif res and res.bought then
				UI.Toast("🪱 Bought " .. bait.Name .. "!", C.Green)
			end
		end).Parent = row
	end
end

-- Аквариум: список рыб и продажа
renderers.Aquarium = function(body: Frame)
	local data = ClientState.Data
	if not data then
		return
	end
	local top = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Parent = body })
	text({ Text = #data.Fish .. "/" .. data.Capacity .. " fish", Size = UDim2.new(0.3, 0, 1, -10), Position = UDim2.fromOffset(4, 5), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26, Parent = top })
	button({ Text = "Sell all Common", Size = UDim2.fromOffset(200, 44), Position = UDim2.new(1, -412, 0, 3), C1 = C.Orange, C2 = C.Orange2, MaxText = 20 }, function()
		local res = Remotes.Get("SellBulk"):InvokeServer(1)
		if res and res.ok then
			UI.Toast("💰 Sold " .. res.count .. " fish for " .. Format.Money(res.cash), C.Gold)
		elseif res then
			UI.Toast(res.msg, C.Red)
		end
	end).Parent = top
	button({ Text = "Sell ≤ Rare", Size = UDim2.fromOffset(200, 44), Position = UDim2.new(1, -204, 0, 3), C1 = C.Red, C2 = C.Red2, MaxText = 20 }, function()
		local res = Remotes.Get("SellBulk"):InvokeServer(3)
		if res and res.ok then
			UI.Toast("💰 Sold " .. res.count .. " fish for " .. Format.Money(res.cash), C.Gold)
		elseif res then
			UI.Toast(res.msg, C.Red)
		end
	end).Parent = top
	local grid = scroller(body, UDim2.new(1, 0, 1, -58), UDim2.fromOffset(0, 58))
	new("UIGridLayout", { CellSize = UDim2.fromOffset(142, 186), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	new("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = grid })
	local fishList = table.clone(data.Fish)
	table.sort(fishList, function(a, b)
		return GameData.FishIncome(a.Id, a.M, a.S) > GameData.FishIncome(b.Id, b.M, b.S)
	end)
	if #fishList == 0 then
		text({ Text = "No fish yet — go cast from the Fishing Pier! 🎣", Size = UDim2.new(1, 0, 0, 40), MaxText = 24, Parent = grid })
	end
	for i, f in ipairs(fishList) do
		local def = GameData.FishById[f.Id]
		if def then
			local rarity = GameData.Rarities[def.Rarity]
			local card = panel({ BackgroundColor3 = C.Panel2, LayoutOrder = i, Parent = grid })
			local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 78), Position = UDim2.fromOffset(0, 4), Parent = card })
			fishViewport(holder, f.Id, f.M, false, false)
			local nameLabel = text({ Text = GameData.FullName(f.Id, f.M, f.S), Size = UDim2.new(1, -8, 0, 34), Position = UDim2.fromOffset(4, 82), TextColor3 = rarity.Color, MaxText = 18, TextWrapped = true, Parent = card })
			rarityGradient(nameLabel, def.Rarity)
			text({ Text = Format.Money(GameData.FishIncome(f.Id, f.M, f.S)) .. "/s", Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 116), TextColor3 = C.Green, MaxText = 18, Parent = card })
			local price = math.floor(GameData.FishIncome(f.Id, f.M, f.S) * Config.SellSeconds)
			button({ Text = "Sell " .. Format.Money(price), Size = UDim2.new(1, -12, 0, 38), Position = UDim2.fromOffset(6, 142), C1 = C.Orange, C2 = C.Orange2, MaxText = 18 }, function()
				local res = Remotes.Get("SellFish"):InvokeServer(f.U)
				if res and res.ok then
					UI.Toast("💰 +" .. Format.Money(res.cash), C.Gold)
				end
			end).Parent = card
		end
	end
end

-- Коллекция (индекс)
renderers.Index = function(body: Frame)
	local data = ClientState.Data
	if not data then
		return
	end
	local found = 0
	for _, f in ipairs(GameData.Fish) do
		if data.Index[f.Id] then
			found += 1
		end
	end
	text({ Text = "Discovered: " .. found .. "/" .. #GameData.Fish, Size = UDim2.new(1, 0, 0, 34), MaxText = 26, Parent = body })
	local list = scroller(body, UDim2.new(1, 0, 1, -42), UDim2.fromOffset(0, 42))
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	new("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingLeft = UDim.new(0, 2), Parent = list })
	for z, zone in ipairs(GameData.Zones) do
		local section = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = z, Parent = list })
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = section })
		text({ Text = zone.Name, Size = UDim2.new(1, 0, 0, 30), TextColor3 = zone.Color, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26, LayoutOrder = 0, Parent = section })
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = section })
		new("UIGridLayout", { CellSize = UDim2.fromOffset(110, 128), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
		for i, f in ipairs(GameData.FishByZone[z]) do
			local known = data.Index[f.Id] == true
			local rarity = GameData.Rarities[f.Rarity]
			local card = panel({ BackgroundColor3 = C.Panel2, LayoutOrder = i, Parent = row })
			local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 2), Parent = card })
			fishViewport(holder, f.Id, "None", not known, false)
			local nameLabel = text({ Text = known and f.Name or "???", Size = UDim2.new(1, -6, 0, 24), Position = UDim2.fromOffset(3, 74), TextColor3 = known and C.White or C.Gray, MaxText = 16, Parent = card })
			nameLabel.TextWrapped = true
			local rl = text({ Text = rarity.Name, Size = UDim2.new(1, -6, 0, 20), Position = UDim2.fromOffset(3, 100), TextColor3 = rarity.Color, MaxText = 15, Parent = card })
			rarityGradient(rl, f.Rarity)
		end
	end
end

-- Магазин за Robux
renderers.Store = function(body: Frame)
	local list = scroller(body, UDim2.fromScale(1, 1))
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	new("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingLeft = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), Parent = list })

	-- лесенка тренировки
	local train = panel({ Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = C.Panel2, LayoutOrder = 1, Parent = list })
	local data = ClientState.Data
	local curMult = 1
	for _, p in ipairs(Config.TrainingPasses) do
		if ClientState.HasPass(p.Key) then
			curMult = math.max(curMult, p.Mult)
		end
	end
	text({ Text = "💪 TRAINING SPEED", Size = UDim2.new(0.6, 0, 0, 34), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold, MaxText = 28, Parent = train })
	text({ Text = "Now: x" .. curMult .. " power per pull-up", Size = UDim2.new(0.6, 0, 0, 24), Position = UDim2.fromOffset(12, 44), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20, Parent = train })
	local ladder = {}
	for _, p in ipairs(Config.TrainingPasses) do
		table.insert(ladder, (ClientState.HasPass(p.Key) and "✅ x" or "x") .. p.Mult)
	end
	text({ Text = table.concat(ladder, "  →  "), Size = UDim2.new(0.6, 0, 0, 22), Position = UDim2.fromOffset(12, 76), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gray, MaxText = 18, Parent = train })
	local nextPass = nextTrainingPass()
	if nextPass then
		local b = button({ Text = "x" .. nextPass.Mult .. "  for  " .. nextPass.Price .. " R$", Size = UDim2.fromOffset(220, 70), Position = UDim2.new(1, -230, 0, 25), C1 = C.Gold, C2 = C.Gold2, MaxText = 26 }, function()
			buy("pass", nextPass.Key, nextPass.Id)
		end)
		b.Parent = train
	else
		button({ Text = "MAXED!", Size = UDim2.fromOffset(220, 70), Position = UDim2.new(1, -230, 0, 25), C1 = C.Gray, C2 = C.Gray2 }).Parent = train
	end

	text({ Text = "⭐ Game Passes", Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26, LayoutOrder = 2, Parent = list })
	local passGrid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = list })
	new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 118), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = passGrid })
	local passOrder = { "AutoCast", "Cash2", "Luck2", "BigTank" }
	for i, key in ipairs(passOrder) do
		local p = Config.Passes[key]
		local owned = ClientState.HasPass(key)
		local card = panel({ BackgroundColor3 = C.Panel2, LayoutOrder = i, Parent = passGrid })
		text({ Text = p.Name, Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 6), TextColor3 = C.Gold, MaxText = 24, Parent = card })
		local d = text({ Text = p.Desc, Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 36), MaxText = 15, TextWrapped = true, Parent = card })
		d.TextColor3 = C.Gray
		button({ Text = owned and "OWNED" or (p.Price .. " R$"), Size = UDim2.new(1, -16, 0, 38), Position = UDim2.fromOffset(8, 74), C1 = owned and C.Gray or C.Green, C2 = owned and C.Gray2 or C.Green2, MaxText = 22 }, function()
			if not owned then
				buy("pass", key, p.Id)
			end
		end).Parent = card
	end

	text({ Text = "🍀 Boosts", Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26, LayoutOrder = 4, Parent = list })
	local prodGrid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = list })
	new("UIGridLayout", { CellSize = UDim2.new(0.333, -7, 0, 128), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = prodGrid })
	for key, p in pairs(Config.Products) do
		local card = panel({ BackgroundColor3 = C.Panel2, LayoutOrder = p.Order, Parent = prodGrid })
		text({ Text = p.Name, Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, 6), TextColor3 = C.Green, MaxText = 20, Parent = card })
		local d = text({ Text = p.Desc, Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 36), MaxText = 14, TextWrapped = true, Parent = card })
		d.TextColor3 = C.Gray
		button({ Text = p.Price .. " R$", Size = UDim2.new(1, -12, 0, 38), Position = UDim2.fromOffset(6, 84), C1 = C.Green, C2 = C.Green2, MaxText = 22 }, function()
			buy("product", key, p.Id)
		end).Parent = card
	end
	local _ = data
end

function UI.OpenWindow(name: string)
	if name == "Shop" then
		openWindow("Shop", "🛒 Shop", C.Orange, C.Orange2)
	elseif name == "Aquarium" then
		openWindow("Aquarium", "🐠 My Aquarium", C.Blue, C.Blue2)
	elseif name == "Index" then
		openWindow("Index", "📖 Fish Index", C.Purple, C.Purple2)
	elseif name == "Store" then
		openWindow("Store", "💎 Store", C.Gold, C.Gold2)
	end
end

-- ===== HUD =====
local cashLabel: TextLabel
local incomeLabel: TextLabel
local powerLabel: TextLabel
local nextLabel: TextLabel
local nextFill: Frame
local eventBanner: Frame
local eventLabel: TextLabel
local luckBanner: Frame
local luckLabel: TextLabel
local luckyBadge: TextLabel
local autoButton: TextButton
local castButton: TextButton
local chargeFrame: Frame
local chargeFill: Frame
local chargeZones: Frame
local chargeLabel: TextLabel
local reelFrame: Frame
local reelFill: Frame
local reelTitle: TextLabel
local trainFrame: Frame
local trainLabel: TextLabel
local trainUpsell: TextButton
local pierButton: TextButton
local displayedCash = 0

local function buildHud()
	-- деньги (крупно слева, как в симуляторах)
	local cashHolder = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, -205), Size = UDim2.fromOffset(320, 96), BackgroundTransparency = 1, Parent = gui })
	scaleable(cashHolder)
	cashLabel = text({ Text = "$0", Size = UDim2.new(1, 0, 0, 62), Font = Enum.Font.LuckiestGuy, TextColor3 = Color3.fromRGB(95, 255, 95), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 58, StrokeThickness = 4, Parent = cashHolder })
	incomeLabel = text({ Text = "+$0/s", Position = UDim2.fromOffset(4, 62), Size = UDim2.new(1, 0, 0, 28), Font = Enum.Font.LuckiestGuy, TextColor3 = Color3.fromRGB(255, 240, 120), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 26, StrokeThickness = 3, Parent = cashHolder })

	eventBanner = panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(420, 38), BackgroundColor3 = C.Purple2, Visible = false, Parent = gui })
	scaleable(eventBanner)
	eventLabel = text({ Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), MaxText = 24, Parent = eventBanner })
	luckBanner = panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Size = UDim2.fromOffset(300, 32), BackgroundColor3 = C.Green2, Visible = false, Parent = gui })
	scaleable(luckBanner)
	luckLabel = text({ Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), MaxText = 20, Parent = luckBanner })

	-- левое меню: яркие квадратные кнопки в 2 столбца
	local menu = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 40), Size = UDim2.fromOffset(180, 280), BackgroundTransparency = 1, Parent = gui })
	scaleable(menu)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(84, 84), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu })
	local function goTo(remote: string)
		return function()
			local ok = Remotes.Get(remote):InvokeServer()
			if not ok then
				UI.Toast("Stop training first!", C.Red)
			end
		end
	end
	local items = {
		{ "🛒", "SHOP", C.Orange, C.Orange2, function() UI.OpenWindow("Shop") end },
		{ "💎", "STORE", C.Gold, C.Gold2, function() UI.OpenWindow("Store") end },
		{ "🐠", "TANK", C.Blue, C.Blue2, function() UI.OpenWindow("Aquarium") end },
		{ "📖", "INDEX", C.Purple, C.Purple2, function() UI.OpenWindow("Index") end },
		{ "🎣", "PIER", Color3.fromRGB(80, 230, 230), Color3.fromRGB(20, 150, 170), goTo("GoToPier") },
		{ "🏠", "BASE", C.Green, C.Green2, goTo("GoToBase") },
	}
	for i, it in ipairs(items) do
		local b = button({ Text = "", LayoutOrder = i, C1 = it[3], C2 = it[4], Corner = 16 }, it[5])
		b.Rotation = (i % 2 == 0) and 2 or -2
		b.Parent = menu
		text({ Text = it[1], Size = UDim2.new(1, -16, 0.58, 0), Position = UDim2.new(0, 8, 0, 6), MaxText = 44, StrokeThickness = 0, Parent = b })
		text({ Text = it[2], Size = UDim2.new(1, -8, 0.3, 0), Position = UDim2.new(0, 4, 0.64, 0), Font = Enum.Font.LuckiestGuy, MaxText = 22, StrokeThickness = 3, Parent = b })
		if it[2] == "PIER" then
			pierButton = b
		end
		if it[2] == "STORE" then
			task.spawn(function()
				local us = b:FindFirstChildOfClass("UIScale")
				while b.Parent do
					task.wait(4)
					if us then
						TweenService:Create(us, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), { Scale = 1.12 }):Play()
					end
				end
			end)
		end
	end

	-- сила внизу
	local powerFrame = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(460, 70), BackgroundColor3 = C.Panel, Parent = gui })
	scaleable(powerFrame)
	powerLabel = text({ Text = "💪 0 Power", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 4), MaxText = 26, Font = Enum.Font.LuckiestGuy, StrokeThickness = 3, Parent = powerFrame })
	local bar = new("Frame", { Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 38), BackgroundColor3 = C.Panel2, Parent = powerFrame })
	corner(10).Parent = bar
	stroke(2).Parent = bar
	nextFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.White, Parent = bar })
	corner(10).Parent = nextFill
	grad(C.Gold, C.Orange2, 0).Parent = nextFill
	nextLabel = text({ Text = "", Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), MaxText = 18, ZIndex = 2, Parent = bar })

	-- кнопка заброса
	castButton = new("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(136, 136),
		BackgroundColor3 = C.White,
		AutoButtonColor = false,
		Text = "",
		Parent = gui,
	})
	scaleable(castButton)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = castButton })
	stroke(4).Parent = castButton
	grad(Color3.fromRGB(110, 230, 255), Color3.fromRGB(30, 120, 230)).Parent = castButton
	text({ Text = "🎣\nCAST", Size = UDim2.new(1, -24, 1, -30), Position = UDim2.fromOffset(12, 15), MaxText = 42, Font = Enum.Font.LuckiestGuy, StrokeThickness = 4, Parent = castButton })
	castButton.MouseButton1Down:Connect(function()
		if UI.Callbacks.CastDown then
			UI.Callbacks.CastDown()
		end
	end)
	castButton.MouseButton1Up:Connect(function()
		if UI.Callbacks.CastUp then
			UI.Callbacks.CastUp()
		end
	end)
	luckyBadge = text({ Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.85, 0, 0.12, 0), Size = UDim2.fromOffset(70, 30), TextColor3 = C.Green, MaxText = 22, Parent = castButton })

	autoButton = button({ Text = "🔒 Auto Cast", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -162), Size = UDim2.fromOffset(136, 40), C1 = C.Gray, C2 = C.Gray2, MaxText = 20 }, function()
		if not ClientState.HasPass("AutoCast") then
			UI.OpenWindow("Store")
			return
		end
		UI.AutoCast = not UI.AutoCast
		UI.Refresh()
	end)
	autoButton.Parent = gui
	scaleable(autoButton)

	-- полоска заряда
	chargeFrame = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96), Size = UDim2.fromOffset(500, 70), BackgroundColor3 = C.Panel2, Visible = false, Parent = gui })
	scaleable(chargeFrame)
	chargeLabel = text({ Text = "", Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 4), MaxText = 24, Parent = chargeFrame })
	local cbar = new("Frame", { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 34), BackgroundColor3 = Color3.fromRGB(10, 20, 40), ClipsDescendants = true, Parent = chargeFrame })
	corner(8).Parent = cbar
	chargeZones = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = cbar })
	chargeFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.White, BackgroundTransparency = 0.15, ZIndex = 3, Parent = cbar })
	grad(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 240, 255), 0).Parent = chargeFill

	-- полоска вываживания
	reelFrame = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.68), Size = UDim2.fromOffset(400, 86), BackgroundColor3 = C.Panel2, Visible = false, Parent = gui })
	scaleable(reelFrame)
	reelTitle = text({ Text = "🎣 CLICK TO REEL!", Size = UDim2.new(1, -12, 0, 36), Position = UDim2.fromOffset(6, 4), MaxText = 30, StrokeThickness = 3, Parent = reelFrame })
	local rbar = new("Frame", { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 46), BackgroundColor3 = Color3.fromRGB(10, 20, 40), Parent = reelFrame })
	corner(10).Parent = rbar
	reelFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.White, Parent = rbar })
	corner(10).Parent = reelFill
	grad(C.Green, C.Green2).Parent = reelFill

	-- тренировка
	trainFrame = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.fromOffset(500, 120), BackgroundColor3 = C.Panel2, Visible = false, Parent = gui })
	scaleable(trainFrame)
	trainLabel = text({ Text = "💪 TRAINING", Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(6, 4), MaxText = 28, Parent = trainFrame })
	text({ Text = "Click / tap anywhere to pull faster!", Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 36), TextColor3 = C.Gray, MaxText = 18, Parent = trainFrame })
	button({ Text = "Stop", Size = UDim2.fromOffset(130, 46), Position = UDim2.fromOffset(12, 64), C1 = C.Red, C2 = C.Red2 }, function()
		Remotes.Get("StopTraining"):InvokeServer()
	end).Parent = trainFrame
	trainUpsell = button({ Text = "", Size = UDim2.new(1, -166, 0, 46), Position = UDim2.fromOffset(154, 64), C1 = C.Gold, C2 = C.Gold2, MaxText = 22 }, function()
		local p = nextTrainingPass()
		if p then
			buy("pass", p.Key, p.Id)
		end
	end)
	trainUpsell.Parent = trainFrame

	-- тосты
	toastList = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(360, 340), BackgroundTransparency = 1, Parent = gui })
	scaleable(toastList)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = toastList })

	windowHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = gui })
	local windowScale = new("UIScale", { Parent = windowHolder })
	local _ = windowScale
end

-- ===== Публичные функции HUD =====
function UI.SetCharge(visible: boolean, charge: number?, maxDist: number?)
	chargeFrame.Visible = visible
	if not visible then
		return
	end
	local md = maxDist or 30
	if chargeZones:GetAttribute("MaxDist") ~= md then
		chargeZones:SetAttribute("MaxDist", md)
		chargeZones:ClearAllChildren()
		for z, zone in ipairs(GameData.Zones) do
			local from = zone.Dist / md
			local nextZone = GameData.Zones[z + 1]
			local to = nextZone and math.min(1, nextZone.Dist / md) or 1
			if from < 1 then
				local seg = new("Frame", { BackgroundColor3 = zone.Color, BackgroundTransparency = 0.25, BorderSizePixel = 0, Position = UDim2.fromScale(from, 0), Size = UDim2.fromScale(to - from, 1), Parent = chargeZones })
				local _ = seg
			end
		end
	end
	local c = charge or 0
	chargeFill.Size = UDim2.fromScale(c, 1)
	local d = math.max(8, md * c)
	local zone = GameData.Zones[GameData.ZoneForDistance(d)]
	chargeLabel.Text = zone.Name .. "  •  " .. math.floor(d) .. "m"
	chargeLabel.TextColor3 = zone.Color
end

function UI.SetReel(visible: boolean, progress: number?, rarity: number?)
	reelFrame.Visible = visible
	if visible then
		reelFill.Size = UDim2.fromScale(math.clamp(progress or 0, 0, 1), 1)
		if rarity and rarity >= GameData.RarityIndex.Legendary then
			reelTitle.Text = "🔥 SOMETHING BIG! CLICK!"
			reelTitle.TextColor3 = GameData.Rarities[rarity].Color
		else
			reelTitle.Text = "🎣 CLICK TO REEL!"
			reelTitle.TextColor3 = C.White
		end
	end
end

function UI.SetTraining(on: boolean)
	trainFrame.Visible = on
	UI.Refresh()
end

function UI.RepPop(gain: number)
	local t = text({
		Text = "+" .. Format.Number(gain) .. " 💪",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-140, 140), 0.55, math.random(-30, 30)),
		Size = UDim2.fromOffset(180, 44),
		TextColor3 = C.Gold,
		MaxText = 34,
		StrokeThickness = 3,
		Parent = gui,
	})
	TweenService:Create(t, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { Position = t.Position - UDim2.fromOffset(0, 90), TextTransparency = 1 }):Play()
	local s = t:FindFirstChildOfClass("UIStroke")
	if s then
		TweenService:Create(s, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	end
	task.delay(0.85, function()
		t:Destroy()
	end)
end

function UI.FlashPier()
	if pierButton then
		local us = pierButton:FindFirstChildOfClass("UIScale")
		if us then
			TweenService:Create(us, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true), { Scale = 1.25 }):Play()
		end
	end
end

function UI.RefreshHud()
	local data = ClientState.Data
	if not data then
		return
	end
	local power = ClientState.Power()
	local maxD = Config.MaxDistance(power)
	local zone = GameData.Zones[GameData.ZoneForDistance(maxD)]
	powerLabel.Text = "💪 " .. Format.Commas(power) .. "   •   🎣 " .. math.floor(maxD) .. "m (" .. zone.Name .. ")"
	local nextZone = nil
	for _, z in ipairs(GameData.Zones) do
		if z.Dist > maxD then
			nextZone = z
			break
		end
	end
	if nextZone then
		local need = Config.PowerForDistance(nextZone.Dist)
		local prevNeed = Config.PowerForDistance(zone.Dist)
		local p = math.clamp((power - prevNeed) / math.max(1, need - prevNeed), 0, 1)
		nextFill.Size = UDim2.fromScale(p, 1)
		nextLabel.Text = "Next: " .. nextZone.Name .. " at " .. Format.Commas(need) .. " 💪"
	else
		nextFill.Size = UDim2.fromScale(1, 1)
		nextLabel.Text = "MAX DISTANCE!"
	end
	luckyBadge.Text = (data.LuckyCasts or 0) > 0 and ("🍀" .. data.LuckyCasts) or ""
	if ClientState.HasPass("AutoCast") then
		autoButton:FindFirstChild("Label").Text = UI.AutoCast and "🤖 Auto: ON" or "🤖 Auto: OFF"
		if UI.AutoCast then
			setButtonColors(autoButton, C.Green, C.Green2)
		else
			setButtonColors(autoButton, C.Blue, C.Blue2)
		end
	else
		autoButton:FindFirstChild("Label").Text = "🔒 Auto Cast"
		setButtonColors(autoButton, C.Gray, C.Gray2)
	end
	local nextPass = nextTrainingPass()
	local mult = data.TrainMult or 1
	trainLabel.Text = "💪 TRAINING  x" .. Format.Number(mult)
	if nextPass then
		trainUpsell.Visible = true
		trainUpsell:FindFirstChild("Label").Text = "⚡ Train x" .. nextPass.Mult .. " — only " .. nextPass.Price .. " R$"
	else
		trainUpsell.Visible = false
	end
end

function UI.Refresh()
	UI.RefreshHud()
	rerenderWindow()
end

-- ===== Карточка улова =====
local cardQueue = {}
local cardShowing = false

local function showNextCard()
	if cardShowing or #cardQueue == 0 then
		return
	end
	cardShowing = true
	local res = table.remove(cardQueue, 1)
	local def = GameData.FishById[res.fish]
	local rarity = GameData.Rarities[def.Rarity]
	local mut = GameData.MutationById[res.mutation]
	local size = GameData.Sizes[res.size]

	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(420, 430), BackgroundTransparency = 1, Parent = gui })
	local hs = new("UIScale", { Scale = 0.2, Parent = holder })
	local baseScale = scaled[1] and scaled[1].Scale or 1
	-- лучи
	local rays = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.35), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Parent = holder })
	for i = 0, 11 do
		local ray = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(48, 560),
			Rotation = i * 15,
			BackgroundColor3 = rarity.Color,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = rays,
		})
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }), Rotation = 90, Parent = ray })
	end
	local card = panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(340, 380), BackgroundColor3 = C.Panel2, Parent = holder })
	local cs = card:FindFirstChildOfClass("UIStroke")
	if cs then
		cs.Color = rarity.Color
		cs.Thickness = 5
	end
	local vpHolder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 190), Position = UDim2.fromOffset(0, 10), Parent = card })
	fishViewport(vpHolder, res.fish, res.mutation, false, true)
	if res.outcome and res.outcome.IsNew then
		local newTag = text({ Text = "NEW!", Rotation = -12, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(110, 44), TextColor3 = C.Gold, MaxText = 40, StrokeThickness = 3, Parent = card })
		local _ = newTag
	end
	local rl = text({ Text = string.upper(rarity.Name), Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 196), TextColor3 = rarity.Color, MaxText = 32, StrokeThickness = 3, Parent = card })
	rarityGradient(rl, def.Rarity)
	local nameText = def.Name
	local nl = text({ Text = nameText, Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 230), MaxText = 40, StrokeThickness = 3, Parent = card })
	local _ = nl
	local tags = {}
	if mut and mut.Id ~= "None" then
		table.insert(tags, mut.Name .. " x" .. mut.Mult)
	end
	if size and size.Name ~= "Normal" then
		table.insert(tags, size.Name .. " x" .. size.Mult)
	end
	local tl = text({ Text = #tags > 0 and table.concat(tags, "  •  ") or " ", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 276), TextColor3 = mut and mut.Id ~= "None" and mut.Color or C.Gray, MaxText = 22, Parent = card })
	if mut and mut.Id == "Rainbow" then
		rarityGradient(tl, GameData.RarityIndex.Secret)
	end
	text({ Text = Format.Money(GameData.FishIncome(res.fish, res.mutation, res.size)) .. "/s", Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 304), TextColor3 = C.Green, MaxText = 30, Parent = card })
	local outcomeText = "Added to your aquarium!"
	if res.outcome then
		if res.outcome.Kind == "swapped" then
			outcomeText = "Tank full: replaced " .. tostring(res.outcome.Old)
		elseif res.outcome.Kind == "sold" then
			outcomeText = "Tank full: sold for " .. Format.Money(res.outcome.Cash or 0)
		end
	end
	text({ Text = outcomeText, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 342), TextColor3 = C.Gray, MaxText = 18, Parent = card })

	TweenService:Create(hs, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = baseScale }):Play()
	local alive = true
	task.spawn(function()
		while alive do
			rays.Rotation += 0.6
			RunService.RenderStepped:Wait()
		end
	end)
	local duration = def.Rarity >= GameData.RarityIndex.Legendary and 3.6 or 2.4
	if UI.AutoCast and def.Rarity < GameData.RarityIndex.Epic then
		duration = 1.2
	end
	task.delay(duration, function()
		local tw = TweenService:Create(hs, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		tw:Play()
		tw.Completed:Wait()
		alive = false
		for i = #spinning, 1, -1 do
			if not spinning[i].vp:IsDescendantOf(game) or spinning[i].vp:IsDescendantOf(holder) then
				table.remove(spinning, i)
			end
		end
		holder:Destroy()
		cardShowing = false
		showNextCard()
	end)
end

function UI.ShowCatch(res)
	table.insert(cardQueue, res)
	showNextCard()
end

function UI.ShowOffline(cash: number, seconds: number)
	local f = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(420, 220), BackgroundColor3 = C.Panel, Parent = gui })
	local s = new("UIScale", { Scale = 0.3, Parent = f })
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = scaled[1] and scaled[1].Scale or 1 }):Play()
	text({ Text = "Welcome back! 👋", Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 12), MaxText = 36, Parent = f })
	text({ Text = "Your fish earned while you were away (" .. Format.Time(seconds) .. "):", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 60), TextColor3 = C.Gray, MaxText = 18, TextWrapped = true, Parent = f })
	text({ Text = "+" .. Format.Money(cash), Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 90), TextColor3 = C.Green, MaxText = 48, StrokeThickness = 3, Parent = f })
	button({ Text = "Collect!", Size = UDim2.fromOffset(200, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 156) }, function()
		f:Destroy()
	end).Parent = f
end

-- ===== Инициализация =====
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local s = math.clamp(math.min(vp.Y / 780, vp.X / 1200), 0.55, 1.15)
	for _, us in ipairs(scaled) do
		us.Scale = s
	end
	local ws = windowHolder and windowHolder:FindFirstChildOfClass("UIScale")
	if ws then
		ws.Scale = s
	end
end

function UI.Init()
	gui = new("ScreenGui", { Name = "GameUI", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	buildHud()
	gui.Parent = player:WaitForChild("PlayerGui")
	updateScale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	ClientState.Changed:Connect(function()
		UI.Refresh()
	end)
	player:GetAttributeChangedSignal("Power"):Connect(function()
		UI.RefreshHud()
	end)
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Pass_" then
			UI.Refresh()
		end
	end)

	Remotes.Get("Notify").OnClientEvent:Connect(function(msg, color)
		UI.Toast(msg, color)
	end)
	Remotes.Get("Offline").OnClientEvent:Connect(function(cash, secs)
		UI.ShowOffline(cash, secs)
	end)
	Remotes.Get("BigCatch").OnClientEvent:Connect(function(name, fishId, mutation, sizeIdx)
		local def = GameData.FishById[fishId]
		if def then
			local rarity = GameData.Rarities[def.Rarity]
			UI.Toast("🔥 " .. name .. " caught " .. string.upper(rarity.Name) .. " " .. GameData.FullName(fishId, mutation, sizeIdx) .. "!", rarity.Color, 5)
		end
	end)

	-- киоски в центре острова
	for _, desc in ipairs(workspace:WaitForChild("Map"):GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			desc.Triggered:Connect(function()
				if desc.Name == "ShopPrompt" then
					UI.OpenWindow("Shop")
				elseif desc.Name == "SellPrompt" then
					UI.OpenWindow("Aquarium")
				elseif desc.Name == "StorePrompt" then
					UI.OpenWindow("Store")
				end
			end)
		end
	end

	-- анимации каждый кадр: деньги, баннеры, вращение 3D
	local bannerTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		local target = ClientState.Cash()
		if target < displayedCash or target - displayedCash < 1 then
			displayedCash = target
		else
			displayedCash += (target - displayedCash) * math.min(1, dt * 7)
		end
		cashLabel.Text = Format.Money(math.floor(displayedCash))
		incomeLabel.Text = "+" .. Format.Money(player:GetAttribute("Income") or 0) .. "/s"

		for _, s in ipairs(spinning) do
			s.model:PivotTo(CFrame.Angles(0, os.clock() * 1.2, 0) * s.cf)
		end
		for i = #rainbowGradients, 1, -1 do
			local g = rainbowGradients[i]
			if g.Parent then
				g.Offset = Vector2.new((os.clock() * 0.4) % 2 - 1, 0)
			else
				table.remove(rainbowGradients, i)
			end
		end

		bannerTimer += dt
		if bannerTimer > 0.25 then
			bannerTimer = 0
			local ev = workspace:GetAttribute("Event")
			local ends = workspace:GetAttribute("EventEnds") or 0
			local def = ev and GameData.Events[ev]
			if def and workspace:GetServerTimeNow() < ends then
				eventBanner.Visible = true
				eventLabel.Text = def.Icon .. " " .. def.Name .. " — " .. def.Desc .. " — " .. Format.Time(ends - workspace:GetServerTimeNow())
			else
				eventBanner.Visible = false
			end
			local lm = workspace:GetAttribute("ServerLuck") or 1
			local lends = workspace:GetAttribute("ServerLuckEnds") or 0
			if lm > 1 and workspace:GetServerTimeNow() < lends then
				luckBanner.Visible = true
				luckLabel.Text = "🍀 Server Luck x" .. lm .. " — " .. Format.Time(lends - workspace:GetServerTimeNow())
			else
				luckBanner.Visible = false
			end
		end
	end)
	UI.Refresh()
end

return UI
