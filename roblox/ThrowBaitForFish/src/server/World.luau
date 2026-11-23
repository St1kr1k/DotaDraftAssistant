-- Строит весь мир скриптом при старте сервера: океан, остров, участки игроков
-- (аквариум + причал + турники), центр со статуей и магазинами, буи зон, освещение.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local FishBuilder = require(Shared.FishBuilder)

local World = {}
World.Plots = {} -- [index] = plot table

local terrain = workspace.Terrain

local GROUND_Y = 4
local DECK_Y = 4.6
local PLOT_R = 92
local PIER_START_R = 106
local PIER_END_R = 214

local rng = Random.new(1337)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function P(props: { [string]: any }): BasePart
	local class = props.Class or "Part"
	local p = Instance.new(class) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Class" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function billboard(parent: Instance, size: UDim2, offset: Vector3, maxDist: number): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffset = offset
	bb.MaxDistance = maxDist
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Parent = parent
	return bb
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = text
	t.TextColor3 = color
	t.TextScaled = true
	t.Font = font or Enum.Font.FredokaOne
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = rgb(20, 30, 50)
	t.Parent = parent
	return t
end

-- ===== Освещение =====
local function setupLighting()
	Lighting.ClockTime = 14.2
	Lighting.Brightness = 2.6
	Lighting.Ambient = rgb(70, 80, 95)
	Lighting.OutdoorAmbient = rgb(140, 150, 165)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.GeographicLatitude = 20

	local atm = Instance.new("Atmosphere")
	atm.Density = 0.28
	atm.Offset = 0.2
	atm.Color = rgb(200, 230, 255)
	atm.Decay = rgb(110, 170, 230)
	atm.Glare = 0.25
	atm.Haze = 1.2
	atm.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MainColor"
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.StarCount = 3000
	sky.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.55
	clouds.Color = rgb(255, 255, 255)
	clouds.Parent = terrain

	terrain.WaterColor = rgb(25, 165, 195)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.45
	terrain.WaterWaveSize = 0.22
	terrain.WaterWaveSpeed = 11
	terrain:SetMaterialColor(Enum.Material.Grass, rgb(95, 185, 75))
	terrain:SetMaterialColor(Enum.Material.Sand, rgb(240, 220, 165))
	terrain:SetMaterialColor(Enum.Material.Rock, rgb(130, 125, 120))
end

-- ===== Рельеф =====
local function buildTerrain()
	terrain:FillBlock(CFrame.new(0, -54, 0), Vector3.new(2000, 12, 2000), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -24, 0), Vector3.new(2000, 48, 2000), Enum.Material.Water)
	-- пляжные ступени, потом сам остров
	terrain:FillCylinder(CFrame.new(0, -26, 0), 44, 192, Enum.Material.Sand) -- верх -4 (под водой)
	terrain:FillCylinder(CFrame.new(0, -24.5, 0), 47, 178, Enum.Material.Sand) -- верх -1
	terrain:FillCylinder(CFrame.new(0, -23, 0), 50, 166, Enum.Material.Sand) -- верх 2
	terrain:FillCylinder(CFrame.new(0, 0.5, 0), 7, 130, Enum.Material.Grass) -- верх 4
	-- камни по берегу
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		if i % 3 ~= 0 then
			local r = rng:NextNumber(150, 172)
			terrain:FillBall(Vector3.new(math.cos(a) * r, rng:NextNumber(-1, 1), math.sin(a) * r), rng:NextNumber(3, 6), Enum.Material.Rock)
		end
	end
	-- подводные скалы и рифы вдали (видно сквозь воду)
	for _ = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(230, 900)
		terrain:FillBall(Vector3.new(math.cos(a) * r, -46, math.sin(a) * r), rng:NextNumber(6, 16), Enum.Material.Rock)
	end
end

