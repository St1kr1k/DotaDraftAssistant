-- Общий мир «Маяк во Тьме»: земли, декор, маяк, обсерватория, табло.
-- Тьму, постройки, находки и теней каждый клиент рисует сам — у каждого игрока свой свет.
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

local function cyl(parent: Instance, pos: Vector3, height: number, diameter: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(pos) * A(0, 0, 90)
	return part(parent, props)
end

local function ball(parent: Instance, pos: Vector3, d: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.new(d, d, d)
	props.CFrame = CFrame.new(pos)
	return part(parent, props)
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

local function billboard(adornee: BasePart, size: UDim2, offset: Vector3, maxDistance: number): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffsetWorldSpace = offset
	bb.LightInfluence = 0
	bb.MaxDistance = maxDistance
	bb.Adornee = adornee
	bb.Parent = adornee
	return bb
end

--------------------------------------------------------------------------------
-- Земли
--------------------------------------------------------------------------------
local function buildGround(root: Instance)
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	local outer = Config.radius(Config.MAX_LIGHT) + 120
	cyl(ground, Vector3.new(0, -1.5, 0), 3, outer * 2, { Name = "Abyss", Color = Color3.fromRGB(8, 8, 12), Material = Enum.Material.Slate })
	for i = #Config.Zones, 1, -1 do
		local z = Config.Zones[i]
		local _, r = Config.zoneRange(i)
		cyl(ground, Vector3.new(0, -0.5 + i * -0.002 + 0.03 * (#Config.Zones - i + 1), 0), 1, r * 2 + (i == #Config.Zones and 30 or 0), {
			Name = "Zone" .. i,
			Color = z.ground,
			Material = z.material,
		})
	end
	ground.Parent = root
end

--------------------------------------------------------------------------------
-- Декор по зонам
--------------------------------------------------------------------------------
type Decor = (Instance, Vector3, Random, Config.Zone) -> ()

local WOOD = Color3.fromRGB(95, 70, 50)

local DECOR: { Decor } = {
	-- 1. Луг: цветы и камни
	function(f, p, rng, z)
		if rng:NextNumber() < 0.7 then
			part(f, { Size = Vector3.new(0.2, 1.4, 0.2), CFrame = CFrame.new(p + Vector3.new(0, 0.7, 0)), Color = Color3.fromRGB(80, 150, 70), CanCollide = false })
			local colors = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 160, 200), Color3.fromRGB(180, 200, 255) }
			ball(f, p + Vector3.new(0, 1.5, 0), 0.7, { Color = colors[rng:NextInteger(1, 3)], Material = Enum.Material.Neon, CanCollide = false })
		else
			local s = rng:NextNumber(1.5, 3)
			part(f, { Size = Vector3.new(s, s * 0.6, s * 0.8), CFrame = CFrame.new(p + Vector3.new(0, s * 0.25, 0)) * A(0, rng:NextNumber(0, 360), 8), Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Rock })
		end
	end,
	-- 2. Лес: деревья
	function(f, p, rng, z)
		local h = rng:NextNumber(10, 18)
		part(f, { Size = Vector3.new(1.4, h, 1.4), CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)), Color = WOOD, Material = Enum.Material.Wood })
		for k = 1, 3 do
			ball(f, p + Vector3.new(rng:NextNumber(-2, 2), h - 1 + k * 1.5, rng:NextNumber(-2, 2)), 7 - k, { Color = Color3.fromRGB(40, 90 + k * 15, 50), Material = Enum.Material.LeafyGrass, CastShadow = false })
		end
		if rng:NextNumber() < 0.5 then
			ball(f, p + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(3, 8), rng:NextNumber(-4, 4)), 0.4, { Color = z.accent, Material = Enum.Material.Neon, CanCollide = false })
		end
	end,
	-- 3. Болото: лужи, камыш, сухие деревья
	function(f, p, rng, z)
		local r = rng:NextNumber()
		if r < 0.4 then
			cyl(f, p + Vector3.new(0, 0.05, 0), 0.2, rng:NextNumber(5, 10), { Color = Color3.fromRGB(30, 60, 60), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false })
		elseif r < 0.75 then
			for k = 1, 5 do
				part(f, { Size = Vector3.new(0.2, rng:NextNumber(2, 4), 0.2), CFrame = CFrame.new(p + Vector3.new(k * 0.4 - 1, 1.5, rng:NextNumber(-0.6, 0.6))) * A(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10)), Color = Color3.fromRGB(90, 110, 60), CanCollide = false })
			end
			ball(f, p + Vector3.new(0, 3, 0), 0.5, { Color = z.accent, Material = Enum.Material.Neon, CanCollide = false })
		else
			local h = rng:NextNumber(6, 10)
			part(f, { Size = Vector3.new(1, h, 1), CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)) * A(0, 0, rng:NextNumber(-8, 8)), Color = Color3.fromRGB(60, 55, 50), Material = Enum.Material.Wood })
			part(f, { Size = Vector3.new(0.5, 4, 0.5), CFrame = CFrame.new(p + Vector3.new(1, h * 0.7, 0)) * A(0, 0, -50), Color = Color3.fromRGB(60, 55, 50), Material = Enum.Material.Wood })
		end
	end,
	-- 4. Руины: колонны и обломки стен
	function(f, p, rng, z)
		if rng:NextNumber() < 0.55 then
			local h = rng:NextNumber(4, 14)
			cyl(f, p + Vector3.new(0, h / 2, 0), h, 3, { Color = Color3.fromRGB(180, 170, 150), Material = Enum.Material.Marble })
			part(f, { Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(p + Vector3.new(0, 0.5, 0)), Color = Color3.fromRGB(160, 150, 130), Material = Enum.Material.Marble })
		else
			local w = rng:NextNumber(6, 12)
			part(f, { Size = Vector3.new(w, rng:NextNumber(3, 7), 1.5), CFrame = CFrame.new(p + Vector3.new(0, 2, 0)) * A(0, rng:NextNumber(0, 180), 0), Color = Color3.fromRGB(140, 130, 115), Material = Enum.Material.Cobblestone })
		end
	end,
	-- 5. Кристальное поле
	function(f, p, rng, z)
		for k = 1, rng:NextInteger(1, 4) do
			local s = rng:NextNumber(1, 3)
			part(f, {
				Size = Vector3.new(s, s * rng:NextNumber(2.5, 5), s),
				CFrame = CFrame.new(p + Vector3.new(rng:NextNumber(-2, 2), s, rng:NextNumber(-2, 2))) * A(rng:NextNumber(-25, 25), rng:NextNumber(0, 90), rng:NextNumber(-25, 25)),
				Color = z.accent:Lerp(Color3.fromRGB(90, 200, 255), rng:NextNumber()),
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				CastShadow = false,
			})
		end
	end,
	-- 6. Грибная чаща
	function(f, p, rng, z)
		local h = rng:NextNumber(4, 12)
		cyl(f, p + Vector3.new(0, h / 2, 0), h, h * 0.18 + 0.6, { Color = Color3.fromRGB(220, 220, 200), Material = Enum.Material.SmoothPlastic })
		cyl(f, p + Vector3.new(0, h, 0), 1.2, h * 0.9, { Color = z.accent:Lerp(Color3.fromRGB(120, 60, 255), rng:NextNumber()), Material = Enum.Material.Neon, CastShadow = false })
	end,
	-- 7. Пепельная пустошь
	function(f, p, rng, z)
		local s = rng:NextNumber(2, 6)
		part(f, { Size = Vector3.new(s, s * 0.8, s), CFrame = CFrame.new(p + Vector3.new(0, s * 0.3, 0)) * A(rng:NextNumber(0, 30), rng:NextNumber(0, 90), 0), Color = Color3.fromRGB(40, 35, 35), Material = Enum.Material.Basalt })
		if rng:NextNumber() < 0.6 then
			ball(f, p + Vector3.new(s * 0.3, s * 0.5, 0), 0.8, { Color = z.accent, Material = Enum.Material.Neon, CanCollide = false })
		end
	end,
	-- 8. Ледяной берег
	function(f, p, rng, z)
		if rng:NextNumber() < 0.6 then
			local h = rng:NextNumber(4, 12)
			part(f, { Size = Vector3.new(h * 0.3, h, h * 0.3), CFrame = CFrame.new(p + Vector3.new(0, h * 0.4, 0)) * A(rng:NextNumber(-15, 15), 45, rng:NextNumber(-15, 15)), Color = z.accent, Material = Enum.Material.Ice, Transparency = 0.2 })
		else
			ball(f, p, rng:NextNumber(4, 8), { Color = Color3.fromRGB(235, 240, 250), Material = Enum.Material.Snow })
		end
	end,
	-- 9. Звёздные дюны
	function(f, p, rng, z)
		if rng:NextNumber() < 0.6 then
			ball(f, p + Vector3.new(0, -2, 0), rng:NextNumber(6, 12), { Color = Color3.fromRGB(140, 120, 170), Material = Enum.Material.Sand })
		else
			ball(f, p + Vector3.new(0, 0.6, 0), rng:NextNumber(0.8, 1.6), { Color = z.accent, Material = Enum.Material.Neon, CanCollide = false })
		end
	end,
	-- 10. Край мира: обелиски
	function(f, p, rng, z)
		local h = rng:NextNumber(8, 20)
		part(f, { Size = Vector3.new(2, h, 2), CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)) * A(0, rng:NextNumber(0, 90), 0), Color = Color3.fromRGB(10, 10, 15), Material = Enum.Material.Glass })
		part(f, { Size = Vector3.new(0.3, h * 0.8, 0.3), CFrame = CFrame.new(p + Vector3.new(0, h / 2, 1.05)), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, CanCollide = false })
	end,
}

