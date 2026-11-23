-- Визуальные эффекты на клиенте: брызги, круги, поплавок с леской, плавание рыб в аквариумах,
-- радужные рыбы, погода событий, чужие забросы, всплывающий доход над своим аквариумом.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local Format = require(Shared.Format)
local FishBuilder = require(Shared.FishBuilder)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer
local Effects = {}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalFx"
fxFolder.Parent = workspace

local rng = Random.new()

local function anchoredPart(props: { [string]: any }): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Class" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent or fxFolder
	return p
end

-- ===== Брызги и круги =====
function Effects.Splash(pos: Vector3, scale: number?, color: Color3?)
	local s = scale or 1
	local holder = anchoredPart({ Size = Vector3.new(1, 1, 1), Position = pos, Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color or Color3.fromRGB(230, 250, 255))
	pe.LightEmission = 0.6
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 * s), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) })
	pe.Lifetime = NumberRange.new(0.5, 0.9)
	pe.Speed = NumberRange.new(10 * s, 22 * s)
	pe.SpreadAngle = Vector2.new(35, 35)
	pe.Acceleration = Vector3.new(0, -60, 0)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = 0
	pe.Parent = holder
	pe:Emit(math.floor(24 * s))
	Debris:AddItem(holder, 1.5)

	local ring = anchoredPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 1.5 * s, 1.5 * s),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(235, 250, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	})
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Size = Vector3.new(0.15, 11 * s, 11 * s), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.8)
end

function Effects.Ripple(pos: Vector3, size: number?)
	local ring = anchoredPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 1, 1),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(240, 250, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
	})
	local s = size or 5
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Size = Vector3.new(0.1, s, s), Transparency = 1 }):Play()
	Debris:AddItem(ring, 1)
end

function Effects.Burst(pos: Vector3, color: Color3, count: number?)
	local holder = anchoredPart({ Size = Vector3.new(1, 1, 1), Position = pos, Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Speed = NumberRange.new(8, 18)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 3
	pe.Rate = 0
	pe.Parent = holder
	pe:Emit(count or 30)
	Debris:AddItem(holder, 1.5)
end

-- ===== Поплавок =====
function Effects.MakeBobber(color: Color3?): (Model, Attachment)
	local m = Instance.new("Model")
	m.Name = "Bobber"
	local top = anchoredPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), Color = color or Color3.fromRGB(255, 60, 60), Parent = m })
	top.Name = "Top"
	local bottom = anchoredPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.86, 0.86, 0.86), Color = Color3.fromRGB(250, 250, 250), Parent = m })
	bottom.Name = "Bottom"
	local stick = anchoredPart({ Size = Vector3.new(0.12, 0.6, 0.12), Color = Color3.fromRGB(255, 220, 60), Material = Enum.Material.Neon, Parent = m })
	stick.Name = "Stick"
	m.PrimaryPart = top
	local att = Instance.new("Attachment")
	att.Name = "LineAttach"
	att.Position = Vector3.new(0, 0.45, 0)
	att.Parent = top
	-- след
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.3, 0)
	a0.Parent = top
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = top
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 220, 255))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Name = "Trail"
	trail.Parent = top
	m.Parent = fxFolder
	return m, att
end

function Effects.PlaceBobber(m: Model, pos: Vector3)
	local top = m:FindFirstChild("Top") :: BasePart
	local bottom = m:FindFirstChild("Bottom") :: BasePart
	local stick = m:FindFirstChild("Stick") :: BasePart
	top.CFrame = CFrame.new(pos + Vector3.new(0, 0.18, 0))
	bottom.CFrame = CFrame.new(pos - Vector3.new(0, 0.2, 0))
	stick.CFrame = CFrame.new(pos + Vector3.new(0, 0.85, 0))
end