-- ===== Декор =====
local function palm(parent: Instance, pos: Vector3, height: number)
	local m = model("Palm", parent)
	local lean = rng:NextNumber(-0.25, 0.25)
	local leanZ = rng:NextNumber(-0.25, 0.25)
	local segs = 6
	local top = pos
	for i = 0, segs - 1 do
		local f = i / segs
		local a = pos + Vector3.new(lean * height * f * f, height * f, leanZ * height * f * f)
		local f2 = (i + 1) / segs
		local b = pos + Vector3.new(lean * height * f2 * f2, height * f2, leanZ * height * f2 * f2)
		local mid = (a + b) / 2
		P({
			Class = "Part",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new((b - a).Magnitude + 0.3, 1.6 - f * 0.5, 1.6 - f * 0.5),
			CFrame = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0),
			Color = i % 2 == 0 and rgb(150, 110, 70) or rgb(130, 95, 60),
			Material = Enum.Material.Wood,
			Parent = m,
		})
		top = b
	end
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local leafLen = height * 0.55
		local mid = top + dir * (leafLen * 0.45) + Vector3.new(0, -leafLen * 0.12, 0)
		local p = P({
			Size = Vector3.new(leafLen * 0.32, 0.25, leafLen),
			CFrame = CFrame.lookAt(mid, mid + dir + Vector3.new(0, -0.35, 0)),
			Color = (i % 2 == 0) and rgb(70, 170, 70) or rgb(55, 145, 60),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = m,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		P({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 1.1),
			Position = top + Vector3.new(math.cos(a) * 0.7, -0.8, math.sin(a) * 0.7),
			Color = rgb(110, 75, 40),
			Parent = m,
		})
	end
end

local function bush(parent: Instance, pos: Vector3)
	local colors = { rgb(70, 160, 70), rgb(90, 180, 80), rgb(60, 140, 65) }
	for i = 1, 3 do
		local s = rng:NextNumber(2.5, 4.5)
		P({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s, s),
			Position = pos + Vector3.new(rng:NextNumber(-1.5, 1.5), s * 0.3, rng:NextNumber(-1.5, 1.5)),
			Color = colors[i],
			Material = Enum.Material.Grass,
			Parent = parent,
		})
	end
	if rng:NextNumber() < 0.6 then
		local flower = ({ rgb(255, 120, 160), rgb(255, 230, 90), rgb(255, 255, 255), rgb(190, 120, 255) })[rng:NextInteger(1, 4)]
		for _ = 1, 4 do
			P({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.7, 0.7, 0.7),
				Position = pos + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(2.2, 3.4), rng:NextNumber(-2, 2)),
				Color = flower,
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = parent,
			})
		end
	end
end

local function lantern(parent: Instance, pos: Vector3)
	P({ Size = Vector3.new(0.5, 5, 0.5), Position = pos + Vector3.new(0, 2.5, 0), Color = rgb(90, 65, 45), Material = Enum.Material.Wood, Parent = parent })
	local lamp = P({ Size = Vector3.new(1.1, 1.3, 1.1), Position = pos + Vector3.new(0, 5.4, 0), Color = rgb(255, 200, 110), Material = Enum.Material.Neon, CanCollide = false, Parent = parent })
	P({ Size = Vector3.new(1.5, 0.3, 1.5), Position = pos + Vector3.new(0, 6.2, 0), Color = rgb(70, 50, 35), Material = Enum.Material.Wood, Parent = parent })
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 190, 110)
	light.Range = 14
	light.Brightness = 1.4
	light.Parent = lamp
end

