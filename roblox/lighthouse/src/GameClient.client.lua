-- Клиент «Маяк во Тьме»: тьма, постройки, находки, тени, созвездия и интерфейс.
-- Всё, что зависит от прогресса, игрок видит только у себя.
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
local IgniteR, BuyUpR, BuyRUpR, RollR = R("Ignite"), R("BuyUp"), R("BuyRUp"), R("Roll")
local RebirthR, ToggleR, TeleportR, FightR, CollectR = R("Rebirth"), R("Toggle"), R("Teleport"), R("Fight"), R("Collect")
local StateR, EventR = R("State"), R("Event")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
player.CameraMaxZoomDistance = 70

local worldFolder = workspace:WaitForChild("World")
local lighthouse = worldFolder:WaitForChild("Lighthouse") :: Model
local door = lighthouse:WaitForChild("Door") :: BasePart
local LAMP_Y = (lighthouse:GetAttribute("LampY") :: number?) or 36

local mine = Instance.new("Folder")
mine.Name = "MyLight"
mine.Parent = workspace

--------------------------------------------------------------------------------
-- Состояние
--------------------------------------------------------------------------------
local state: Config.Data = Config.newData()
local income = 0
local stateTime = os.clock()
local hasState = false
type FightInfo = { zone: number, hp: number, maxHp: number, timeLeft: number }
local fight: FightInfo? = nil

local function coinsNow(): number
	return state.coins + income * math.min(os.clock() - stateTime, 1.5)
end

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------
local BG = Color3.fromRGB(14, 14, 24)
local PANEL = Color3.fromRGB(28, 27, 44)
local CARD = Color3.fromRGB(40, 38, 60)
local CARD_DIM = Color3.fromRGB(30, 29, 46)
local WARM = Color3.fromRGB(255, 205, 110)
local GOOD = Color3.fromRGB(60, 180, 100)
local BAD = Color3.fromRGB(70, 68, 90)
local RED = Color3.fromRGB(235, 75, 85)
local VIOLET = Color3.fromRGB(190, 140, 255)
local SKY = Color3.fromRGB(120, 200, 255)
local MUTED = Color3.fromRGB(180, 178, 205)
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
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
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
local SND_BUY = "rbxasset://sounds/button.wav"
local SND_PING = "rbxasset://sounds/electronicpingshort.wav"
local SND_WIN = "rbxasset://sounds/victory.wav"
local SND_HIT = "rbxasset://sounds/swordslash.wav"

