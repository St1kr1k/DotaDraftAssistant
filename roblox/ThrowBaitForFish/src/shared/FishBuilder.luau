-- Собирает 3D-модель рыбы из деталей (без загрузки мешей).
-- Модель длиной 1 «единица» вдоль оси Z, голова смотрит в -Z (как LookVector), потом масштабируется.
-- Body — заякоренная главная деталь, остальные приварены к ней: двигать можно одним Body.CFrame.

local CollectionService = game:GetService("CollectionService")

local GameData = require(script.Parent.GameData)

local FishBuilder = {}

local BLACK = Color3.fromRGB(20, 20, 25)
local WHITE = Color3.fromRGB(250, 250, 250)

type Ctx = {
	model: Model,
	s: number,
	def: any,
	parts: { BasePart },
}

local function newPart(ctx: Ctx, kind: string, name: string, size: Vector3, cf: CFrame, color: Color3, tag: string?): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if kind == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif kind == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
		p = part
	end
	p.Name = name
	p.Size = Vector3.new(math.max(0.05, size.X * ctx.s), math.max(0.05, size.Y * ctx.s), math.max(0.05, size.Z * ctx.s))
	p.CFrame = CFrame.new(cf.Position * ctx.s) * cf.Rotation
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "Sphere" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	if tag then
		p:SetAttribute("Role", tag) -- "fixed" (глаза/зубы), "accent", "main", "belly"
	end
	p.Parent = ctx.model
	table.insert(ctx.parts, p)
	return p
end

local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end

local function sphere(ctx: Ctx, name, sx, sy, sz, cf, color, tag)
	return newPart(ctx, "Sphere", name, Vector3.new(sx, sy, sz), cf, color, tag)
end

local function eyes(ctx: Ctx, x: number, y: number, z: number, size: number, cute: boolean?)
	for _, side in ipairs({ -1, 1 }) do
		if cute or size >= 0.1 then
			newPart(ctx, "Ball", "Eye", Vector3.new(size, size, size), at(side * x, y, z), WHITE, "fixed")
			local ps = size * 0.55
			newPart(ctx, "Ball", "Pupil", Vector3.new(ps, ps, ps), at(side * (x + size * 0.32), y + size * 0.05, z - size * 0.18), BLACK, "fixed")
		else
			newPart(ctx, "Ball", "Pupil", Vector3.new(size, size, size), at(side * x, y, z), BLACK, "fixed")
		end
	end
end

local function tailLobes(ctx: Ctx, z: number, spread: number, len: number, color: Color3, upperScale: number?, lowerScale: number?)
	local u = upperScale or 1
	local l = lowerScale or 1
	sphere(ctx, "Tail", 0.05, 0.13 * u, len * u, at(0, spread * u, z, -0.65, 0, 0), color, "accent")
	sphere(ctx, "Tail", 0.05, 0.13 * l, len * l, at(0, -spread * l, z, 0.65, 0, 0), color, "accent")
end

-- ===== Формы =====

local Shapes = {}