function Effects.MakeLine(from: Attachment, to: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Width0 = 0.06
	beam.Width1 = 0.06
	beam.Color = ColorSequence.new(Color3.fromRGB(245, 245, 255))
	beam.Transparency = NumberSequence.new(0.1)
	beam.LightEmission = 0.4
	beam.FaceCamera = true
	beam.Segments = 24
	beam.Parent = fxFolder
	return beam
end

-- Траектория дуги
function Effects.Arc(a: Vector3, b: Vector3, height: number, t: number): Vector3
	return a:Lerp(b, t) + Vector3.new(0, 4 * height * t * (1 - t), 0)
end

function Effects.RodTip(character: Model?): Attachment?
	local rod = character and character:FindFirstChild("Rod")
	local shaft = rod and rod:FindFirstChild("Shaft")
	return shaft and shaft:FindFirstChild("RodTip") :: Attachment?
end

-- ===== Чужие забросы =====
local function otherCast(userId: number, landing: Vector3, flight: number, total: number)
	local other = Players:GetPlayerByUserId(userId)
	local character = other and other.Character
	local tip = Effects.RodTip(character)
	if not tip then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - tip.WorldPosition).Magnitude > 400 then
		return
	end
	local bobber, att = Effects.MakeBobber()
	local line = Effects.MakeLine(tip, att)
	local from = tip.WorldPosition
	local height = 6 + (landing - from).Magnitude * 0.18
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < flight do
			local t = (os.clock() - t0) / flight
			Effects.PlaceBobber(bobber, Effects.Arc(from, landing, height, t))
			RunService.RenderStepped:Wait()
		end
		Effects.Splash(landing, 0.7)
		local t1 = os.clock()
		while os.clock() - t1 < total - flight and bobber.Parent do
			local bob = math.sin(os.clock() * 4) * 0.15
			Effects.PlaceBobber(bobber, landing + Vector3.new(0, bob, 0))
			RunService.RenderStepped:Wait()
		end
		Effects.Splash(landing, 1)
		bobber:Destroy()
		line:Destroy()
	end)
end

-- ===== Аквариумы =====
local fishStates = setmetatable({}, { __mode = "k" }) :: { [Model]: any }

local function animateTanks(dt: number)
	local plots = workspace:FindFirstChild("Plots")
	local cam = workspace.CurrentCamera
	if not plots or not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local t = os.clock()
	for _, plot in ipairs(plots:GetChildren()) do
		local tank = plot:FindFirstChild("Tank")
		local water = tank and tank:FindFirstChild("Water") :: BasePart?
		local folder = tank and tank:FindFirstChild("Fish")
		if water and folder and (water.Position - camPos).Magnitude < 320 then
			local half = water.Size / 2
			for _, m in ipairs(folder:GetChildren()) do
				local body = m:IsA("Model") and m.PrimaryPart
				if body then
					local st = fishStates[m]
					local len = m:GetAttribute("Length") or 2
					local margin = Vector3.new(math.min(half.X - 0.2, len * 0.6), math.min(half.Y - 0.2, len * 0.35), math.min(half.Z - 0.2, len * 0.45))
					local function newTarget()
						local r = half - margin
						return Vector3.new(rng:NextNumber(-r.X, r.X), rng:NextNumber(-r.Y, r.Y), rng:NextNumber(-r.Z, r.Z))
					end
					if not st then
						st = {
							pos = water.CFrame:PointToObjectSpace(body.Position),
							target = newTarget(),
							speed = rng:NextNumber(1.2, 2.6),
							yaw = rng:NextNumber(0, math.pi * 2),
							phase = rng:NextNumber(0, 10),
						}
						fishStates[m] = st
					end
					local toT = st.target - st.pos
					if toT.Magnitude < 0.4 then
						st.target = newTarget()
					else
						local step = math.min(toT.Magnitude, st.speed * dt)
						st.pos += toT.Unit * step
						local wantYaw = math.atan2(-toT.X, -toT.Z)
						local diff = (wantYaw - st.yaw + math.pi) % (math.pi * 2) - math.pi
						st.yaw += diff * math.min(1, dt * 2.5)
					end
					local wiggle = math.sin(t * 6 + st.phase) * 0.12
					local bob = math.sin(t * 1.7 + st.phase) * 0.12
					body.CFrame = water.CFrame * CFrame.new(st.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, st.yaw + wiggle, 0)
				end
			end
		end
	end