local function pop(inst: GuiObject, from: number?)
	local sc = inst:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = inst })
	sc.Scale = from or 0.9
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function wpart(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function wlight(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
end

--------------------------------------------------------------------------------
-- Тьма: стена, отступающая с ростом света
--------------------------------------------------------------------------------
local SEG = 72
local WALL_H = 90
type Ring = { parts: { Part }, offset: number }
local darkness = Instance.new("Folder")
darkness.Name = "Darkness"
darkness.Parent = mine
local rings: { Ring } = {}
for k, spec in ipairs({ { 0, 0, true }, { -1.6, 0.45, false }, { -3.4, 0.75, false } }) do
	local ring: Ring = { parts = {}, offset = spec[1] }
	for i = 1, SEG do
		ring.parts[i] = wpart(darkness, {
			Name = "Dark" .. k,
			Color = k == 1 and Color3.new(0, 0, 0) or Color3.fromRGB(10, 6, 20),
			Material = Enum.Material.SmoothPlastic,
			Transparency = spec[2],
			CanCollide = spec[3],
			Size = Vector3.new(3, WALL_H, 4),
		})
	end
	table.insert(rings, ring)
end
local shownRadius = Config.radius(0)
local wallRadius = -1
local function placeWall(r: number)
	for _, ring in ipairs(rings) do
		local rr = r + ring.offset
		local w = 2 * math.pi * rr / SEG + 0.6
		for i, p in ipairs(ring.parts) do
			local a = (i - 0.5) / SEG * math.pi * 2
			p.Size = Vector3.new(3, WALL_H, w)
			p.CFrame = CFrame.new(math.cos(a) * (rr + 1.5), WALL_H / 2 - 1, math.sin(a) * (rr + 1.5)) * CFrame.Angles(0, -a, 0)
		end
	end
	wallRadius = r
end
placeWall(shownRadius)

--------------------------------------------------------------------------------
-- Маяк: лампа и вращающийся луч (растут с «Линзой»)
--------------------------------------------------------------------------------
local lamp = wpart(mine, {
	Name = "Lamp",
	Shape = Enum.PartType.Ball,
	Size = Vector3.new(2.5, 2.5, 2.5),
	CFrame = CFrame.new(0, LAMP_Y, 0),
	Color = Color3.fromRGB(255, 240, 190),
	Material = Enum.Material.Neon,
})
local lampLight = new("PointLight", { Color = Color3.fromRGB(255, 225, 160), Range = 40, Brightness = 2, Parent = lamp })
local lampAtt = new("Attachment", { Parent = lamp })
local beamEnds: { Attachment } = {}
local beams: { Beam } = {}
for i = 1, 2 do
	local endPart = wpart(mine, { Name = "BeamEnd", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(0, LAMP_Y, 0) })
	local att = new("Attachment", { Parent = endPart })
	beamEnds[i] = att
	beams[i] = new("Beam", {
		Attachment0 = lampAtt,
		Attachment1 = att,
		Color = ColorSequence.new(Color3.fromRGB(255, 235, 170)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 1,
		Width0 = 1.5,
		Width1 = 14,
		FaceCamera = true,
		Segments = 2,
		Parent = lamp,
	})
end

-- Тень у стены и луч атаки
local fightBeam = new("Beam", {
	Attachment0 = lampAtt,
	Color = ColorSequence.new(Color3.fromRGB(255, 255, 220)),
	LightEmission = 1,
	Width0 = 2,
	Width1 = 4,
	FaceCamera = true,
	Enabled = false,
	Parent = lamp,
})

--------------------------------------------------------------------------------
-- Постройки-улучшения
--------------------------------------------------------------------------------
type Anim = { part: BasePart, kind: string, base: CFrame, phase: number, pivot: Vector3? }
local anims: { Anim } = {}

type Building = {
	u: Config.Upgrade,
	anchor: CFrame,
	model: Model?,
	tier: number,
	locked: boolean?,
	billboard: BillboardGui,
	title: TextLabel,
	info: TextLabel,
	cost: TextLabel,
	prompt: ProximityPrompt,
	promptMax: ProximityPrompt,
	host: BasePart,
}
local buildings: { [string]: Building } = {}

local function clearAnims(model: Instance)
	for i = #anims, 1, -1 do
		if anims[i].part:IsDescendantOf(model) then
			table.remove(anims, i)
		end
	end
end

local function addAnim(p: BasePart, kind: string, pivot: Vector3?)
	table.insert(anims, { part = p, kind = kind, base = p.CFrame, phase = math.random() * 6, pivot = pivot })
end

-- Сколько «шагов» визуального роста у уровня
local function tierOf(id: string, lvl: number): number
	if lvl <= 0 then
		return 0
	end
	if id == "lamps" then
		return math.min(lvl, 40)
	elseif id == "mirror" or id == "battery" or id == "relay" or id == "net" or id == "focus" then
		return lvl
	end
	return math.floor(math.log(lvl, 2)) + 1
end

local BUILDERS: { [string]: (Model, CFrame, number, Config.Upgrade) -> () } = {
	-- Фонарщик: домик + фонари по кругу
	lamps = function(m, cf, t, u)
		wpart(m, { Size = Vector3.new(6, 4, 5), CFrame = cf * CFrame.new(0, 2, 0), Color = Color3.fromRGB(120, 85, 60), Material = Enum.Material.WoodPlanks, CanCollide = true })
		wpart(m, { Size = Vector3.new(7, 0.6, 6), CFrame = cf * CFrame.new(0, 4.6, 0) * A(0, 0, 0), Color = Color3.fromRGB(70, 50, 40) })
		local w = wpart(m, { Size = Vector3.new(1.2, 1.2, 0.2), CFrame = cf * CFrame.new(1.5, 2.4, -2.55), Color = u.color, Material = Enum.Material.Neon })
		wlight(w, u.color, 10, 1)
		for i = 1, t do
			local a = (i - 1) / math.max(t, 12) * math.pi * 2 + 0.15
			local r = 29
			local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			wpart(m, { Size = Vector3.new(0.4, 7, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 3.5, 0)), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal })
			local bulb = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(pos + Vector3.new(0, 7.3, 0)), Color = u.color, Material = Enum.Material.Neon })
			if i % 3 == 1 then
				wlight(bulb, u.color, 16, 1.2)
			end
		end
	end,
	-- Улей: растущая стопка сот и светлячки
	hive = function(m, cf, t, u)
		wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 4, 4), CFrame = cf * CFrame.new(0, 1, 0) * A(0, 0, 90), Color = Color3.fromRGB(100, 75, 50), Material = Enum.Material.Wood, CanCollide = true })
		local h = 2
		for i = 1, math.min(t + 1, 8) do
			local d = 3.6 - math.abs(i - 3) * 0.3
			wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, d, d), CFrame = cf * CFrame.new(0, h + 0.55, 0) * A(0, 0, 90), Color = Color3.fromRGB(235, 185, 60), Material = Enum.Material.SmoothPlastic })
			h += 1.1
		end
		local top = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, h + 0.5, 0), Color = u.color, Material = Enum.Material.Neon })
		wlight(top, u.color, 12, 1)
		new("ParticleEmitter", {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(u.color),
			Size = NumberSequence.new(0.35, 0.1),
			LightEmission = 1,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(180, 180),
			Rate = 2 + t * 3,
			Acceleration = Vector3.new(0, 0.4, 0),
			Parent = top,
		})
	end,
	-- Прожектор: тумба и вращающаяся фара
	search = function(m, cf, t, u)
		local s = 1 + t * 0.12
		wpart(m, { Size = Vector3.new(4, 3, 4) * s, CFrame = cf * CFrame.new(0, 1.5 * s, 0), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.DiamondPlate, CanCollide = true })
		local head = wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 3, 3) * s, CFrame = cf * CFrame.new(0, 4.6 * s, 0) * A(0, 90, 0), Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal })
		head.Name = "SearchHead"
		local glass = wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.6, 2.6) * s, CFrame = head.CFrame * CFrame.new(-1.55 * s, 0, 0), Color = u.color, Material = Enum.Material.Neon })
		addAnim(head, "spin", head.Position)
		addAnim(glass, "spin", head.Position)
	end,
	-- Зеркала: панели полукругом
	mirror = function(m, cf, t, u)
		wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 5, 5), CFrame = cf * CFrame.new(0, 0.3, 0) * A(0, 0, 90), Color = Color3.fromRGB(80, 80, 95), Material = Enum.Material.Metal })
		for i = 1, math.min(t, 20) do
			local a = math.rad(-80 + (i - 1) * (160 / math.max(math.min(t, 20) - 1, 1)))
			local r = 2.5 + math.floor((i - 1) / 10) * 1.6
			local pcf = cf * CFrame.new(math.sin(a) * r, 2.8, -math.cos(a) * r) * CFrame.Angles(0, -a, 0)
			wpart(m, { Size = Vector3.new(1.4, 4, 0.2), CFrame = pcf, Color = u.color, Material = Enum.Material.Glass, Reflectance = 0.7, Transparency = 0.1 })
		end
	end,
	-- Призма: парящий кристалл растёт
	prism = function(m, cf, t, u)
		wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.5, 3, 3), CFrame = cf * CFrame.new(0, 1.25, 0) * A(0, 0, 90), Color = Color3.fromRGB(70, 60, 90), Material = Enum.Material.Marble, CanCollide = true })
		local s = 1.4 + t * 0.35
		local p = wpart(m, { Size = Vector3.new(s, s, s), CFrame = cf * CFrame.new(0, 4 + s * 0.6, 0) * A(45, 0, 35.26), Color = u.color, Material = Enum.Material.Neon, Transparency = 0.1 })
		wlight(p, u.color, 10 + t * 2, 1.2)
		addAnim(p, "float")
	end,
	-- Сачок: стойки с сетками
	net = function(m, cf, t, u)
		for i = 1, math.max(t, 1) do
			local x = (i - (t + 1) / 2) * 1.8
			wpart(m, { Size = Vector3.new(0.3, 5, 0.3), CFrame = cf * CFrame.new(x, 2.5, 0) * A(0, 0, 8), Color = Color3.fromRGB(120, 90, 60), Material = Enum.Material.Wood })
			wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2, 2), CFrame = cf * CFrame.new(x + 0.4, 5.3, 0) * A(0, 0, 0), Color = u.color, Material = Enum.Material.ForceField, Transparency = 0.1 })
		end
	end,
	-- Аккумулятор: батареи рядком
	battery = function(m, cf, t, u)
		wpart(m, { Size = Vector3.new(6.5, 0.5, 4), CFrame = cf * CFrame.new(0, 0.25, 0), Color = Color3.fromRGB(50, 50, 60), Material = Enum.Material.DiamondPlate })
		for i = 1, math.max(t, 1) do
			local col = (i - 1) % 5
			local row = math.floor((i - 1) / 5)
			local pos = CFrame.new(-2.4 + col * 1.2, 0, -1 + row * 2)
			wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 1, 1), CFrame = cf * pos * CFrame.new(0, 1.7, 0) * A(0, 0, 90), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal })
			local cap = wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.9, 0.9), CFrame = cf * pos * CFrame.new(0, 3.05, 0) * A(0, 0, 90), Color = u.color, Material = Enum.Material.Neon })
			addAnim(cap, "blink")
		end
	end,
	-- Фокусировка: кольца вокруг линзы
	focus = function(m, cf, t, u)
		wpart(m, { Size = Vector3.new(0.6, 4, 0.6), CFrame = cf * CFrame.new(0, 2, 0), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Metal })
		local lens = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = cf * CFrame.new(0, 5, 0), Color = u.color, Material = Enum.Material.Neon })
		wlight(lens, u.color, 10, 1)
		for i = 1, math.max(t, 1) do
			local ring = wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2.4 + i * 0.7, 2.4 + i * 0.7), CFrame = cf * CFrame.new(0, 5, 0) * A(i * 30, i * 50, 0), Color = u.color, Material = Enum.Material.ForceField })
			addAnim(ring, "tumble")
		end
	end,
	-- Ретрансляторы: антенны с мигающими огнями
	relay = function(m, cf, t, u)
		for i = 1, math.max(t, 1) do
			local a = i * 2.4
			local r = 1 + math.sqrt(i) * 1.2
			local base = cf * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r)
			local h = 4 + (i % 3) * 1.5
			wpart(m, { Size = Vector3.new(0.4, h, 0.4), CFrame = base * CFrame.new(0, h / 2, 0), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Metal })
			local tip = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), CFrame = base * CFrame.new(0, h + 0.3, 0), Color = u.color, Material = Enum.Material.Neon })
			addAnim(tip, "blink")
		end
	end,
}