function Shapes.fish(ctx: Ctx)
	local d = ctx.def
	local t = d.Tall and 1.55 or 1
	sphere(ctx, "Body", 0.42, 0.5 * t, 1, at(0, 0, 0), d.C1, "main")
	sphere(ctx, "Belly", 0.38, 0.34 * t, 0.84, at(0, -0.09 * t, 0.02), d.C2, "belly")
	tailLobes(ctx, 0.6, 0.1 * t, 0.34, d.C3)
	sphere(ctx, "Fin", 0.04, 0.24 * t, 0.46, at(0, 0.22 * t, 0.06), d.C3, "accent")
	sphere(ctx, "Fin", 0.04, 0.14 * t, 0.3, at(0, -0.22 * t, 0.16), d.C3, "accent")
	for _, side in ipairs({ -1, 1 }) do
		sphere(ctx, "Fin", 0.2, 0.04, 0.14, at(side * 0.22, -0.06, -0.1, 0, side * 0.5, side * 0.3), d.C3, "accent")
	end
	eyes(ctx, 0.16, 0.06 * t, -0.3, d.Big and 0.13 or 0.16)
	if d.Stripes then
		for _, z in ipairs({ -0.17, 0.16 }) do
			local k = math.sqrt(1 - (z / 0.5) ^ 2)
			sphere(ctx, "Stripe", 0.43 * k + 0.02, 0.5 * t * k + 0.02, 0.08, at(0, 0, z), d.C2, "belly")
		end
	end
	if d.Spots then
		for _, side in ipairs({ -1, 1 }) do
			for _, p in ipairs({ { 0.15, 0.1, -0.03 }, { 0.17, 0.0, 0.15 }, { 0.12, 0.12, 0.27 } }) do
				newPart(ctx, "Ball", "Spot", Vector3.new(0.07, 0.07, 0.07), at(side * p[1], p[2] * t, p[3]), d.C3, "accent")
			end
		end
	end
	if d.Sword then
		newPart(ctx, "Block", "Sword", Vector3.new(0.035, 0.035, 0.6), at(0, 0.03, -0.78), d.C2, "accent")
	end
	if d.Spikes then
		for i = 0, 4 do
			newPart(ctx, "Block", "Spike", Vector3.new(0.025, 0.32, 0.025), at(0, 0.3 * t + 0.08, -0.15 + i * 0.1, 0.35, 0, 0), d.C2, "accent")
		end
	end
end

function Shapes.puffer(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 0.85, 0.8, 0.9, at(0, 0, 0), d.C1, "main")
	sphere(ctx, "Belly", 0.74, 0.58, 0.8, at(0, -0.13, 0.02), d.C2, "belly")
	tailLobes(ctx, 0.5, 0.07, 0.24, d.C3)
	for _, side in ipairs({ -1, 1 }) do
		sphere(ctx, "Fin", 0.18, 0.04, 0.12, at(side * 0.42, -0.02, -0.05, 0, side * 0.6, 0), d.C3, "accent")
	end
	eyes(ctx, 0.25, 0.1, -0.3, 0.2, true)
	newPart(ctx, "Ball", "Mouth", Vector3.new(0.09, 0.09, 0.09), at(0, -0.06, -0.44), BLACK, "fixed")
	if d.Spikes then
		local n = 22
		local golden = math.pi * (3 - math.sqrt(5))
		for i = 0, n - 1 do
			local y = 1 - (i / (n - 1)) * 2
			local r = math.sqrt(1 - y * y)
			local th = golden * i
			local dir = Vector3.new(math.cos(th) * r, y, math.sin(th) * r)
			if dir.Z > -0.6 and dir.Y > -0.85 then
				local pos = Vector3.new(dir.X * 0.42, dir.Y * 0.39, dir.Z * 0.44)
				local cf = CFrame.lookAt(pos, pos + dir)
				newPart(ctx, "Block", "Spike", Vector3.new(0.045, 0.045, 0.17), cf, d.C3, "accent")
			end
		end
	end
end

