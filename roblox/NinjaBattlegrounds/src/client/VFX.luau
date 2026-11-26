-- Визуальные эффекты (только клиент). Всё из деталей и частиц — без загрузки ассетов.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local VFX = {}

local folder = Instance.new("Folder")
folder.Name = "VFX"
folder.Parent = workspace

local rng = Random.new()
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

local CHAKRA = Color3.fromRGB(80, 190, 255)
VFX.CHAKRA = CHAKRA

local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Class" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent or folder
	return p
end

local function tween(obj: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.LightEmission = 0.6
	for k, v in pairs(props) do
		(pe :: any)[k] = v
	end
	pe.Parent = parent
	return pe
end

local function holder(pos: Vector3): BasePart
	return part({ Size = Vector3.new(0.2, 0.2, 0.2), Position = pos, Transparency = 1 })
end

-- ===== Камера =====
local shakeAmp = 0
local fovKick = 0
function VFX.Shake(power: number)
	shakeAmp = math.max(shakeAmp, power)
end
function VFX.FovKick(amount: number)
	fovKick = amount
end

RunService:BindToRenderStep("VFXCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if shakeAmp > 0.01 then
		cam.CFrame = cam.CFrame * CFrame.Angles((rng:NextNumber() - 0.5) * shakeAmp * 0.04, (rng:NextNumber() - 0.5) * shakeAmp * 0.04, (rng:NextNumber() - 0.5) * shakeAmp * 0.02)
		shakeAmp *= math.exp(-dt * 7)
	end
	if math.abs(fovKick) > 0.05 then
		cam.FieldOfView = 70 + fovKick
		fovKick *= math.exp(-dt * 6)
	end
end)

-- ===== Вспышка экрана =====
function VFX.Flash(color: Color3?, strength: number?)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = color or Color3.new(1, 1, 1)
	cc.Brightness = strength or 0.4
	cc.Parent = Lighting
	tween(cc, 0.35, { Brightness = 0, TintColor = Color3.new(1, 1, 1) })
	Debris:AddItem(cc, 0.4)
end

-- ===== Дым (появление/исчезновение двойника) =====
function VFX.Smoke(pos: Vector3, scale: number?)
	local s = scale or 1
	for _ = 1, 14 do
		local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit
		local size = rng:NextNumber(2, 3.4) * s
		local puff = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.4, Position = pos + d * s, Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.SmoothPlastic, Transparency = 0.05 })
		tween(puff, rng:NextNumber(0.45, 0.7), { Size = Vector3.one * size * 1.4, Position = pos + d * s * 3.2 + Vector3.new(0, 1.5 * s, 0), Transparency = 1 })
		Debris:AddItem(puff, 0.75)
	end
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2 * s, 2 * s), CFrame = CFrame.new(pos - Vector3.new(0, 2.6 * s, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(240, 240, 245), Material = Enum.Material.Neon, Transparency = 0.3 })
	tween(ring, 0.5, { Size = Vector3.new(0.2, 12 * s, 12 * s), Transparency = 1 })
	Debris:AddItem(ring, 0.55)
	local h = holder(pos)
	emitter(h, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(230, 230, 235)), Size = NumberSequence.new(3 * s, 6 * s),
		Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.1, Drag = 3 }):Emit(18)
	Debris:AddItem(h, 1.2)
end

-- ===== Удар =====
-- pos — точка удара, dir — направление удара, power 1..3
function VFX.Impact(pos: Vector3, dir: Vector3?, power: number?, color: Color3?)
	local p = power or 1
	local col = color or Color3.fromRGB(255, 245, 220)
	local d = (dir and dir.Magnitude > 0.01) and dir.Unit or Vector3.new(0, 0, -1)
	-- белая вспышка
	local flash = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2 * p, Position = pos, Color = col, Material = Enum.Material.Neon })
	tween(flash, 0.18, { Size = Vector3.one * 5 * p, Transparency = 1 })
	Debris:AddItem(flash, 0.2)
	-- кольцо ударной волны поперёк удара
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 1.5 * p, 1.5 * p), CFrame = CFrame.lookAt(pos, pos + d) * CFrame.Angles(0, math.pi / 2, 0), Color = col, Material = Enum.Material.Neon, Transparency = 0.1 })
	tween(ring, 0.3, { Size = Vector3.new(0.05, 9 * p, 9 * p), Transparency = 1 })
	Debris:AddItem(ring, 0.32)
	-- лучи-штрихи во все стороны
	for _ = 1, math.floor(8 * p) do
		local r = (d + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 1.3).Unit
		local len = rng:NextNumber(2, 4) * p
		local line = part({ Size = Vector3.new(0.12, 0.12, len), CFrame = CFrame.lookAt(pos + r * 0.5, pos + r * 2), Color = col, Material = Enum.Material.Neon })
		tween(line, 0.22, { CFrame = CFrame.lookAt(pos + r * (len + 2), pos + r * (len + 4)), Size = Vector3.new(0.03, 0.03, len * 0.3), Transparency = 1 })
		Debris:AddItem(line, 0.25)
	end
	-- искры
	local h = holder(pos)
	emitter(h, { Texture = TEX_SPARK, Color = ColorSequence.new(col), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * p), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.2, 0.5), Speed = NumberRange.new(20, 45), SpreadAngle = Vector2.new(180, 180), Drag = 6, LightEmission = 1 }):Emit(math.floor(25 * p))
	local light = Instance.new("PointLight")
	light.Color = col
	light.Range = 14 * p
	light.Brightness = 4
	light.Parent = h
	tween(light, 0.25, { Brightness = 0 })
	Debris:AddItem(h, 0.6)
	VFX.Shake(0.8 * p)
