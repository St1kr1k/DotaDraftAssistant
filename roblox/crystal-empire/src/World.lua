-- Постройка мира: лобби, участки игроков, станции генераторов, табло рекордов.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local World = {}

World.PLOT_COUNT = 8
World.PLOT_RADIUS = 200 -- расстояние от центра лобби до центра участка
World.STATION_RING = 42 -- радиус кольца станций вокруг кристалла

export type Plot = {
	index: number,
	model: Model,
	center: Vector3,
	crystal: BasePart,
	spawnCFrame: CFrame,
	ownerLabel: TextLabel,
	stations: { [string]: Station },
	owner: Player?,
}

export type Station = {
	gen: any,
	pad: BasePart,
	padCFrame: CFrame,
	build: Model?,
	builtTier: number, -- -1 = не построена; иначе число пройденных рубежей
	label: TextLabel,
	subLabel: TextLabel,
	beam: Beam?,
}

type PartSpec = {
	shape: string?,
	size: Vector3,
	cf: CFrame,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
}

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

local function billboard(parent: BasePart, size: UDim2, offset: Vector3, maxDistance: number?): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffsetWorldSpace = offset
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = maxDistance or 200
	bb.Adornee = parent
	bb.Parent = parent
	return bb
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	for k, v in pairs(props) do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

--------------------------------------------------------------------------------
-- Рецепты станций (по одному на генератор). Координаты относительно центра площадки,
-- ось -Z смотрит на кристалл.
--------------------------------------------------------------------------------
local WOOD = Color3.fromRGB(120, 80, 50)
local DARK = Color3.fromRGB(45, 42, 55)
local METAL = Color3.fromRGB(150, 150, 165)

