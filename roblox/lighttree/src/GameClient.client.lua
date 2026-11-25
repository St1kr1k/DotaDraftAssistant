-- Клиент: раскраска дерева, покупка стоянием на плитке, мосты, растущие центры островов,
-- падающие звёзды, интерфейс. Всё, что зависит от прогресса, рисуется только у себя.
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
local BuyR, TeleportR, ClaimR, StateR, EventR = R("Buy"), R("Teleport"), R("Claim"), R("State"), R("Event")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local worldFolder = workspace:WaitForChild("World")
local tilesFolder = worldFolder:WaitForChild("Tiles")
local linksFolder = worldFolder:WaitForChild("Links")

local mine = Instance.new("Folder")
mine.Name = "Mine"
mine.Parent = workspace

--------------------------------------------------------------------------------
-- Состояние
--------------------------------------------------------------------------------
local state: Config.Data = Config.newData()
local lps = 0
local stateTime = os.clock()
local hasState = false

local function curNow(c: string): number
	if c == "L" then
		return state.cur.L + lps * math.min(os.clock() - stateTime, 1)
	end
	return state.cur[c] or 0
end

-- Данные для расчётов с «живым» балансом
local function liveData(): Config.Data
	local d = table.clone(state)
	d.cur = table.clone(state.cur)
	d.cur.L = curNow("L")
	return d
end

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------
local BG = Color3.fromRGB(16, 15, 26)
local GOLD = Color3.fromRGB(255, 205, 90)
local GREEN = Color3.fromRGB(110, 240, 140)
local REDT = Color3.fromRGB(255, 130, 130)
local MUTED = Color3.fromRGB(170, 168, 190)
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
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function label(props: { [string]: any }): TextLabel
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	props.Font = props.Font or Enum.Font.FredokaOne
	props.TextColor3 = props.TextColor3 or WHITE
	return new("TextLabel", props)
end
local function button(props: { [string]: any }, children: { Instance }?): TextButton
	props.Font = props.Font or Enum.Font.FredokaOne
	props.TextColor3 = props.TextColor3 or WHITE
	props.AutoButtonColor = true
	return new("TextButton", props, children)
end
local function pop(inst: GuiObject, from: number?)
	local sc = inst:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = inst })
	sc.Scale = from or 0.9
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end
local function playSound(id: string, volume: number, pitch: number?)
	local s = new("Sound", { SoundId = id, Volume = volume, PlaybackSpeed = pitch or 1, Parent = SoundService })
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end
local SND_BUY = "rbxasset://sounds/electronicpingshort.wav"
local SND_CLICK = "rbxasset://sounds/button.wav"
local SND_WIN = "rbxasset://sounds/victory.wav"

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
	new("PointLight", { Color = color, Range = range, Brightness = brightness, Parent = parent })
end

--------------------------------------------------------------------------------
-- Плитки
--------------------------------------------------------------------------------
type Tile = {
	node: Config.Node,
	part: BasePart,
	border: BasePart,
	bg: Frame,
	stroke: UIStroke,
	icon: TextLabel,
	title: TextLabel,
	level: TextLabel,
	desc: TextLabel,
	cost: TextLabel,
	burst: ParticleEmitter,
	status: string,
}
local tiles: { [string]: Tile } = {}
for _, n in ipairs(Config.Nodes) do
	local p = tilesFolder:WaitForChild("Tile_" .. n.id) :: BasePart
	local card = p:WaitForChild("Card") :: BillboardGui
	local bg = card:WaitForChild("Bg") :: Frame
	local isl = Config.IslandById[n.island]
	local burst = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(isl.color),
		Size = NumberSequence.new(1.2, 0),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Rate = 0,
		Parent = p,
	})
	tiles[n.id] = {
		node = n,
		part = p,
		border = p:WaitForChild("Border") :: BasePart,
		bg = bg,
		stroke = bg:WaitForChild("Stroke") :: UIStroke,
		icon = bg:WaitForChild("Icon") :: TextLabel,
		title = bg:WaitForChild("Title") :: TextLabel,
		level = bg:WaitForChild("Level") :: TextLabel,
		desc = bg:WaitForChild("Desc") :: TextLabel,
		cost = bg:WaitForChild("Cost") :: TextLabel,
		burst = burst,
		status = "",
	}
end

type Link = { part: BasePart, from: string, color: Color3 }
local links: { Link } = {}
for _, l in ipairs(linksFolder:GetChildren()) do
	if l:IsA("BasePart") then
		local from = l:GetAttribute("From")
		local to = l:GetAttribute("To")
		if typeof(from) == "string" and typeof(to) == "string" then
			local n = Config.NodeById[to]
			table.insert(links, { part = l, from = from, color = Config.IslandById[n.island].color })
		end
	end