function Shapes.shark(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 0.3, 0.32, 1, at(0, 0, 0), d.C1, "main")
	sphere(ctx, "Belly", 0.26, 0.2, 0.88, at(0, -0.075, 0.01), d.C2, "belly")
	newPart(ctx, "Wedge", "Fin", Vector3.new(0.04, 0.3, 0.27), at(0, 0.28, 0.06), d.C1, "accent")
	newPart(ctx, "Wedge", "Fin", Vector3.new(0.03, 0.09, 0.1), at(0, 0.12, 0.38), d.C1, "accent")
	sphere(ctx, "Tail", 0.04, 0.12, 0.44, at(0, 0.15, 0.64, -0.85, 0, 0), d.C1, "accent")
	sphere(ctx, "Tail", 0.04, 0.1, 0.26, at(0, -0.07, 0.59, 0.75, 0, 0), d.C1, "accent")
	for _, side in ipairs({ -1, 1 }) do
		sphere(ctx, "Fin", 0.36, 0.03, 0.16, at(side * 0.2, -0.09, -0.08, 0, side * 0.45, side * -0.35), d.C1, "accent")
		for i = 0, 2 do
			newPart(ctx, "Block", "Gill", Vector3.new(0.01, 0.1, 0.014), at(side * 0.138, 0.0, -0.2 + i * 0.05), d.C3, "fixed")
		end
	end
	if d.Cute then
		eyes(ctx, 0.1, 0.06, -0.32, 0.12, true)
	else
		local eyeColor = d.Glow and Color3.fromRGB(255, 40, 30) or BLACK
		for _, side in ipairs({ -1, 1 }) do
			local e = newPart(ctx, "Ball", "Pupil", Vector3.new(0.065, 0.065, 0.065), at(side * 0.12, 0.06, -0.34), eyeColor, "fixed")
			if d.Glow then
				e.Material = Enum.Material.Neon
			end
		end
	end
	if d.Teeth then
		sphere(ctx, "Mouth", 0.16, 0.05, 0.12, at(0, -0.085, -0.37), BLACK, "fixed")
		for i = -3, 3 do
			local x = i * 0.022
			newPart(ctx, "Wedge", "Tooth", Vector3.new(0.018, 0.04, 0.02), at(x, -0.07, -0.425 + math.abs(i) * 0.012, math.pi, 0, 0), WHITE, "fixed")
		end
	end
	if d.Hammer then
		sphere(ctx, "Hammer", 0.64, 0.07, 0.17, at(0, 0.02, -0.46), d.C1, "main")
		for _, side in ipairs({ -1, 1 }) do
			newPart(ctx, "Ball", "Pupil", Vector3.new(0.06, 0.06, 0.06), at(side * 0.31, 0.03, -0.46), BLACK, "fixed")
		end
	end
end

function Shapes.ray(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 1, 0.1, 0.7, at(0, 0, 0), d.C1, "main")
	sphere(ctx, "Belly", 0.9, 0.07, 0.62, at(0, -0.022, 0.01), d.C2, "belly")
	sphere(ctx, "Back", 0.3, 0.12, 0.4, at(0, 0.02, 0.0), d.C1, "main")
	for _, side in ipairs({ -1, 1 }) do
		sphere(ctx, "Horn", 0.06, 0.05, 0.2, at(side * 0.12, 0, -0.38, 0, side * -0.2, 0), d.C1, "accent")
		newPart(ctx, "Ball", "Pupil", Vector3.new(0.05, 0.05, 0.05), at(side * 0.13, 0.04, -0.24), BLACK, "fixed")
	end
	newPart(ctx, "Block", "Tail", Vector3.new(0.03, 0.03, 0.75), at(0, 0, 0.68), d.C3, "accent")
end

function Shapes.jelly(ctx: Ctx)
	local d = ctx.def
	local dome = sphere(ctx, "Body", 0.72, 0.52, 0.72, at(0, 0.15, 0), d.C1, "main")
	dome.Material = Enum.Material.Glass
	dome.Transparency = 0.3
	local core = sphere(ctx, "Core", 0.38, 0.28, 0.38, at(0, 0.16, 0), d.C3, "accent")
	core.Material = Enum.Material.Neon
	sphere(ctx, "Rim", 0.74, 0.08, 0.74, at(0, -0.04, 0), d.C2, "belly")
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		newPart(ctx, "Block", "Tentacle", Vector3.new(0.03, 0.62, 0.03), at(math.cos(a) * 0.24, -0.36, math.sin(a) * 0.24, math.sin(a) * 0.15, 0, -math.cos(a) * 0.15), d.C3, "accent")
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + 0.4
		sphere(ctx, "Arm", 0.08, 0.5, 0.08, at(math.cos(a) * 0.06, -0.27, math.sin(a) * 0.06), d.C2, "belly")
	end
	eyes(ctx, 0.14, 0.18, -0.3, 0.1, true)
end