local function makeBuilding(u: Config.Upgrade)
	local host: BasePart
	local anchor: CFrame
	if u.id == "lens" then
		host = door
		anchor = door.CFrame
	else
		local a = math.rad(u.angle)
		local pos = Vector3.new(math.cos(a) * Config.BUILDING_RING, 0, math.sin(a) * Config.BUILDING_RING)
		anchor = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
		host = wpart(mine, {
			Name = "Pad_" .. u.id,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 8, 8),
			CFrame = anchor * CFrame.new(0, 0.3, 0) * A(0, 0, 90),
			Color = Color3.fromRGB(60, 58, 72),
			Material = Enum.Material.Cobblestone,
		})
		wpart(mine, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 8.6, 8.6),
			CFrame = anchor * CFrame.new(0, 0.27, 0) * A(0, 0, 90),
			Color = u.color,
			Material = Enum.Material.Neon,
			Transparency = 0.4,
		})
	end
	local bb = new("BillboardGui", {
		Size = UDim2.fromOffset(250, 84),
		StudsOffsetWorldSpace = Vector3.new(0, u.id == "lens" and 4 or 10, 0),
		LightInfluence = 0,
		MaxDistance = 90,
		Adornee = host,
		Parent = host,
	})
	local title = label({ Size = UDim2.new(1, 0, 0.4, 0), Text = u.name, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = u.color, TextStrokeTransparency = 0.2, Parent = bb })
	local info = label({ Position = UDim2.fromScale(0, 0.4), Size = UDim2.new(1, 0, 0.3, 0), Text = "", TextScaled = true, TextStrokeTransparency = 0.3, Parent = bb })
	local cost = label({ Position = UDim2.fromScale(0, 0.7), Size = UDim2.new(1, 0, 0.3, 0), Text = "", TextScaled = true, TextStrokeTransparency = 0.3, Parent = bb })
	local prompt = new("ProximityPrompt", {
		ActionText = "Улучшить",
		ObjectText = u.name,
		HoldDuration = 0,
		MaxActivationDistance = 12,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.E,
		Parent = host,
	})
	local promptMax = new("ProximityPrompt", {
		ActionText = "Улучшить на всё",
		ObjectText = "",
		HoldDuration = 0.4,
		MaxActivationDistance = 12,
		RequiresLineOfSight = false,
		KeyboardKeyCode = Enum.KeyCode.F,
		UIOffset = Vector2.new(0, 70),
		Parent = host,
	})
	prompt.Triggered:Connect(function()
		BuyUpR:FireServer(u.id, 1)
	end)
	promptMax.Triggered:Connect(function()
		BuyUpR:FireServer(u.id, "max")
	end)
	buildings[u.id] = {
		u = u,
		anchor = anchor,
		model = nil,
		tier = -1,
		billboard = bb,
		title = title,
		info = info,
		cost = cost,
		prompt = prompt,
		promptMax = promptMax,
		host = host,
	}
end

for _, u in ipairs(Config.Upgrades) do
	makeBuilding(u)
end

local function effectText(u: Config.Upgrade, lvl: number): string
	if u.id == "lamps" then
		return string.format("%d фонарей · +%d/с", lvl, lvl * 2)
	elseif u.id == "lens" then
		return string.format("сияние ×%s", Config.format(1.2 ^ lvl))
	elseif u.id == "hive" then
		return string.format("удача +%d%% · огонёк раз в %.1f с", lvl * 15, Config.pickupInterval(state))
	elseif u.id == "search" then
		return string.format("урон ×%s", Config.format(1.4 ^ lvl))
	elseif u.id == "mirror" then
		return string.format("свет дешевле на %d%%", math.floor((1 - 0.96 ^ lvl) * 100 + 0.5))
	elseif u.id == "prism" then
		return string.format("сияющие +%d%%", lvl * 15)
	elseif u.id == "net" then
		return string.format("до %d огоньков сразу", Config.maxPickups(state))
	elseif u.id == "battery" then
		return string.format("бой %d с", Config.fightDuration(state))
	elseif u.id == "focus" then
		return string.format("крит %d%%", lvl * 5)
	elseif u.id == "relay" then
		return string.format("+%.1f%% за уровень света", (Config.LIGHT_BONUS + 0.001 * lvl) * 100)
	end
	return ""
end

local function updateBuildings(coins: number)
	for id, b in pairs(buildings) do
		local u = b.u
		local lvl = Config.lvl(state, id)
		local locked = state.bosses < u.needBoss
		local tier = locked and -2 or tierOf(id, lvl)
		if tier ~= b.tier and id ~= "lens" then
			b.tier = tier
			if b.model then
				clearAnims(b.model)
				b.model:Destroy()
			end
			local m = Instance.new("Model")
			m.Name = "B_" .. id
			if locked then
				-- строительные леса
				for i = 1, 4 do
					local a = i * math.pi / 2 + math.pi / 4
					wpart(m, { Size = Vector3.new(0.3, 6, 0.3), CFrame = b.anchor * CFrame.new(math.cos(a) * 2.5, 3, math.sin(a) * 2.5), Color = Color3.fromRGB(110, 90, 60), Material = Enum.Material.Wood })
				end
				wpart(m, { Size = Vector3.new(5.4, 0.3, 5.4), CFrame = b.anchor * CFrame.new(0, 6, 0), Color = Color3.fromRGB(110, 90, 60), Material = Enum.Material.Wood })
			elseif lvl > 0 then
				BUILDERS[id](m, b.anchor, tier, u)
			else
				-- призрачный контур: купи, чтобы построить
				local ghost = Instance.new("Model")
				BUILDERS[id](ghost, b.anchor, 1, u)
				for _, d in ipairs(ghost:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Transparency = 0.8
						d.Material = Enum.Material.ForceField
						d.Color = u.color
						d.CanCollide = false
						for _, l in ipairs(d:GetChildren()) do
							if l:IsA("Light") or l:IsA("ParticleEmitter") then
								l:Destroy()
							end
						end
					end
				end
				clearAnims(ghost)
				ghost.Parent = m
			end
			m.Parent = mine
			b.model = m
		end
		b.prompt.Enabled = not locked and lvl < u.maxLevel
		b.promptMax.Enabled = b.prompt.Enabled
		if locked then
			b.info.Text = string.format("🔒 после %d-й тени", u.needBoss)
			b.cost.Text = u.desc
			b.cost.TextColor3 = MUTED
		elseif lvl >= u.maxLevel then
			b.info.Text = string.format("ур. %d (макс) · %s", lvl, effectText(u, lvl))
			b.cost.Text = "★ Максимум"
			b.cost.TextColor3 = WARM
		else
			local c = Config.upCost(u, lvl)
			b.info.Text = lvl > 0 and string.format("ур. %d · %s", lvl, effectText(u, lvl)) or u.desc
			b.cost.Text = string.format("[E] 💡 %s", Config.format(c))
			b.cost.TextColor3 = coins >= c and Color3.fromRGB(140, 255, 150) or Color3.fromRGB(255, 150, 150)
			b.prompt.ObjectText = "💡 " .. Config.format(c)
		end
	end
	-- Линза: лампа и лучи
	local lens = Config.lvl(state, "lens")
	local size = 2.5 + math.min(lens, 40) * 0.12
	lamp.Size = Vector3.new(size, size, size)
	lampLight.Range = math.min(60, 40 + lens)
	lampLight.Brightness = 2 + math.min(lens, 30) * 0.1
	for _, bm in ipairs(beams) do
		bm.Width1 = 12 + math.min(lens, 40) * 0.5
	end
end

--------------------------------------------------------------------------------
-- Огоньки-находки на земле
--------------------------------------------------------------------------------
type Pickup = { token: string, part: BasePart, pos: Vector3, sent: boolean }
local pickups: { [string]: Pickup } = {}

local function removePickup(token: string, burst: boolean)
	local p = pickups[token]
	if not p then
		return
	end
	pickups[token] = nil
	if burst then
		TweenService:Create(p.part, TweenInfo.new(0.3), { Size = Vector3.new(4, 4, 4), Transparency = 1 }):Play()
		task.delay(0.35, function()
			p.part:Destroy()
		end)
	else
		p.part:Destroy()
	end
end

local function spawnPickup(token: string, pos: Vector3, zone: number)
	local z = Config.Zones[zone]
	local orb = wpart(mine, {
		Name = "Pickup",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = CFrame.new(pos),
		Color = z.accent,
		Material = Enum.Material.Neon,
	})
	wlight(orb, z.accent, 14, 1.5)
	new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(z.accent),
		Size = NumberSequence.new(0.5, 0),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 6,
		Parent = orb,
	})
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(40, 40), StudsOffsetWorldSpace = Vector3.new(0, 3, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 400, Adornee = orb, Parent = orb })
	label({ Size = UDim2.fromScale(1, 1), Text = "✨", TextScaled = true, Parent = bb })
	pickups[token] = { token = token, part = orb, pos = pos, sent = false }
	addAnim(orb, "bob")