end

local function rateOf(c: string): number
	if c == "L" then
		return lps
	elseif c == "Z" then
		return Config.passiveZ(state) * Config.gainZ(state)
	elseif c == "S" then
		return Config.passiveS(state) * Config.gainS(state)
	end
	return 0
end

local CUR_ICON = { L = "💡", Z = "🌅", S = "✦", E = "🌑" }

local function paintTiles()
	local d = liveData()
	local t = os.clock()
	for id, tile in pairs(tiles) do
		local n = tile.node
		local isl = Config.IslandById[n.island]
		local lvl = Config.lvl(d, id)
		local open = Config.islandOpen(d, n.island)
		local available = open and Config.isAvailable(d, n)
		local status: string
		if lvl >= n.max then
			status = "max"
		elseif not available then
			status = "locked"
		elseif Config.canBuy(d, n) then
			status = "afford"
		else
			status = "wait"
		end
		local icon = CUR_ICON[n.island]
		if status ~= tile.status then
			tile.status = status
			if status == "max" then
				tile.part.Color = isl.color:Lerp(WHITE, 0.2)
				tile.part.Material = Enum.Material.Neon
				tile.border.Color = GOLD
				tile.border.Transparency = 0
				tile.stroke.Color = GOLD
				tile.bg.BackgroundTransparency = 0.15
				tile.icon.TextTransparency = 0
				tile.title.TextColor3 = GOLD
			elseif status == "locked" then
				tile.part.Color = Color3.fromRGB(40, 40, 48)
				tile.part.Material = Enum.Material.SmoothPlastic
				tile.border.Color = Color3.fromRGB(60, 60, 70)
				tile.border.Transparency = 0.6
				tile.stroke.Color = Color3.fromRGB(60, 60, 70)
				tile.bg.BackgroundTransparency = 0.45
				tile.icon.TextTransparency = 0.6
				tile.title.TextColor3 = MUTED
			else
				tile.part.Color = lvl > 0 and isl.color:Lerp(Color3.new(0, 0, 0), 0.35) or isl.dark
				tile.part.Material = lvl > 0 and Enum.Material.Neon or Enum.Material.SmoothPlastic
				tile.border.Color = isl.color
				tile.border.Transparency = 0
				tile.stroke.Color = isl.color
				tile.bg.BackgroundTransparency = 0.15
				tile.icon.TextTransparency = 0
				tile.title.TextColor3 = WHITE
			end
		end
		-- текст
		tile.level.Text = n.max > 1 and string.format("ур. %d / %d", lvl, n.max) or (lvl > 0 and "куплено" or "")
		if status == "max" then
			tile.cost.Text = "★ МАКС"
			tile.cost.TextColor3 = GOLD
		elseif status == "locked" then
			tile.cost.Text = open and "🔒 купи соседнюю" or ("🔒 остров закрыт")
			tile.cost.TextColor3 = MUTED
		else
			local cost = Config.nodeCost(d, n)
			if status == "afford" then
				tile.cost.Text = string.format("%s %s ⬇ встань", icon, Config.format(cost))
				tile.cost.TextColor3 = GREEN
				local pulse = (math.sin(t * 6) + 1) / 2
				tile.border.Transparency = pulse * 0.6
			else
				local rate = rateOf(n.island)
				local need = cost - (d.cur[n.island] or 0)
				local eta = rate > 0 and string.format(" · %s", Config.formatTime(need / rate)) or ""
				tile.cost.Text = string.format("%s %s%s", icon, Config.format(cost), eta)
				tile.cost.TextColor3 = REDT
				tile.border.Transparency = 0.35
			end
		end
	end
	for _, link in ipairs(links) do
		local on = Config.lvl(d, link.from) > 0
		link.part.Color = on and link.color or Color3.fromRGB(55, 55, 65)
		link.part.Transparency = on and 0 or 0.4
	end
end

--------------------------------------------------------------------------------
-- Покупка: встань на плитку
--------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { tilesFolder }
local pendingUntil = 0
local standingOn: string? = nil

