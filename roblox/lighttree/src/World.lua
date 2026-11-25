-- Общий мир: парящие острова, плитки дерева, связи, алтари, табло.
-- Состояние плиток (куплено/доступно/цена) каждый клиент раскрашивает сам.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local World = {}

local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function disc(parent: Instance, pos: Vector3, height: number, diameter: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(pos) * A(0, 0, 90)
	return part(parent, props)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	for k, v in pairs(props) do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

--------------------------------------------------------------------------------
-- Остров
--------------------------------------------------------------------------------
local TOP_MAT = { Enum.Material.Grass, Enum.Material.Sand, Enum.Material.Slate, Enum.Material.Basalt }
local TOP_COLOR = {
	Color3.fromRGB(84, 130, 72),
	Color3.fromRGB(205, 140, 110),
	Color3.fromRGB(70, 68, 110),
	Color3.fromRGB(35, 34, 44),
}

local function buildIsland(isl: Config.Island, root: Instance): Model
	local m = Instance.new("Model")
	m.Name = "Island_" .. isl.id
	local c = isl.center
	local R = isl.radius
	-- Верх
	disc(m, c + Vector3.new(0, -1, 0), 2, R * 2, { Name = "Top", Color = TOP_COLOR[isl.index], Material = TOP_MAT[isl.index] })
	disc(m, c + Vector3.new(0, -3.2, 0), 2.6, R * 2 + 1.5, { Name = "Edge", Color = Color3.fromRGB(110, 92, 75), Material = Enum.Material.Ground })
	disc(m, c + Vector3.new(0, -0.05, 0), 0.25, R * 2 + 2.2, { Name = "Rim", Color = isl.color, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })
	-- Скала снизу: сужающиеся слои
	local rng = Random.new(isl.index * 31)
	local y = -4.5
	local r = R * 0.98
	local rockColor = Color3.fromRGB(95, 85, 80):Lerp(isl.dark, 0.35)
	for i = 1, 7 do
		local h = 5 + i * 1.5
		disc(m, c + Vector3.new(rng:NextNumber(-3, 3), y - h / 2, rng:NextNumber(-3, 3)), h, r * 2, { Name = "Rock", Color = rockColor:Lerp(Color3.new(0, 0, 0), i * 0.06), Material = Enum.Material.Rock, CastShadow = false })
		y -= h * 0.8
		r *= 0.72
	end
	-- Каменные выступы по краю
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local s = rng:NextNumber(6, 13)
		part(m, {
			Name = "Crag",
			Size = Vector3.new(s, s * 1.6, s),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * (R - s * 0.3), -s * 0.9, math.sin(a) * (R - s * 0.3))) * A(rng:NextNumber(-20, 20), rng:NextNumber(0, 90), rng:NextNumber(150, 210)),
			Color = rockColor,
			Material = Enum.Material.Rock,
			CastShadow = false,
		})
	end
	-- Висящие кристаллы-огоньки снизу
	for i = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		local rr = rng:NextNumber(5, R * 0.5)
		local cr = part(m, {
			Name = "Hanging",
			Size = Vector3.new(1.4, rng:NextNumber(3, 6), 1.4),
			CFrame = CFrame.new(c + Vector3.new(math.cos(a) * rr, -18 - rng:NextNumber(0, 10), math.sin(a) * rr)) * A(0, 45, 0),
			Color = isl.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		local l = Instance.new("PointLight")
		l.Color = isl.color
		l.Range = 14
		l.Brightness = 1
		l.Parent = cr
	end
	-- Фонарики по краю
	for i = 1, 16 do
		local a = (i + 0.5) / 16 * math.pi * 2
		local pos = c + Vector3.new(math.cos(a) * (R - 3), 0, math.sin(a) * (R - 3))
		part(m, { Name = "Post", Size = Vector3.new(0.4, 4, 0.4), CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)), Color = Color3.fromRGB(45, 42, 50), Material = Enum.Material.Metal })
		local b = part(m, {
			Name = "PostLamp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(pos + Vector3.new(0, 4.3, 0)),
			Color = isl.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		if i % 2 == 0 then
			local l = Instance.new("PointLight")
			l.Color = isl.color
			l.Range = 16
			l.Brightness = 0.8
			l.Parent = b
		end
	end
	-- Название острова
	local sign = part(m, { Name = "Sign", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, CFrame = CFrame.new(c + Vector3.new(0, 40, 0)) })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(40, 0, 8, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 1000
	bb.Parent = sign
	text(bb, { Size = UDim2.fromScale(1, 1), Text = isl.icon .. " " .. string.upper(isl.name), TextColor3 = isl.color })
	m.Parent = root
	return m
end

--------------------------------------------------------------------------------
-- Плитки дерева и связи
--------------------------------------------------------------------------------
local function buildTree(root: Instance)
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	local links = Instance.new("Folder")
	links.Name = "Links"
	for _, n in ipairs(Config.Nodes) do
		local pos = Config.nodePosition(n)
		local tile = part(tiles, {
			Name = "Tile_" .. n.id,
			Size = Vector3.new(Config.TILE_SIZE, 0.8, Config.TILE_SIZE),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)),
			Color = Color3.fromRGB(60, 60, 70),
			Material = Enum.Material.SmoothPlastic,
		})
		tile:SetAttribute("Node", n.id)
		-- Неоновая окантовка (её цвет меняет клиент)
		local border = part(tile, {
			Name = "Border",
			Size = Vector3.new(Config.TILE_SIZE + 0.6, 0.6, Config.TILE_SIZE + 0.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)),
			Color = Color3.fromRGB(80, 80, 90),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		border.CastShadow = false
		-- Карточка над плиткой (размер в метрах, как вывеска)
		local bb = Instance.new("BillboardGui")
		bb.Name = "Card"
		bb.Size = UDim2.new(8, 0, 5.2, 0)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
		bb.LightInfluence = 0
		bb.MaxDistance = 140
		bb.Adornee = tile
		bb.Parent = tile
		local card = Instance.new("Frame")
		card.Name = "Bg"
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		card.BackgroundTransparency = 0.15
		card.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.12, 0)
		corner.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(90, 90, 100)
		stroke.Parent = card
		text(card, { Name = "Icon", Size = UDim2.fromScale(0.3, 0.42), Position = UDim2.fromScale(0.03, 0.05), Text = n.icon })
		text(card, { Name = "Title", Size = UDim2.fromScale(0.64, 0.24), Position = UDim2.fromScale(0.34, 0.06), Text = n.name, TextXAlignment = Enum.TextXAlignment.Left })
		text(card, { Name = "Level", Size = UDim2.fromScale(0.64, 0.18), Position = UDim2.fromScale(0.34, 0.3), Text = "", Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 210) })
		text(card, { Name = "Desc", Size = UDim2.fromScale(0.94, 0.2), Position = UDim2.fromScale(0.03, 0.5), Text = n.desc, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 220, 235) })
		text(card, { Name = "Cost", Size = UDim2.fromScale(0.94, 0.24), Position = UDim2.fromScale(0.03, 0.72), Text = "" })

		-- Связи с родителями
		for _, pid in ipairs(n.parents) do
			local p = Config.NodeById[pid]
			local a = Config.nodePosition(p)
			local b = pos
			local mid = (a + b) / 2
			local len = (b - a).Magnitude - Config.TILE_SIZE
			if len > 0.5 then
				local link = part(links, {
					Name = "Link_" .. pid .. "_" .. n.id,
					Size = Vector3.new(1.2, 0.3, len),
					CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.15, 0), b + Vector3.new(0, 0.15, 0)),
					Color = Color3.fromRGB(70, 70, 80),
					Material = Enum.Material.Neon,
					CanCollide = false,
				})
				link.CastShadow = false
				link:SetAttribute("From", pid)
				link:SetAttribute("To", n.id)
			end
		end
	end
	tiles.Parent = root
	links.Parent = root