end

--------------------------------------------------------------------------------
-- Тень у стены
--------------------------------------------------------------------------------
local shadow: Model? = nil
local shadowZone = 0
local shadowRoot: BasePart? = nil
local shadowAtt: Attachment? = nil

local function buildShadow(zone: number)
	if shadow then
		clearAnims(shadow)
		shadow:Destroy()
		shadow = nil
		shadowRoot = nil
	end
	shadowZone = zone
	if zone == 0 then
		fightBeam.Enabled = false
		return
	end
	local z = Config.Zones[zone]
	local m = Instance.new("Model")
	m.Name = "Shadow"
	local ang = Config.bossAngle(zone)
	local r = Config.radius(Config.bossLevel(zone)) - 5
	local pos = Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
	local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
	local s = 1 + zone * 0.12
	local BLACK = Color3.fromRGB(8, 6, 14)
	local body = wpart(m, { Size = Vector3.new(7, 9, 5) * s, CFrame = cf * CFrame.new(0, 6 * s, 0), Color = BLACK, Material = Enum.Material.SmoothPlastic })
	wpart(m, { Size = Vector3.new(5, 5, 4) * s, CFrame = cf * CFrame.new(0, 12.5 * s, -0.5 * s), Color = BLACK })
	for _, x in ipairs({ -1.2, 1.2 }) do
		local eye = wpart(m, { Size = Vector3.new(1.1, 0.7, 0.3) * s, CFrame = cf * CFrame.new(x * s, 13 * s, -2.6 * s), Color = RED, Material = Enum.Material.Neon })
		wlight(eye, RED, 10, 1)
	end
	for _, x in ipairs({ -1, 1 }) do
		local arm = wpart(m, { Size = Vector3.new(1.6, 9, 1.6) * s, CFrame = cf * CFrame.new(x * 4.6 * s, 6 * s, -1 * s) * A(20, 0, x * -18), Color = BLACK })
		addAnim(arm, "sway")
		wpart(m, { Size = Vector3.new(6, 1, 1) * s, CFrame = cf * CFrame.new(x * 6.5 * s, 10 * s, 1 * s) * A(0, 0, x * 35), Color = z.accent, Material = Enum.Material.Neon, Transparency = 0.4 })
	end
	new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(20, 10, 30)),
		Size = NumberSequence.new(4, 8),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(60, 60),
		Rate = 12,
		Parent = body,
	})
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(300, 60), StudsOffsetWorldSpace = Vector3.new(0, 10 * s, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 600, Adornee = body, Parent = body })
	label({ Size = UDim2.fromScale(1, 0.6), Text = "👁 " .. z.boss, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = RED, TextStrokeTransparency = 0.2, Parent = bb })
	label({ Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.6), Text = "❤ " .. Config.format(Config.bossHP(zone)), TextScaled = true, TextStrokeTransparency = 0.3, Parent = bb })
	local prompt = new("ProximityPrompt", { ActionText = "Изгнать лучом", ObjectText = z.boss, HoldDuration = 0, MaxActivationDistance = 30, RequiresLineOfSight = false, Parent = body })
	prompt.Triggered:Connect(function()
		FightR:FireServer()
	end)
	m.Parent = mine
	shadow = m
	shadowRoot = body
	shadowAtt = new("Attachment", { Parent = body })
	fightBeam.Attachment1 = shadowAtt
end

--------------------------------------------------------------------------------
-- Созвездия в небе
--------------------------------------------------------------------------------
local sky = Instance.new("Folder")
sky.Name = "Sky"
sky.Parent = mine
local drawnTitles: { [string]: boolean } = {}
local drawnActive: string? = nil

local function drawConstellation(t: Config.Title, index: number, active: boolean): Model
	local m = Instance.new("Model")
	m.Name = t.id
	local seed = 0
	for i = 1, #t.id do
		seed += string.byte(t.id, i) * i
	end
	local rng = Random.new(seed)
	local center: Vector3
	if active then
		center = Vector3.new(0, 230, 0)
	else
		local a = index * 0.57 * math.pi
		center = Vector3.new(math.cos(a) * 220, 170 + (index % 3) * 25, math.sin(a) * 220)
	end
	local spread = active and 60 or 35
	local prevAtt: Attachment? = nil
	for i = 1, t.stars do
		local p = center + Vector3.new(rng:NextNumber(-spread, spread), rng:NextNumber(-spread * 0.4, spread * 0.4), rng:NextNumber(-spread, spread))
		local star = wpart(m, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (active and rng:NextNumber(3, 5) or rng:NextNumber(1.6, 2.6)),
			CFrame = CFrame.new(p),
			Color = t.color,
			Material = Enum.Material.Neon,
			Transparency = active and 0 or 0.35,
		})
		local att = new("Attachment", { Parent = star })
		if prevAtt then
			new("Beam", {
				Attachment0 = prevAtt,
				Attachment1 = att,
				Color = ColorSequence.new(t.color),
				Transparency = NumberSequence.new(active and 0.4 or 0.75),
				LightEmission = 1,
				Width0 = active and 0.8 or 0.4,
				Width1 = active and 0.8 or 0.4,
				FaceCamera = true,
				Parent = star,
			})
		end
		prevAtt = att
		if i == 1 and active then
			local bb = new("BillboardGui", { Size = UDim2.fromOffset(260, 44), StudsOffsetWorldSpace = Vector3.new(0, 12, 0), LightInfluence = 0, MaxDistance = 2000, Adornee = star, Parent = star })
			label({ Size = UDim2.fromScale(1, 1), Text = "✦ " .. t.name, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = t.color, Parent = bb })
		end
	end
	m.Parent = sky
	return m
end

local function updateSky()
	local key = state.title
	local changed = key ~= drawnActive
	for _, t in ipairs(Config.Titles) do
		if (state.titles[t.id] or 0) > 0 and not drawnTitles[t.id] then
			changed = true
		end
	end
	if not changed then
		return
	end
	sky:ClearAllChildren()
	table.clear(drawnTitles)
	for i, t in ipairs(Config.Titles) do
		if (state.titles[t.id] or 0) > 0 then
			drawnTitles[t.id] = true
			drawConstellation(t, i, false)
		end
	end
	local active = key and Config.TitleById[key]
	if active then
		drawConstellation(active, 0, true)
	end
	drawnActive = key
end