task.spawn(function()
	while true do
		task.wait(0.12)
		standingOn = nil
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and hasState then
			local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), rayParams)
			if hit and hit.Instance then
				local id = hit.Instance:GetAttribute("Node")
				if typeof(id) == "string" then
					standingOn = id
					local n = Config.NodeById[id]
					if n and os.clock() > pendingUntil and Config.canBuy(liveData(), n) then
						pendingUntil = os.clock() + 0.3
						BuyR:FireServer(id)
					end
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Мосты между островами
--------------------------------------------------------------------------------
local bridges: { [string]: Model } = {}
local function buildBridge(fromId: string, toId: string): Model
	local a = Config.IslandById[fromId]
	local b = Config.IslandById[toId]
	local dir = (b.center - a.center)
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local p0 = a.center + flat * (a.radius - 2)
	local p1 = b.center - flat * (b.radius - 2)
	local m = Instance.new("Model")
	m.Name = "Bridge_" .. toId
	local segs = 18
	for i = 0, segs - 1 do
		local t0, t1 = i / segs, (i + 1) / segs
		local q0 = p0:Lerp(p1, t0)
		local q1 = p0:Lerp(p1, t1)
		local mid = (q0 + q1) / 2
		local len = (q1 - q0).Magnitude + 0.3
		local cf = CFrame.lookAt(mid, q1)
		wpart(m, { Size = Vector3.new(10, 0.8, len), CFrame = cf * CFrame.new(0, -0.4, 0), Color = Color3.fromRGB(70, 62, 80), Material = Enum.Material.WoodPlanks, CanCollide = true, CastShadow = true })
		for _, side in ipairs({ -1, 1 }) do
			wpart(m, { Size = Vector3.new(0.5, 0.5, len), CFrame = cf * CFrame.new(side * 5, 2.2, 0), Color = b.color, Material = Enum.Material.Neon })
			if i % 3 == 0 then
				wpart(m, { Size = Vector3.new(0.4, 2.4, 0.4), CFrame = cf * CFrame.new(side * 5, 1, 0), Color = Color3.fromRGB(50, 46, 60), Material = Enum.Material.Metal, CanCollide = true })
			end
		end
	end
	m.Parent = mine
	return m
end
local BRIDGES = { { "L", "Z" }, { "Z", "S" }, { "S", "E" } }

--------------------------------------------------------------------------------
-- Растущие центры островов
--------------------------------------------------------------------------------
local centerpieces = Instance.new("Folder")
centerpieces.Name = "Centerpieces"
centerpieces.Parent = mine
type Spin = { part: BasePart, base: CFrame, speed: number, axis: string, phase: number }
local spins: { Spin } = {}

-- Маяк: этажи растут с уровнями на острове Маяк
local lighthouseModel: Model? = nil
local lighthouseFloors = -1
local beamEnds: { BasePart } = {}
local lampPart: BasePart? = nil
local function buildLighthouse(floors: number)
	if lighthouseModel then
		lighthouseModel:Destroy()
	end
	table.clear(beamEnds)
	local m = Instance.new("Model")
	m.Name = "Lighthouse"
	local base = Config.Islands[1].center + Config.LIGHTHOUSE_POS
	local y = 5.5
	for i = 1, floors do
		local d = math.max(5, 11 - i * 0.35)
		wpart(m, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(4, d, d),
			CFrame = CFrame.new(base + Vector3.new(0, y + 2, 0)) * A(0, 0, 90),
			Color = i % 2 == 0 and Color3.fromRGB(205, 60, 55) or Color3.fromRGB(240, 238, 230),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			CastShadow = true,
		})
		if i % 3 == 0 then
			wpart(m, { Size = Vector3.new(0.3, 1.6, 1.2), CFrame = CFrame.new(base + Vector3.new(d / 2 + 0.05, y + 2, 0)), Color = GOLD, Material = Enum.Material.Neon })
		end
		y += 4
	end
	local top = math.max(5, 11 - floors * 0.35)
	wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, top + 3, top + 3), CFrame = CFrame.new(base + Vector3.new(0, y + 0.4, 0)) * A(0, 0, 90), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Metal })
	wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.5, top, top), CFrame = CFrame.new(base + Vector3.new(0, y + 3, 0)) * A(0, 0, 90), Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 0.6 })
	local lampSize = 2 + floors * 0.25
	local lamp = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * lampSize, CFrame = CFrame.new(base + Vector3.new(0, y + 3, 0)), Color = Color3.fromRGB(255, 240, 190), Material = Enum.Material.Neon })
	wlight(lamp, Color3.fromRGB(255, 225, 160), 30 + floors * 3, 2 + floors * 0.15)
	wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, top + 1, top + 1), CFrame = CFrame.new(base + Vector3.new(0, y + 5.8, 0)) * A(0, 0, 90), Color = Color3.fromRGB(205, 60, 55) })
	wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(base + Vector3.new(0, y + 6.8, 0)), Color = Color3.fromRGB(205, 60, 55) })
	local att0 = new("Attachment", { Parent = lamp })
	for i = 1, 2 do
		local e = wpart(m, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(base) })
		local att1 = new("Attachment", { Parent = e })
		new("Beam", {
			Attachment0 = att0,
			Attachment1 = att1,
			Color = ColorSequence.new(Color3.fromRGB(255, 235, 170)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 1,
			Width0 = lampSize * 0.7,
			Width1 = 10 + floors * 1.5,
			FaceCamera = true,
			Segments = 2,
			Parent = lamp,
		})
		table.insert(beamEnds, e)
	end
	lampPart = lamp
	m.Parent = centerpieces
	lighthouseModel = m
end

-- Солнце Зари
local sunModel: Model? = nil
local sunLevel = -1
local function buildSun(levels: number)
	if sunModel then
		sunModel:Destroy()
	end
	local isl = Config.IslandById.Z
	local m = Instance.new("Model")
	m.Name = "Sun"
	local base = isl.center + Vector3.new(-36, 0, -12)
	local h = 8 + math.min(levels, 40) * 1.2
	local size = 5 + math.min(levels, 40) * 0.35
	local sun = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(base + Vector3.new(0, h, 0)), Color = Color3.fromRGB(255, 150, 70), Material = Enum.Material.Neon })
	wlight(sun, Color3.fromRGB(255, 170, 100), 40 + levels * 2, 3)
	local halo = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * (size * 1.5), CFrame = sun.CFrame, Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.ForceField, Transparency = 0.2 })
	local _ = halo
	for i = 1, math.min(8 + levels, 24) do
		local a = i / math.min(8 + levels, 24) * 360
		local ray = wpart(m, { Size = Vector3.new(0.5, size * 0.7, 0.5), CFrame = sun.CFrame * A(0, 0, a) * CFrame.new(0, size * 0.95, 0), Color = Color3.fromRGB(255, 210, 110), Material = Enum.Material.Neon })
		table.insert(spins, { part = ray, base = ray.CFrame, speed = 0.2, axis = "sun", phase = 0 })
	end
	wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 14, 14), CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)) * A(0, 0, 90), Color = Color3.fromRGB(120, 70, 55), Material = Enum.Material.Sandstone, CanCollide = true })
	m:SetAttribute("Center", sun.Position)
	m.Parent = centerpieces
	sunModel = m