end

-- ===== Чакра-вспышка у рук (знак) =====
function VFX.ChakraBurst(pos: Vector3, scale: number?)
	local s = scale or 1
	local orb = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Position = pos, Color = CHAKRA, Material = Enum.Material.Neon })
	tween(orb, 0.25, { Size = Vector3.one * 7 * s, Transparency = 1 })
	Debris:AddItem(orb, 0.3)
	for i = 1, 2 do
		local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1, 1), CFrame = CFrame.new(pos) * CFrame.Angles(i * 1.1, i * 0.7, math.pi / 2), Color = CHAKRA, Material = Enum.Material.Neon, Transparency = 0.1 })
		tween(ring, 0.4, { Size = Vector3.new(0.05, 14 * s, 14 * s), Transparency = 1 })
		Debris:AddItem(ring, 0.45)
	end
	local h = holder(pos)
	emitter(h, { Texture = TEX_SPARK, Color = ColorSequence.new(CHAKRA, Color3.new(1, 1, 1)), Size = NumberSequence.new(0.6, 0), Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(12, 26), SpreadAngle = Vector2.new(180, 180), Drag = 4, LightEmission = 1 }):Emit(40)
	Debris:AddItem(h, 1)
end

-- ===== Аура чакры на персонаже =====
local auras = {} :: { [Model]: { Instance } }
function VFX.Aura(model: Model, on: boolean)
	if auras[model] then
		for _, inst in ipairs(auras[model]) do
			inst:Destroy()
		end
		auras[model] = nil
	end
	if not on then
		return
	end
	local list = {}
	for _, name in ipairs({ "UpperTorso", "LowerTorso", "LeftLowerLeg", "RightLowerLeg", "LeftLowerArm", "RightLowerArm" }) do
		local p = model:FindFirstChild(name)
		if p then
			local flames = emitter(p, { Texture = TEX_FIRE, Color = ColorSequence.new(Color3.fromRGB(140, 220, 255), CHAKRA),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.3, 0.55), Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 9, 0),
				SpreadAngle = Vector2.new(25, 25), LightEmission = 1, Rate = 45 })
			table.insert(list, flames)
		end
	end
	local torso = model:FindFirstChild("UpperTorso")
	if torso then
		local l = Instance.new("PointLight")
		l.Color = CHAKRA
		l.Range = 12
		l.Brightness = 2
		l.Parent = torso
		table.insert(list, l)
	end
	auras[model] = list
end

-- ===== Следы рук и ног =====
local trails = {} :: { [Model]: { Trail } }
function VFX.Trails(model: Model, on: boolean, color: Color3?)
	if not trails[model] then
		local list = {}
		for _, name in ipairs({ "RightHand", "LeftHand", "RightFoot", "LeftFoot" }) do
			local p = model:FindFirstChild(name)
			if p then
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, 0.35, 0)
				a0.Parent = p
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, -0.35, 0)
				a1.Parent = p
				local tr = Instance.new("Trail")
				tr.Attachment0 = a0
				tr.Attachment1 = a1
				tr.Lifetime = 0.18
				tr.LightEmission = 1
				tr.FaceCamera = true
				tr.Transparency = NumberSequence.new(0.15, 1)
				tr.Enabled = false
				tr.Parent = p
				table.insert(list, tr)
			end
		end
		trails[model] = list
	end
	for _, tr in ipairs(trails[model]) do
		tr.Color = ColorSequence.new(color or Color3.new(1, 1, 1))
		tr.Enabled = on
	end
end

