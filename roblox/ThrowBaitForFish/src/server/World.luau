-- Строит весь мир скриптом при старте сервера: океан, остров, базы игроков
-- (забор, ворота, аквариум, турник), общий пирс для заброса, центр со статуей и магазинами, буи зон, вечернее освещение.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local FishBuilder = require(Shared.FishBuilder)

local World = {}
World.Plots = {} -- [index] = plot table
World.Pier = nil :: any

local terrain = workspace.Terrain

local GROUND_Y = 4
local DECK_Y = 4.6
local PLOT_R = 96
local PIER_START = 112
local PIER_END = 250
local PIER_W = 18
local END_W = 66
local END_DEPTH = 26

local rng = Random.new(1337)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local WOOD = rgb(170, 120, 75)
local WOOD_DARK = rgb(120, 82, 52)
local PLOT_COLORS = {
	rgb(255, 90, 90),
	rgb(255, 170, 50),
	rgb(255, 230, 70),
	rgb(90, 220, 110),
	rgb(70, 200, 255),
	rgb(90, 120, 255),
	rgb(190, 100, 255),
	rgb(255, 110, 200),
}

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
	t.Font = font or Enum.Font.LuckiestGuy
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = rgb(15, 15, 25)
	t.Parent = parent
	return t
end

local function surfaceSign(part: BasePart, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.CanvasSize = Vector2.new(500, 100)
	sg.LightInfluence = 0
	sg.Parent = part
	return label(sg, text, UDim2.fromScale(0.94, 0.86), UDim2.fromScale(0.03, 0.07), color)
end

-- ===== Освещение: вечер =====
local function setupLighting()
	Lighting.ClockTime = 17.55
	Lighting.Brightness = 2.2
	Lighting.Ambient = rgb(80, 70, 90)
	Lighting.OutdoorAmbient = rgb(160, 125, 135)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.GeographicLatitude = 25
	Lighting.ColorShift_Top = rgb(255, 200, 150)

	local atm = Instance.new("Atmosphere")
	atm.Density = 0.32
	atm.Offset = 0.15
	atm.Color = rgb(255, 205, 175)
	atm.Decay = rgb(130, 95, 160)
	atm.Glare = 0.6
	atm.Haze = 1.6
	atm.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.8
	bloom.Size = 30
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MainColor"
	cc.Saturation = 0.22
	cc.Contrast = 0.08
	cc.Brightness = 0.02
	cc.TintColor = rgb(255, 242, 232)
	cc.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.12
	rays.Spread = 0.7
	rays.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 18
	sky.MoonAngularSize = 9
	sky.StarCount = 3000
	sky.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.5
	clouds.Density = 0.6
	clouds.Color = rgb(255, 215, 200)
	clouds.Parent = terrain

	terrain.WaterColor = rgb(20, 130, 170)
	terrain.WaterTransparency = 0.5
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.22
	terrain.WaterWaveSpeed = 10
	terrain:SetMaterialColor(Enum.Material.Grass, rgb(95, 175, 75))
	terrain:SetMaterialColor(Enum.Material.Sand, rgb(240, 215, 160))
	terrain:SetMaterialColor(Enum.Material.Rock, rgb(130, 120, 120))
end

-- ===== Рельеф =====
local function buildTerrain()
	terrain:FillBlock(CFrame.new(0, -54, 0), Vector3.new(2000, 12, 2000), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -24, 0), Vector3.new(2000, 48, 2000), Enum.Material.Water)
	terrain:FillCylinder(CFrame.new(0, -26, 0), 44, 192, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -24.5, 0), 47, 178, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -23, 0), 50, 166, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, 0.5, 0), 7, 130, Enum.Material.Grass)
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		-- у пирса (угол 0) камней нет
		if i % 3 ~= 0 and math.abs(math.sin(a)) > 0.2 then
			local r = rng:NextNumber(150, 172)
			terrain:FillBall(Vector3.new(math.cos(a) * r, rng:NextNumber(-1, 1), math.sin(a) * r), rng:NextNumber(3, 6), Enum.Material.Rock)
		end
	end
	for _ = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(300, 900)
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
			Color = (i % 2 == 0) and rgb(70, 160, 70) or rgb(55, 135, 60),
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
		P({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1), Position = top + Vector3.new(math.cos(a) * 0.7, -0.8, math.sin(a) * 0.7), Color = rgb(110, 75, 40), Parent = m })
	end
end