--------------------------------------------------------------------------------
-- Анимации
--------------------------------------------------------------------------------
local beamAngle = 0
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	-- Плавное движение тьмы
	local target = Config.radius(state.light)
	if math.abs(shownRadius - target) > 0.05 then
		shownRadius += (target - shownRadius) * math.min(1, dt * 3)
		placeWall(shownRadius)
	elseif wallRadius ~= target then
		shownRadius = target
		placeWall(target)
	end
	-- Лучи маяка
	beamAngle += dt * 0.5
	for i, att in ipairs(beamEnds) do
		local a = beamAngle + (i - 1) * math.pi
		local r = shownRadius - 2
		local endPart = att.Parent :: BasePart
		endPart.CFrame = CFrame.new(math.cos(a) * r, 2, math.sin(a) * r)
	end
	-- Анимированные детали
	for _, an in ipairs(anims) do
		local p = an.part
		if an.kind == "spin" then
			local pv = CFrame.new(an.pivot or an.base.Position)
			p.CFrame = pv * CFrame.Angles(0, t * 0.8, 0) * pv:Inverse() * an.base
		elseif an.kind == "float" then
			p.CFrame = an.base * CFrame.new(0, math.sin(t * 1.5 + an.phase) * 0.5, 0) * CFrame.Angles(0, t, 0)
		elseif an.kind == "bob" then
			p.CFrame = an.base * CFrame.new(0, math.sin(t * 2 + an.phase) * 0.4, 0)
		elseif an.kind == "blink" then
			p.Transparency = (math.sin(t * 3 + an.phase) > 0.3) and 0 or 0.7
		elseif an.kind == "tumble" then
			p.CFrame = an.base * CFrame.Angles(t * 0.7 + an.phase, t * 0.4, 0)
		elseif an.kind == "sway" then
			p.CFrame = an.base * CFrame.Angles(math.sin(t * 2 + an.phase) * 0.15, 0, 0)
		end
	end
	-- Бой: дрожь тени
	if fight and shadowRoot then
		local root = shadowRoot :: BasePart
		root.Transparency = (math.floor(t * 10) % 2 == 0) and 0 or 0.3
	end
end)

-- Сбор огоньков: подходишь — и он твой
task.spawn(function()
	while true do
		task.wait(0.15)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			for token, p in pairs(pickups) do
				if not p.sent and (root.Position - p.pos).Magnitude < 6 then
					p.sent = true
					CollectR:FireServer(token)
					task.delay(2, function()
						local still = pickups[token]
						if still then
							still.sent = false
						end
					end)
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Интерфейс
--------------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "LightUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
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

-- HUD
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(480, 104),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.2,
	Parent = gui,
}, { corner(18), stroke(WARM, 2, 0.2) })
local coinsLabel = label({ Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 4), Text = "💡 0", TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = WARM, Parent = hud })
local incomeLabel = label({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 54), Text = "", TextSize = 18, Parent = hud })
local zoneLabel = label({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 78), Text = "", TextSize = 15, Font = Enum.Font.Gotham, TextColor3 = SKY, Parent = hud })
local hintLabel = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 118),
	Size = UDim2.fromOffset(600, 24),
	Text = "",
	TextSize = 17,
	Font = Enum.Font.FredokaOne,
	TextStrokeTransparency = 0.3,
	TextColor3 = Color3.fromRGB(255, 240, 200),
	Parent = gui,
})

-- Разжечь
local bottom = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(440, 80), BackgroundTransparency = 1, Parent = gui })
local igniteButton = button({ Size = UDim2.new(1, -110, 1, 0), BackgroundColor3 = BAD, Text = "", Parent = bottom }, { corner(18), stroke(WHITE, 3) })
local igniteTitle = label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 6), Text = "🔥 РАЗЖЕЧЬ", TextSize = 28, Font = Enum.Font.FredokaOne, Parent = igniteButton })
local igniteCost = label({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 46), Text = "", TextSize = 18, Parent = igniteButton })
local maxButton = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 100, 1, 0), BackgroundColor3 = PANEL, Text = "МАКС", TextSize = 20, Font = Enum.Font.FredokaOne, Parent = bottom }, { corner(18), stroke(WARM, 2) })

local bossRow = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -104), Size = UDim2.fromOffset(460, 46), BackgroundTransparency = 1, Visible = false, Parent = gui }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
})
local fightButton = button({ Size = UDim2.fromOffset(270, 46), BackgroundColor3 = RED, Text = "", TextSize = 17, Font = Enum.Font.FredokaOne, Parent = bossRow }, { corner(12) })
local toShadowButton = button({ Size = UDim2.fromOffset(170, 46), BackgroundColor3 = PANEL, Text = "🏃 К тени", TextSize = 16, Parent = bossRow }, { corner(12), stroke(RED, 2) })
local bossHint = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -154), Size = UDim2.fromOffset(560, 22), Text = "", TextSize = 15, TextStrokeTransparency = 0.3, Visible = false, Parent = gui })

-- Бой
local fightFrame = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 148), Size = UDim2.fromOffset(480, 64), BackgroundColor3 = BG, BackgroundTransparency = 0.1, Visible = false, Parent = gui }, { corner(14), stroke(RED, 2) })
local fightName = label({ Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 22), Text = "", TextSize = 17, Font = Enum.Font.FredokaOne, TextColor3 = RED, Parent = fightFrame })
local hpBg = new("Frame", { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 24), BackgroundColor3 = Color3.fromRGB(40, 15, 20), Parent = fightFrame }, { corner(8) })
local hpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED, Parent = hpBg }, { corner(8) })
local hpText = label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 14, ZIndex = 2, Parent = hpBg })

-- Боковые кнопки
local leftBar = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(70, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui }, {
	new("UIListLayout", { Padding = UDim.new(0, 8) }),
})
local function sideButton(icon: string, caption: string, color: Color3?): TextButton
	local b = button({ Size = UDim2.fromOffset(70, 66), BackgroundColor3 = PANEL, BackgroundTransparency = 0.1, Text = "", Parent = leftBar }, { corner(14), stroke(color or WARM, 1.5, 0.3) })
	label({ Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 4), Text = icon, TextSize = 28, Parent = b })
	label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 44), Text = caption, TextSize = 11, TextColor3 = MUTED, Parent = b })
	return b
end
local homeButton = sideButton("🗼", "К маяку")
local edgeButton = sideButton("🌑", "К краю", RED)
local relicButton = sideButton("📖", "Находки", SKY)
local starButton = sideButton("✦", "Созвездия", VIOLET)
local dawnButton = sideButton("🌅", "Заря", WARM)
local dawnBadge = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 0, BackgroundColor3 = RED, Text = "!", TextSize = 13, Visible = false, ZIndex = 3, Parent = dawnButton })
corner(10).Parent = dawnBadge

-- Окна (по одному)
local windows: { [string]: Frame } = {}
local function window(id: string, title: string, color: Color3): (Frame, ScrollingFrame)
	local w = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(560, 600),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { corner(20), stroke(color, 2) })
	label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -80, 0, 36), Text = title, TextSize = 24, Font = Enum.Font.FredokaOne, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21, Parent = w })
	local close = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = PANEL, Text = "✕", TextSize = 18, ZIndex = 21, Parent = w }, { corner(10) })
	close.Activated:Connect(function()
		w.Visible = false
	end)
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 54),
		Size = UDim2.new(1, -24, 1, -66),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = color,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 21,
		Parent = w,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }),
	})
	windows[id] = w
	return w, list
end
local function toggleWindow(id: string)
	for wid, w in pairs(windows) do
		if wid == id then
			w.Visible = not w.Visible
			if w.Visible then
				pop(w, 0.92)
				playSound(SND_BUY, 0.25, 1.3)
			end
		else
			w.Visible = false
		end
	end
end