end

-- Звёзды
local starsModel: Model? = nil
local starsLevel = -1
local function buildStars(levels: number)
	if starsModel then
		starsModel:Destroy()
	end
	local isl = Config.IslandById.S
	local m = Instance.new("Model")
	m.Name = "Stars"
	local base = isl.center + Vector3.new(-32, 18, -10)
	local count = math.min(5 + levels * 2, 70)
	local rng = Random.new(77)
	local prev: Attachment? = nil
	for i = 1, count do
		local p = base + Vector3.new(rng:NextNumber(-16, 16), rng:NextNumber(-8, 14), rng:NextNumber(-16, 16))
		local s = rng:NextNumber(0.8, 2)
		local star = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = CFrame.new(p), Color = isl.color:Lerp(WHITE, rng:NextNumber(0, 0.7)), Material = Enum.Material.Neon })
		table.insert(spins, { part = star, base = star.CFrame, speed = 1, axis = "bob", phase = rng:NextNumber(0, 6) })
		if i <= 10 then
			local att = new("Attachment", { Parent = star })
			if prev then
				new("Beam", { Attachment0 = prev, Attachment1 = att, Color = ColorSequence.new(isl.color), Transparency = NumberSequence.new(0.5), LightEmission = 1, Width0 = 0.25, Width1 = 0.25, FaceCamera = true, Parent = star })
			end
			prev = att
		end
		if i % 8 == 1 then
			wlight(star, isl.color, 20, 1)
		end
	end
	m.Parent = centerpieces
	starsModel = m
end

-- Затмение
local eclipseModel: Model? = nil
local eclipseLevel = -1
local function buildEclipse(levels: number)
	if eclipseModel then
		eclipseModel:Destroy()
	end
	local isl = Config.IslandById.E
	local m = Instance.new("Model")
	m.Name = "Eclipse"
	local center = isl.center + Vector3.new(-28, 22, -8)
	local size = 10 + levels * 0.8
	local corona = wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * (size * 1.15), CFrame = CFrame.new(center + Vector3.new(0, 0, 0.5)), Color = WHITE, Material = Enum.Material.Neon })
	wlight(corona, Color3.fromRGB(220, 220, 255), 60, 2)
	wpart(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(center + Vector3.new(0, 0, -1)), Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
	for i = 1, math.min(1 + levels, 8) do
		local ring = wpart(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, size * (1.4 + i * 0.25), size * (1.4 + i * 0.25)), CFrame = CFrame.new(center) * A(i * 25, i * 40, 0), Color = WHITE, Material = Enum.Material.ForceField })
		table.insert(spins, { part = ring, base = ring.CFrame, speed = 0.3 + i * 0.05, axis = "tumble", phase = i })
	end
	m.Parent = centerpieces
	eclipseModel = m
end