local function bush(parent: Instance, pos: Vector3)
	local colors = { rgb(70, 150, 70), rgb(90, 170, 80), rgb(60, 130, 65) }
	for i = 1, 3 do
		local s = rng:NextNumber(2.5, 4.5)
		P({ Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = pos + Vector3.new(rng:NextNumber(-1.5, 1.5), s * 0.3, rng:NextNumber(-1.5, 1.5)), Color = colors[i], Material = Enum.Material.Grass, Parent = parent })
	end
	if rng:NextNumber() < 0.7 then
		local flower = ({ rgb(255, 120, 160), rgb(255, 230, 90), rgb(255, 255, 255), rgb(190, 120, 255) })[rng:NextInteger(1, 4)]
		for _ = 1, 4 do
			P({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), Position = pos + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(2.2, 3.4), rng:NextNumber(-2, 2)), Color = flower, Material = Enum.Material.Neon, CanCollide = false, Parent = parent })
		end
	end
end

local function lantern(parent: Instance, pos: Vector3, height: number?)
	local h = height or 5
	P({ Size = Vector3.new(0.5, h, 0.5), Position = pos + Vector3.new(0, h / 2, 0), Color = rgb(70, 50, 35), Material = Enum.Material.Wood, Parent = parent })
	local lamp = P({ Size = Vector3.new(1.1, 1.3, 1.1), Position = pos + Vector3.new(0, h + 0.4, 0), Color = rgb(255, 195, 110), Material = Enum.Material.Neon, CanCollide = false, Parent = parent })
	P({ Size = Vector3.new(1.5, 0.3, 1.5), Position = pos + Vector3.new(0, h + 1.2, 0), Color = rgb(60, 45, 30), Material = Enum.Material.Wood, Parent = parent })
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 180, 100)
	light.Range = 16
	light.Brightness = 1.8
	light.Shadows = false
	light.Parent = lamp
end

-- Деревянный забор по отрезку: столбики + две доски
local function fence(parent: Instance, a: Vector3, b: Vector3, height: number?)
	local h = height or 3.6
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local dir = (b - a).Unit
	local n = math.max(1, math.floor(len / 5))
	for i = 0, n do
		local p = a + dir * (len * i / n)
		P({ Size = Vector3.new(0.7, h + 0.4, 0.7), CFrame = CFrame.lookAt(p, p + dir) * CFrame.new(0, (h + 0.4) / 2, 0), Color = WOOD_DARK, Material = Enum.Material.Wood, Parent = parent })
	end
	local mid = (a + b) / 2
	for _, y in ipairs({ h * 0.38, h * 0.82 }) do
		P({ Size = Vector3.new(0.35, 0.75, len), CFrame = CFrame.lookAt(mid, mid + dir) * CFrame.new(0, y, 0), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = parent })
	end
end

-- ===== Турник (вид зависит от снаряда владельца) =====
local BAR_LOOKS = {
	{ Post = rgb(120, 80, 60), PostMat = Enum.Material.CorrodedMetal, Bar = rgb(150, 100, 70), BarMat = Enum.Material.CorrodedMetal },
	{ Post = rgb(70, 80, 95), PostMat = Enum.Material.Metal, Bar = rgb(220, 225, 235), BarMat = Enum.Material.Metal },
	{ Post = rgb(90, 70, 30), PostMat = Enum.Material.Metal, Bar = rgb(255, 205, 60), BarMat = Enum.Material.Foil },
	{ Post = rgb(60, 90, 120), PostMat = Enum.Material.Metal, Bar = rgb(140, 235, 255), BarMat = Enum.Material.Glass },
	{ Post = rgb(50, 30, 80), PostMat = Enum.Material.Metal, Bar = rgb(200, 110, 255), BarMat = Enum.Material.Neon },
	{ Post = rgb(70, 20, 20), PostMat = Enum.Material.Metal, Bar = rgb(255, 80, 80), BarMat = Enum.Material.Neon },
	{ Post = rgb(20, 60, 45), PostMat = Enum.Material.Metal, Bar = rgb(60, 255, 170), BarMat = Enum.Material.Neon },
}