local function A(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local RECIPES: { [string]: (Color3) -> { PartSpec } } = {
	gnome = function(c)
		return {
			{ size = Vector3.new(6, 4, 6), cf = CFrame.new(0, 2, 0), color = WOOD, material = Enum.Material.WoodPlanks },
			{ size = Vector3.new(7, 1, 7), cf = CFrame.new(0, 4.5, 0), color = Color3.fromRGB(200, 60, 50) },
			{ size = Vector3.new(5, 1, 5), cf = CFrame.new(0, 5.5, 0), color = Color3.fromRGB(200, 60, 50) },
			{ size = Vector3.new(3, 1, 3), cf = CFrame.new(0, 6.5, 0), color = Color3.fromRGB(200, 60, 50) },
			{ size = Vector3.new(2, 3, 0.2), cf = CFrame.new(0, 1.5, -3.05), color = DARK },
			-- гном
			{ shape = "Ball", size = Vector3.new(1.6, 1.6, 1.6), cf = CFrame.new(3, 2.2, -4), color = Color3.fromRGB(255, 205, 170) },
			{ size = Vector3.new(1.6, 1.8, 1.2), cf = CFrame.new(3, 0.9, -4), color = c },
			{ size = Vector3.new(1.2, 1.4, 1.2), cf = CFrame.new(3, 3.4, -4) * A(0, 45, 0), color = Color3.fromRGB(200, 60, 50) },
			{ size = Vector3.new(0.3, 2.5, 0.3), cf = CFrame.new(4.2, 1.5, -4) * A(0, 0, 30), color = WOOD },
		}
	end,
	cart = function(c)
		return {
			{ size = Vector3.new(0.4, 0.4, 12), cf = CFrame.new(-1.5, 0.2, 0), color = METAL, material = Enum.Material.Metal },
			{ size = Vector3.new(0.4, 0.4, 12), cf = CFrame.new(1.5, 0.2, 0), color = METAL, material = Enum.Material.Metal },
			{ size = Vector3.new(4, 2.5, 5), cf = CFrame.new(0, 2, 0), color = WOOD, material = Enum.Material.WoodPlanks },
			{ shape = "Cylinder", size = Vector3.new(0.5, 1.6, 1.6), cf = CFrame.new(-2.1, 0.8, -1.6), color = DARK },
			{ shape = "Cylinder", size = Vector3.new(0.5, 1.6, 1.6), cf = CFrame.new(2.1, 0.8, -1.6), color = DARK },
			{ shape = "Cylinder", size = Vector3.new(0.5, 1.6, 1.6), cf = CFrame.new(-2.1, 0.8, 1.6), color = DARK },
			{ shape = "Cylinder", size = Vector3.new(0.5, 1.6, 1.6), cf = CFrame.new(2.1, 0.8, 1.6), color = DARK },
			{ size = Vector3.new(1.2, 1.2, 1.2), cf = CFrame.new(-0.8, 3.6, -0.8) * A(45, 0, 35), color = Color3.fromRGB(70, 210, 255), material = Enum.Material.Neon },
			{ size = Vector3.new(1, 1, 1), cf = CFrame.new(0.9, 3.5, 0.6) * A(30, 20, 45), color = Color3.fromRGB(255, 90, 200), material = Enum.Material.Neon },
			{ size = Vector3.new(0.9, 0.9, 0.9), cf = CFrame.new(0.2, 3.5, 1.4) * A(10, 45, 30), color = c, material = Enum.Material.Neon },
		}
	end,
	drill = function(c)
		local list: { PartSpec } = {
			{ size = Vector3.new(7, 1, 7), cf = CFrame.new(0, 0.5, 0), color = DARK, material = Enum.Material.DiamondPlate },
			{ size = Vector3.new(6, 1, 6), cf = CFrame.new(0, 11, 0), color = c },
			{ shape = "Cylinder", size = Vector3.new(9, 2.2, 2.2), cf = CFrame.new(0, 6, 0) * A(0, 0, 90), color = METAL, material = Enum.Material.Metal },
			{ size = Vector3.new(1.5, 1.5, 1.5), cf = CFrame.new(0, 1.5, 0) * A(45, 0, 35), color = METAL, material = Enum.Material.Metal },
		}
		for _, p in ipairs({ { -2.6, -2.6 }, { 2.6, -2.6 }, { -2.6, 2.6 }, { 2.6, 2.6 } }) do
			table.insert(list, { size = Vector3.new(0.6, 10, 0.6), cf = CFrame.new(p[1], 6, p[2]), color = c })
		end
		return list
	end,
	mine = function(c)
		return {
			{ size = Vector3.new(12, 7, 10), cf = CFrame.new(0, 3.5, 1), color = Color3.fromRGB(95, 90, 100), material = Enum.Material.Slate },
			{ size = Vector3.new(8, 4, 8), cf = CFrame.new(1, 8, 2) * A(0, 20, 0), color = Color3.fromRGB(85, 80, 95), material = Enum.Material.Slate },
			{ size = Vector3.new(4, 4.5, 0.4), cf = CFrame.new(0, 2.25, -4.1), color = Color3.fromRGB(10, 10, 15) },
			{ size = Vector3.new(0.6, 5, 0.6), cf = CFrame.new(-2.3, 2.5, -4.4), color = WOOD },
			{ size = Vector3.new(0.6, 5, 0.6), cf = CFrame.new(2.3, 2.5, -4.4), color = WOOD },
			{ size = Vector3.new(5.6, 0.6, 0.6), cf = CFrame.new(0, 5, -4.4), color = WOOD },
			{ size = Vector3.new(1.5, 1.5, 1.5), cf = CFrame.new(-4, 7.6, -1) * A(45, 10, 35), color = c, material = Enum.Material.Neon },
			{ size = Vector3.new(1.2, 1.2, 1.2), cf = CFrame.new(4.5, 7.2, 0) * A(20, 45, 35), color = Color3.fromRGB(70, 210, 255), material = Enum.Material.Neon },
		}
	end,
	smelter = function(c)
		return {
			{ size = Vector3.new(9, 6, 8), cf = CFrame.new(0, 3, 0), color = Color3.fromRGB(140, 60, 45), material = Enum.Material.Brick },
			{ shape = "Cylinder", size = Vector3.new(10, 2.6, 2.6), cf = CFrame.new(2.5, 11, 2) * A(0, 0, 90), color = Color3.fromRGB(90, 50, 40), material = Enum.Material.Brick },
			{ size = Vector3.new(4, 2.5, 0.3), cf = CFrame.new(-1, 2, -4.1), color = c, material = Enum.Material.Neon },
			{ size = Vector3.new(10, 0.6, 9), cf = CFrame.new(0, 6.3, 0), color = DARK },
		}
	end,
	laser = function(c)
		return {
			{ shape = "Cylinder", size = Vector3.new(2, 8, 8), cf = CFrame.new(0, 1, 0) * A(0, 0, 90), color = DARK, material = Enum.Material.DiamondPlate },
			{ size = Vector3.new(3, 5, 3), cf = CFrame.new(0, 4.5, 0), color = METAL, material = Enum.Material.Metal },
			{ shape = "Cylinder", size = Vector3.new(8, 1.6, 1.6), cf = CFrame.new(0, 8, -2.5) * A(0, 90, 0) * A(0, 0, 30), color = METAL, material = Enum.Material.Metal },
			{ shape = "Ball", size = Vector3.new(1.4, 1.4, 1.4), cf = CFrame.new(0, 9.9, -5.9), color = c, material = Enum.Material.Neon },
			{ size = Vector3.new(3.2, 1, 3.2), cf = CFrame.new(0, 7, 0), color = c, material = Enum.Material.Neon },
		}
	end,
	portal = function(c)
		local list: { PartSpec } = {
			{ size = Vector3.new(10, 1, 4), cf = CFrame.new(0, 0.5, 0), color = DARK, material = Enum.Material.Slate },
			{ shape = "Cylinder", size = Vector3.new(0.4, 8, 8), cf = CFrame.new(0, 6, 0) * A(0, 90, 0), color = c, material = Enum.Material.Neon, transparency = 0.25 },
		}
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			table.insert(list, {
				size = Vector3.new(1.4, 2.6, 1.4),
				cf = CFrame.new(math.cos(a) * 4.8, 6 + math.sin(a) * 4.8, 0) * A(0, 0, math.deg(a)),
				color = Color3.fromRGB(60, 55, 75),
				material = Enum.Material.Slate,
			})
		end
		return list
	end,
	dragon = function(c)
		return {
			{ size = Vector3.new(4, 3.5, 9), cf = CFrame.new(0, 3.5, 1), color = c, material = Enum.Material.Glass },
			{ size = Vector3.new(2, 2, 5), cf = CFrame.new(0, 6, -4.5) * A(40, 0, 0), color = c, material = Enum.Material.Glass },
			{ size = Vector3.new(2.6, 2, 3.2), cf = CFrame.new(0, 7.8, -7.4), color = c, material = Enum.Material.Glass },
			{ size = Vector3.new(0.6, 0.6, 0.6), cf = CFrame.new(-0.8, 8.4, -9), color = Color3.fromRGB(255, 240, 80), material = Enum.Material.Neon },
			{ size = Vector3.new(0.6, 0.6, 0.6), cf = CFrame.new(0.8, 8.4, -9), color = Color3.fromRGB(255, 240, 80), material = Enum.Material.Neon },
			{ size = Vector3.new(8, 0.3, 5), cf = CFrame.new(-5, 6, 1) * A(0, 0, 25), color = c, material = Enum.Material.Neon, transparency = 0.3 },
			{ size = Vector3.new(8, 0.3, 5), cf = CFrame.new(5, 6, 1) * A(0, 0, -25), color = c, material = Enum.Material.Neon, transparency = 0.3 },
			{ size = Vector3.new(1.4, 1.4, 6), cf = CFrame.new(0, 2.5, 7.5) * A(-20, 0, 0), color = c, material = Enum.Material.Glass },
			{ size = Vector3.new(1, 2.5, 1), cf = CFrame.new(-1.4, 1.25, -1.5), color = c, material = Enum.Material.Glass },
			{ size = Vector3.new(1, 2.5, 1), cf = CFrame.new(1.4, 1.25, -1.5), color = c, material = Enum.Material.Glass },
			{ size = Vector3.new(1, 2.5, 1), cf = CFrame.new(-1.4, 1.25, 3.5), color = c, material = Enum.Material.Glass },
			{ size = Vector3.new(1, 2.5, 1), cf = CFrame.new(1.4, 1.25, 3.5), color = c, material = Enum.Material.Glass },
		}
	end,
	forge = function(c)
		return {
			{ size = Vector3.new(8, 1, 8), cf = CFrame.new(0, 0.5, 0), color = DARK, material = Enum.Material.DiamondPlate },
			{ size = Vector3.new(3, 3, 2.4), cf = CFrame.new(0, 2.5, 0), color = METAL, material = Enum.Material.Metal },
			{ size = Vector3.new(6, 1.4, 3), cf = CFrame.new(0.6, 4.7, 0), color = METAL, material = Enum.Material.Metal },
			{ shape = "Ball", size = Vector3.new(4, 4, 4), cf = CFrame.new(0, 10, 0), color = c, material = Enum.Material.Neon },
			{ size = Vector3.new(6.5, 0.5, 0.5), cf = CFrame.new(0, 10, 0) * A(0, 0, 45), color = c, material = Enum.Material.Neon },
			{ size = Vector3.new(6.5, 0.5, 0.5), cf = CFrame.new(0, 10, 0) * A(0, 0, -45), color = c, material = Enum.Material.Neon },
			{ size = Vector3.new(6.5, 0.5, 0.5), cf = CFrame.new(0, 10, 0) * A(0, 90, 45), color = c, material = Enum.Material.Neon },
		}
	end,
	hole = function(c)
		return {
			{ size = Vector3.new(9, 1, 9), cf = CFrame.new(0, 0.5, 0), color = DARK, material = Enum.Material.Slate },
			{ shape = "Ball", size = Vector3.new(7, 7, 7), cf = CFrame.new(0, 8, 0), color = Color3.new(0, 0, 0), material = Enum.Material.SmoothPlastic },
			{ shape = "Cylinder", size = Vector3.new(0.3, 12, 12), cf = CFrame.new(0, 8, 0) * A(0, 0, 90) * A(20, 0, 0), color = c, material = Enum.Material.Neon, transparency = 0.2 },
			{ shape = "Cylinder", size = Vector3.new(0.3, 10, 10), cf = CFrame.new(0, 8, 0) * A(70, 0, 0), color = Color3.fromRGB(255, 120, 220), material = Enum.Material.Neon, transparency = 0.3 },
		}
	end,
}

local function buildStationModel(gen, padCFrame: CFrame, tier: number): Model
	local model = Instance.new("Model")
	model.Name = "Station"
	local recipe = RECIPES[gen.id]
	for _, spec in ipairs(recipe(gen.color)) do
		local p = part(model, {
			Size = spec.size,
			CFrame = padCFrame * spec.cf,
			Color = spec.color or gen.color,
			Material = spec.material or Enum.Material.SmoothPlastic,
			Transparency = spec.transparency or 0,
			CanCollide = false,
			CastShadow = false,
		})
		if spec.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif spec.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
	end
	model.WorldPivot = padCFrame
	-- Чем больше рубежей пройдено, тем крупнее постройка
	local scale = 1 + 0.12 * math.min(tier, 10)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

--------------------------------------------------------------------------------
-- Участок
--------------------------------------------------------------------------------
local PLOT_COLORS = {
	Color3.fromRGB(70, 210, 255),
	Color3.fromRGB(255, 100, 200),
	Color3.fromRGB(90, 255, 150),
	Color3.fromRGB(255, 200, 70),
	Color3.fromRGB(160, 120, 255),
	Color3.fromRGB(255, 120, 90),
	Color3.fromRGB(80, 255, 230),
	Color3.fromRGB(230, 230, 255),
}

local function buildPlot(index: number, parent: Instance): Plot
	local angle = (index - 1) / World.PLOT_COUNT * math.pi * 2
	local center = Vector3.new(math.cos(angle) * World.PLOT_RADIUS, 0, math.sin(angle) * World.PLOT_RADIUS)
	local toLobby = (Vector3.zero - center).Unit
	local accent = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]

	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	part(model, {
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 136, 136),
		CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * A(0, 0, 90),
		Color = Color3.fromRGB(38, 34, 52),
		Material = Enum.Material.Slate,
	})
	part(model, {
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, 138, 138),
		CFrame = CFrame.new(center + Vector3.new(0, 0.45, 0)) * A(0, 0, 90),
		Color = accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	-- Дорожка к лобби
	local pathStart = center + toLobby * 66
	local pathEnd = toLobby * 40
	local pathLen = (pathEnd - pathStart).Magnitude
	part(model, {
		Name = "Path",
		Size = Vector3.new(10, 0.6, pathLen),
		CFrame = CFrame.lookAt((pathStart + pathEnd) / 2 + Vector3.new(0, 0.3, 0), pathEnd + Vector3.new(0, 0.3, 0)),
		Color = Color3.fromRGB(60, 55, 80),
		Material = Enum.Material.Cobblestone,
	})

	-- Пьедестал и главный кристалл
	part(model, {
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 20, 20),
		CFrame = CFrame.new(center + Vector3.new(0, 2, 0)) * A(0, 0, 90),
		Color = Color3.fromRGB(50, 45, 70),
		Material = Enum.Material.Slate,
	})
	part(model, {
		Name = "PedestalGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 21, 21),
		CFrame = CFrame.new(center + Vector3.new(0, 3.6, 0)) * A(0, 0, 90),
		Color = accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	local crystalPos = center + Vector3.new(0, 13, 0)
	local crystal = part(model, {
		Name = "Crystal",
		Size = Vector3.new(9, 9, 9),
		CFrame = CFrame.new(crystalPos) * A(45, 0, 35.264),
		Color = accent,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.2,
	})
	crystal:SetAttribute("BasePos", crystalPos)
	part(crystal, {
		Name = "Core",
		Size = Vector3.new(5.5, 5.5, 5.5),
		CFrame = crystal.CFrame,
		Color = accent:Lerp(Color3.new(1, 1, 1), 0.5),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 40
	light.Brightness = 3
	light.Parent = crystal
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = 150
	detector.Parent = crystal
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.4))
	sparkles.Size = NumberSequence.new(0.7, 0)
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Rate = 4
	sparkles.Speed = NumberRange.new(3, 6)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.LightEmission = 1
	sparkles.Parent = crystal
	local crystalAttachment = Instance.new("Attachment")
	crystalAttachment.Name = "BeamTarget"
	crystalAttachment.Parent = crystal

	local ownerBB = billboard(crystal, UDim2.fromOffset(420, 70), Vector3.new(0, 11, 0), 400)
	ownerBB.AlwaysOnTop = true
	local ownerLabel = text(ownerBB, { Size = UDim2.fromScale(1, 1), Text = "Свободный участок" })

	-- Точка появления: у края участка со стороны лобби, лицом к кристаллу
	local spawnPos = center + toLobby * 56 + Vector3.new(0, 4, 0)
	local spawnCFrame = CFrame.lookAt(spawnPos, Vector3.new(center.X, spawnPos.Y, center.Z))

	local plot: Plot = {
		index = index,
		model = model,
		center = center,
		crystal = crystal,
		spawnCFrame = spawnCFrame,
		ownerLabel = ownerLabel,
		stations = {},
		owner = nil,
	}

	-- Площадки станций по кругу. Первая — ближе всех к точке появления.
	local baseAngle = math.atan2(toLobby.Z, toLobby.X)
	local n = #Config.Generators
	for i, gen in ipairs(Config.Generators) do
		-- раскладываем от тропинки по часовой стрелке, оставив проход
		local a = baseAngle + math.rad(25) + (i - 1) / n * math.rad(310)
		local padPos = center + Vector3.new(math.cos(a) * World.STATION_RING, 1, math.sin(a) * World.STATION_RING)
		local padCFrame = CFrame.lookAt(padPos, Vector3.new(center.X, padPos.Y, center.Z))
		local pad = part(model, {
			Name = "Pad_" .. gen.id,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 16, 16),
			CFrame = padCFrame * A(0, 0, 90),
			Color = Color3.fromRGB(60, 56, 78),
			Material = Enum.Material.DiamondPlate,
		})
		part(model, {
			Name = "PadRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 16.8, 16.8),
			CFrame = padCFrame * CFrame.new(0, -0.08, 0) * A(0, 0, 90),
			Color = gen.color,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			CanCollide = false,
		})
		local bb = billboard(pad, UDim2.fromOffset(260, 80), Vector3.new(0, 9, 0), 160)
		local label = text(bb, { Size = UDim2.new(1, 0, 0.55, 0), Text = "🔒 " .. gen.name })
		local sub = text(bb, {
			Size = UDim2.new(1, 0, 0.42, 0),
			Position = UDim2.fromScale(0, 0.58),
			Text = "Купи в магазине",
			TextColor3 = Color3.fromRGB(200, 200, 220),
			Font = Enum.Font.GothamBold,
		})
		plot.stations[gen.id] = {
			gen = gen,
			pad = pad,
			padCFrame = padCFrame * CFrame.new(0, 0.3, 0),
			build = nil,
			builtTier = -1,
			label = label,
			subLabel = sub,
			beam = nil,
		}
	end

	model.Parent = parent
	return plot
end

-- Обновить постройку станции под текущий уровень
function World.updateStation(plot: Plot, genId: string, level: number, production: number)
	local st = plot.stations[genId]
	if not st then
		return
	end
	local tier = level > 0 and Config.milestonesReached(level) or -1
	if tier ~= st.builtTier then
		st.builtTier = tier
		if st.build then
			st.build:Destroy()
			st.build = nil
		end
		if st.beam then
			st.beam:Destroy()
			st.beam = nil
		end
		if tier >= 0 then
			local m = buildStationModel(st.gen, st.padCFrame, tier)
			m.Parent = plot.model
			st.build = m
			-- Луч добычи к кристаллу
			local att = Instance.new("Attachment")
			att.Name = "BeamSource"
			att.Parent = st.pad
			att.WorldPosition = st.padCFrame.Position + Vector3.new(0, 6 + tier, 0)
			local beam = Instance.new("Beam")
			beam.Attachment0 = att
			beam.Attachment1 = plot.crystal:FindFirstChild("BeamTarget") :: Attachment
			beam.Color = ColorSequence.new(st.gen.color)
			beam.LightEmission = 1
			beam.FaceCamera = true
			beam.Width0 = 0.3 + 0.12 * tier
			beam.Width1 = 0.15
			beam.Transparency = NumberSequence.new(0.2, 0.6)
			beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = 3
			beam.TextureSpeed = 1 + tier * 0.3
			beam.Segments = 1
			beam.Parent = att
			st.beam = beam
		end
	end
	if level > 0 then
		st.label.Text = string.format("%s %s", st.gen.icon, st.gen.name)
		st.subLabel.Text = string.format("Ур. %d · +%s/с", level, Config.format(production))
	else
		st.label.Text = "🔒 " .. st.gen.name
		st.subLabel.Text = "Купи в магазине"
	end
end

function World.resetPlot(plot: Plot)
	for id in pairs(plot.stations) do
		World.updateStation(plot, id, 0, 0)
	end
	plot.ownerLabel.Text = "Свободный участок"
	local sparkles = plot.crystal:FindFirstChild("Sparkles") :: ParticleEmitter?
	if sparkles then
		sparkles.Rate = 4
	end
end

--------------------------------------------------------------------------------
-- Лобби и табло
--------------------------------------------------------------------------------
local leaderRows: { TextLabel } = {}

local function buildLobby(parent: Instance)
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	part(lobby, {
		Name = "LobbyFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 80, 80),
		CFrame = CFrame.new(0, 0.5, 0) * A(0, 0, 90),
		Color = Color3.fromRGB(55, 50, 75),
		Material = Enum.Material.Marble,
	})
	part(lobby, {
		Name = "LobbyRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, 82, 82),
		CFrame = CFrame.new(0, 0.45, 0) * A(0, 0, 90),
		Color = Color3.fromRGB(255, 205, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	-- Табло рекордов
	local board = part(lobby, {
		Name = "Leaderboard",
		Size = Vector3.new(26, 22, 1),
		CFrame = CFrame.new(0, 13, 22),
		Color = Color3.fromRGB(25, 22, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	part(lobby, { Size = Vector3.new(1.2, 14, 1.2), CFrame = CFrame.new(-10, 7, 22.8), Color = Color3.fromRGB(60, 55, 80) })
	part(lobby, { Size = Vector3.new(1.2, 14, 1.2), CFrame = CFrame.new(10, 7, 22.8), Color = Color3.fromRGB(60, 55, 80) })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Parent = board
	text(sg, {
		Size = UDim2.new(1, 0, 0, 90),
		Text = "🏆 Самые богатые империи",
		TextColor3 = Color3.fromRGB(255, 205, 60),
	})
	for i = 1, 10 do
		local row = text(sg, {
			Size = UDim2.new(1, -40, 0, 50),
			Position = UDim2.fromOffset(20, 95 + (i - 1) * 56),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
		})
		leaderRows[i] = row
	end
	leaderRows[1].Text = "Загрузка…"

	-- Название
	local sign = part(lobby, {
		Name = "Title",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 26, 22),
		Transparency = 1,
		CanCollide = false,
	})
	local bb = billboard(sign, UDim2.fromOffset(700, 110), Vector3.zero, 500)
	text(bb, { Size = UDim2.fromScale(1, 1), Text = "💎 КРИСТАЛЬНАЯ ИМПЕРИЯ", TextColor3 = Color3.fromRGB(150, 235, 255) })

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 1, -10)
	spawn.Color = Color3.fromRGB(70, 210, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby

	lobby.Parent = parent
end

function World.setLeaderboard(rows: { { name: string, value: number } })
	for i = 1, 10 do
		local r = rows[i]
		if r then
			local medal = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or (i .. ".")
			leaderRows[i].Text = string.format("%s %s — 💎 %s", medal, r.name, Config.format(r.value))
		else
			leaderRows[i].Text = i == 1 and "Пока пусто — стань первым!" or ""
		end
	end
end

--------------------------------------------------------------------------------
-- Россыпь декоративных кристаллов между участками
--------------------------------------------------------------------------------
local function scatter(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	local rng = Random.new(7)
	local palette = { Color3.fromRGB(255, 90, 200), Color3.fromRGB(90, 255, 150), Color3.fromRGB(255, 210, 70), Color3.fromRGB(140, 110, 255), Color3.fromRGB(70, 210, 255) }
	local placed = 0
	local tries = 0
	while placed < 120 and tries < 2000 do
		tries += 1
		local pos = Vector3.new(rng:NextNumber(-380, 380), 0, rng:NextNumber(-380, 380))
		local ok = pos.Magnitude > 50
		for i = 1, World.PLOT_COUNT do
			local a = (i - 1) / World.PLOT_COUNT * math.pi * 2
			local c = Vector3.new(math.cos(a) * World.PLOT_RADIUS, 0, math.sin(a) * World.PLOT_RADIUS)
			if (pos - c).Magnitude < 75 then
				ok = false
			end
		end
		if ok then
			placed += 1
			local s = rng:NextNumber(2, 7)
			part(folder, {
				Name = "Shard",
				Size = Vector3.new(s * 0.6, s * 2, s * 0.6),
				CFrame = CFrame.new(pos + Vector3.new(0, s * 0.6, 0)) * A(rng:NextNumber(-20, 20), rng:NextNumber(0, 360), rng:NextNumber(-20, 20)),
				Color = palette[rng:NextInteger(1, #palette)],
				Material = Enum.Material.Neon,
				CastShadow = false,
			})
		end
	end
	folder.Parent = parent
end

--------------------------------------------------------------------------------
function World.build(): { Plot }
	Lighting.ClockTime = 20
	Lighting.Brightness = 1.2
	Lighting.Ambient = Color3.fromRGB(70, 60, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 80, 140)
	Lighting.EnvironmentDiffuseScale = 0.5
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.08
	cc.Parent = Lighting
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.3
	atmo.Color = Color3.fromRGB(120, 100, 170)
	atmo.Decay = Color3.fromRGB(60, 40, 100)
	atmo.Glare = 0.2
	atmo.Haze = 1.5
	atmo.Parent = Lighting

	local root = Instance.new("Folder")
	root.Name = "Empire"
	buildLobby(root)
	scatter(root)
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = root
	local plots = {}
	for i = 1, World.PLOT_COUNT do
		plots[i] = buildPlot(i, plotsFolder)
	end
	root.Parent = workspace
	return plots
end

return World
