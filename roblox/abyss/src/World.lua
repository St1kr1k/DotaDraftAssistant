-- Постройка мира «В Бездну»: поверхность, яма со спиральной лестницей, слои, стражи, раскопы, алтарь.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local World = {}

local SY = Config.SURFACE_Y
local WALL_R = 37.5
local SEGMENTS = 24

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

local function billboard(adornee: BasePart, size: UDim2, offset: Vector3, maxDistance: number, alwaysOnTop: boolean?): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffsetWorldSpace = offset
	bb.AlwaysOnTop = alwaysOnTop == true
	bb.LightInfluence = 0
	bb.MaxDistance = maxDistance
	bb.Adornee = adornee
	bb.Parent = adornee
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

-- CFrame ступени: ось X смотрит от центра наружу
local function stepCFrame(n: number): CFrame
	local pos = Config.stepPosition(n)
	return CFrame.new(pos - Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, -Config.stepAngle(n), 0)
end
World.stepCFrame = stepCFrame

-- Точка, куда ставить игрока на ступени n
function World.standCFrame(n: number): CFrame
	local pos = Config.stepPosition(n) + Vector3.new(0, 3.5, 0)
	-- смотрим вниз по лестнице
	local ahead = Config.stepPosition(n + 1) + Vector3.new(0, 3.5, 0)
	return CFrame.lookAt(pos, ahead)
end

--------------------------------------------------------------------------------
-- Поверхность
--------------------------------------------------------------------------------
local leaderRows: { TextLabel } = {}