local function buildDecor(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	local rng = Random.new(2026)
	for i, z in ipairs(Config.Zones) do
		local zf = Instance.new("Folder")
		zf.Name = "Zone" .. i
		local inner, outer = Config.zoneRange(i)
		inner = math.max(inner, 40) + 3
		outer -= 3
		local count = math.floor((outer * outer - inner * inner) / 900)
		for _ = 1, count do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = math.sqrt(rng:NextNumber(inner * inner, outer * outer))
			DECOR[i](zf, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng, z)
		end
		zf.Parent = folder
	end
	folder.Parent = root
end

--------------------------------------------------------------------------------
-- Маяк, обсерватория, табло
--------------------------------------------------------------------------------
local leaderRows: { TextLabel } = {}

local function buildCenter(root: Instance): (ProximityPrompt, CFrame)
	local c = Instance.new("Model")
	c.Name = "Lighthouse"
	local WHITE = Color3.fromRGB(240, 238, 230)
	local REDC = Color3.fromRGB(200, 60, 55)
	-- Площадка
	cyl(c, Vector3.new(0, 0.2, 0), 0.6, 30, { Color = Color3.fromRGB(150, 140, 130), Material = Enum.Material.Cobblestone })
	-- Башня из полос
	local y = 0.5
	for i = 1, 8 do
		local h = 4
		local d = 11 - i * 0.55
		cyl(c, Vector3.new(0, y + h / 2, 0), h, d, { Color = i % 2 == 0 and REDC or WHITE, Material = Enum.Material.SmoothPlastic })
		y += h
	end
	-- Галерея и фонарная комната
	cyl(c, Vector3.new(0, y + 0.4, 0), 0.8, 10, { Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal })
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		part(c, { Size = Vector3.new(0.3, 1.6, 0.3), CFrame = CFrame.new(math.cos(a) * 4.7, y + 1.6, math.sin(a) * 4.7), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal })
	end
	cyl(c, Vector3.new(0, y + 3.2, 0), 4.4, 6.4, { Name = "LampRoom", Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 0.6, CanCollide = false })
	cyl(c, Vector3.new(0, y + 6, 0), 1.2, 7, { Color = REDC, Material = Enum.Material.SmoothPlastic })
	ball(c, Vector3.new(0, y + 7, 0), 1.2, { Color = REDC })
	local lampY = y + 3.2
	c:SetAttribute("LampY", lampY)
	-- Дверь
	local door = part(c, { Name = "Door", Size = Vector3.new(0.4, 5, 3), CFrame = CFrame.new(5.4, 3, 0), Color = Color3.fromRGB(90, 60, 40), Material = Enum.Material.WoodPlanks })
	door.Name = "Door"

	-- Обсерватория (рулетка созвездий)
	local oa = math.rad(344)
	local opos = Vector3.new(math.cos(oa) * Config.BUILDING_RING, 0, math.sin(oa) * Config.BUILDING_RING)
	local obs = Instance.new("Model")
	obs.Name = "Observatory"
	cyl(obs, opos + Vector3.new(0, 3, 0), 6, 9, { Color = Color3.fromRGB(70, 65, 90), Material = Enum.Material.Brick })
	ball(obs, opos + Vector3.new(0, 6, 0), 9, { Color = Color3.fromRGB(180, 180, 200), Material = Enum.Material.Metal })
	part(obs, {
		Size = Vector3.new(1.4, 1.4, 6),
		CFrame = CFrame.lookAt(opos + Vector3.new(0, 9, 0), opos + Vector3.new(0, 14, 0) + (opos.Unit * 3)) * CFrame.new(0, 0, -2),
		Color = Color3.fromRGB(60, 60, 70),
		Material = Enum.Material.Metal,
	})
	local orb = ball(obs, opos + Vector3.new(0, 13, 0), 1.4, { Name = "Star", Color = Color3.fromRGB(200, 160, 255), Material = Enum.Material.Neon, CanCollide = false })
	local bb = billboard(orb, UDim2.fromOffset(300, 64), Vector3.new(0, 2.5, 0), 120)
	text(bb, { Size = UDim2.fromScale(1, 0.6), Text = "🔭 Обсерватория", TextColor3 = Color3.fromRGB(220, 190, 255) })
	text(bb, { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.6), Text = "Зажги созвездие — оно умножит сияние", Font = Enum.Font.GothamBold })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Искать созвездие"
	prompt.ObjectText = "Телескоп"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = orb
	obs.Parent = c

	-- Табло
	local board = part(c, {
		Name = "Leaderboard",
		Size = Vector3.new(20, 17, 0.8),
		CFrame = CFrame.lookAt(Vector3.new(-26, 9, -12), Vector3.new(0, 9, 0)),
		Color = Color3.fromRGB(22, 20, 30),
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 36
	sg.LightInfluence = 0
	sg.Parent = board
	text(sg, { Size = UDim2.new(1, 0, 0, 80), Text = "🏆 Самый яркий свет", TextColor3 = Color3.fromRGB(255, 220, 120) })
	for i = 1, 10 do
		leaderRows[i] = text(sg, {
			Size = UDim2.new(1, -40, 0, 46),
			Position = UDim2.fromOffset(20, 84 + (i - 1) * 52),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold,
		})
	end
	leaderRows[1].Text = "Загрузка…"

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(11, 0.7, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Duration = 0
	spawn.Parent = c

	c.Parent = root
	return prompt, CFrame.lookAt(Vector3.new(12, 3.5, 0), Vector3.new(30, 3.5, 0))
end

function World.setLeaderboard(rows: { { name: string, value: number } })
	for i = 1, 10 do
		local r = rows[i]
		if r then
			local medal = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or (i .. ".")
			leaderRows[i].Text = string.format("%s %s — 💡 %d (%s)", medal, r.name, r.value, Config.Zones[Config.zoneOfLevel(r.value)].name)
		else
			leaderRows[i].Text = i == 1 and "Пока пусто — стань первым!" or ""
		end
	end
end

function World.build(): { rollPrompt: ProximityPrompt, spawnCFrame: CFrame }
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(70, 70, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(80, 85, 120)
	Lighting.FogColor = Color3.fromRGB(5, 5, 10)
	Lighting.FogStart = 350
	Lighting.FogEnd = 1400
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.8
	bloom.Size = 26
	bloom.Threshold = 1.3
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.1
	cc.Parent = Lighting

	local root = Instance.new("Folder")
	root.Name = "World"
	buildGround(root)
	buildDecor(root)
	local prompt, spawnCFrame = buildCenter(root)
	root.Parent = workspace
	return { rollPrompt = prompt, spawnCFrame = spawnCFrame }
end

return World