-- Окно «Находки»
local _, relicList = window("relics", "📖 Находки", SKY)
local relicSummary = label({ Size = UDim2.new(1, 0, 0, 48), Text = "", TextSize = 14, TextWrapped = true, Font = Enum.Font.Gotham, TextColor3 = MUTED, LayoutOrder = 0, ZIndex = 22, Parent = relicList })
type RelicCell = { relic: Config.Relic, frame: Frame, name: TextLabel, info: TextLabel }
local relicCells: { RelicCell } = {}
for zi, z in ipairs(Config.Zones) do
	label({ Size = UDim2.new(1, 0, 0, 24), Text = string.format("%d · %s", zi, z.name), TextSize = 15, Font = Enum.Font.FredokaOne, TextColor3 = z.accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = zi * 2 - 1, ZIndex = 22, Parent = relicList })
	local grid = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = zi * 2, ZIndex = 22, Parent = relicList }, {
		new("UIGridLayout", { CellSize = UDim2.new(0.333, -5, 0, 50), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, relic in ipairs(Config.RelicsByZone[zi]) do
		local frame = new("Frame", { BackgroundColor3 = CARD_DIM, LayoutOrder = i, ZIndex = 22, Parent = grid }, { corner(10), stroke(relic.rarity.color, 1.5, 0.6) })
		local name = label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 20), Text = "???", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = MUTED, ZIndex = 23, Parent = frame })
		local info = label({ Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 22), Text = relic.rarity.name, TextSize = 11, TextWrapped = true, Font = Enum.Font.Gotham, TextColor3 = relic.rarity.color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
		table.insert(relicCells, { relic = relic, frame = frame, name = name, info = info })
	end
end

-- Окно «Созвездия»
local _, starList = window("stars", "✦ Созвездия", VIOLET)
local starHeader = new("Frame", { Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = CARD, LayoutOrder = 0, ZIndex = 22, Parent = starList }, { corner(12) })
local starCurrent = label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 28), Text = "", TextSize = 20, Font = Enum.Font.FredokaOne, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = starHeader })
local starInfo = label({ Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 18), Text = "", TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = starHeader })
local rollBig = button({ Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 0, 46), BackgroundColor3 = VIOLET, Text = "", TextSize = 18, Font = Enum.Font.FredokaOne, ZIndex = 23, Parent = starHeader }, { corner(12) })
rollBig.Activated:Connect(function()
	RollR:FireServer()
	pop(rollBig, 0.92)
end)
type TitleRow = { t: Config.Title, frame: Frame, owned: TextLabel }
local titleRows: { TitleRow } = {}
for i, t in ipairs(Config.Titles) do
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = CARD_DIM, LayoutOrder = i, ZIndex = 22, Parent = starList }, { corner(10) })
	label({ Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.45, 0, 1, 0), Text = "✦ " .. t.name, TextSize = 15, TextColor3 = t.color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
	label({ Position = UDim2.new(0.45, 0, 0, 0), Size = UDim2.new(0.25, 0, 1, 0), Text = Config.formatChance(t.chance), TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = MUTED, ZIndex = 23, Parent = frame })
	local owned = label({ Position = UDim2.new(0.7, 0, 0, 0), Size = UDim2.new(0.3, -10, 1, 0), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 23, Parent = frame })
	table.insert(titleRows, { t = t, frame = frame, owned = owned })
end

-- Окно «Новая заря»
local _, dawnList = window("dawn", "🌅 Новая заря", WARM)
local dawnHeader = new("Frame", { Size = UDim2.new(1, 0, 0, 230), BackgroundColor3 = CARD, LayoutOrder = 0, ZIndex = 22, Parent = dawnList }, { corner(12) })
local dustLabel = label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 30), Text = "", TextSize = 21, Font = Enum.Font.FredokaOne, TextColor3 = WARM, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = dawnHeader })
local dawnInfo = label({ Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, 66), Text = "", TextSize = 13, TextWrapped = true, Font = Enum.Font.Gotham, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 23, Parent = dawnHeader })
local dawnBtn = button({ Position = UDim2.fromOffset(12, 110), Size = UDim2.new(1, -24, 0, 46), BackgroundColor3 = BAD, Text = "", TextSize = 18, Font = Enum.Font.FredokaOne, ZIndex = 23, Parent = dawnHeader }, { corner(12) })
local autoLightToggle = button({ Position = UDim2.fromOffset(12, 162), Size = UDim2.new(1, -24, 0, 28), BackgroundColor3 = PANEL, Text = "", TextSize = 13, Visible = false, ZIndex = 23, Parent = dawnHeader }, { corner(8) })
local autoPickToggle = button({ Position = UDim2.fromOffset(12, 194), Size = UDim2.new(1, -24, 0, 28), BackgroundColor3 = PANEL, Text = "", TextSize = 13, Visible = false, ZIndex = 23, Parent = dawnHeader }, { corner(8) })
autoLightToggle.Activated:Connect(function()
	ToggleR:FireServer("autoLight")
end)
autoPickToggle.Activated:Connect(function()
	ToggleR:FireServer("autoPick")
end)
local confirmUntil = 0
dawnBtn.Activated:Connect(function()
	if Config.dustOnRebirth(state) < 1 then
		return
	end
	if os.clock() < confirmUntil then
		confirmUntil = 0
		RebirthR:FireServer()
	else
		confirmUntil = os.clock() + 3
		dawnBtn.Text = "Точно? Нажми ещё раз"
		pop(dawnBtn, 0.9)
	end
end)
type RCard = { r: Config.RebirthUp, lvl: TextLabel, buy: TextButton }
local rCards: { RCard } = {}
for i, r in ipairs(Config.RebirthUps) do
	local frame = new("Frame", { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = CARD, LayoutOrder = i, ZIndex = 22, Parent = dawnList }, { corner(12) })
	label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -140, 0, 22), Text = "✦ " .. r.name, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
	label({ Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -140, 0, 20), Text = r.desc, TextSize = 12, TextWrapped = true, Font = Enum.Font.Gotham, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
	local lvl = label({ Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -140, 0, 14), Text = "", TextSize = 11, Font = Enum.Font.Gotham, TextColor3 = WARM, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
	local buy = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(112, 44), BackgroundColor3 = BAD, Text = "", TextSize = 15, ZIndex = 23, Parent = frame }, { corner(10) })
	buy.Activated:Connect(function()
		BuyRUpR:FireServer(r.id)
		pop(buy, 0.9)
	end)
	table.insert(rCards, { r = r, lvl = lvl, buy = buy })
end

-- Сообщения
local toastHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 222), Size = UDim2.fromOffset(520, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 30, Parent = gui }, {
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
})
local function toast(text: string, color: Color3?)
	local t = label({ Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.15, BackgroundColor3 = BG, Text = "  " .. text .. "  ", TextSize = 18, Font = Enum.Font.FredokaOne, TextColor3 = color or WARM, ZIndex = 30, Parent = toastHolder })
	corner(12).Parent = t
	stroke(color or WARM, 1.5, 0.3).Parent = t
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
	local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(480, 300), BackgroundColor3 = BG, ZIndex = 51, Parent = shade }, { corner(20), stroke(color or WARM, 3) })
	label({ Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 40), Text = title, TextSize = 28, Font = Enum.Font.FredokaOne, TextColor3 = color or WARM, ZIndex = 52, Parent = box })
	label({ Position = UDim2.fromOffset(24, 64), Size = UDim2.new(1, -48, 0, 150), Text = body, TextSize = 17, TextWrapped = true, Font = Enum.Font.Gotham, ZIndex = 52, Parent = box })
	local ok = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(220, 52), BackgroundColor3 = GOOD, Text = buttonText, TextSize = 20, Font = Enum.Font.FredokaOne, ZIndex = 52, Parent = box }, { corner(14) })
	pop(box, 0.6)
	ok.Activated:Connect(function()
		shade:Destroy()
	end)
end