end

-- ===== Радужные детали =====
local rainbowParts = {} :: { [BasePart]: boolean }
local function trackRainbow(p: Instance)
	if p:IsA("BasePart") then
		rainbowParts[p] = true
	end
end

-- ===== Погода событий =====
local rainPart: BasePart? = nil
local flash: ColorCorrectionEffect? = nil
local currentEvent = ""

local function setRain(on: boolean)
	if on and not rainPart then
		local p = anchoredPart({ Size = Vector3.new(120, 1, 120), Transparency = 1 })
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(190, 210, 235))
		pe.Size = NumberSequence.new(0.18)
		pe.Transparency = NumberSequence.new(0.35)
		pe.Lifetime = NumberRange.new(0.9, 1.2)
		pe.Rate = 600
		pe.Speed = NumberRange.new(70, 85)
		pe.EmissionDirection = Enum.NormalId.Bottom
		pe.SpreadAngle = Vector2.new(4, 4)
		pe.LightEmission = 0.2
		pe.Parent = p
		rainPart = p
	elseif not on and rainPart then
		rainPart:Destroy()
		rainPart = nil
	end
end

local function lightning()
	if not flash then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "LightningFlash"
		cc.Parent = Lighting
		flash = cc
	end
	local f = flash :: ColorCorrectionEffect
	f.Brightness = 0.55
	TweenService:Create(f, TweenInfo.new(0.35), { Brightness = 0 }):Play()
end

local function meteor()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local center = cam.CFrame.Position
	local a = rng:NextNumber(0, math.pi * 2)
	local land = center + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(120, 400)
	land = Vector3.new(land.X, Config.WaterY, land.Z)
	local start = land + Vector3.new(rng:NextNumber(-150, 150), 260, rng:NextNumber(-150, 150))
	local rock = anchoredPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = start, Color = Color3.fromRGB(255, 140, 50), Material = Enum.Material.Neon })
	local fire = Instance.new("Fire")
	fire.Size = 12
	fire.Heat = 20
	fire.Color = Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
	fire.Parent = rock
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 40
	light.Brightness = 3
	light.Parent = rock
	local tw = TweenService:Create(rock, TweenInfo.new(1.6, Enum.EasingStyle.Linear), { Position = land })
	tw:Play()
	tw.Completed:Connect(function()
		Effects.Splash(land, 3, Color3.fromRGB(255, 200, 150))
		rock:Destroy()
	end)
end