end

--------------------------------------------------------------------------------
-- Алтари перерождения
--------------------------------------------------------------------------------
export type Altar = { layer: string, part: BasePart, prompt: ProximityPrompt }

local ALTARS = {
	{ on = "L", layer = "Z" },
	{ on = "Z", layer = "S" },
	{ on = "S", layer = "E" },
}

local function maxZ(island: string): number
	local m = 0
	for _, n in ipairs(Config.Nodes) do
		if n.island == island then
			m = math.max(m, n.z)
		end
	end
	return m
end

local function buildAltars(root: Instance): { Altar }
	local list = {}
	for _, a in ipairs(ALTARS) do
		local isl = Config.IslandById[a.on]
		local target = Config.IslandById[a.layer]
		-- справа от последнего ряда дерева
		local z = isl.radius * -0.55 + (maxZ(a.on) - 1) * Config.TILE_STEP
		local pos = isl.center + Vector3.new(3.2 * Config.TILE_STEP, 0, z)
		local m = Instance.new("Model")
		m.Name = "Altar_" .. a.layer
		disc(m, pos + Vector3.new(0, 0.5, 0), 1, 12, { Color = Color3.fromRGB(50, 48, 60), Material = Enum.Material.Marble })
		disc(m, pos + Vector3.new(0, 1.05, 0), 0.2, 10, { Name = "Glow", Color = target.color, Material = Enum.Material.Neon, CanCollide = false })
		local orb = part(m, {
			Name = "Orb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(pos + Vector3.new(0, 5, 0)),
			Color = target.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local l = Instance.new("PointLight")
		l.Color = target.color
		l.Range = 20
		l.Brightness = 2
		l.Parent = orb
		local bb = Instance.new("BillboardGui")
		bb.Name = "Info"
		bb.Size = UDim2.new(14, 0, 4.5, 0)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		bb.LightInfluence = 0
		bb.MaxDistance = 160
		bb.Parent = orb
		text(bb, { Name = "Title", Size = UDim2.fromScale(1, 0.5), Text = target.icon .. " " .. target.name, TextColor3 = target.color })
		text(bb, { Name = "Sub", Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.55), Text = "", Font = Enum.Font.GothamBold })
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Переродиться"
		prompt.ObjectText = target.name
		prompt.HoldDuration = 1
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = orb
		m.Parent = root
		table.insert(list, { layer = a.layer, part = orb, prompt = prompt })
	end
	return list
end

--------------------------------------------------------------------------------
-- Облака и табло
--------------------------------------------------------------------------------
local function buildClouds(root: Instance)
	local f = Instance.new("Folder")
	f.Name = "Clouds"
	local rng = Random.new(5)
	for _ = 1, 45 do
		local center = Vector3.new(rng:NextNumber(-500, 300), rng:NextNumber(-90, -40), rng:NextNumber(-500, 250))
		for _ = 1, rng:NextInteger(3, 6) do
			local s = rng:NextNumber(18, 40)
			part(f, {
				Name = "Cloud",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(s, s, s),
				CFrame = CFrame.new(center + Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(-5, 5), rng:NextNumber(-25, 25))),
				Color = Color3.fromRGB(200, 195, 230),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.35,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
	f.Parent = root
end

local leaderRows: { TextLabel } = {}

local function buildBoard(root: Instance)
	local isl = Config.Islands[1]
	local pos = isl.center + Vector3.new(44, 10, -30)
	local board = part(root, {
		Name = "Leaderboard",
		Size = Vector3.new(20, 17, 0.8),
		CFrame = CFrame.lookAt(pos, isl.center + Vector3.new(0, 10, -20)),
		Color = Color3.fromRGB(20, 20, 28),
	})
	part(root, { Size = Vector3.new(0.8, 10, 0.8), CFrame = CFrame.new(pos + Vector3.new(0, -9, 0)), Color = Color3.fromRGB(45, 42, 50), Material = Enum.Material.Metal })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 36
	sg.LightInfluence = 0
	sg.Parent = board
	text(sg, { Size = UDim2.new(1, 0, 0, 80), Text = "🏆 Самый яркий свет", TextColor3 = Color3.fromRGB(255, 215, 110) })
	for i = 1, 10 do
		leaderRows[i] = text(sg, { Size = UDim2.new(1, -40, 0, 46), Position = UDim2.fromOffset(20, 84 + (i - 1) * 52), Text = "", TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold })
	end
	leaderRows[1].Text = "Загрузка…"
end

function World.setLeaderboard(rows: { { name: string, value: number } })
	for i = 1, 10 do
		local r = rows[i]
		if r then
			local medal = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or (i .. ".")
			leaderRows[i].Text = string.format("%s %s — 💡 %s", medal, r.name, Config.format(r.value))
		else
			leaderRows[i].Text = i == 1 and "Пока пусто — стань первым!" or ""
		end
	end
end

--------------------------------------------------------------------------------
-- Маяк (основание; этажи надстраивает клиент)
--------------------------------------------------------------------------------
World.LIGHTHOUSE_POS = Config.Islands[1].center + Config.LIGHTHOUSE_POS

local function buildLighthouseBase(root: Instance)
	local p = World.LIGHTHOUSE_POS
	local m = Instance.new("Model")
	m.Name = "LighthouseBase"
	disc(m, p + Vector3.new(0, 0.4, 0), 0.8, 20, { Color = Color3.fromRGB(150, 140, 130), Material = Enum.Material.Cobblestone })
	disc(m, p + Vector3.new(0, 3, 0), 5, 12, { Color = Color3.fromRGB(235, 232, 222), Material = Enum.Material.Plaster })
	part(m, { Name = "Door", Size = Vector3.new(0.6, 4, 2.6), CFrame = CFrame.new(p + Vector3.new(6, 2.4, 0)), Color = Color3.fromRGB(110, 70, 45), Material = Enum.Material.WoodPlanks })
	m.Parent = root
end

--------------------------------------------------------------------------------
function World.build(): { altars: { Altar }, spawnCFrame: CFrame }
	Lighting.ClockTime = 20.6
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(70, 65, 95)
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 100, 140)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GeographicLatitude = 30
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.32
	atmo.Offset = 0.15
	atmo.Color = Color3.fromRGB(170, 140, 200)
	atmo.Decay = Color3.fromRGB(90, 70, 140)
	atmo.Glare = 0.4
	atmo.Haze = 1.4
	atmo.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 24
	bloom.Threshold = 1.2
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.12
	cc.Contrast = 0.08
	cc.TintColor = Color3.fromRGB(255, 245, 240)
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting

	local root = Instance.new("Folder")
	root.Name = "World"
	for _, isl in ipairs(Config.Islands) do
		buildIsland(isl, root)
	end
	buildTree(root)
	local altars = buildAltars(root)
	buildClouds(root)
	buildBoard(root)
	buildLighthouseBase(root)

	local c = Config.Islands[1].center
	local spawnPos = c + Vector3.new(0, 0.5, Config.Islands[1].radius * -0.55 - 14)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(spawnPos)
	spawn.Color = Config.Islands[1].color
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.3
	spawn.Duration = 0
	spawn.Parent = root
	root.Parent = workspace
	return { altars = altars, spawnCFrame = CFrame.lookAt(spawnPos + Vector3.new(0, 3, 0), c + Vector3.new(0, 3, 30)) }
end

-- Точка прибытия на остров (перед корнем дерева)
function World.islandSpawn(id: string): CFrame
	local isl = Config.IslandById[id]
	local pos = isl.center + Vector3.new(0, 3.5, isl.radius * -0.55 - 12)
	return CFrame.lookAt(pos, isl.center + Vector3.new(0, 3.5, 30))
end

return World