local function clearSpinsOf(model: Model?)
	if not model then
		return
	end
	for i = #spins, 1, -1 do
		if spins[i].part:IsDescendantOf(model) then
			table.remove(spins, i)
		end
	end
end

local function updateWorld()
	local d = state
	-- маяк
	local floors = math.min(2 + math.floor(Config.islandLevels(d, "L") / 5), 16)
	if floors ~= lighthouseFloors then
		local grew = lighthouseFloors >= 0 and floors > lighthouseFloors
		lighthouseFloors = floors
		buildLighthouse(floors)
		if grew then
			playSound(SND_CLICK, 0.4, 0.8)
		end
	end
	-- острова
	if Config.islandOpen(d, "Z") then
		local lv = Config.islandLevels(d, "Z")
		if lv ~= sunLevel then
			clearSpinsOf(sunModel)
			sunLevel = lv
			buildSun(lv)
		end
	end
	if Config.islandOpen(d, "S") then
		local lv = Config.islandLevels(d, "S")
		if lv ~= starsLevel then
			clearSpinsOf(starsModel)
			starsLevel = lv
			buildStars(lv)
		end
	end
	if Config.islandOpen(d, "E") then
		local lv = Config.islandLevels(d, "E")
		if lv ~= eclipseLevel then
			clearSpinsOf(eclipseModel)
			eclipseLevel = lv
			buildEclipse(lv)
		end
	end
	-- мосты
	for _, b in ipairs(BRIDGES) do
		local open = Config.islandOpen(d, b[2])
		if open and not bridges[b[2]] then
			bridges[b[2]] = buildBridge(b[1], b[2])
		elseif not open and bridges[b[2]] then
			bridges[b[2]]:Destroy()
			bridges[b[2]] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Алтари
--------------------------------------------------------------------------------
type AltarUI = { layer: string, sub: TextLabel, prompt: ProximityPrompt, model: Instance }
local altars: { AltarUI } = {}
for _, layer in ipairs({ "Z", "S", "E" }) do
	local model = worldFolder:WaitForChild("Altar_" .. layer)
	local orb = model:WaitForChild("Orb")
	local info = orb:WaitForChild("Info")
	table.insert(altars, { layer = layer, sub = info:WaitForChild("Sub") :: TextLabel, prompt = orb:WaitForChild("ProximityPrompt") :: ProximityPrompt, model = model })
end
local GAIN = { Z = Config.gainZ, S = Config.gainS, E = Config.gainE }
local function updateAltars()
	for _, a in ipairs(altars) do
		local open = Config.islandOpen(state, a.layer)
		local gain = open and GAIN[a.layer](state) or 0
		if not open then
			a.sub.Text = "🔒 купи мост в дереве"
			a.sub.TextColor3 = MUTED
		elseif gain < 1 then
			a.sub.Text = "Копи дальше — пока +0"
			a.sub.TextColor3 = REDT
		else
			a.sub.Text = string.format("Удерживай E: +%s %s", Config.format(gain), CUR_ICON[a.layer])
			a.sub.TextColor3 = GREEN
		end
		a.prompt.Enabled = open and gain >= 1
		a.prompt.ObjectText = string.format("+%s %s · сброс", Config.format(gain), CUR_ICON[a.layer])
	end
end

--------------------------------------------------------------------------------
-- Падающая звезда
--------------------------------------------------------------------------------
local golden: { token: string, part: BasePart, pos: Vector3 }? = nil
local function removeGolden(burst: boolean)
	local g = golden
	if not g then
		return
	end
	golden = nil
	if burst then
		local e = g.part:FindFirstChildOfClass("ParticleEmitter")
		if e then
			e:Emit(60)
		end
		TweenService:Create(g.part, TweenInfo.new(0.4), { Size = Vector3.new(8, 8, 8), Transparency = 1 }):Play()
		task.delay(1, function()
			g.part:Destroy()
		end)
	else
		g.part:Destroy()
	end
end
local function spawnGolden(token: string, pos: Vector3)
	removeGolden(false)
	local star = wpart(mine, { Name = "FallingStar", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(pos + Vector3.new(0, 60, 0)), Color = GOLD, Material = Enum.Material.Neon })
	wlight(star, GOLD, 22, 3)
	new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(GOLD),
		Size = NumberSequence.new(1, 0),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 25,
		Parent = star,
	})
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(160, 40), StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 500, Adornee = star, Parent = star })
	label({ Size = UDim2.fromScale(1, 1), Text = "⭐ Лови!", TextScaled = true, TextColor3 = GOLD, TextStrokeTransparency = 0.2, Parent = bb })
	TweenService:Create(star, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(pos) }):Play()
	golden = { token = token, part = star, pos = pos }
	playSound(SND_BUY, 0.5, 1.6)