function Shapes.squid(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 0.3, 0.3, 0.72, at(0, 0, 0.2), d.C1, "main")
	for _, side in ipairs({ -1, 1 }) do
		sphere(ctx, "Fin", 0.32, 0.03, 0.2, at(side * 0.12, 0, 0.47, 0, side * 0.5, 0), d.C3, "accent")
	end
	sphere(ctx, "Head", 0.25, 0.24, 0.24, at(0, 0, -0.2), d.C2, "belly")
	eyes(ctx, 0.11, 0.04, -0.22, 0.13, true)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local x, y = math.cos(a) * 0.07, math.sin(a) * 0.07
		newPart(ctx, "Block", "Tentacle", Vector3.new(0.04, 0.04, 0.45), at(x, y, -0.5, -y * 1.5, x * 1.5, 0), d.C1, "accent")
	end
	for _, side in ipairs({ -1, 1 }) do
		newPart(ctx, "Block", "Tentacle", Vector3.new(0.03, 0.03, 0.75), at(side * 0.03, -0.03, -0.62, 0.05, side * 0.1, 0), d.C3, "accent")
	end
end

function Shapes.octopus(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 0.56, 0.62, 0.6, at(0, 0.27, 0.06, -0.3, 0, 0), d.C1, "main")
	sphere(ctx, "Under", 0.44, 0.16, 0.44, at(0, -0.02, 0), d.C2, "belly")
	eyes(ctx, 0.15, 0.13, -0.2, 0.15, true)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local p1 = out * 0.22 + Vector3.new(0, -0.08, 0)
		local p2 = out * 0.42 + Vector3.new(0, -0.14, 0)
		newPart(ctx, "Sphere", "Tentacle", Vector3.new(0.11, 0.11, 0.34), CFrame.lookAt(p1, p1 + out + Vector3.new(0, -0.4, 0)), d.C1, "main")
		newPart(ctx, "Sphere", "Tentacle", Vector3.new(0.08, 0.08, 0.26), CFrame.lookAt(p2, p2 + out + Vector3.new(0, 0.35, 0)), d.C3, "accent")
	end
end

function Shapes.eel(ctx: Ctx)
	local d = ctx.def
	local n = 8
	for i = 0, n - 1 do
		local f = i / (n - 1)
		local z = -0.42 + f * 0.92
		local r = 0.15 * (1 - f * 0.55)
		local x = math.sin(f * math.pi * 2) * 0.05
		local col = (d.Spots and i % 2 == 1) and d.C2 or d.C1
		local seg = sphere(ctx, i == 0 and "Body" or "Segment", r * 1.8, r * 2, 0.2, at(x, 0, z), col, i % 2 == 1 and d.Spots and "belly" or "main")
		if d.Spikes then
			newPart(ctx, "Wedge", "Spike", Vector3.new(0.03, r * 1.1, 0.09), at(x, r + r * 0.4, z), d.C3, "accent")
		end
		if i == 0 then
			seg.Size = seg.Size * Vector3.new(1.15, 1.05, 1.4)
		end
	end
	sphere(ctx, "Fin", 0.02, 0.1, 0.9, at(0, 0.13, 0.08), d.C3, "accent")
	sphere(ctx, "Jaw", 0.18, 0.08, 0.14, at(0, -0.07, -0.5), d.C2, "belly")
	eyes(ctx, 0.1, 0.06, -0.48, 0.07)
	if d.Glow then
		sphere(ctx, "Stripe", 0.03, 0.03, 0.85, at(0.0, 0.0, 0.05), d.C3, "accent")
	end
end

function Shapes.whale(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 0.45, 0.42, 1, at(0, 0, 0), d.C1, "main")
	sphere(ctx, "Belly", 0.4, 0.28, 0.9, at(0, -0.1, 0.0), d.C2, "belly")
	for _, side in ipairs({ -1, 1 }) do
		sphere(ctx, "Fluke", 0.42, 0.04, 0.18, at(side * 0.15, 0.02, 0.57, 0, side * -0.45, 0), d.C1, "accent")
		sphere(ctx, "Flipper", 0.3, 0.04, 0.12, at(side * 0.24, -0.11, -0.1, 0, side * 0.5, side * -0.4), d.C1, "accent")
		newPart(ctx, "Ball", "Pupil", Vector3.new(0.06, 0.06, 0.06), at(side * 0.19, -0.04, -0.3), BLACK, "fixed")
		if d.Orca then
			sphere(ctx, "Patch", 0.06, 0.09, 0.18, at(side * 0.18, 0.07, -0.26), WHITE, "fixed")
		end
	end
	if d.Orca then
		newPart(ctx, "Wedge", "Fin", Vector3.new(0.04, 0.36, 0.2), at(0, 0.36, 0.02), d.C1, "accent")
	else
		newPart(ctx, "Wedge", "Fin", Vector3.new(0.03, 0.1, 0.14), at(0, 0.22, 0.22), d.C1, "accent")
	end
	if d.Glow then
		for i = 0, 4 do
			newPart(ctx, "Ball", "Spot", Vector3.new(0.05, 0.05, 0.05), at(0.12 * math.sin(i * 1.7), 0.18, -0.2 + i * 0.12), d.C3, "accent")
		end
	end