-- Турник
local function pullUpBar(parent: Instance, cf: CFrame, index: number): BasePart
	local m = model("PullUpBar", parent)
	local postColor = rgb(60, 70, 85)
	for _, side in ipairs({ -1, 1 }) do
		P({ Size = Vector3.new(0.7, 10, 0.7), CFrame = cf * CFrame.new(side * 3.2, 5, 0), Color = postColor, Material = Enum.Material.Metal, Parent = m })
		P({ Size = Vector3.new(1.6, 0.5, 1.6), CFrame = cf * CFrame.new(side * 3.2, 0.25, 0), Color = postColor, Material = Enum.Material.Metal, Parent = m })
	end
	local bar = P({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7.2, 0.45, 0.45),
		CFrame = cf * CFrame.new(0, 9.6, 0),
		Color = rgb(220, 220, 230),
		Material = Enum.Material.Metal,
		Parent = m,
	})
	bar.Name = "Bar"
	bar:SetAttribute("BarId", index)
	local mat = P({ Size = Vector3.new(6, 0.2, 4), CFrame = cf * CFrame.new(0, 0.1, 0), Color = rgb(255, 120, 60), CanCollide = false, Parent = m })
	mat.Name = "Mat"
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Train"
	prompt.ObjectText = "Pull-up Bar 💪"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = bar
	local bb = billboard(bar, UDim2.fromOffset(160, 40), Vector3.new(0, 2.2, 0), 60)
	label(bb, "💪 TRAIN", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), rgb(255, 230, 90))
	return bar
end