local jumpers = { "Guppy", "Clownfish", "Blue Tang", "Tuna", "Mahi-Mahi", "Parrotfish" }
local function jumpingFish()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(185, 320)
	local from = Vector3.new(math.cos(a) * r, Config.WaterY - 1, math.sin(a) * r)
	local dir = Vector3.new(-math.sin(a), 0, math.cos(a)) * rng:NextNumber(6, 12)
	local to = from + dir
	local m = FishBuilder.Build(jumpers[rng:NextInteger(1, #jumpers)], "None", rng:NextNumber(1.5, 2.5))
	m.Parent = fxFolder
	local body = m.PrimaryPart :: BasePart
	Effects.Splash(from + Vector3.new(0, 1, 0), 0.6)
	task.spawn(function()
		local t0 = os.clock()
		local dur = 0.9
		local prev = from
		while os.clock() - t0 < dur do
			local t = (os.clock() - t0) / dur
			local p = Effects.Arc(from, to, 5, t)
			if (p - prev).Magnitude > 0.01 then
				body.CFrame = CFrame.lookAt(p, p + (p - prev))
			end
			prev = p
			RunService.RenderStepped:Wait()
		end
		Effects.Splash(to + Vector3.new(0, 1, 0), 0.6)
		m:Destroy()
	end)
end

-- ===== Доход над своим аквариумом =====
local function incomePopup()
	local plot = ClientState.MyPlot()
	local tank = plot and plot:FindFirstChild("Tank")
	local water = tank and tank:FindFirstChild("Water") :: BasePart?
	local income = player:GetAttribute("Income") or 0
	if not water or income <= 0 then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - water.Position).Magnitude > 120 then
		return
	end
	local anchor = anchoredPart({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Position = water.Position + Vector3.new(rng:NextNumber(-8, 8), water.Size.Y / 2 + 1, 0) })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "+" .. Format.Money(income * 2)
	t.TextColor3 = Color3.fromRGB(120, 255, 120)
	t.TextStrokeTransparency = 0
	t.Parent = bb
	TweenService:Create(anchor, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Position = anchor.Position + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(1.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.7)
end

-- ===== Сцена улучшения базы =====
local function upgradeBanner(parent: BasePart, line1: string, line2: string, color: Color3)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(520, 150)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = parent
	local function line(text: string, y: number, h: number, col: Color3)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, h, 0)
		t.Position = UDim2.fromScale(0, y)
		t.Font = Enum.Font.LuckiestGuy
		t.TextScaled = true
		t.Text = text
		t.TextColor3 = col
		t.TextStrokeTransparency = 0
		t.Parent = bb
		local sc = Instance.new("UIScale")
		sc.Scale = 0.1
		sc.Parent = t
		TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	line(line1, 0, 0.55, color)
	line(line2, 0.58, 0.42, Color3.fromRGB(255, 255, 255))
	return bb
end

function Effects.UpgradeCutscene(kind: string, title: string, oldTank: Instance?)
	local plot = ClientState.MyPlot()
	local cam = workspace.CurrentCamera
	if not plot or not cam then
		return
	end
	-- дождаться новой модели аквариума с сервера
	local target: Instance? = nil
	local t0 = os.clock()
	if kind == "Tank" then
		repeat
			local t = plot:FindFirstChild("Tank")
			if t and t ~= oldTank then
				target = t
			end
			task.wait(0.05)
		until target or os.clock() - t0 > 2
	else
		target = plot:FindFirstChild("PullUpBar")
	end
	if not target then
		return
	end
	local cf, size = (target :: Model):GetBoundingBox()
	local center = cf.Position
	local color = kind == "Tank" and Color3.fromRGB(90, 220, 255) or Color3.fromRGB(255, 190, 60)

	-- спрятать детали, чтобы потом «собрать»
	local parts = {}
	for _, d in ipairs(target:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored and not d:FindFirstAncestor("Fish") then
			table.insert(parts, { part = d, cf = d.CFrame })
			d.LocalTransparencyModifier = 1
		end
	end
	table.sort(parts, function(a, b)
		return a.cf.Position.Y < b.cf.Position.Y
	end)

	-- камера облетает базу
	local savedType = cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable
	local radius = math.max(22, size.Magnitude * 1.1)
	local baseYaw = math.atan2((cam.CFrame.Position - center).X, (cam.CFrame.Position - center).Z)
	local duration = 3.4
	local running = true
	task.spawn(function()
		local s0 = os.clock()
		while running do
			local k = math.min(1, (os.clock() - s0) / duration)
			local yaw = baseYaw + k * 1.6
			local pos = center + Vector3.new(math.sin(yaw) * radius, radius * 0.45, math.cos(yaw) * radius)
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(pos, center + Vector3.new(0, 2, 0)), 0.12)
			RunService.RenderStepped:Wait()
		end
	end)

	task.wait(0.5)
	-- столб света и вспышка
	local pillar = anchoredPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(200, 2, 2), CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), Color = color, Material = Enum.Material.Neon, Transparency = 0.2 })
	TweenService:Create(pillar, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = Vector3.new(200, size.X * 0.9, size.X * 0.9), Transparency = 0.75 }):Play()
	local flashCc = Instance.new("ColorCorrectionEffect")
	flashCc.Brightness = 0.6
	flashCc.TintColor = color
	flashCc.Parent = Lighting
	TweenService:Create(flashCc, TweenInfo.new(0.8), { Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	Debris:AddItem(flashCc, 1)

	-- детали падают на место по очереди
	local stagger = math.min(0.03, 1.2 / math.max(1, #parts))
	for i, p in ipairs(parts) do
		local part = p.part :: BasePart
		if part.Parent then
			part.CFrame = p.cf * CFrame.new(0, 10 + (i % 5), 0) * CFrame.Angles(0, (i % 2 == 0) and 0.6 or -0.6, 0)
			TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Bounce), { CFrame = p.cf, LocalTransparencyModifier = 0 }):Play()
		end
		if i % 6 == 0 then
			task.wait(stagger * 6)
		end
	end
	task.wait(0.4)
	Effects.Burst(center + Vector3.new(0, 4, 0), color, 120)
	Effects.Burst(center + Vector3.new(0, 8, 0), Color3.fromRGB(255, 255, 255), 60)
	local banner = upgradeBanner(pillar, kind == "Tank" and "AQUARIUM UPGRADED!" or "NEW PULL-UP BAR!", title, color)
	TweenService:Create(pillar, TweenInfo.new(1.6), { Transparency = 1 }):Play()
	task.wait(1.8)
	banner:Destroy()
	pillar:Destroy()
	for _, p in ipairs(parts) do
		if p.part.Parent then
			p.part.CFrame = p.cf
			p.part.LocalTransparencyModifier = 0
		end
	end
	running = false
	cam.CameraType = savedType == Enum.CameraType.Scriptable and Enum.CameraType.Custom or savedType
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

function Effects.Init()
	Remotes.Get("CastFx").OnClientEvent:Connect(otherCast)

	for _, p in ipairs(CollectionService:GetTagged("RainbowPart")) do
		trackRainbow(p)
	end
	CollectionService:GetInstanceAddedSignal("RainbowPart"):Connect(trackRainbow)
	CollectionService:GetInstanceRemovedSignal("RainbowPart"):Connect(function(p)
		rainbowParts[p :: BasePart] = nil
	end)

	local timers = { income = 0, weather = 0 }
	RunService.RenderStepped:Connect(function(dt)
		animateTanks(dt)
		local t = os.clock()
		for p in pairs(rainbowParts) do
			if p.Parent then
				local h = ((p:GetAttribute("Hue") or 0) + t * 0.25) % 1
				p.Color = Color3.fromHSV(h, 0.75, 1)
			else
				rainbowParts[p] = nil
			end
		end
		local cam = workspace.CurrentCamera
		if rainPart and cam then
			rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
		end
		timers.income += dt
		if timers.income >= 2 then
			timers.income = 0
			incomePopup()
		end
		timers.weather += dt
		if timers.weather >= 0.5 then
			timers.weather = 0
			local ev = workspace:GetAttribute("Event") or ""
			local ends = workspace:GetAttribute("EventEnds") or 0
			if ev ~= "" and workspace:GetServerTimeNow() >= ends then
				ev = ""
			end
			if ev ~= currentEvent then
				currentEvent = ev
				setRain(ev == "Storm")
			end
			if ev == "Storm" and rng:NextNumber() < 0.06 then
				lightning()
			elseif ev == "MeteorShower" and rng:NextNumber() < 0.45 then
				meteor()
			elseif ev == "Frenzy" then
				jumpingFish()
			elseif ev == "" and rng:NextNumber() < 0.08 then
				jumpingFish()
			end
		end
	end)
end

Effects.Folder = fxFolder
local _ = GameData

return Effects