function World.SetBarTier(barModel: Model, tier: number)
	local look = BAR_LOOKS[math.clamp(tier, 1, #BAR_LOOKS)]
	for _, p in ipairs(barModel:GetChildren()) do
		if p:IsA("BasePart") then
			if p.Name == "Bar" then
				p.Color = look.Bar
				p.Material = look.BarMat
			elseif p.Name == "Post" then
				p.Color = look.Post
				p.Material = look.PostMat
			end
		end
	end
	local bar = barModel:FindFirstChild("Bar")
	local sparkle = bar and bar:FindFirstChild("TierSparkle") :: ParticleEmitter?
	if sparkle then
		sparkle.Enabled = tier >= 4
		sparkle.Color = ColorSequence.new(look.Bar)
	end
end

local function pullUpBar(parent: Instance, cf: CFrame, index: number, withUpgrade: boolean): Model
	local m = model("PullUpBar", parent)
	for _, side in ipairs({ -1, 1 }) do
		local post = P({ Size = Vector3.new(0.8, 10.4, 0.8), CFrame = cf * CFrame.new(side * 3.4, 5.2, 0), Parent = m })
		post.Name = "Post"
		local foot = P({ Size = Vector3.new(1.8, 0.6, 1.8), CFrame = cf * CFrame.new(side * 3.4, 0.3, 0), Parent = m })
		foot.Name = "Post"
	end
	local bar = P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(7.6, 0.5, 0.5), CFrame = cf * CFrame.new(0, 9.8, 0), Parent = m })
	bar.Name = "Bar"
	bar:SetAttribute("BarId", index)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "TierSparkle"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Rate = 10
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Enabled = false
	sparkle.Parent = bar
	local mat = P({ Size = Vector3.new(6.6, 0.25, 4.4), CFrame = cf * CFrame.new(0, 0.12, 0), Color = rgb(255, 120, 60), CanCollide = false, Parent = m })
	mat.Name = "Mat"
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, -5, 0)
	att.Parent = bar
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TrainPrompt"
	prompt.ActionText = "Train"
	prompt.ObjectText = "Pull-up Bar"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = att
	if withUpgrade then
		local up = Instance.new("ProximityPrompt")
		up.Name = "BarUpgrade"
		up.ActionText = "Upgrade Bar"
		up.ObjectText = "Gym"
		up.KeyboardKeyCode = Enum.KeyCode.F
		up.HoldDuration = 0
		up.MaxActivationDistance = 9
		up.RequiresLineOfSight = false
		up.UIOffset = Vector2.new(0, 70)
		up.Parent = att
	end
	local bb = billboard(bar, UDim2.fromOffset(170, 44), Vector3.new(0, 2.4, 0), 70)
	label(bb, "💪 TRAIN", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), rgb(255, 230, 90))
	World.SetBarTier(m, 1)
	return m
end

-- ===== Аквариум (5 уровней вида) =====
local TANK_FRAMES = {
	{ Color = WOOD_DARK, Mat = Enum.Material.Wood },
	{ Color = rgb(150, 105, 65), Mat = Enum.Material.WoodPlanks },
	{ Color = rgb(255, 200, 60), Mat = Enum.Material.Foil },
	{ Color = rgb(80, 220, 255), Mat = Enum.Material.Neon },
	{ Color = rgb(255, 120, 230), Mat = Enum.Material.Neon },
}