local function buildSurface(root: Instance): (BasePart, CFrame)
	local surface = Instance.new("Model")
	surface.Name = "Surface"
	local grass = Color3.fromRGB(80, 130, 70)

	-- Кольцо вокруг ямы
	for i = 0, SEGMENTS - 1 do
		local a = i / SEGMENTS * math.pi * 2
		local r = (WALL_R + 62) / 2
		part(surface, {
			Name = "Ring",
			Size = Vector3.new(62 - WALL_R + 1, 4, 2 * math.pi * 62 / SEGMENTS + 1),
			CFrame = CFrame.new(math.cos(a) * r, SY - 2, math.sin(a) * r) * CFrame.Angles(0, -a, 0),
			Color = grass,
			Material = Enum.Material.Grass,
		})
	end
	-- Земля вокруг (квадрат с дырой)
	local H = 44 -- полуширина дыры (кольцо её перекрывает)
	local S = 400
	local function slab(cx: number, cz: number, sx: number, sz: number)
		part(surface, {
			Name = "Ground",
			Size = Vector3.new(sx, 4, sz),
			CFrame = CFrame.new(cx, SY - 2.02, cz),
			Color = grass,
			Material = Enum.Material.Grass,
		})
	end
	slab(0, (H + S) / 2, 2 * S, S - H)
	slab(0, -(H + S) / 2, 2 * S, S - H)
	slab((H + S) / 2, 0, S - H, 2 * H)
	slab(-(H + S) / 2, 0, S - H, 2 * H)

	-- Ограждение у края ямы с проходом к первой ступени
	for i = 0, SEGMENTS - 1 do
		local a = (i + 0.5) / SEGMENTS * math.pi * 2
		local deg = math.deg(a)
		if deg > 22 and deg < 345 then
			part(surface, {
				Name = "Fence",
				Size = Vector3.new(1, 3, 2 * math.pi * WALL_R / SEGMENTS + 0.6),
				CFrame = CFrame.new(math.cos(a) * (WALL_R + 0.5), SY + 1.5, math.sin(a) * (WALL_R + 0.5)) * CFrame.Angles(0, -a, 0),
				Color = Color3.fromRGB(110, 80, 50),
				Material = Enum.Material.WoodPlanks,
			})
		end
	end

	-- Вход: табличка
	local signPost = part(surface, {
		Name = "EntrySign",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(WALL_R + 6, SY + 9, -6),
		Transparency = 1,
		CanCollide = false,
	})
	local bb = billboard(signPost, UDim2.fromOffset(520, 100), Vector3.zero, 400)
	text(bb, { Size = UDim2.fromScale(1, 0.65), Text = "⬇ В БЕЗДНУ ⬇", TextColor3 = Color3.fromRGB(255, 220, 120) })
	text(bb, {
		Size = UDim2.fromScale(1, 0.35),
		Position = UDim2.fromScale(0, 0.65),
		Text = "Покупай ступени и спускайся глубже",
		Font = Enum.Font.GothamBold,
	})

	-- Деревья вокруг
	local rng = Random.new(11)
	for _ = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(80, 300)
		local pos = Vector3.new(math.cos(a) * r, SY, math.sin(a) * r)
		local h = rng:NextNumber(8, 16)
		part(surface, { Size = Vector3.new(1.6, h, 1.6), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)), Color = Color3.fromRGB(100, 70, 45), Material = Enum.Material.Wood })
		local crown = part(surface, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(h * 0.8, h * 0.8, h * 0.8),
			CFrame = CFrame.new(pos + Vector3.new(0, h, 0)),
			Color = Color3.fromRGB(60 + rng:NextInteger(0, 40), 140 + rng:NextInteger(0, 40), 60),
			Material = Enum.Material.Grass,
		})
		crown.CastShadow = false
	end

	-- Алтарь званий
	local altarPos = Vector3.new(-62, SY, 30)
	part(surface, {
		Name = "AltarBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 16, 16),
		CFrame = CFrame.new(altarPos + Vector3.new(0, 1, 0)) * A(0, 0, 90),
		Color = Color3.fromRGB(70, 60, 90),
		Material = Enum.Material.Marble,
	})
	local orb = part(surface, {
		Name = "AltarOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(altarPos + Vector3.new(0, 7, 0)),
		Color = Color3.fromRGB(200, 120, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local orbLight = Instance.new("PointLight")
	orbLight.Color = Color3.fromRGB(200, 120, 255)
	orbLight.Range = 20
	orbLight.Brightness = 2
	orbLight.Parent = orb
	part(surface, {
		Name = "AltarPillar",
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(altarPos + Vector3.new(0, 3.5, 0)) * A(0, 45, 0),
		Color = Color3.fromRGB(90, 80, 110),
		Material = Enum.Material.Marble,
	})
	local altarBB = billboard(orb, UDim2.fromOffset(300, 70), Vector3.new(0, 5, 0), 150)
	text(altarBB, { Size = UDim2.fromScale(1, 0.6), Text = "🎖 Алтарь званий", TextColor3 = Color3.fromRGB(230, 180, 255) })
	text(altarBB, { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.6), Text = "Крути звания — они умножают доход", Font = Enum.Font.GothamBold })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RollPrompt"
	prompt.ActionText = "Крутить звание"
	prompt.ObjectText = "Алтарь"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = orb

	-- Табло рекордов
	local board = part(surface, {
		Name = "Leaderboard",
		Size = Vector3.new(26, 22, 1),
		CFrame = CFrame.new(62, SY + 13, 40) * A(0, -120, 0),
		Color = Color3.fromRGB(25, 22, 35),
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Parent = board
	text(sg, { Size = UDim2.new(1, 0, 0, 90), Text = "🏆 Глубже всех", TextColor3 = Color3.fromRGB(255, 205, 60) })
	for i = 1, 10 do
		leaderRows[i] = text(sg, {
			Size = UDim2.new(1, -40, 0, 50),
			Position = UDim2.fromOffset(20, 95 + (i - 1) * 56),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
		})
	end
	leaderRows[1].Text = "Загрузка…"

	local spawnCFrame = CFrame.new(0, SY + 4, 62) * CFrame.Angles(0, 0, 0)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, SY + 0.5, 62)
	spawn.Color = Color3.fromRGB(255, 200, 80)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = surface

	surface.Parent = root
	return orb, spawnCFrame
end

function World.setLeaderboard(rows: { { name: string, value: number } })
	for i = 1, 10 do
		local r = rows[i]
		if r then
			local medal = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or (i .. ".")
			local layer = Config.layerOfStep(r.value)
			leaderRows[i].Text = string.format("%s %s — ⬇ %d (%s)", medal, r.name, r.value, Config.Layers[layer].name)
		else
			leaderRows[i].Text = i == 1 and "Пока пусто — стань первым!" or ""
		end
	end
end

--------------------------------------------------------------------------------
-- Стражи
--------------------------------------------------------------------------------
export type Boss = { layer: number, model: Model, root: BasePart, prompt: ProximityPrompt }

local function buildBoss(layerInfo: Config.Layer, parent: Instance): Boss
	local L = layerInfo.index
	local stepN = Config.bossStep(L) + 2
	local base = stepCFrame(stepN) * CFrame.new(0, 0.6, 0)
	-- страж смотрит вверх по лестнице
	local up = Config.stepPosition(stepN - 3)
	local look = CFrame.lookAt(base.Position, Vector3.new(up.X, base.Position.Y, up.Z))
	local c = layerInfo.bossColor
	local model = Instance.new("Model")
	model.Name = "Boss" .. L
	local size = 1 + L * 0.08
	local function bp(sz: Vector3, off: CFrame, color: Color3?, mat: Enum.Material?, shape: Enum.PartType?): Part
		local p = part(model, {
			Size = sz * size,
			CFrame = look * CFrame.new(off.Position * size) * off.Rotation,
			Color = color or c,
			Material = mat or layerInfo.material,
			CanCollide = false,
		})
		if shape then
			p.Shape = shape
		end
		return p
	end
	local root = bp(Vector3.new(7, 7, 6), CFrame.new(0, 5.5, 0))
	bp(Vector3.new(5, 4, 4), CFrame.new(0, 10.5, -0.5))
	bp(Vector3.new(1.2, 1.2, 0.4), CFrame.new(-1.2, 11, -2.6), layerInfo.glow, Enum.Material.Neon)
	bp(Vector3.new(1.2, 1.2, 0.4), CFrame.new(1.2, 11, -2.6), layerInfo.glow, Enum.Material.Neon)
	bp(Vector3.new(2, 6, 2), CFrame.new(-5, 5, 0) * A(0, 0, -15))
	bp(Vector3.new(2, 6, 2), CFrame.new(5, 5, 0) * A(0, 0, 15))
	bp(Vector3.new(2.2, 3, 2.2), CFrame.new(-2, 1.5, 0))
	bp(Vector3.new(2.2, 3, 2.2), CFrame.new(2, 1.5, 0))
	bp(Vector3.new(1, 3, 1), CFrame.new(-1.8, 13.5, 0) * A(0, 0, 20), layerInfo.glow, Enum.Material.Neon)
	bp(Vector3.new(1, 3, 1), CFrame.new(1.8, 13.5, 0) * A(0, 0, -20), layerInfo.glow, Enum.Material.Neon)
	root.Name = "Root"
	local light = Instance.new("PointLight")
	light.Color = layerInfo.glow
	light.Range = 24
	light.Brightness = 2
	light.Parent = root
	local bb = billboard(root, UDim2.fromOffset(320, 70), Vector3.new(0, 14 * size, 0), 120)
	text(bb, { Size = UDim2.fromScale(1, 0.6), Text = "⚔ " .. layerInfo.boss, TextColor3 = layerInfo.glow })
	text(bb, {
		Size = UDim2.fromScale(1, 0.4),
		Position = UDim2.fromScale(0, 0.6),
		Text = "Страж слоя " .. L .. " · ❤ " .. Config.format(Config.bossHP(L)),
		Font = Enum.Font.GothamBold,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FightPrompt"
	prompt.ActionText = "Сразиться"
	prompt.ObjectText = layerInfo.boss
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	model:SetAttribute("Layer", L)
	model.Parent = parent
	return { layer = L, model = model, root = root, prompt = prompt }
end

--------------------------------------------------------------------------------
-- Раскопы
--------------------------------------------------------------------------------
export type DigSite = { layer: number, root: BasePart, prompt: ProximityPrompt }

local function buildDigSite(layerInfo: Config.Layer, parent: Instance): DigSite
	local L = layerInfo.index
	local n = Config.digSiteStep(L)
	local cf = stepCFrame(n) * CFrame.new(5, 0.6, 0)
	local model = Instance.new("Model")
	model.Name = "Dig" .. L
	local mound = part(model, {
		Name = "Mound",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = layerInfo.wall,
		Material = layerInfo.material,
		CanCollide = false,
	})
	part(model, { Size = Vector3.new(0.3, 4, 0.3), CFrame = cf * CFrame.new(-1, 2.5, 1) * A(20, 0, 15), Color = Color3.fromRGB(120, 85, 50), Material = Enum.Material.Wood, CanCollide = false })
	part(model, { Size = Vector3.new(1.2, 1.4, 0.2), CFrame = cf * CFrame.new(-1.6, 0.6, 1.5) * A(20, 0, 15), Color = Color3.fromRGB(160, 160, 170), Material = Enum.Material.Metal, CanCollide = false })
	for i = 1, 3 do
		part(model, {
			Size = Vector3.new(0.6, 0.6, 0.6),
			CFrame = cf * CFrame.new(math.cos(i * 2) * 1.6, 2.4, math.sin(i * 2) * 1.6) * A(45, i * 30, 35),
			Color = layerInfo.glow,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
	end
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(layerInfo.glow)
	sparkle.Size = NumberSequence.new(0.4, 0)
	sparkle.Rate = 3
	sparkle.Lifetime = NumberRange.new(1, 1.5)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.SpreadAngle = Vector2.new(60, 60)
	sparkle.LightEmission = 1
	sparkle.Parent = mound
	local bb = billboard(mound, UDim2.fromOffset(240, 50), Vector3.new(0, 4.5, 0), 70)
	text(bb, { Size = UDim2.fromScale(1, 1), Text = "🦴 Раскоп: " .. layerInfo.name, TextColor3 = layerInfo.glow })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DigPrompt"
	prompt.ActionText = "Копать"
	prompt.ObjectText = "Раскоп"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = mound
	model.Parent = parent
	return { layer = L, root = mound, prompt = prompt }
end

--------------------------------------------------------------------------------
-- Яма
--------------------------------------------------------------------------------
local function buildPit(root: Instance): ({ Boss }, { DigSite })
	local pit = Instance.new("Folder")
	pit.Name = "Pit"
	local stepsFolder = Instance.new("Folder")
	stepsFolder.Name = "Steps"
	stepsFolder.Parent = pit
	local bosses = {}
	local digs = {}
	local layerH = Config.STEPS_PER_LAYER * Config.STEP_DROP

	for _, layer in ipairs(Config.Layers) do
		local L = layer.index
		local topY = SY - (L - 1) * layerH
		local midY = topY - layerH / 2
		-- Стены
		for i = 0, SEGMENTS - 1 do
			local a = (i + 0.5) / SEGMENTS * math.pi * 2
			part(pit, {
				Name = "Wall",
				Size = Vector3.new(2, layerH + 0.2, 2 * math.pi * WALL_R / SEGMENTS + 0.8),
				CFrame = CFrame.new(math.cos(a) * (WALL_R + 1), midY, math.sin(a) * (WALL_R + 1)) * CFrame.Angles(0, -a, 0),
				Color = layer.wall,
				Material = layer.material,
			})
		end
		-- Центральный столб
		part(pit, {
			Name = "Pillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(layerH + 0.2, Config.PIT_INNER * 2, Config.PIT_INNER * 2),
			CFrame = CFrame.new(0, midY, 0) * A(0, 0, 90),
			Color = layer.wall:Lerp(Color3.new(0, 0, 0), 0.2),
			Material = layer.material,
		})
		-- Светящаяся полоса на границе слоёв
		part(pit, {
			Name = "LayerRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, Config.PIT_INNER * 2 + 0.4, Config.PIT_INNER * 2 + 0.4),
			CFrame = CFrame.new(0, topY - 0.5, 0) * A(0, 0, 90),
			Color = layer.glow,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		-- Надпись слоя на столбе
		local first = (L - 1) * Config.STEPS_PER_LAYER + 1
		local signPos = Config.stepPosition(first)
		local dir = Vector3.new(signPos.X, 0, signPos.Z).Unit
		local signAnchor = part(pit, {
			Name = "LayerSign",
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(dir * (Config.PIT_INNER + 0.5) + Vector3.new(0, signPos.Y + 7, 0)),
			Transparency = 1,
			CanCollide = false,
		})
		local bb = billboard(signAnchor, UDim2.fromOffset(360, 70), Vector3.zero, 90)
		text(bb, { Size = UDim2.fromScale(1, 0.6), Text = string.format("Слой %d · %s", L, layer.name), TextColor3 = layer.glow })
		text(bb, {
			Size = UDim2.fromScale(1, 0.4),
			Position = UDim2.fromScale(0, 0.6),
			Text = string.format("ступени %d–%d", first, L * Config.STEPS_PER_LAYER),
			Font = Enum.Font.GothamBold,
		})

		table.insert(bosses, buildBoss(layer, pit))
		table.insert(digs, buildDigSite(layer, pit))
	end

	-- Ступени
	for n = 1, Config.MAX_STEP do
		local layer = Config.Layers[Config.layerOfStep(n)]
		local isBoss = n % Config.STEPS_PER_LAYER == 0
		local step = part(stepsFolder, {
			Name = tostring(n),
			Size = Vector3.new(Config.PIT_OUTER - Config.PIT_INNER + 1, 1.2, 6.4),
			CFrame = stepCFrame(n) * CFrame.new((Config.PIT_INNER + Config.PIT_OUTER) / 2 - Config.STEP_RADIUS, 0, 0),
			Color = isBoss and layer.glow or (n % 2 == 0 and layer.step or layer.step:Lerp(Color3.new(0, 0, 0), 0.12)),
			Material = isBoss and Enum.Material.Neon or layer.material,
		})
		if n % 10 == 0 then
			local bb = billboard(step, UDim2.fromOffset(90, 34), Vector3.new(4, 2.5, 0), 60)
			text(bb, { Size = UDim2.fromScale(1, 1), Text = "⬇ " .. n, TextColor3 = layer.glow })
		end
		if n % 6 == 0 then
			local lamp = part(stepsFolder, {
				Name = "Lamp",
				Size = Vector3.new(0.8, 0.8, 0.8),
				CFrame = stepCFrame(n) * CFrame.new(Config.PIT_INNER - Config.STEP_RADIUS + 0.4, 3, 0),
				Color = layer.glow,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			})
			local l = Instance.new("PointLight")
			l.Color = layer.glow
			l.Range = 18
			l.Brightness = 1.4
			l.Parent = lamp
		end
	end

	-- Площадка у входа (ступень 0, вровень с поверхностью)
	part(stepsFolder, {
		Name = "0",
		Size = Vector3.new(Config.PIT_OUTER - Config.PIT_INNER + 2, 1.2, 8),
		CFrame = stepCFrame(0),
		Color = Color3.fromRGB(120, 85, 55),
		Material = Enum.Material.WoodPlanks,
	})

	-- Дно
	local bottomY = SY - Config.MAX_STEP * Config.STEP_DROP - 2
	part(pit, {
		Name = "Bottom",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, WALL_R * 2 + 4, WALL_R * 2 + 4),
		CFrame = CFrame.new(0, bottomY, 0) * A(0, 0, 90),
		Color = Color3.fromRGB(10, 8, 18),
		Material = Enum.Material.Neon,
	})

	pit.Parent = root
	return bosses, digs
end

--------------------------------------------------------------------------------
function World.build(): { altar: BasePart, spawnCFrame: CFrame, bosses: { Boss }, digs: { DigSite } }
	Lighting.ClockTime = 16
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(60, 60, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 120)
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "DepthTint"
	cc.Saturation = 0.1
	cc.Parent = Lighting

	local root = Instance.new("Folder")
	root.Name = "Abyss"
	local altar, spawnCFrame = buildSurface(root)
	local bosses, digs = buildPit(root)
	root.Parent = workspace
	return { altar = altar, spawnCFrame = spawnCFrame, bosses = bosses, digs = digs }
end

return World