-- Аквариум
local function buildTank(parent: Instance, cf: CFrame)
	local m = model("Tank", parent)
	local W, H, D = 26, 11, 9
	local baseH = 1.6
	P({ Size = Vector3.new(W + 2, baseH, D + 2), CFrame = cf * CFrame.new(0, baseH / 2, 0), Color = rgb(85, 95, 110), Material = Enum.Material.Slate, Parent = m })
	local glassY = baseH + H / 2
	local glass = rgb(200, 240, 255)
	local function wall(size: Vector3, offset: Vector3)
		P({ Size = size, CFrame = cf * CFrame.new(offset), Color = glass, Material = Enum.Material.Glass, Transparency = 0.82, Parent = m })
	end
	wall(Vector3.new(W, H, 0.3), Vector3.new(0, glassY, -D / 2))
	wall(Vector3.new(W, H, 0.3), Vector3.new(0, glassY, D / 2))
	wall(Vector3.new(0.3, H, D), Vector3.new(-W / 2, glassY, 0))
	wall(Vector3.new(0.3, H, D), Vector3.new(W / 2, glassY, 0))
	-- рамка
	local frame = rgb(120, 85, 55)
	for _, z in ipairs({ -D / 2, D / 2 }) do
		P({ Size = Vector3.new(W + 0.8, 0.6, 0.6), CFrame = cf * CFrame.new(0, baseH + H, z), Color = frame, Material = Enum.Material.Wood, Parent = m })
	end
	for _, x in ipairs({ -W / 2, W / 2 }) do
		P({ Size = Vector3.new(0.6, 0.6, D + 0.8), CFrame = cf * CFrame.new(x, baseH + H, 0), Color = frame, Material = Enum.Material.Wood, Parent = m })
		for _, z in ipairs({ -D / 2, D / 2 }) do
			P({ Size = Vector3.new(0.6, H, 0.6), CFrame = cf * CFrame.new(x, glassY, z), Color = frame, Material = Enum.Material.Wood, Parent = m })
		end
	end
	-- песок, вода, кораллы
	P({ Size = Vector3.new(W - 0.4, 1, D - 0.4), CFrame = cf * CFrame.new(0, baseH + 0.5, 0), Color = rgb(240, 220, 160), Material = Enum.Material.Sand, CanCollide = false, Parent = m })
	local water = P({
		Size = Vector3.new(W - 0.6, H - 1.6, D - 0.6),
		CFrame = cf * CFrame.new(0, baseH + 1 + (H - 1.6) / 2, 0),
		Color = rgb(70, 190, 230),
		Transparency = 0.8,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = m,
	})
	water.Name = "Water"
	local light = Instance.new("PointLight")
	light.Color = rgb(120, 220, 255)
	light.Range = 16
	light.Brightness = 1.3
	light.Parent = water
	local coralColors = { rgb(255, 110, 150), rgb(255, 170, 80), rgb(170, 110, 255), rgb(90, 220, 200) }
	for i = 1, 9 do
		local x = rng:NextNumber(-W / 2 + 1.5, W / 2 - 1.5)
		local z = rng:NextNumber(0.5, D / 2 - 1.2)
		local h = rng:NextNumber(1.2, 3.2)
		local c = coralColors[(i % #coralColors) + 1]
		P({ Size = Vector3.new(0.5, h, 0.5), CFrame = cf * CFrame.new(x, baseH + 1 + h / 2, z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)), Color = c, CanCollide = false, Parent = m })
		P({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(x, baseH + 1 + h, z), Color = c, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	end
	for _ = 1, 5 do
		local s = rng:NextNumber(1, 2)
		P({ Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), CFrame = cf * CFrame.new(rng:NextNumber(-W / 2 + 1, W / 2 - 1), baseH + 1, rng:NextNumber(-D / 2 + 1, D / 2 - 1)), Color = rgb(120, 120, 130), Material = Enum.Material.Slate, CanCollide = false, Parent = m })
	end
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(rgb(220, 250, 255))
	bubbles.Size = NumberSequence.new(0.25)
	bubbles.Transparency = NumberSequence.new(0.3)
	bubbles.Lifetime = NumberRange.new(2, 3)
	bubbles.Rate = 8
	bubbles.Speed = NumberRange.new(2.5, 4)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(10, 10)
	bubbles.LightEmission = 0.5
	bubbles.Parent = water
	local fish = folder("Fish", m)
	return m, water, fish
end

-- Причал
local function buildPier(parent: Instance, dir: Vector3, right: Vector3): BasePart
	local m = model("Pier", parent)
	local len = PIER_END_R - PIER_START_R
	local startPos = dir * PIER_START_R
	local mid = dir * (PIER_START_R + len / 2)
	local cf = CFrame.lookAt(Vector3.new(mid.X, DECK_Y - 0.5, mid.Z), Vector3.new(mid.X, DECK_Y - 0.5, mid.Z) + dir)
	P({ Size = Vector3.new(8, 1, len), CFrame = cf, Color = rgb(170, 125, 80), Material = Enum.Material.WoodPlanks, Parent = m })
	for _, side in ipairs({ -1, 1 }) do
		P({ Size = Vector3.new(0.6, 0.6, len), CFrame = cf * CFrame.new(side * 3.9, 2.2, 0), Color = rgb(130, 95, 60), Material = Enum.Material.Wood, Parent = m })
	end
	local steps = math.floor(len / 12)
	for i = 0, steps do
		local along = -len / 2 + i * (len / steps)
		for _, side in ipairs({ -1, 1 }) do
			P({ Size = Vector3.new(0.9, 16, 0.9), CFrame = cf * CFrame.new(side * 3.9, -6, along), Color = rgb(110, 80, 55), Material = Enum.Material.Wood, Parent = m })
		end
		if i % 2 == 1 then
			local p = (cf * CFrame.new(-4.6, 0.5, along)).Position
			lantern(m, p)
		end
	end
	-- площадка на конце
	local endPos = dir * (PIER_END_R + 5)
	local endCf = CFrame.lookAt(Vector3.new(endPos.X, DECK_Y - 0.5, endPos.Z), Vector3.new(endPos.X, DECK_Y - 0.5, endPos.Z) + dir)
	P({ Size = Vector3.new(16, 1, 12), CFrame = endCf, Color = rgb(170, 125, 80), Material = Enum.Material.WoodPlanks, Parent = m })
	for _, x in ipairs({ -7.5, 7.5 }) do
		for _, z in ipairs({ -5.5, 5.5 }) do
			P({ Size = Vector3.new(1, 16, 1), CFrame = endCf * CFrame.new(x, -6, z), Color = rgb(110, 80, 55), Material = Enum.Material.Wood, Parent = m })
		end
	end
	local spotPos = dir * (PIER_END_R + 4) + Vector3.new(0, DECK_Y + 0.05, 0)
	local spot = P({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 7, 7),
		CFrame = CFrame.new(spotPos) * CFrame.Angles(0, 0, math.pi / 2),
		Color = rgb(90, 230, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = m,
	})
	spot.Name = "CastSpot"
	local bb = billboard(spot, UDim2.fromOffset(220, 60), Vector3.new(0, 7, 0), 120)
	label(bb, "🎣 CAST HERE", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), rgb(120, 240, 255))
	-- ступеньки к воде сбоку (чтобы вылезать из воды)
	for i = 1, 5 do
		local p = startPos + dir * (len * 0.6) + right * (4 + i * 1.2) + Vector3.new(0, DECK_Y - 0.5 - i * 1.1, 0)
		P({ Size = Vector3.new(2.4, 0.6, 3), CFrame = CFrame.lookAt(p, p + dir), Color = rgb(150, 110, 70), Material = Enum.Material.WoodPlanks, Parent = m })
	end
	return spot
end

local function buoy(parent: Instance, pos: Vector3, zone: any)
	local m = model("Buoy_" .. zone.Name, parent)
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 3.4, 3.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = zone.Color, Parent = m })
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3.6, 3.6), CFrame = CFrame.new(pos + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(255, 255, 255), Parent = m })
	P({ Size = Vector3.new(0.4, 4, 0.4), Position = pos + Vector3.new(0, 4, 0), Color = rgb(60, 60, 70), Material = Enum.Material.Metal, Parent = m })
	local lamp = P({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), Position = pos + Vector3.new(0, 6.3, 0), Color = zone.Color, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	local light = Instance.new("PointLight")
	light.Color = zone.Color
	light.Range = 12
	light.Parent = lamp
	local bb = billboard(lamp, UDim2.fromOffset(220, 70), Vector3.new(0, 4, 0), 700)
	label(bb, zone.Name, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0), zone.Color)
	label(bb, "💪 " .. tostring(Config.PowerForDistance(zone.Dist)) .. " Power", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6), rgb(255, 255, 255))
