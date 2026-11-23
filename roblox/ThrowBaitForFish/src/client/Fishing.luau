-- Рыбалка на клиенте с мини-катсценой:
-- камера за плечом при замахе -> полёт за поплавком -> наезд при клёве ->
-- рыба выпрыгивает в замедлении, камера облетает её -> рыба летит к игроку -> карточка улова.
-- Тело игрока анимируется суставами: замах, хлёст, держит удочку, крутит катушку, подсекает.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local FishBuilder = require(Shared.FishBuilder)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.ClientState)
local UI = require(script.Parent.UI)
local Effects = require(script.Parent.Effects)

local player = Players.LocalPlayer
local Fishing = {}

local state = "Idle" -- Idle | Charging | Busy
local chargeStart = 0
local reelProgress = 0
local reeling = false
local cinematic = true

local UP = Vector3.new(0, 1, 0)

local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function pierDir(): Vector3
	local zone = ClientState.CastZone()
	return zone and zone.CFrame.LookVector or Vector3.new(1, 0, 0)
end

-- ===== Позы тела =====
local JOINTS = {
	RightShoulder = "RightUpperArm",
	LeftShoulder = "LeftUpperArm",
	RightElbow = "RightLowerArm",
	LeftElbow = "LeftLowerArm",
	Waist = "UpperTorso",
}
local joints = {} :: { [string]: { motor: Motor6D, base: CFrame, cur: CFrame, goal: CFrame } }
local poseSpeed = 12
local poseName = "Rest"
local poseCharge = 0

local function bindJoints()
	joints = {}
	local character = player.Character
	if not character then
		return
	end
	for jointName, partName in pairs(JOINTS) do
		local part = character:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(jointName)
		if motor and motor:IsA("Motor6D") then
			joints[jointName] = { motor = motor, base = motor.C0, cur = CFrame.identity, goal = CFrame.identity }
		end
	end
end

local function rad(d: number): number
	return math.rad(d)
end

-- Цели суставов для каждой позы
local function poseGoals(name: string, t: number): { [string]: CFrame }
	local A = CFrame.Angles
	if name == "Windup" then
		local c = poseCharge
		return {
			RightShoulder = A(rad(-155 * c), 0, 0.25 * c),
			RightElbow = A(rad(25 * c), 0, 0),
			LeftShoulder = A(rad(45 * c), 0, 0.35 * c),
			Waist = A(0, -0.65 * c, 0) * A(-0.12 * c, 0, 0),
		}
	elseif name == "Whip" then
		return {
			RightShoulder = A(rad(85), 0, 0),
			RightElbow = A(rad(5), 0, 0),
			LeftShoulder = A(rad(30), 0, 0.2),
			Waist = A(0, 0.4, 0) * A(0.15, 0, 0),
		}
	elseif name == "Hold" then
		local breathe = math.sin(t * 2) * 0.03
		return {
			RightShoulder = A(rad(40) + breathe, 0, 0),
			RightElbow = A(rad(35), 0, 0),
			LeftShoulder = A(rad(50) + breathe, 0, 0.35),
			LeftElbow = A(rad(55), 0, 0),
			Waist = A(0, 0.1, 0),
		}
	elseif name == "Reel" then
		local crank = t * 16
		local tug = math.sin(t * 9) * 0.06
		return {
			RightShoulder = A(rad(58) + tug, 0, 0),
			RightElbow = A(rad(45), 0, 0),
			LeftShoulder = A(rad(48) + math.sin(crank) * 0.22, 0, 0.35 + math.cos(crank) * 0.1),
			LeftElbow = A(rad(60) + math.cos(crank) * 0.25, 0, 0),
			Waist = A(-0.12 + tug, 0.08, 0),
		}
	elseif name == "Hook" then
		return {
			RightShoulder = A(rad(160), 0, 0.1),
			RightElbow = A(rad(20), 0, 0),
			LeftShoulder = A(rad(120), 0, 0.3),
			LeftElbow = A(rad(30), 0, 0),
			Waist = A(-0.3, 0, 0),
		}
	end
	return {}
end

local function setPose(name: string, speed: number?)
	poseName = name
	poseSpeed = speed or 12
end