end

function Shapes.turtle(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 0.7, 0.34, 0.86, at(0, 0.06, 0), d.C1, "main")
	sphere(ctx, "Belly", 0.66, 0.14, 0.8, at(0, -0.05, 0), d.C2, "belly")
	local plate = d.C1:Lerp(BLACK, 0.3)
	for _, p in ipairs({ { 0, 0.21, -0.05 }, { -0.16, 0.17, 0.05 }, { 0.16, 0.17, 0.05 }, { 0, 0.18, 0.2 }, { -0.14, 0.17, -0.18 }, { 0.14, 0.17, -0.18 } }) do
		sphere(ctx, "Plate", 0.17, 0.05, 0.17, at(p[1], p[2], p[3]), plate, "main")
	end
	sphere(ctx, "Head", 0.22, 0.2, 0.27, at(0, 0.03, -0.5), d.C3, "accent")
	for _, side in ipairs({ -1, 1 }) do
		newPart(ctx, "Ball", "Pupil", Vector3.new(0.05, 0.05, 0.05), at(side * 0.08, 0.07, -0.57), BLACK, "fixed")
		sphere(ctx, "Flipper", 0.44, 0.04, 0.14, at(side * 0.4, -0.02, -0.2, 0, side * 0.5, 0), d.C3, "accent")
		sphere(ctx, "Flipper", 0.2, 0.04, 0.12, at(side * 0.26, -0.02, 0.36, 0, side * -0.5, 0), d.C3, "accent")
	end
end

function Shapes.angler(ctx: Ctx)
	local d = ctx.def
	sphere(ctx, "Body", 0.6, 0.56, 0.82, at(0, 0, 0), d.C1, "main")
	sphere(ctx, "Belly", 0.52, 0.36, 0.7, at(0, -0.1, 0.03), d.C2, "belly")
	sphere(ctx, "Mouth", 0.46, 0.18, 0.12, at(0, -0.08, -0.37), BLACK, "fixed")
	for i = -3, 3 do
		newPart(ctx, "Wedge", "Tooth", Vector3.new(0.025, 0.07, 0.025), at(i * 0.055, -0.03, -0.42, math.pi, 0, 0), WHITE, "fixed")
		newPart(ctx, "Wedge", "Tooth", Vector3.new(0.025, 0.06, 0.025), at(i * 0.055 + 0.027, -0.14, -0.42), WHITE, "fixed")
	end
	tailLobes(ctx, 0.48, 0.08, 0.26, d.C1)
	eyes(ctx, 0.19, 0.12, -0.25, 0.1, true)
	local stalkFrom = Vector3.new(0, 0.27, -0.12)
	local stalkTo = Vector3.new(0, 0.5, -0.5)
	local mid = (stalkFrom + stalkTo) / 2
	newPart(ctx, "Block", "Stalk", Vector3.new(0.025, 0.025, (stalkTo - stalkFrom).Magnitude), CFrame.lookAt(mid, stalkTo), d.C1, "main")
	local lure = newPart(ctx, "Ball", "Lure", Vector3.new(0.13, 0.13, 0.13), CFrame.new(stalkTo), d.C3, "accent")
	lure.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Color = d.C3
	light.Range = 6
	light.Brightness = 2
	light.Parent = lure
end

-- ===== Мутации =====

local function sparkles(body: BasePart, color: Color3, rate: number)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "MutationSparkles"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.6, 1.2)
	pe.Rate = rate
	pe.Speed = NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = body
end