end
task.spawn(function()
	while true do
		task.wait(0.15)
		local g = golden
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if g and root and (root.Position - g.pos).Magnitude < 7 then
			ClaimR:FireServer(g.token)
			task.wait(0.5)
		end
	end
end)

--------------------------------------------------------------------------------
-- Анимации
--------------------------------------------------------------------------------
local beamAngle = 0
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	beamAngle += dt * 0.6
	local lamp = lampPart
	if lamp then
		for i, e in ipairs(beamEnds) do
			local a = beamAngle + (i - 1) * math.pi
			e.CFrame = CFrame.new(lamp.Position + Vector3.new(math.cos(a) * 140, -lamp.Position.Y + 2, math.sin(a) * 140))
		end
	end
	for _, s in ipairs(spins) do
		if s.axis == "bob" then
			s.part.CFrame = s.base * CFrame.new(0, math.sin(t * s.speed + s.phase) * 0.6, 0)
		elseif s.axis == "tumble" then
			s.part.CFrame = s.base * CFrame.Angles(t * s.speed + s.phase, t * s.speed * 0.6, 0)
		elseif s.axis == "sun" then
			local c = sunModel and sunModel:GetAttribute("Center")
			if typeof(c) == "Vector3" then
				local pv = CFrame.new(c)
				s.part.CFrame = pv * CFrame.Angles(0, 0, t * s.speed) * pv:Inverse() * s.base
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Интерфейс
--------------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "TreeUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
local uiScale = new("UIScale", { Parent = gui })
local function updateScale()
	local cam = workspace.CurrentCamera
	if cam then
		uiScale.Scale = math.clamp(math.min(cam.ViewportSize.Y / 950, cam.ViewportSize.X / 1500), 0.55, 1.2)
	end
end
updateScale()
local cam0 = workspace.CurrentCamera
if cam0 then
	cam0:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- Валюты слева
local curFrame = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.42, 0), Size = UDim2.fromOffset(380, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui }, {
	new("UIListLayout", { Padding = UDim.new(0, 8) }),
})
type CurRow = { frame: Frame, amount: TextLabel, rate: TextLabel, id: string }
local curRows: { CurRow } = {}
for _, isl in ipairs(Config.Islands) do
	local f = new("Frame", { Size = UDim2.fromOffset(380, 58), BackgroundColor3 = Color3.fromRGB(10, 10, 16), BackgroundTransparency = 0.15, Visible = isl.id == "L", Parent = curFrame }, { corner(12), stroke(isl.color, 2.5) })
	label({ Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(52, 58), Text = isl.icon, TextSize = 36, TextColor3 = isl.color, Parent = f })
	local amount = label({ Position = UDim2.fromOffset(64, 4), Size = UDim2.new(1, -74, 0, 30), Text = "0", TextSize = 28, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = isl.color, Parent = f })
	local rate = label({ Position = UDim2.fromOffset(64, 33), Size = UDim2.new(1, -74, 0, 20), Text = "", TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = MUTED, Parent = f })
	table.insert(curRows, { frame = f, amount = amount, rate = rate, id = isl.id })
end

-- Цель сверху
local goal = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(10, 10, 16), BackgroundTransparency = 0.2, Parent = gui }, {
	corner(14),
	stroke(GOLD, 2, 0.3),
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
})
local goalText = label({ Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 20, Parent = goal })
local goalBarBg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(360, 8), BackgroundColor3 = Color3.fromRGB(10, 10, 16), BackgroundTransparency = 0.2, Parent = gui }, { corner(4) })
local goalBar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, Parent = goalBarBg }, { corner(4) })

-- Острова снизу
local bottom = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(0, 62), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Parent = gui }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }),
})
type IslandBtn = { button: TextButton, id: string }
local islandBtns: { IslandBtn } = {}
for _, isl in ipairs(Config.Islands) do
	local b = button({ Size = UDim2.fromOffset(170, 62), BackgroundColor3 = isl.color, Text = isl.icon .. " " .. isl.name, TextSize = 24, TextColor3 = Color3.fromRGB(20, 18, 28), Parent = bottom }, { corner(14), stroke(Color3.new(0, 0, 0), 3) })
	b.Activated:Connect(function()
		if Config.islandOpen(state, isl.id) then
			TeleportR:FireServer(isl.id)
			playSound(SND_CLICK, 0.4, 1.2)
		else
			pop(b, 0.9)
		end
	end)
	table.insert(islandBtns, { button = b, id = isl.id })
end