-- ===== Удар ногой вверх: вертикальный росчерк =====
function VFX.UpStreak(pos: Vector3)
	local beam = part({ Size = Vector3.new(0.4, 14, 0.4), Position = pos + Vector3.new(0, 7, 0), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Transparency = 0.1 })
	tween(beam, 0.3, { Size = Vector3.new(0.05, 22, 0.05), Position = pos + Vector3.new(0, 12, 0), Transparency = 1 })
	Debris:AddItem(beam, 0.32)
end

-- ===== Кратер от удара в землю =====
function VFX.Crater(pos: Vector3, radius: number?)
	local r = radius or 9
	local ground = Vector3.new(pos.X, pos.Y, pos.Z)
	-- тёмный круг
	local disc = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, r * 1.6, r * 1.6), CFrame = CFrame.new(ground + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(70, 60, 55), Material = Enum.Material.Slate })
	-- вздыбленные плиты по краю
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local sz = Vector3.new(rng:NextNumber(2, 3.5), rng:NextNumber(0.6, 1.2), rng:NextNumber(2, 4))
		local slab = part({ Size = sz, CFrame = CFrame.lookAt(ground + dir * r * 0.75, ground + dir * r * 2) * CFrame.Angles(math.rad(rng:NextNumber(20, 40)), 0, 0) + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(110, 100, 95), Material = Enum.Material.Slate })
		local target = slab.CFrame
		slab.CFrame = target - Vector3.new(0, 2, 0)
		tween(slab, 0.15, { CFrame = target }, Enum.EasingStyle.Back)
		task.delay(4, function()
			tween(slab, 1, { CFrame = target - Vector3.new(0, 2.5, 0), Transparency = 1 })
		end)
		Debris:AddItem(slab, 5.2)
	end
	task.delay(4, function()
		tween(disc, 1, { Transparency = 1 })
	end)
	Debris:AddItem(disc, 5.2)
	-- летящие обломки
	for _ = 1, 16 do
		local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.8, 1.8), rng:NextNumber(-1, 1)).Unit
		local s = rng:NextNumber(0.5, 1.4)
		local rock = Instance.new("Part")
		rock.Size = Vector3.new(s, s * 0.8, s)
		rock.CFrame = CFrame.new(ground + Vector3.new(0, 1, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		rock.Color = Color3.fromRGB(120, 110, 100)
		rock.Material = Enum.Material.Slate
		rock.CanCollide = true
		rock.CanQuery = false
		rock.CollisionGroup = "Default"
		rock.AssemblyLinearVelocity = d * rng:NextNumber(35, 60)
		rock.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
		rock.Parent = folder
		Debris:AddItem(rock, 3)
	end
	-- пыль кольцом
	local h = holder(ground + Vector3.new(0, 1, 0))
	emitter(h, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(180, 165, 150)), Size = NumberSequence.new(4, 9), Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(25, 40), SpreadAngle = Vector2.new(5, 180), EmissionDirection = Enum.NormalId.Top,
		Drag = 4, LightEmission = 0 }):Emit(40)
	Debris:AddItem(h, 2)
	-- огромная ударная волна
	local wave = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4, 4), CFrame = CFrame.new(ground + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Transparency = 0.1 })
	tween(wave, 0.45, { Size = Vector3.new(0.1, r * 6, r * 6), Transparency = 1 })
	Debris:AddItem(wave, 0.5)
	VFX.Shake(3)
	VFX.FovKick(10)
	VFX.Flash(Color3.new(1, 1, 1), 0.5)
end

-- ===== Остаточные силуэты при рывке =====
function VFX.Afterimage(model: Model, color: Color3?)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 1 then
			local ghost = part({ Size = p.Size, CFrame = p.CFrame, Color = color or CHAKRA, Material = Enum.Material.Neon, Transparency = 0.45 })
			if p:IsA("MeshPart") then
				ghost:Destroy()
				ghost = part({ Size = p.Size * 0.9, CFrame = p.CFrame, Color = color or CHAKRA, Material = Enum.Material.Neon, Transparency = 0.45 })
			end
			tween(ghost, 0.35, { Transparency = 1 })
			Debris:AddItem(ghost, 0.4)
		end
	end
end

-- ===== Невидимость (рывок/уклонение) =====
function VFX.SetVisible(model: Model, visible: boolean)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") or p:IsA("Decal") then
			(p :: any).LocalTransparencyModifier = visible and 0 or 1
		end
	end
end

-- ===== Пыль из-под ног =====
function VFX.Dust(pos: Vector3, scale: number?)
	local s = scale or 1
	local h = holder(pos)
	emitter(h, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(190, 175, 160)), Size = NumberSequence.new(1.5 * s, 4 * s), Transparency = NumberSequence.new(0.35, 1),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top, Drag = 4, LightEmission = 0 }):Emit(math.floor(12 * s))
	Debris:AddItem(h, 1.2)
end

local _ = Players
return VFX