local function updatePose(dt: number)
	if player:GetAttribute("Training") then
		return -- позой на турнике управляет сервер
	end
	local character = player.Character
	if not character then
		return
	end
	local any = next(joints)
	if not any or not joints[any].motor.Parent or not joints[any].motor:IsDescendantOf(character) then
		bindJoints()
	end
	local goals = poseGoals(poseName, os.clock())
	local a = 1 - math.exp(-dt * poseSpeed)
	for name, j in pairs(joints) do
		j.goal = goals[name] or CFrame.identity
		j.cur = j.cur:Lerp(j.goal, a)
		if j.motor.Parent then
			j.motor.C0 = j.base * j.cur
		end
	end
end

-- ===== Камера =====
local cam = {
	active = false,
	fn = nil :: ((number) -> (CFrame, number))?,
	speed = 6,
	shake = 0,
	t0 = 0,
}

local function camStart()
	if not cinematic then
		return
	end
	local c = workspace.CurrentCamera
	if c then
		c.CameraType = Enum.CameraType.Scriptable
		cam.active = true
	end
end

local function camShot(fn: (number) -> (CFrame, number), speed: number?)
	cam.fn = fn
	cam.speed = speed or 6
	cam.t0 = os.clock()
end

local function camStop()
	cam.active = false
	cam.fn = nil
	local c = workspace.CurrentCamera
	if c then
		c.CameraType = Enum.CameraType.Custom
		local hum = humanoid()
		if hum then
			c.CameraSubject = hum
		end
		TweenService:Create(c, TweenInfo.new(0.4), { FieldOfView = 70 }):Play()
	end
end

local function camShake(power: number)
	cam.shake = math.max(cam.shake, power)
end

local function updateCamera(dt: number)
	if not cam.active or not cam.fn then
		return
	end
	local c = workspace.CurrentCamera
	if not c then
		return
	end
	local cf, fov = cam.fn(os.clock() - cam.t0)
	local a = 1 - math.exp(-dt * cam.speed)
	local nextCf = c.CFrame:Lerp(cf, a)
	if cam.shake > 0.01 then
		nextCf = nextCf * CFrame.Angles((math.random() - 0.5) * cam.shake * 0.05, (math.random() - 0.5) * cam.shake * 0.05, 0)
		cam.shake *= math.exp(-dt * 6)
	end
	c.CFrame = nextCf
	c.FieldOfView += (fov - c.FieldOfView) * a
end

local function overShoulder(): CFrame
	local r = root()
	local dir = pierDir()
	if not r then
		return workspace.CurrentCamera.CFrame
	end
	local right = dir:Cross(UP)
	local pos = r.Position - dir * 10 + right * 4 + UP * 4.5
	return CFrame.lookAt(pos, r.Position + dir * 40 + UP * 6)
end