-- Сообщения
local toastHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 82), Size = UDim2.fromOffset(600, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui }, {
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
})
local function toast(text: string, color: Color3?)
	local t = label({ Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.15, BackgroundColor3 = BG, Text = "  " .. text .. "  ", TextSize = 20, TextColor3 = color or GOLD, Parent = toastHolder })
	corner(12).Parent = t
	stroke(color or GOLD, 2, 0.3).Parent = t
	pop(t, 0.6)
	task.delay(3, function()
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
	if #labels > 4 then
		labels[1]:Destroy()
	end
end

local function modal(title: string, body: string, buttonText: string, color: Color3?)
	local shade = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = 50, Parent = gui })
	local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 300), BackgroundColor3 = BG, ZIndex = 51, Parent = shade }, { corner(22), stroke(color or GOLD, 3) })
	label({ Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 44), Text = title, TextSize = 32, TextColor3 = color or GOLD, ZIndex = 52, Parent = box })
	label({ Position = UDim2.fromOffset(26, 68), Size = UDim2.new(1, -52, 0, 150), Text = body, TextSize = 18, TextWrapped = true, Font = Enum.Font.GothamBold, ZIndex = 52, Parent = box })
	local ok = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(230, 54), BackgroundColor3 = Color3.fromRGB(70, 190, 100), Text = buttonText, TextSize = 24, ZIndex = 52, Parent = box }, { corner(14) })
	pop(box, 0.6)
	ok.Activated:Connect(function()
		shade:Destroy()
	end)
end