end

-- ===== Участок игрока =====
local function buildPlot(root: Instance, index: number)
	local angle = (index - 1) / Config.PlotCount * math.pi * 2
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local center = dir * PLOT_R + Vector3.new(0, GROUND_Y, 0)
	-- локальная система: -Z (LookVector) смотрит наружу, к морю; +Z — к центру острова
	local cf = CFrame.lookAt(center, center + dir)
	local m = model("Plot" .. index, root)

	P({ Size = Vector3.new(38, 1, 32), CFrame = cf * CFrame.new(0, 0.1, 0), Color = rgb(175, 130, 85), Material = Enum.Material.WoodPlanks, Parent = m })
	-- аквариум у дальней от моря стороны, лицом к причалу
	local tankCf = cf * CFrame.new(0, 0.6, 8)
	local tank, water, fishFolder = buildTank(m, tankCf)
	-- табличка владельца
	local signAnchor = P({ Size = Vector3.new(1, 1, 1), CFrame = tankCf * CFrame.new(0, 17, 0), Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
	signAnchor.Name = "Sign"
	local bb = billboard(signAnchor, UDim2.fromOffset(320, 110), Vector3.zero, 250)
	local ownerLabel = label(bb, "Empty Plot", UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0), rgb(255, 255, 255))
	ownerLabel.Name = "Owner"
	local incomeLabel = label(bb, "", UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55), rgb(120, 255, 120))
	incomeLabel.Name = "Income"
	-- турники по бокам
	local bars = {}
	for k, side in ipairs({ -1, 1 }) do
		local barCf = cf * CFrame.new(side * 14.5, 0.6, -8)
		table.insert(bars, pullUpBar(m, barCf, index * 10 + k))
	end
	-- причал
	local castSpot = buildPier(m, dir, right)
	-- фонари у участка
	lantern(m, (cf * CFrame.new(-18, 0.6, -15)).Position)
	lantern(m, (cf * CFrame.new(18, 0.6, -15)).Position)
	-- буи зон в направлении этого причала
	for z = 2, #GameData.Zones do
		local zone = GameData.Zones[z]
		local pos = castSpot.Position + dir * zone.Dist
		buoy(m, Vector3.new(pos.X, Config.WaterY, pos.Z) + right * 6, zone)
	end

	local plot = {
		Index = index,
		Model = m,
		CFrame = cf,
		Dir = dir,
		CastSpot = castSpot,
		Tank = tank,
		Water = water,
		FishFolder = fishFolder,
		OwnerLabel = ownerLabel,
		IncomeLabel = incomeLabel,
		Bars = bars,
		Owner = nil :: Player?,
	}
	m:SetAttribute("PlotIndex", index)
	castSpot:SetAttribute("PlotIndex", index)
	World.Plots[index] = plot