-- ===== Вспомогательное =====
local function flashScreen(color: Color3, strength: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = color
	cc.Brightness = strength
	cc.Parent = Lighting
	local tw = TweenService:Create(cc, TweenInfo.new(0.6), { Brightness = 0, TintColor = Color3.new(1, 1, 1) })
	tw:Play()
	tw.Completed:Connect(function()
		cc:Destroy()
	end)
end

local function bigText(parent: BasePart, text: string, color: Color3)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(420, 90)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = parent
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.LuckiestGuy
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0
	t.Parent = bb
	local s = Instance.new("UIScale")
	s.Scale = 0.2
	s.Parent = t
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	return bb
end

local function exclamation(parent: BasePart, rarity: number)
	local col = rarity >= GameData.RarityIndex.Epic and GameData.Rarities[rarity].Color or Color3.fromRGB(255, 230, 60)
	return bigText(parent, rarity >= GameData.RarityIndex.Legendary and "!!!" or "!", col)
end

local function lockMovement(lock: boolean)
	local hum = humanoid()
	if not hum then
		return
	end
	if lock then
		if not hum:GetAttribute("SavedSpeed") then
			hum:SetAttribute("SavedSpeed", hum.WalkSpeed)
			hum:SetAttribute("SavedJump", hum.JumpHeight)
		end
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
		local r = root()
		if r then
			local dir = pierDir()
			r.CFrame = CFrame.lookAt(r.Position, r.Position + dir)
		end
	else
		local ws = hum:GetAttribute("SavedSpeed")
		if ws then
			hum.WalkSpeed = ws
			hum.JumpHeight = hum:GetAttribute("SavedJump") or 7.2
			hum:SetAttribute("SavedSpeed", nil)
			hum:SetAttribute("SavedJump", nil)
		end
	end
end

local guideBeam: Beam? = nil
local function showGuide()
	local r = root()
	local spot = r and ClientState.NearestSpot(r.Position)
	if not spot or not r then
		return
	end
	if guideBeam then
		guideBeam:Destroy()
	end
	local a0 = Instance.new("Attachment")
	a0.Parent = r
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 1, 0)
	a1.Parent = spot
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 1.2
	beam.Width1 = 1.2
	beam.Color = ColorSequence.new(Color3.fromRGB(120, 240, 255))
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureSpeed = 2
	beam.TextureLength = 3
	beam.Parent = r
	guideBeam = beam
	task.delay(8, function()
		beam:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- ===== Катсцена улова =====
local function catchCutscene(res, from: Vector3)
	local def = GameData.FishById[res.fish]
	local r = root()
	if not def or not r then
		return
	end
	local rarity = GameData.Rarities[def.Rarity]
	local big = def.Rarity >= GameData.RarityIndex.Legendary
	local fancy = def.Rarity >= GameData.RarityIndex.Rare
	local len = math.min(7, FishBuilder.DisplayLength(res.fish, res.size) * 1.4)
	local m = FishBuilder.Build(res.fish, res.mutation, len)
	m.Parent = Effects.Folder
	local body = m.PrimaryPart :: BasePart
	-- шлейф и свет цвета редкости
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, len * 0.15, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -len * 0.15, 0)
	a1.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.Color = ColorSequence.new(rarity.Color)
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = body
	local glow = Instance.new("PointLight")
	glow.Color = rarity.Color
	glow.Range = 14
	glow.Brightness = fancy and 3 or 1.5
	glow.Parent = body

	-- 1) прыжок из воды
	local dir = pierDir()
	local right = dir:Cross(UP)
	local apex = from + UP * (7 + def.Rarity * 1.2)
	local start = from - UP * 2
	Effects.Splash(from, 1.8)
	setPose("Hook", 18)
	camShake(fancy and 1.2 or 0.6)
	camShot(function(t)
		local p = body.Position
		return CFrame.lookAt(p - dir * 16 + right * 8 + UP * 2, p), 55
	end, 7)
	local t0 = os.clock()
	local leap = 0.35
	while os.clock() - t0 < leap do
		local k = (os.clock() - t0) / leap
		local e = 1 - (1 - k) ^ 2
		local p = start:Lerp(apex, e)
		body.CFrame = CFrame.new(p) * CFrame.Angles(-math.pi / 2 * (1 - k), k * 2, 0)
		RunService.RenderStepped:Wait()
	end

	-- 2) замедление в верхней точке, камера облетает рыбу
	local hover = big and 1.9 or (fancy and 1.1 or 0.45)
	local label: BillboardGui? = nil
	if fancy then
		Effects.Burst(apex, rarity.Color, big and 90 or 45)
		flashScreen(rarity.Color, big and 0.45 or 0.2)
		if big then
			label = bigText(body, string.upper(rarity.Name) .. "!", rarity.Color)
		end
	end
	local orbitFrom = math.random() < 0.5 and -1 or 1
	camShot(function(t)
		local k = math.clamp(t / hover, 0, 1)
		local ang = orbitFrom * (0.9 - k * 1.6)
		local offset = (CFrame.Angles(0, ang, 0) * CFrame.new(0, 1.5, 9 + len)).Position
		local camPos = apex + (CFrame.lookAt(Vector3.zero, -dir)).Rotation * offset
		return CFrame.lookAt(camPos, apex), big and 40 or 48
	end, 5)
	local h0 = os.clock()
	while os.clock() - h0 < hover do
		local k = (os.clock() - h0) / hover
		local bob = math.sin(k * math.pi) * 0.8
		body.CFrame = CFrame.new(apex + UP * bob) * CFrame.Angles(0, 2 + k * math.pi * 2, math.sin(k * 12) * 0.15)
		RunService.RenderStepped:Wait()
	end
	if label then
		label:Destroy()
	end

	-- 3) полёт к игроку
	local target = r.Position + UP * 3.5 + dir * 2
	local dist = (target - apex).Magnitude
	local dur = 0.7 + math.min(0.9, dist / 600)
	local height = 6 + dist * 0.1
	camShot(function()
		local p = body.Position
		local toPlayer = (r.Position - p)
		local back = toPlayer.Magnitude > 1 and -toPlayer.Unit or dir
		return CFrame.lookAt(p + back * 14 + UP * 5 + right * 4, p), 65
	end, 9)
	setPose("Hold", 10)
	local f0 = os.clock()
	local prev = apex
	local spin = 0
	while os.clock() - f0 < dur do
		local k = (os.clock() - f0) / dur
		local e = k < 0.5 and 2 * k * k or 1 - (-2 * k + 2) ^ 2 / 2
		local p = Effects.Arc(apex, target, height, e)
		spin += 0.3
		if (p - prev).Magnitude > 0.001 then
			body.CFrame = CFrame.lookAt(p, p + (p - prev)) * CFrame.Angles(0, 0, spin)
		end
		prev = p
		RunService.RenderStepped:Wait()
	end
	Effects.Burst(target, rarity.Color, big and 80 or 30)
	camShake(0.4)
	m:Destroy()