local function showRelic(relic: Config.Relic, shiny: boolean, isNew: boolean)
	local color = relic.rarity.color
	local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(320, 140), BackgroundColor3 = BG, ZIndex = 40, Parent = gui }, { corner(18), stroke(shiny and WHITE or color, shiny and 4 or 3) })
	label({ Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 22), Text = isNew and "✨ НОВАЯ НАХОДКА ✨" or "Находка", TextSize = 15, TextColor3 = MUTED, ZIndex = 41, Parent = card })
	label({ Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 40), Text = (shiny and "🌟 " or "") .. relic.name, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = color, ZIndex = 41, Parent = card })
	label({ Position = UDim2.fromOffset(10, 76), Size = UDim2.new(1, -20, 0, 22), Text = relic.rarity.name .. (shiny and (" · СИЯЮЩАЯ ×" .. Config.SHINY_MULT) or ""), TextSize = 16, TextColor3 = shiny and Color3.fromRGB(255, 255, 180) or color, ZIndex = 41, Parent = card })
	local entry = state.relics[relic.id]
	local bonus = entry and Config.relicBonus(relic, entry) or 0
	label({ Position = UDim2.fromOffset(10, 102), Size = UDim2.new(1, -20, 0, 26), Text = string.format("Бонус к сиянию: +%d%%", math.floor(bonus * 100 + 0.5)), TextSize = 14, Font = Enum.Font.Gotham, ZIndex = 41, Parent = card })
	pop(card, 0.4)
	if relic.rarityIndex >= 4 or shiny then
		playSound(SND_WIN, 0.6, shiny and 1.3 or 1)
	else
		playSound(SND_PING, 0.4, 1.2)
	end
	task.delay(isNew and 2.2 or 1.2, function()
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
	end)
end

-- Кнопки
igniteButton.Activated:Connect(function()
	IgniteR:FireServer(1)
	pop(igniteButton, 0.94)
end)
maxButton.Activated:Connect(function()
	IgniteR:FireServer("max")
	pop(maxButton, 0.9)
end)
fightButton.Activated:Connect(function()
	FightR:FireServer()
end)
toShadowButton.Activated:Connect(function()
	TeleportR:FireServer("edge")
end)
homeButton.Activated:Connect(function()
	TeleportR:FireServer("home")
end)
edgeButton.Activated:Connect(function()
	TeleportR:FireServer("edge")
end)
relicButton.Activated:Connect(function()
	toggleWindow("relics")
end)
starButton.Activated:Connect(function()
	toggleWindow("stars")
end)
dawnButton.Activated:Connect(function()
	toggleWindow("dawn")
end)

--------------------------------------------------------------------------------
-- Подсказка «что делать дальше»
--------------------------------------------------------------------------------
local function nextHint(coins: number): string
	local d = state
	if Config.lvl(d, "lamps") == 0 then
		return "👉 Подойди к призрачному «Фонарщику» у маяка и нажми E — он поставит первый фонарь"
	end
	if d.light == 0 then
		return "👉 Жми «🔥 Разжечь» — тьма отступит, а сияния станет больше"
	end
	if d.picks == 0 and next(pickups) then
		return "👉 На земле светятся огоньки ✨ — подбеги и собери находку"
	end
	if Config.lvl(d, "lens") == 0 and coins >= Config.upCost(Config.UpById.lens, 0) then
		return "👉 Улучши «Линзу маяка» у двери башни — всё сияние ×1.2"
	end
	if d.rolls == 0 and coins >= Config.titleRollCost(d) and d.light >= 20 then
		return "👉 Загляни в 🔭 обсерваторию — найди своё созвездие"
	end
	return ""
end