local function applyBaseLook(ctx: Ctx)
	local d = ctx.def
	for _, p in ipairs(ctx.parts) do
		local role = p:GetAttribute("Role")
		if d.Glow and role == "accent" then
			p.Material = Enum.Material.Neon
		end
		if d.Ghost and role ~= "fixed" then
			p.Material = Enum.Material.Glass
			p.Transparency = 0.35
		end
	end
	if d.Glow then
		local body = ctx.model:FindFirstChild("Body") :: BasePart
		local light = Instance.new("PointLight")
		light.Color = d.C3
		light.Range = 5 + ctx.s * 1.5
		light.Brightness = 1.2
		light.Parent = body
	end
end

local GALAXY = { Color3.fromRGB(40, 15, 110), Color3.fromRGB(120, 40, 220), Color3.fromRGB(20, 40, 140), Color3.fromRGB(230, 90, 255) }

local function applyMutation(ctx: Ctx, mutation: string)
	local body = ctx.model:FindFirstChild("Body") :: BasePart
	if mutation == "None" then
		if ctx.def.Galaxy then
			mutation = "Galaxy"
		else
			return
		end
	end
	local mut = GameData.MutationById[mutation]
	for i, p in ipairs(ctx.parts) do
		local role = p:GetAttribute("Role")
		if role ~= "fixed" then
			if mutation == "Golden" then
				p.Color = p.Color:Lerp(Color3.fromRGB(255, 200, 40), 0.8)
				p.Material = Enum.Material.Foil
				p.Reflectance = 0.15
			elseif mutation == "Crystal" then
				p.Color = p.Color:Lerp(Color3.fromRGB(170, 240, 255), 0.65)
				p.Material = Enum.Material.Glass
				p.Transparency = 0.25
			elseif mutation == "Neon" then
				p.Color = p.Color:Lerp(Color3.fromRGB(60, 255, 150), 0.35)
				p.Material = Enum.Material.Neon
			elseif mutation == "Galaxy" then
				p.Color = GALAXY[(i % #GALAXY) + 1]
				p.Material = Enum.Material.Neon
			elseif mutation == "Rainbow" then
				p.Material = Enum.Material.SmoothPlastic
				p:SetAttribute("Hue", (i * 0.07) % 1)
				p.Color = Color3.fromHSV((i * 0.07) % 1, 0.75, 1)
				CollectionService:AddTag(p, "RainbowPart")
			end
		end
	end
	if mut then
		sparkles(body, mut.Color, mutation == "Golden" and 4 or 8)
	end
end

local function weldAll(ctx: Ctx, body: BasePart)
	for _, p in ipairs(ctx.parts) do
		if p ~= body then
			p.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
		end
	end
end

-- Собрать модель. length — длина в studs. Возвращает Model с PrimaryPart = Body.
-- opts.static = true — все детали заякорены (для статуй), без сварки.
function FishBuilder.Build(fishId: string, mutation: string?, length: number, opts: { static: boolean? }?): Model
	local def = GameData.FishById[fishId] or GameData.Fish[1]
	local model = Instance.new("Model")
	model.Name = fishId
	local ctx: Ctx = { model = model, s = length, def = def, parts = {} }
	local builder = Shapes[def.Shape] or Shapes.fish
	builder(ctx)
	local body = model:FindFirstChild("Body") :: BasePart
	model.PrimaryPart = body
	applyBaseLook(ctx)
	applyMutation(ctx, mutation or "None")
	if not (opts and opts.static) then
		weldAll(ctx, body)
	end
	model:SetAttribute("FishId", fishId)
	model:SetAttribute("Mutation", mutation or "None")
	return model
end

-- Длина рыбы для показа (в аквариуме и в руках): зависит от редкости и размера
function FishBuilder.DisplayLength(fishId: string, sizeIndex: number): number
	local def = GameData.FishById[fishId]
	local base = ({ 1.6, 1.8, 2.0, 2.3, 2.7, 3.1, 3.6 })[def and def.Rarity or 1]
	if def and def.Big then
		base *= 1.25
	end
	if def and (def.Shape == "jelly" or def.Shape == "puffer" or def.Shape == "octopus") then
		base *= 0.8
	end
	local size = GameData.Sizes[sizeIndex] or GameData.Sizes[2]
	return base * size.Scale
end

return FishBuilder