end

-- ===== Сам заброс =====
local function finish()
	state = "Idle"
	reeling = false
	setPose("Rest", 8)
	UI.SetReel(false)
	camStop()
	lockMovement(false)
end

local function doCast(charge: number)
	state = "Busy"
	UI.SetCharge(false)
	setPose("Whip", 28)
	camShake(0.3)
	local res = Remotes.Get("Cast"):InvokeServer(charge)
	if not res or not res.ok then
		finish()
		local reason = res and res.reason
		if reason == "far" then
			UI.Toast("🎣 Go to the FISHING PIER to cast!", Color3.fromRGB(255, 200, 80))
			showGuide()
			UI.FlashPier()
		elseif reason == "training" then
			UI.Toast("Stop training first!", Color3.fromRGB(255, 120, 90))
		end
		return
	end
	if res.lucky then
		UI.Toast("🍀 LUCKY CAST! x" .. Config.LuckyCastLuck .. " luck", Color3.fromRGB(120, 255, 120))
	end
	local tip = Effects.RodTip(player.Character)
	local r = root()
	local from = tip and tip.WorldPosition or ((r and r.Position or Vector3.zero) + UP * 3)
	local bobber, att = Effects.MakeBobber()
	local line = tip and Effects.MakeLine(tip, att) or nil
	local landing: Vector3 = res.land
	local height = 8 + res.dist * 0.22
	local top = bobber.PrimaryPart :: BasePart
	local dir = pierDir()
	local right = dir:Cross(UP)

	-- полёт: камера летит за поплавком
	camShot(function()
		local p = top.Position
		return CFrame.lookAt(p - dir * 22 + UP * 8 + right * 7, p + dir * 6), 78
	end, 7)
	if line then
		line.CurveSize0 = 0
		line.CurveSize1 = 0
	end
	local t0 = os.clock()
	while os.clock() - t0 < res.flight do
		local t = (os.clock() - t0) / res.flight
		Effects.PlaceBobber(bobber, Effects.Arc(from, landing, height, t))
		if t > 0.25 then
			setPose("Hold", 6)
		end
		RunService.RenderStepped:Wait()
	end
	Effects.PlaceBobber(bobber, landing)
	Effects.Splash(landing, 1.2)
	camShake(0.25)
	local zone = GameData.Zones[res.zone]
	UI.Toast("🌊 " .. zone.Name .. "  •  " .. math.floor(res.dist) .. "m", zone.Color, 2)
	if line then
		line.CurveSize0 = -2
		line.CurveSize1 = 3
	end

	-- ожидание поклёвки: спокойный общий план
	camShot(function(t)
		local sway = math.sin(t * 0.6) * 3
		return CFrame.lookAt(landing - dir * 26 + UP * 11 + right * (10 + sway), landing + UP * 1), 58
	end, 3)
	local t1 = os.clock()
	local nextRipple = 0
	while os.clock() - t1 < res.bite do
		local bob = math.sin(os.clock() * 3.5) * 0.15
		Effects.PlaceBobber(bobber, landing + Vector3.new(0, bob, 0))
		if os.clock() > nextRipple then
			nextRipple = os.clock() + 1.2
			Effects.Ripple(landing, 4)
		end
		RunService.RenderStepped:Wait()
	end

	-- клюёт! наезд камеры
	local bb = exclamation(top, res.rarity)
	Effects.Splash(landing, 0.8)
	camShake(res.rarity >= GameData.RarityIndex.Legendary and 1.5 or 0.7)
	camShot(function(t)
		local push = math.min(1, t / 3) * 3
		return CFrame.lookAt(landing - dir * (14 - push) + UP * 5 + right * 5, landing), 48
	end, 6)
	reelProgress = 0
	reeling = true
	setPose("Reel", 14)
	if line then
		line.CurveSize0 = 0
		line.CurveSize1 = 0
	end
	UI.SetReel(true, 0, res.rarity)
	local autoTime = res.reel * 1.7
	local nextSplash = 0
	while reelProgress < 1 do
		local dt = RunService.RenderStepped:Wait()
		reelProgress += dt / autoTime
		UI.SetReel(true, reelProgress, res.rarity)
		local jitter = Vector3.new(math.random() - 0.5, -0.3, math.random() - 0.5) * 0.6
		Effects.PlaceBobber(bobber, landing + jitter)
		if os.clock() > nextSplash then
			nextSplash = os.clock() + 0.3
			Effects.Ripple(landing, 3)
		end
	end
	reeling = false
	UI.SetReel(false)
	bb:Destroy()

	-- забрать рыбу с сервера
	local catch = nil
	for _ = 1, 6 do
		catch = Remotes.Get("Reel"):InvokeServer()
		if catch and catch.ok then
			break
		elseif catch and catch.reason == "early" then
			task.wait(math.max(0.05, catch.wait or 0.2))
		else
			break
		end
	end
	bobber:Destroy()
	if line then
		line:Destroy()
	end
	if catch and catch.ok then
		local ok, err = pcall(catchCutscene, catch, landing)
		if not ok then
			warn("[Fishing] cutscene: " .. tostring(err))
		end
		finish()
		UI.ShowCatch(catch)
	else
		finish()
		UI.Toast("The fish got away... 🐟", Color3.fromRGB(200, 200, 220))
	end