end

-- ===== Центр острова =====
local function kiosk(parent: Instance, cf: CFrame, title: string, color: Color3, promptName: string)
	local m = model(promptName, parent)
	local wood = rgb(150, 105, 65)
	P({ Size = Vector3.new(12, 3.5, 4), CFrame = cf * CFrame.new(0, 1.75, 0), Color = wood, Material = Enum.Material.WoodPlanks, Parent = m })
	P({ Size = Vector3.new(12.6, 0.4, 4.6), CFrame = cf * CFrame.new(0, 3.7, 0), Color = rgb(235, 225, 210), Material = Enum.Material.Wood, Parent = m })
	for _, x in ipairs({ -5.8, 5.8 }) do
		P({ Size = Vector3.new(0.6, 9, 0.6), CFrame = cf * CFrame.new(x, 4.5, 1.6), Color = wood, Material = Enum.Material.Wood, Parent = m })
	end
	for i = 0, 5 do
		P({
			Class = "WedgePart",
			Size = Vector3.new(2.2, 1.4, 6),
			CFrame = cf * CFrame.new(-5.5 + i * 2.2, 9.6, -0.4) * CFrame.Angles(0, math.pi, 0),
			Color = (i % 2 == 0) and color or rgb(255, 255, 255),
			Parent = m,
		})
	end
	local signPart = P({ Size = Vector3.new(10, 2.4, 0.4), CFrame = cf * CFrame.new(0, 11.6, 1.6), Color = rgb(60, 45, 35), Material = Enum.Material.Wood, Parent = m })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(400, 96)
	sg.LightInfluence = 0
	sg.Parent = signPart
	label(sg, title, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), color)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = "Open"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = signPart
	return m
end