local function buildTank(parent: Instance, cf: CFrame, tier: number, accent: Color3)
	local m = Instance.new("Model")
	m.Name = "Tank"
	local W = 18 + tier * 4
	local H = 9 + tier * 0.7
	local D = 8 + tier * 0.6
	local baseH = 1.6
	local frame = TANK_FRAMES[tier + 1] or TANK_FRAMES[1]
	P({ Size = Vector3.new(W + 2, baseH, D + 2), CFrame = cf * CFrame.new(0, baseH / 2, 0), Color = rgb(80, 85, 100), Material = Enum.Material.Slate, Parent = m })
	if tier >= 2 then
		P({ Size = Vector3.new(W + 2.4, 0.35, D + 2.4), CFrame = cf * CFrame.new(0, baseH - 0.15, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	end
	local glassY = baseH + H / 2
	local function wall(size: Vector3, offset: Vector3)
		P({ Size = size, CFrame = cf * CFrame.new(offset), Color = rgb(200, 240, 255), Material = Enum.Material.Glass, Transparency = 0.82, Parent = m })
	end
	wall(Vector3.new(W, H, 0.3), Vector3.new(0, glassY, -D / 2))
	wall(Vector3.new(W, H, 0.3), Vector3.new(0, glassY, D / 2))
	wall(Vector3.new(0.3, H, D), Vector3.new(-W / 2, glassY, 0))
	wall(Vector3.new(0.3, H, D), Vector3.new(W / 2, glassY, 0))
	for _, z in ipairs({ -D / 2, D / 2 }) do
		P({ Size = Vector3.new(W + 0.8, 0.6, 0.6), CFrame = cf * CFrame.new(0, baseH + H, z), Color = frame.Color, Material = frame.Mat, Parent = m })
	end
	for _, x in ipairs({ -W / 2, W / 2 }) do
		P({ Size = Vector3.new(0.6, 0.6, D + 0.8), CFrame = cf * CFrame.new(x, baseH + H, 0), Color = frame.Color, Material = frame.Mat, Parent = m })
		for _, z in ipairs({ -D / 2, D / 2 }) do
			P({ Size = Vector3.new(0.6, H, 0.6), CFrame = cf * CFrame.new(x, glassY, z), Color = frame.Color, Material = frame.Mat, Parent = m })
		end
	end
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
	light.Range = 14 + tier * 3
	light.Brightness = 1.4
	light.Parent = water
	local coralColors = { rgb(255, 110, 150), rgb(255, 170, 80), rgb(170, 110, 255), rgb(90, 220, 200) }
	for i = 1, 5 + tier * 3 do
		local x = rng:NextNumber(-W / 2 + 1.5, W / 2 - 1.5)
		local z = rng:NextNumber(0.5, D / 2 - 1.2)
		local h = rng:NextNumber(1.2, 3.2)
		local c = coralColors[(i % #coralColors) + 1]
		P({ Size = Vector3.new(0.5, h, 0.5), CFrame = cf * CFrame.new(x, baseH + 1 + h / 2, z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)), Color = c, CanCollide = false, Parent = m })
		P({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(x, baseH + 1 + h, z), Color = c, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	end
	if tier >= 1 then
		for _ = 1, 3 + tier * 2 do
			local x = rng:NextNumber(-W / 2 + 1, W / 2 - 1)
			local h = rng:NextNumber(3, H - 2)
			P({ Size = Vector3.new(0.35, h, 0.35), CFrame = cf * CFrame.new(x, baseH + 1 + h / 2, rng:NextNumber(1, D / 2 - 0.8)) * CFrame.Angles(0, 0, rng:NextNumber(-0.15, 0.15)), Color = rgb(60, 190, 90), Material = Enum.Material.Grass, CanCollide = false, Parent = m })
		end
	end
	if tier >= 4 then
		local chest = cf * CFrame.new(W / 2 - 3, baseH + 1.7, 0)
		P({ Size = Vector3.new(2.4, 1.4, 1.6), CFrame = chest, Color = rgb(140, 90, 50), Material = Enum.Material.Wood, CanCollide = false, Parent = m })
		local gold = P({ Size = Vector3.new(2, 0.5, 1.2), CFrame = chest * CFrame.new(0, 0.9, 0), Color = rgb(255, 210, 60), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
		local gl = Instance.new("PointLight")
		gl.Color = rgb(255, 200, 80)
		gl.Range = 8
		gl.Parent = gold
	end
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(rgb(220, 250, 255))
	bubbles.Size = NumberSequence.new(0.25)
	bubbles.Transparency = NumberSequence.new(0.3)
	bubbles.Lifetime = NumberRange.new(2, 3)
	bubbles.Rate = 6 + tier * 3
	bubbles.Speed = NumberRange.new(2.5, 4)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(10, 10)
	bubbles.LightEmission = 0.5
	bubbles.Parent = water
	-- кнопка улучшения у передней стенки
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, -(H - 1.6) / 2 + 1, -D / 2)
	att.Parent = water
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TankUpgrade"
	prompt.ActionText = "Upgrade Aquarium"
	prompt.ObjectText = "Aquarium"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = att
	local fish = folder("Fish", m)
	m:SetAttribute("Tier", tier)
	m.Parent = parent
	return m, water, fish, prompt
end

-- Пересобрать аквариум под новый уровень, рыб перенести
function World.RebuildTank(plot, tier: number)
	local oldFish = plot.FishFolder:GetChildren()
	local tank, water, fish, prompt = buildTank(plot.Model, plot.TankCf, tier, plot.Color)
	for _, f in ipairs(oldFish) do
		f.Parent = fish
		local len = f:GetAttribute("Length") or 2
		local half = water.Size / 2 - Vector3.new(len * 0.6, len * 0.35, len * 0.45)
		f:PivotTo(water.CFrame * CFrame.new(rng:NextNumber(-half.X, half.X), rng:NextNumber(-math.max(0.1, half.Y), math.max(0.1, half.Y)), 0))
	end
	plot.Tank:Destroy()
	plot.Tank, plot.Water, plot.FishFolder, plot.TankPrompt = tank, water, fish, prompt
	plot.TankTier = tier
	if World.OnTankPrompt then
		World.OnTankPrompt(plot)
	end
end

-- ===== База игрока =====
local function buildBase(root: Instance, index: number)
	local angle = (index - 0.5) / Config.PlotCount * math.pi * 2
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local center = dir * PLOT_R + Vector3.new(0, GROUND_Y, 0)
	-- -Z (LookVector) смотрит в центр острова: там ворота
	local cf = CFrame.lookAt(center, center - dir)
	local color = PLOT_COLORS[index]
	local m = model("Plot" .. index, root)
	local W, D = 46, 42

	P({ Size = Vector3.new(W, 1, D), CFrame = cf * CFrame.new(0, 0.1, 0), Color = rgb(215, 190, 150), Material = Enum.Material.WoodPlanks, Parent = m })
	-- неоновая окантовка цвета игрока
	for _, e in ipairs({ { 0, -D / 2, W, 0.5 }, { 0, D / 2, W, 0.5 }, { -W / 2, 0, 0.5, D }, { W / 2, 0, 0.5, D } }) do
		P({ Size = Vector3.new(e[3], 0.3, e[4]), CFrame = cf * CFrame.new(e[1], 0.7, e[2]), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	end
	-- забор: бока, зад, перед с проёмом под ворота
	local function L(x, z)
		return (cf * CFrame.new(x, 0.6, z)).Position
	end
	fence(m, L(-W / 2, -D / 2), L(-W / 2, D / 2))
	fence(m, L(W / 2, -D / 2), L(W / 2, D / 2))
	fence(m, L(-W / 2, D / 2), L(W / 2, D / 2))
	fence(m, L(-W / 2, -D / 2), L(-7.5, -D / 2))
	fence(m, L(7.5, -D / 2), L(W / 2, -D / 2))
	-- ворота
	for _, x in ipairs({ -7.5, 7.5 }) do
		P({ Size = Vector3.new(1.6, 13, 1.6), CFrame = cf * CFrame.new(x, 7, -D / 2), Color = WOOD_DARK, Material = Enum.Material.Wood, Parent = m })
		P({ Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), CFrame = cf * CFrame.new(x, 13.8, -D / 2), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	end
	local beam = P({ Size = Vector3.new(17, 3, 1.2), CFrame = cf * CFrame.new(0, 12.2, -D / 2), Color = rgb(70, 50, 35), Material = Enum.Material.Wood, Parent = m })
	local gateFront = surfaceSign(beam, Enum.NormalId.Front, "EMPTY BASE", rgb(255, 255, 255))
	local gateBack = surfaceSign(beam, Enum.NormalId.Back, "EMPTY BASE", rgb(255, 255, 255))
	-- флаг
	local poleCf = cf * CFrame.new(-W / 2 + 2.5, 0.6, D / 2 - 2.5)
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(18, 0.5, 0.5), CFrame = poleCf * CFrame.new(0, 9, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(230, 230, 235), Material = Enum.Material.Metal, Parent = m })
	local flag = P({ Size = Vector3.new(6, 3.6, 0.2), CFrame = poleCf * CFrame.new(3.1, 16, 0), Color = color, Material = Enum.Material.Fabric, CanCollide = false, Parent = m })
	flag.Name = "Flag"
	-- аквариум в глубине базы
	local tankCf = cf * CFrame.new(0, 0.6, 9)
	local tank, water, fishFolder, tankPrompt = buildTank(m, tankCf, 0, color)
	-- табличка дохода над аквариумом
	local signAnchor = P({ Size = Vector3.new(1, 1, 1), CFrame = tankCf * CFrame.new(0, 15, 0), Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
	signAnchor.Name = "Sign"
	local bb = billboard(signAnchor, UDim2.fromOffset(300, 100), Vector3.zero, 250)
	local ownerLabel = label(bb, "", UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0), rgb(255, 255, 255))
	ownerLabel.Name = "Owner"
	local incomeLabel = label(bb, "", UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5), rgb(120, 255, 120))
	incomeLabel.Name = "Income"
	-- турник
	local barModel = pullUpBar(m, cf * CFrame.new(15, 0.6, -10), index * 10 + 1, true)
	-- фонари у ворот
	lantern(m, L(-10.5, -D / 2 - 1.5), 6)
	lantern(m, L(10.5, -D / 2 - 1.5), 6)

	local plot = {
		Index = index,
		Model = m,
		CFrame = cf,
		Dir = dir,
		Color = color,
		TankCf = tankCf,
		Tank = tank,
		TankTier = 0,
		Water = water,
		FishFolder = fishFolder,
		TankPrompt = tankPrompt,
		OwnerLabel = ownerLabel,
		IncomeLabel = incomeLabel,
		GateLabels = { gateFront, gateBack },
		BarModel = barModel,
		BarPrompt = barModel:FindFirstChild("BarUpgrade", true),
		Bars = { barModel:FindFirstChild("Bar") },
		SpawnCf = cf * CFrame.new(0, 3.5, -12),
		Owner = nil :: Player?,
	}
	m:SetAttribute("PlotIndex", index)
	World.Plots[index] = plot
end

-- ===== Общий пирс =====
local function buoy(parent: Instance, pos: Vector3, zone: any, withLabel: boolean)
	local m = model("Buoy_" .. zone.Name, parent)
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 3.4, 3.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = zone.Color, Parent = m })
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3.6, 3.6), CFrame = CFrame.new(pos + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(255, 255, 255), Parent = m })
	P({ Size = Vector3.new(0.4, 4, 0.4), Position = pos + Vector3.new(0, 4, 0), Color = rgb(60, 60, 70), Material = Enum.Material.Metal, Parent = m })
	local lamp = P({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Position = pos + Vector3.new(0, 6.3, 0), Color = zone.Color, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	local light = Instance.new("PointLight")
	light.Color = zone.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = lamp
	if withLabel then
		local bb = billboard(lamp, UDim2.fromOffset(260, 80), Vector3.new(0, 4, 0), 900)
		label(bb, zone.Name, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0), zone.Color)
		label(bb, "💪 " .. tostring(Config.PowerForDistance(zone.Dist)) .. " Power", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6), rgb(255, 255, 255), Enum.Font.FredokaOne)
	end
end

local function buildPier(root: Instance)
	local m = model("Pier", root)
	local dir = Vector3.new(1, 0, 0)
	local right = Vector3.new(0, 0, 1)
	local function at(r: number, side: number, y: number): CFrame
		local p = dir * r + right * side + Vector3.new(0, y, 0)
		return CFrame.lookAt(p, p + dir)
	end
	-- дорожка от площади к пирсу
	local pathLen = PIER_START - 34
	P({ Size = Vector3.new(10, 0.6, pathLen), CFrame = at(34 + pathLen / 2, 0, GROUND_Y + 0.2), Color = rgb(200, 160, 110), Material = Enum.Material.WoodPlanks, Parent = m })
	for r = 44, PIER_START - 6, 16 do
		lantern(m, (at(r, -6.5, GROUND_Y)).Position, 5)
		lantern(m, (at(r + 8, 6.5, GROUND_Y)).Position, 5)
	end
	-- арка «FISHING PIER»
	for _, s in ipairs({ -10.5, 10.5 }) do
		P({ Size = Vector3.new(1.8, 16, 1.8), CFrame = at(PIER_START, s, DECK_Y + 7), Color = WOOD_DARK, Material = Enum.Material.Wood, Parent = m })
	end
	local arch = P({ Size = Vector3.new(24, 3.6, 1.4), CFrame = at(PIER_START, 0, DECK_Y + 15), Color = rgb(60, 40, 30), Material = Enum.Material.Wood, Parent = m })
	surfaceSign(arch, Enum.NormalId.Front, "🎣 FISHING PIER", rgb(120, 230, 255))
	surfaceSign(arch, Enum.NormalId.Back, "🎣 FISHING PIER", rgb(120, 230, 255))
	-- настил
	local len = PIER_END - PIER_START
	P({ Size = Vector3.new(PIER_W, 1, len), CFrame = at(PIER_START + len / 2, 0, DECK_Y - 0.5), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = m })
	for r = PIER_START + 4, PIER_END, 11 do
		for _, s in ipairs({ -PIER_W / 2 + 0.5, PIER_W / 2 - 0.5 }) do
			P({ Size = Vector3.new(1.1, 18, 1.1), CFrame = at(r, s, DECK_Y - 9.5), Color = WOOD_DARK, Material = Enum.Material.Wood, Parent = m })
		end
	end
	-- перила из досок
	for _, s in ipairs({ -PIER_W / 2 + 0.4, PIER_W / 2 - 0.4 }) do
		fence(m, (at(PIER_START, s, DECK_Y)).Position, (at(PIER_END, s, DECK_Y)).Position, 3.4)
	end
	for r = PIER_START + 12, PIER_END - 6, 24 do
		lantern(m, (at(r, -PIER_W / 2 + 1.2, DECK_Y)).Position, 5)
		lantern(m, (at(r + 12, PIER_W / 2 - 1.2, DECK_Y)).Position, 5)
	end
	-- широкая площадка на конце
	local endR = PIER_END + END_DEPTH / 2
	P({ Size = Vector3.new(END_W, 1, END_DEPTH), CFrame = at(endR, 0, DECK_Y - 0.5), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = m })
	for _, s in ipairs({ -END_W / 2 + 1, -END_W / 4, 0, END_W / 4, END_W / 2 - 1 }) do
		for _, r in ipairs({ PIER_END + 1, PIER_END + END_DEPTH - 1 }) do
			P({ Size = Vector3.new(1.2, 18, 1.2), CFrame = at(r, s, DECK_Y - 9.5), Color = WOOD_DARK, Material = Enum.Material.Wood, Parent = m })
		end
	end
	-- перила площадки: бока, перед (низкий), задние крылья
	fence(m, (at(PIER_END, -END_W / 2 + 0.4, DECK_Y)).Position, (at(PIER_END + END_DEPTH, -END_W / 2 + 0.4, DECK_Y)).Position, 3.4)
	fence(m, (at(PIER_END, END_W / 2 - 0.4, DECK_Y)).Position, (at(PIER_END + END_DEPTH, END_W / 2 - 0.4, DECK_Y)).Position, 3.4)
	fence(m, (at(PIER_END + END_DEPTH - 0.4, -END_W / 2, DECK_Y)).Position, (at(PIER_END + END_DEPTH - 0.4, END_W / 2, DECK_Y)).Position, 2.4)
	fence(m, (at(PIER_END + 0.4, -END_W / 2, DECK_Y)).Position, (at(PIER_END + 0.4, -PIER_W / 2, DECK_Y)).Position, 3.4)
	fence(m, (at(PIER_END + 0.4, PIER_W / 2, DECK_Y)).Position, (at(PIER_END + 0.4, END_W / 2, DECK_Y)).Position, 3.4)
	for _, s in ipairs({ -END_W / 2 + 1.2, END_W / 2 - 1.2 }) do
		lantern(m, (at(PIER_END + END_DEPTH - 1.5, s, DECK_Y)).Position, 6)
	end
	-- места для заброса
	local spots = {}
	local castR = PIER_END + END_DEPTH - 5
	for i = 0, 7 do
		local s = -END_W / 2 + 5 + i * ((END_W - 10) / 7)
		local spot = P({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 5.5, 5.5),
			CFrame = CFrame.new(dir * castR + right * s + Vector3.new(0, DECK_Y + 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = rgb(90, 230, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			Parent = m,
		})
		spot.Name = "CastSpot"
		table.insert(spots, spot)
	end
	local zonePart = P({
		Size = Vector3.new(END_W, 12, END_DEPTH),
		CFrame = at(endR, 0, DECK_Y + 5.5),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = m,
	})
	zonePart.Name = "CastZone"
	local signAnchor = P({ Size = Vector3.new(1, 1, 1), CFrame = at(endR, 0, DECK_Y + 11), Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
	local bb = billboard(signAnchor, UDim2.fromOffset(300, 70), Vector3.zero, 200)
	label(bb, "🎣 CAST HERE", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), rgb(120, 240, 255))

	local edge = dir * (PIER_END + END_DEPTH) + Vector3.new(0, Config.WaterY, 0)
	for z = 2, #GameData.Zones do
		local zone = GameData.Zones[z]
		local pos = edge + dir * zone.Dist
		buoy(m, pos - right * 42, zone, true)
		buoy(m, pos + right * 42, zone, false)
	end

	World.Pier = {
		Model = m,
		Dir = dir,
		Right = right,
		CastZone = zonePart,
		Spots = spots,
		Edge = edge,
	}
end

-- ===== Центр острова =====
local function kiosk(parent: Instance, cf: CFrame, title: string, color: Color3, promptName: string)
	local m = model(promptName, parent)
	P({ Size = Vector3.new(12, 3.5, 4), CFrame = cf * CFrame.new(0, 1.75, 0), Color = WOOD, Material = Enum.Material.WoodPlanks, Parent = m })
	P({ Size = Vector3.new(12.6, 0.4, 4.6), CFrame = cf * CFrame.new(0, 3.7, 0), Color = rgb(235, 225, 210), Material = Enum.Material.Wood, Parent = m })
	for _, x in ipairs({ -5.8, 5.8 }) do
		P({ Size = Vector3.new(0.6, 9, 0.6), CFrame = cf * CFrame.new(x, 4.5, 1.6), Color = WOOD_DARK, Material = Enum.Material.Wood, Parent = m })
	end
	for i = 0, 5 do
		P({ Class = "WedgePart", Size = Vector3.new(2.2, 1.4, 6), CFrame = cf * CFrame.new(-5.5 + i * 2.2, 9.6, -0.4) * CFrame.Angles(0, math.pi, 0), Color = (i % 2 == 0) and color or rgb(255, 255, 255), Parent = m })
	end
	local signPart = P({ Size = Vector3.new(10, 2.4, 0.4), CFrame = cf * CFrame.new(0, 11.6, 1.6), Color = rgb(60, 45, 35), Material = Enum.Material.Wood, Parent = m })
	surfaceSign(signPart, Enum.NormalId.Front, title, color)
	local lampPart = P({ Size = Vector3.new(0.6, 0.6, 0.6), CFrame = cf * CFrame.new(0, 8, -1), Transparency = 1, CanCollide = false, Parent = m })
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 200, 130)
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = lampPart
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
		P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 9 - i * 0.5, 9 - i * 0.5), CFrame = CFrame.new(pos + Vector3.new(0, 2 + i * 4, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = (i % 2 == 0) and rgb(240, 240, 240) or rgb(220, 60, 60), Parent = m })
	end
	local top = pos + Vector3.new(0, 34, 0)
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 8, 8), CFrame = CFrame.new(top - Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(50, 50, 60), Parent = m })
	local lamp = P({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = top, Color = rgb(255, 240, 170), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	lamp.Name = "Lamp"
	P({ Size = Vector3.new(6, 1.4, 6), Position = top + Vector3.new(0, 2.4, 0), Color = rgb(220, 60, 60), Parent = m })
	local spot = Instance.new("SpotLight")
	spot.Color = rgb(255, 240, 180)
	spot.Range = 60
	spot.Angle = 25
	spot.Brightness = 5
	spot.Face = Enum.NormalId.Front
	spot.Parent = lamp
	local pl = Instance.new("PointLight")
	pl.Color = rgb(255, 230, 160)
	pl.Range = 24
	pl.Parent = lamp
	return m
end

local function buildCenter(root: Instance)
	local m = model("Center", root)
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 70, 70), CFrame = CFrame.new(0, GROUND_Y + 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(215, 200, 180), Material = Enum.Material.Pavement, Parent = m })
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 20, 20), CFrame = CFrame.new(0, GROUND_Y + 3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(150, 150, 160), Material = Enum.Material.Slate, Parent = m })
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 22, 22), CFrame = CFrame.new(0, GROUND_Y + 6.2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(255, 205, 60), Material = Enum.Material.Foil, Parent = m })
	local statue = FishBuilder.Build("Megalodon", "Golden", 26, { static = true })
	statue:PivotTo(CFrame.new(0, GROUND_Y + 19, 0) * CFrame.Angles(0.35, math.rad(30), 0))
	statue.Name = "MegalodonStatue"
	statue.Parent = m
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		lantern(m, Vector3.new(math.cos(a) * 14, GROUND_Y, math.sin(a) * 14), 5)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(-26, GROUND_Y + 1.2, 0)
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
	kiosk(m, CFrame.lookAt(Vector3.new(-16, GROUND_Y, -30), Vector3.new(0, GROUND_Y, 0)), "SHOP", rgb(255, 140, 60), "ShopPrompt")
	kiosk(m, CFrame.lookAt(Vector3.new(-16, GROUND_Y, 30), Vector3.new(0, GROUND_Y, 0)), "SELL FISH", rgb(80, 220, 120), "SellPrompt")
	kiosk(m, CFrame.lookAt(Vector3.new(-34, GROUND_Y, 0), Vector3.new(0, GROUND_Y, 0)), "ROBUX SHOP", rgb(255, 210, 60), "StorePrompt")
	local gymBars = {}
	for i = 0, 3 do
		local a = math.rad(130 + i * 33)
		local p = Vector3.new(math.cos(a) * 42, GROUND_Y, math.sin(a) * 42)
		local bm = pullUpBar(m, CFrame.lookAt(p, Vector3.new(0, GROUND_Y, 0)), 900 + i, false)
		World.SetBarTier(bm, 2)
		table.insert(gymBars, bm:FindFirstChild("Bar"))
	end
	World.GymBars = gymBars