end

-- ===== Ввод =====
local function nearPier(): boolean
	local r = root()
	return r ~= nil and ClientState.InCastZone(r.Position)
end

local function beginCharge(auto: boolean?)
	if state ~= "Idle" or player:GetAttribute("Training") or not ClientState.Data then
		return
	end
	if not nearPier() then
		UI.Toast("🎣 Go to the FISHING PIER to cast!", Color3.fromRGB(255, 200, 80))
		showGuide()
		UI.FlashPier()
		return
	end
	-- в автозабросе камера не дёргается (игрок может быть АФК)
	cinematic = not auto
	state = "Charging"
	chargeStart = os.clock()
	poseCharge = 0
	setPose("Windup", 14)
	lockMovement(true)
	camStart()
	camShot(function()
		return overShoulder(), 62
	end, 6)
end

local function releaseCharge()
	if state ~= "Charging" then
		return
	end
	local charge = math.clamp((os.clock() - chargeStart) / Config.ChargeTime, 0.05, 1)
	task.spawn(function()
		local ok, err = pcall(doCast, charge)
		if not ok then
			warn("[Fishing] " .. tostring(err))
			finish()
		end
	end)
end

local function reelClick()
	if reeling then
		reelProgress += 0.12
		camShake(0.15)
	end
end

function Fishing.Init()
	UI.Callbacks.CastDown = function()
		beginCharge(false)
	end
	UI.Callbacks.CastUp = releaseCharge

	UserInputService.InputBegan:Connect(function(input, processed)
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
		if not isClick then
			if input.KeyCode == Enum.KeyCode.E and not processed then
				if reeling then
					reelClick()
				else
					beginCharge(false)
				end
			end
			return
		end
		if reeling then
			reelClick()
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and nearPier() then
			beginCharge(false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.E then
			releaseCharge()
		end
	end)

	player.CharacterAdded:Connect(function()
		joints = {}
		if state == "Charging" then
			state = "Idle"
			UI.SetCharge(false)
			camStop()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if state == "Charging" then
			local charge = math.clamp((os.clock() - chargeStart) / Config.ChargeTime, 0, 1)
			poseCharge = charge
			UI.SetCharge(true, charge, Config.MaxDistance(ClientState.Power()))
		end
		updatePose(dt)
		updateCamera(dt)
	end)

	-- Автозаброс (геймпасс)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if UI.AutoCast and ClientState.HasPass("AutoCast") and state == "Idle" and not player:GetAttribute("Training") and nearPier() then
				beginCharge(true)
				task.wait(Config.ChargeTime + 0.1)
				if state == "Charging" then
					releaseCharge()
				end
			end
		end
	end)
end

return Fishing