local function flash(color: Color3)
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0.2, ZIndex = 45, Parent = gui })
	TweenService:Create(f, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	task.delay(1.3, function()
		f:Destroy()
	end)
end

-- Всплывающая надпись над плиткой
local function floatText(adornee: BasePart, text: string, color: Color3)
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(200, 50), StudsOffsetWorldSpace = Vector3.new(0, 7, 0), AlwaysOnTop = true, LightInfluence = 0, Adornee = adornee, Parent = playerGui })
	local t = label({ Size = UDim2.fromScale(1, 1), Text = text, TextScaled = true, TextColor3 = color, TextStrokeTransparency = 0.1, Parent = bb })
	local info = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { StudsOffsetWorldSpace = Vector3.new(0, 12, 0) }):Play()
	TweenService:Create(t, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.1, function()
		bb:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Цель
--------------------------------------------------------------------------------
local function currentGoal(d: Config.Data): (string, number)
	-- сначала: можно переродиться с хорошим приростом
	for i = #altars, 1, -1 do
		local a = altars[i]
		if Config.islandOpen(d, a.layer) then
			local g = GAIN[a.layer](d)
			local have = d.cur[a.layer] or 0
			if g >= 1 and g >= math.max(1, have) then
				local isl = Config.IslandById[a.layer]
				return string.format("🎯 Переродись на алтаре: +%s %s (удвоишь %s)", Config.format(g), isl.icon, isl.name), 1
			end
		end
	end
	-- иначе: самый дешёвый новый узел
	local best: Config.Node? = nil
	local bestEta = math.huge
	for _, n in ipairs(Config.Nodes) do
		if Config.lvl(d, n.id) == 0 and Config.islandOpen(d, n.island) and Config.isAvailable(d, n) then
			local cost = Config.nodeCost(d, n)
			local rate = rateOf(n.island)
			local have = d.cur[n.island] or 0
			local eta = have >= cost and 0 or (rate > 0 and (cost - have) / rate or math.huge)
			if n.kind == "unlock" then
				eta *= 0.5 -- мосты в приоритете
			end
			if eta < bestEta then
				best, bestEta = n, eta
			end
		end
	end
	if best then
		local b = best :: Config.Node
		local cost = Config.nodeCost(d, b)
		local have = d.cur[b.island] or 0
		local isl = Config.IslandById[b.island]
		if have >= cost then
			return string.format("🎯 Встань на «%s %s» (%s) — уже хватает!", b.icon, b.name, isl.name), 1
		end
		return string.format("🎯 Цель: %s %s — %s %s", b.icon, b.name, CUR_ICON[b.island], Config.format(cost)), math.clamp(have / cost, 0, 1)
	end
	return "🎯 Качай уровни на плитках и копи на перерождение", 0
end

--------------------------------------------------------------------------------
-- Обновление
--------------------------------------------------------------------------------
local function updateUI()
	if not hasState then
		return
	end
	local d = liveData()
	for _, row in ipairs(curRows) do
		local open = Config.islandOpen(d, row.id) or (d.total[row.id] or 0) > 0
		row.frame.Visible = open
		if open then
			row.amount.Text = Config.format(d.cur[row.id] or 0)
			local rate = rateOf(row.id)
			local gain = GAIN[row.id] and GAIN[row.id](d) or 0
			if row.id == "L" then
				row.rate.Text = "+" .. Config.format(rate) .. "/с"
			elseif rate > 0 then
				row.rate.Text = string.format("+%s/с · сброс +%s", Config.format(rate), Config.format(gain))
			else
				row.rate.Text = string.format("сброс даст +%s", Config.format(gain))
			end
		end
	end
	local text, progress = currentGoal(d)
	goalText.Text = text
	goalBar.Size = UDim2.fromScale(progress, 1)
	for _, ib in ipairs(islandBtns) do
		local open = Config.islandOpen(d, ib.id)
		local isl = Config.IslandById[ib.id]
		ib.button.Text = (open and isl.icon or "🔒") .. " " .. isl.name
		ib.button.BackgroundColor3 = open and isl.color or Color3.fromRGB(60, 58, 70)
		ib.button.TextColor3 = open and Color3.fromRGB(20, 18, 28) or MUTED
	end
	updateAltars()
end

task.spawn(function()
	while true do
		if hasState then
			paintTiles()
			updateUI()
		end
		task.wait(0.1)
	end
end)
RunService.Heartbeat:Connect(function()
	if hasState then
		curRows[1].amount.Text = Config.format(curNow("L"))
	end
end)

--------------------------------------------------------------------------------
-- Сеть
--------------------------------------------------------------------------------
StateR.OnClientEvent:Connect(function(s: any)
	state.cur = s.cur
	state.run = s.run
	state.total = s.total
	state.nodes = s.nodes or {}
	state.resets = s.resets
	state.golden = s.golden
	state.playTime = s.playTime
	lps = s.lps
	stateTime = os.clock()
	local first = not hasState
	hasState = true
	updateWorld()
	if first then
		paintTiles()
	end
end)

local streak = 0
local lastBuy = 0
EventR.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
	if kind == "bought" then
		local tile = tiles[a]
		pendingUntil = 0
		if os.clock() - lastBuy < 1.5 then
			streak = math.min(streak + 1, 12)
		else
			streak = 0
		end
		lastBuy = os.clock()
		playSound(SND_BUY, 0.45, 1 + streak * 0.06)
		if tile then
			tile.burst:Emit(18)
			local n = tile.node
			local isl = Config.IslandById[n.island]
			floatText(tile.part, n.max > 1 and string.format("%s ур. %d", n.icon, b) or (n.icon .. " куплено!"), isl.color)
			tile.status = "" -- перекрасить сразу
			if n.max > 1 and b == n.max then
				toast("★ " .. n.name .. " — максимум!", GOLD)
			elseif b == 1 then
				toast(n.icon .. " " .. n.name .. ": " .. n.desc, isl.color)
			end
		end
	elseif kind == "islandOpen" then
		local isl = Config.IslandById[a]
		playSound(SND_WIN, 0.6)
		flash(isl.color)
		modal(isl.icon .. " Открыт остров " .. isl.name .. "!", "По мосту можно дойти пешком или нажать кнопку острова внизу.\n\nНа его алтаре перерождение даёт новую валюту — она усиливает всё, что было до неё.", "Вперёд!", isl.color)
	elseif kind == "prestige" then
		local isl = Config.IslandById[a]
		playSound(SND_WIN, 0.7, 1.1)
		flash(isl.color)
		toast(string.format("%s %s! +%s %s", isl.icon, isl.name, Config.format(b), isl.icon), isl.color)
	elseif kind == "newLayer" then
		local isl = Config.IslandById[a]
		modal(
			isl.icon .. " Первая " .. isl.name .. "!",
			string.format("Ты получил %s и новый тег над головой.\n\nТрать %s на острове %s — дерево там делает всё предыдущее в разы сильнее, а потом и автоматизирует.", isl.icon, isl.icon, isl.name),
			"Круто!",
			isl.color
		)
	elseif kind == "goldenSpawn" then
		spawnGolden(a, b)
		toast("⭐ Падающая звезда рядом — беги и лови!", GOLD)
	elseif kind == "goldenGone" then
		removeGolden(false)
	elseif kind == "golden" then
		removeGolden(true)
		playSound(SND_WIN, 0.5, 1.3)
		toast("⭐ Звезда поймана! +" .. Config.format(a) .. " 💡", GOLD)
	elseif kind == "offline" then
		local extra = (c and c >= 1) and string.format("\n🌅 +%s", Config.format(c)) or ""
		modal("С возвращением!", string.format("Пока тебя не было (%s), маяк светил сам:\n\n💡 +%s%s", Config.formatTime(b), Config.format(a), extra), "Забрать")
	elseif kind == "welcome" then
		modal(
			"🗼 Маяк",
			"Свет копится сам. Встань на светящуюся плитку дерева — она купится.\n\nКаждая плитка усиливает свет и открывает следующие. Дойди до моста к Заре — и начнётся настоящее.",
			"Играть!"
		)
	elseif kind == "message" then
		toast(tostring(a), GOLD)
	end
end)