end

local function buildDecor(root: Instance)
	local m = model("Decor", root)
	for i = 1, Config.PlotCount - 1 do
		-- между базами (угол 0 — пирс, там пусто)
		local a = i / Config.PlotCount * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		for _, r in ipairs({ 80, 104, 124, 146 }) do
			local jitter = Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
			local y = r > 128 and 2 or GROUND_Y
			palm(m, dir * r + jitter + Vector3.new(0, y - 0.5, 0), rng:NextNumber(14, 22))
		end
		bush(m, dir * 92 + Vector3.new(rng:NextNumber(-3, 3), GROUND_Y, rng:NextNumber(-3, 3)))
		bush(m, dir * 60 + Vector3.new(rng:NextNumber(-3, 3), GROUND_Y, rng:NextNumber(-3, 3)))
		lantern(m, dir * 112 + Vector3.new(0, GROUND_Y, 0), 6)
	end
	for _, s in ipairs({ -1, 1 }) do
		palm(m, Vector3.new(150, 1.5, s * 26), 20)
		palm(m, Vector3.new(135, 1.5, s * 34), 17)
	end
	World.Lighthouse = lighthouse(m, Vector3.new(-158, 0, 0))
end

function World.Build()
	setupLighting()
	buildTerrain()
	local root = folder("Map", workspace)
	local plots = folder("Plots", workspace)
	for i = 1, Config.PlotCount do
		buildBase(plots, i)
	end
	buildPier(root)
	buildCenter(root)
	buildDecor(root)

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

-- Стоит ли игрок на площадке заброса
function World.InCastZone(pos: Vector3): boolean
	local zone = World.Pier and World.Pier.CastZone
	if not zone then
		return false
	end
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X + 1 and math.abs(rel.Y) <= half.Y + 2 and math.abs(rel.Z) <= half.Z + 1
end

return World