local function lighthouse(parent: Instance, pos: Vector3)
	local m = model("Lighthouse", parent)
	for i = 0, 7 do
		P({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(4, 9 - i * 0.5, 9 - i * 0.5),
			CFrame = CFrame.new(pos + Vector3.new(0, 2 + i * 4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = (i % 2 == 0) and rgb(240, 240, 240) or rgb(220, 60, 60),
			Parent = m,
		})
	end
	local top = pos + Vector3.new(0, 34, 0)
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 8, 8), CFrame = CFrame.new(top - Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(50, 50, 60), Parent = m })
	local lamp = P({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = top, Color = rgb(255, 240, 170), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	lamp.Name = "Lamp"
	P({ Class = "Part", Size = Vector3.new(6, 1.4, 6), Position = top + Vector3.new(0, 2.4, 0), Color = rgb(220, 60, 60), Parent = m })
	local spot = Instance.new("SpotLight")
	spot.Name = "Beam"
	spot.Color = rgb(255, 240, 180)
	spot.Range = 60
	spot.Angle = 25
	spot.Brightness = 4
	spot.Face = Enum.NormalId.Front
	spot.Parent = lamp
	local pl = Instance.new("PointLight")
	pl.Color = rgb(255, 230, 160)
	pl.Range = 20
	pl.Parent = lamp
	return m
end

local function buildCenter(root: Instance)
	local m = model("Center", root)
	-- площадь
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 70, 70), CFrame = CFrame.new(0, GROUND_Y + 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(215, 205, 185), Material = Enum.Material.Pavement, Parent = m })
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 20, 20), CFrame = CFrame.new(0, GROUND_Y + 3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(150, 150, 160), Material = Enum.Material.Slate, Parent = m })
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 22, 22), CFrame = CFrame.new(0, GROUND_Y + 6.2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(255, 205, 60), Material = Enum.Material.Foil, Parent = m })
	-- золотой мегалодон
	local statue = FishBuilder.Build("Megalodon", "Golden", 26, { static = true })
	statue:PivotTo(CFrame.new(0, GROUND_Y + 19, 0) * CFrame.Angles(0.35, math.rad(30), 0))
	statue.Name = "MegalodonStatue"
	statue.Parent = m
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, GROUND_Y + 1.2, 26)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = m
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	-- магазины
	kiosk(m, CFrame.lookAt(Vector3.new(-30, GROUND_Y, -16), Vector3.new(0, GROUND_Y, 0)), "BAIT SHOP", rgb(255, 120, 60), "ShopPrompt")
	kiosk(m, CFrame.lookAt(Vector3.new(30, GROUND_Y, -16), Vector3.new(0, GROUND_Y, 0)), "SELL FISH", rgb(80, 220, 120), "SellPrompt")
	kiosk(m, CFrame.lookAt(Vector3.new(0, GROUND_Y, -36), Vector3.new(0, GROUND_Y, 0)), "ROBUX SHOP", rgb(255, 210, 60), "StorePrompt")
	-- спортзал вокруг статуи
	local gymBars = {}
	for i = 0, 3 do
		local a = math.rad(55 + i * 22)
		local p = Vector3.new(math.cos(a) * 40, GROUND_Y, math.sin(a) * 40)
		table.insert(gymBars, pullUpBar(m, CFrame.lookAt(p, Vector3.new(0, GROUND_Y, 0)), 900 + i))
	end
	World.GymBars = gymBars
end

local function buildDecor(root: Instance)
	local m = model("Decor", root)
	for i = 0, Config.PlotCount - 1 do
		local a = (i + 0.5) / Config.PlotCount * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		-- пальмы между участками
		for _, r in ipairs({ 82, 104, 122, 145 }) do
			local jitter = Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
			local y = r > 128 and 2 or GROUND_Y
			palm(m, dir * r + jitter + Vector3.new(0, y - 0.5, 0), rng:NextNumber(14, 22))
		end
		bush(m, dir * 92 + Vector3.new(rng:NextNumber(-4, 4), GROUND_Y, rng:NextNumber(-4, 4)))
		bush(m, dir * 60 + Vector3.new(rng:NextNumber(-4, 4), GROUND_Y, rng:NextNumber(-4, 4)))
	end
	for _ = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(42, 62)
		bush(m, Vector3.new(math.cos(a) * r, GROUND_Y, math.sin(a) * r))
	end
	local la = (0.5 / Config.PlotCount) * math.pi * 2
	World.Lighthouse = lighthouse(m, Vector3.new(math.cos(la) * 158, 0, math.sin(la) * 158))
end

function World.Build()
	setupLighting()
	buildTerrain()
	local root = folder("Map", workspace)
	local plots = folder("Plots", workspace)
	for i = 1, Config.PlotCount do
		buildPlot(plots, i)
	end
	buildCenter(root)
	buildDecor(root)

	-- вращение луча маяка
	task.spawn(function()
		local lamp = World.Lighthouse and World.Lighthouse:FindFirstChild("Lamp") :: BasePart?
		if not lamp then
			return
		end
		local base = lamp.CFrame
		local t = 0
		while true do
			t += task.wait(0.05)
			lamp.CFrame = base * CFrame.Angles(0, t * 0.8, 0)
		end
	end)
end

function World.PlotOf(player: Player)
	for _, plot in ipairs(World.Plots) do
		if plot.Owner == player then
			return plot
		end
	end
	return nil
end

return World