--------------------------------------------------------------------------------
-- Обновление
--------------------------------------------------------------------------------
local function updateUI()
	if not hasState then
		return
	end
	local d = state
	local coins = coinsNow()
	coinsLabel.Text = "💡 " .. Config.format(coins)
	incomeLabel.Text = string.format("+%s/с   ·   🍀 удача ×%s", Config.format(income), Config.format(Config.luck(d)))
	local zone = Config.Zones[Config.zoneOfLevel(math.max(d.light, 1))]
	zoneLabel.Text = string.format("🔥 Свет %d / %d · радиус %d м · %s · бонус ×%s", d.light, Config.MAX_LIGHT, math.floor(Config.radius(d.light)), zone.name, Config.format(Config.lightMult(d)))
	hintLabel.Text = nextHint(coins)

	local canLight, why = Config.canBuyLight(d)
	local nextZone = d.bosses + 1
	local atBoss = not canLight and d.light < Config.MAX_LIGHT and nextZone <= #Config.Zones
	if canLight then
		local cost = Config.lightCost(d, d.light + 1)
		igniteTitle.Text = "🔥 РАЗЖЕЧЬ"
		igniteCost.Text = "💡 " .. Config.format(cost)
		igniteButton.BackgroundColor3 = coins >= cost and Color3.fromRGB(220, 130, 40) or BAD
	elseif atBoss then
		igniteTitle.Text = "👁 ТЕНЬ"
		igniteCost.Text = Config.Zones[nextZone].boss .. " держит тьму"
		igniteButton.BackgroundColor3 = RED
	else
		igniteTitle.Text = "☀ РАССВЕТ"
		igniteCost.Text = why or ""
		igniteButton.BackgroundColor3 = WARM
	end
	bossRow.Visible = atBoss and fight == nil
	bossHint.Visible = atBoss and fight == nil
	if atBoss then
		local hp = Config.bossHP(nextZone)
		local total = Config.damagePerSec(d) * Config.fightDuration(d)
		local pct = math.floor(math.min(total / hp, 9.99) * 100)
		bossHint.Text = string.format("Луч за бой ≈ %s из ❤ %s (%d%%)%s", Config.format(total), Config.format(hp), pct, pct < 100 and " — качай Прожектор" or " — можно изгонять!")
		bossHint.TextColor3 = pct < 100 and Color3.fromRGB(255, 160, 140) or Color3.fromRGB(150, 255, 160)
		fightButton.Text = "☀ Изгнать: " .. Config.Zones[nextZone].boss
	end
	-- Тень на месте?
	local wantShadow = atBoss and nextZone or 0
	if wantShadow ~= shadowZone then
		buildShadow(wantShadow)
	end
	local f = fight
	fightFrame.Visible = f ~= nil
	fightBeam.Enabled = f ~= nil and shadowRoot ~= nil
	if f then
		fightName.Text = string.format("☀ %s — %d с", Config.Zones[f.zone].boss, math.ceil(f.timeLeft))
		hpFill.Size = UDim2.fromScale(math.clamp(f.hp / f.maxHp, 0, 1), 1)
		hpText.Text = "❤ " .. Config.format(math.max(0, f.hp)) .. " / " .. Config.format(f.maxHp)
	end

	updateBuildings(coins)
	updateSky()

	-- Окна
	if windows.relics.Visible then
		local found = 0
		for _, cell in ipairs(relicCells) do
			local e = d.relics[cell.relic.id]
			if e and e.n > 0 then
				found += 1
				cell.name.Text = (e.s > 0 and "🌟 " or "") .. cell.relic.name
				cell.name.TextColor3 = cell.relic.rarity.color
				cell.info.Text = string.format("×%d · +%d%%", e.n, math.floor(Config.relicBonus(cell.relic, e) * 100 + 0.5))
				cell.frame.BackgroundColor3 = CARD
			else
				cell.name.Text = "???"
				cell.name.TextColor3 = MUTED
				cell.info.Text = cell.relic.rarity.name
				cell.frame.BackgroundColor3 = CARD_DIM
			end
		end
		relicSummary.Text = string.format("Найдено %d из %d · всё вместе: сияние ×%s.\nОгоньки ✨ появляются на освещённой земле — подбеги, чтобы подобрать. Находки остаются навсегда.", found, #Config.Relics, Config.format(Config.relicMult(d)))
	end
	local rollCost = Config.titleRollCost(d)
	if windows.stars.Visible then
		local title = d.title and Config.TitleById[d.title]
		starCurrent.Text = title and ("✦ " .. title.name .. "  · сияние ×" .. tostring(title.mult)) or "✦ Небо пустое"
		starCurrent.TextColor3 = title and title.color or MUTED
		starInfo.Text = string.format("Поисков: %d · удача ×%s делит знаменатель · лучшее созвездие горит над маяком", d.rolls, Config.format(Config.luck(d)))
		rollBig.Text = "🔭 Искать — 💡 " .. Config.format(rollCost)
		rollBig.BackgroundColor3 = coins >= rollCost and VIOLET or BAD
		for _, row in ipairs(titleRows) do
			local n = d.titles[row.t.id] or 0
			row.frame.BackgroundColor3 = n > 0 and CARD or CARD_DIM
			row.owned.Text = (n > 0 and ("✓" .. n .. "  ") or "") .. "×" .. tostring(row.t.mult)
			row.owned.TextColor3 = n > 0 and row.t.color or MUTED
		end
	end
	local gain = Config.dustOnRebirth(d)
	dawnBadge.Visible = gain >= math.max(5, d.dustEver)
	if windows.dawn.Visible then
		dustLabel.Text = string.format("✦ %d звёздной пыли", d.dust)
		dawnInfo.Text = string.format(
			"Получено всего: %d → сияние +%d%% навсегда.\nЗаря открывается после %d-й тени. Гаснут свет, сияние, тени и постройки. Находки, созвездия и пыль остаются.",
			d.dustEver,
			math.floor(d.dustEver * Config.DUST_BONUS * 100 + 0.5),
			Config.REBIRTH_NEED_BOSSES
		)
		if os.clock() >= confirmUntil then
			dawnBtn.Text = gain >= 1 and string.format("🌅 Встретить зарю: +%d ✦", gain) or string.format("🔒 Изгони %d тени", Config.REBIRTH_NEED_BOSSES)
		end
		dawnBtn.BackgroundColor3 = gain >= 1 and Color3.fromRGB(200, 120, 40) or BAD
		autoLightToggle.Visible = Config.rlvl(d, "r_autolight") >= 1
		autoLightToggle.Text = d.autoLight and "🔥 Сам горит: ВКЛ" or "🔥 Сам горит: ВЫКЛ"
		autoLightToggle.BackgroundColor3 = d.autoLight and Color3.fromRGB(40, 110, 70) or PANEL
		autoPickToggle.Visible = Config.rlvl(d, "r_autopick") >= 1
		autoPickToggle.Text = d.autoPick and "🐝 Светлячки-сборщики: ВКЛ" or "🐝 Светлячки-сборщики: ВЫКЛ"
		autoPickToggle.BackgroundColor3 = d.autoPick and Color3.fromRGB(40, 110, 70) or PANEL
		for _, card in ipairs(rCards) do
			local lvl = Config.rlvl(d, card.r.id)
			card.lvl.Text = string.format("Уровень %d/%d", lvl, card.r.maxLevel)
			if lvl >= card.r.maxLevel then
				card.buy.Text = "МАКС"
				card.buy.BackgroundColor3 = WARM
				card.buy.TextColor3 = DARKTEXT
			else
				local cost = Config.rupCost(card.r, lvl)
				card.buy.Text = "✦ " .. cost
				card.buy.BackgroundColor3 = d.dust >= cost and GOOD or BAD
				card.buy.TextColor3 = WHITE
			end
		end
	end
end

task.spawn(function()
	while true do
		updateUI()
		task.wait(0.15)
	end
end)
RunService.Heartbeat:Connect(function(dt)
	if hasState then
		coinsLabel.Text = "💡 " .. Config.format(coinsNow())
	end
	local f = fight
	if f then
		f.timeLeft = math.max(0, f.timeLeft - dt)
	end
end)

--------------------------------------------------------------------------------
-- Сеть
--------------------------------------------------------------------------------
StateR.OnClientEvent:Connect(function(s: any)
	state.coins = s.coins
	state.totalCoins = s.totalCoins
	state.light = s.light
	state.bestLight = s.bestLight
	state.bosses = s.bosses
	state.ups = s.ups or {}
	state.relics = s.relics or {}
	state.titles = s.titles or {}
	state.title = s.title
	state.dust = s.dust
	state.dustEver = s.dustEver
	state.rebirths = s.rebirths
	state.rups = s.rups or {}
	state.picks = s.picks
	state.rolls = s.rolls
	state.playTime = s.playTime
	state.autoLight = s.autoLight
	state.autoPick = s.autoPick
	income = s.income
	fight = s.fight
	stateTime = os.clock()
	hasState = true
end)

EventR.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, dd: any, e: any)
	if kind == "pickupSpawn" then
		spawnPickup(a, b, c)
	elseif kind == "pickupsClear" then
		for token in pairs(pickups) do
			removePickup(token, false)
		end
	elseif kind == "relic" then
		removePickup(e, true)
		local relic = Config.RelicById[a]
		if relic then
			if dd and not c and relic.rarityIndex < 3 and not b then
				return
			end
			showRelic(relic, b, c)
		end
	elseif kind == "bossReached" then
		toast("👁 У края света ждёт " .. Config.Zones[a].boss, RED)
		playSound(SND_HIT, 0.5, 0.7)
	elseif kind == "newZone" then
		local z = Config.Zones[a]
		toast("🌄 Свет дошёл до новых земель: " .. z.name, z.accent)
		playSound(SND_WIN, 0.4, 1.1)
	elseif kind == "fightStart" then
		playSound(SND_HIT, 0.6)
		toast("☀ Луч маяка бьёт по тени!", WARM)
	elseif kind == "fightWon" then
		playSound(SND_WIN, 0.7)
		modal("☀ Тень изгнана!", string.format("%s растворилась в свете.\nНаграда: 💡 %s\n\nТьма отступит дальше — новые земли ждут.", Config.Zones[a].boss, Config.format(b)), "Дальше!", WARM)
	elseif kind == "fightLost" then
		playSound(SND_HIT, 0.5, 0.6)
		toast(string.format("Тень выстояла (осталось %d%%). Улучши Прожектор и попробуй снова", math.floor(b * 100 + 0.5)), RED)
	elseif kind == "title" then
		local t = Config.TitleById[a]
		if t then
			if b then
				playSound(SND_WIN, 0.6, 1.2)
				toast(string.format("✦ Новое созвездие: %s (%s) — сияние ×%s!", t.name, Config.formatChance(t.chance), tostring(t.mult)), t.color)
			else
				playSound(SND_PING, 0.3, 0.9)
				toast(string.format("🔭 %s (%s)", t.name, Config.formatChance(t.chance)), t.color)
			end
		end
	elseif kind == "upgraded" then
		local u = Config.UpById[a]
		playSound(SND_BUY, 0.5, 1.1)
		if u then
			toast(string.format("🔨 %s — ур. %d", u.name, b), u.color)
		end
	elseif kind == "rebirth" then
		playSound(SND_WIN, 0.7)
		modal("🌅 Новая заря!", string.format("Получено ✦ %d звёздной пыли.\nСвет погас, но теперь разгорится ярче. Загляни в окно «Заря» — там улучшения за пыль.", a), "Зажечь снова", WARM)
	elseif kind == "offline" then
		modal("С возвращением!", string.format("Пока тебя не было (%s), маяк светил сам:\n\n💡 %s", Config.formatTime(b), Config.format(a)), "Забрать")
	elseif kind == "welcome" then
		modal(
			"🗼 Маяк во Тьме",
			"Мир поглотила тьма. Твой маяк — последний свет.\n\nСтрой постройки у маяка, разжигай свет, чтобы тьма отступала, собирай огоньки-находки и изгоняй теней у края.",
			"Зажечь!"
		)
	elseif kind == "message" then
		toast(tostring(a), WARM)
	end
end)
