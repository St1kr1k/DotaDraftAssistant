-- Рыбалка на клиенте: зарядка, замах удочкой, полёт поплавка, клёв, вываживание, рыба летит к игроку.

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

-- ===== Рука с удочкой =====
local shoulder: Motor6D? = nil
local shoulderC0: CFrame? = nil
local armAngle = 0
local armTarget = 0
local armShake = 0

local function findShoulder()
	local character = player.Character
	local arm = character and character:FindFirstChild("RightUpperArm")
	local joint = arm and arm:FindFirstChild("RightShoulder")
	if joint and joint:IsA("Motor6D") then
		if shoulder ~= joint then
			shoulder = joint
			shoulderC0 = joint.C0
		end
	else
		shoulder = nil
	end
end

local function updateArm(dt: number)
	if not shoulder or not shoulderC0 or not shoulder.Parent then
		findShoulder()
		return
	end
	if player:GetAttribute("Training") then
		return -- руками управляет сервер
	end
	armAngle += (armTarget - armAngle) * math.min(1, dt * 18)
	local shake = armShake > 0 and math.sin(os.clock() * 50) * armShake or 0
	shoulder.C0 = (shoulderC0 :: CFrame) * CFrame.Angles(armAngle + shake, 0, 0)
end

-- ===== Проверки =====
local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearSpot(): boolean
	local spot = ClientState.CastSpot()
	local r = root()
	if not spot or not r then
		return false
	end
	local d = (r.Position - spot.Position) * Vector3.new(1, 0, 1)
	return d.Magnitude <= Config.CastSpotRadius - 1 and math.abs(r.Position.Y - spot.Position.Y) < 8
end

local guideBeam: Beam? = nil
local function showGuide()
	local spot = ClientState.CastSpot()
	local r = root()
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
	task.delay(6, function()
		beam:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- ===== Камера =====
local function setCameraSubject(part: BasePart?)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if part then
		cam.CameraSubject = part
	else
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
end

local function cameraShake(power: number, duration: number)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local k = 1 - (os.clock() - t0) / duration
			hum.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * power * k
			RunService.RenderStepped:Wait()
		end
		hum.CameraOffset = Vector3.zero
	end)
end

-- ===== «!» над поплавком =====
local function exclamation(parent: BasePart, rarity: number)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(90, 90)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = parent
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = rarity >= GameData.RarityIndex.Legendary and "!!!" or "!"
	t.TextColor3 = rarity >= GameData.RarityIndex.Epic and GameData.Rarities[rarity].Color or Color3.fromRGB(255, 230, 60)
	t.TextStrokeTransparency = 0
	t.Parent = bb
	local s = Instance.new("UIScale")
	s.Scale = 0.1
	s.Parent = t
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	return bb
end

-- ===== Сам заброс =====
local function finish()
	state = "Idle"
	reeling = false
	armTarget = 0
	armShake = 0
	UI.SetReel(false)
	setCameraSubject(nil)
end

local function flyFishToPlayer(res, from: Vector3)
	local def = GameData.FishById[res.fish]
	local r = root()
	if not def or not r then
		return
	end
	local len = math.min(6, FishBuilder.DisplayLength(res.fish, res.size) * 1.3)
	local m = FishBuilder.Build(res.fish, res.mutation, len)
	m.Parent = Effects.Folder
	local body = m.PrimaryPart :: BasePart
	local rarity = GameData.Rarities[def.Rarity]
	-- шлейф цвета редкости
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, len * 0.15, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -len * 0.15, 0)
	a1.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new(rarity.Color)
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = body
	Effects.Splash(from, 1.6)
	if def.Rarity >= GameData.RarityIndex.Epic then
		Effects.Burst(from + Vector3.new(0, 2, 0), rarity.Color, 40)
		cameraShake(0.6, 0.4)
	end
	setCameraSubject(body)
	local target = r.Position + Vector3.new(0, 4, 0) + r.CFrame.LookVector * 3
	local dist = (target - from).Magnitude
	local dur = 0.8 + math.min(1.2, dist / 500)
	local height = 10 + dist * 0.15
	local t0 = os.clock()
	local prev = from
	local spin = 0
	while os.clock() - t0 < dur do
		local t = (os.clock() - t0) / dur
		local e = t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
		local p = Effects.Arc(from, target, height, e)
		spin += 0.35
		if (p - prev).Magnitude > 0.001 then
			body.CFrame = CFrame.lookAt(p, p + (p - prev)) * CFrame.Angles(0, 0, spin)
		end
		prev = p
		RunService.RenderStepped:Wait()
	end
	Effects.Burst(target, rarity.Color, def.Rarity >= GameData.RarityIndex.Legendary and 70 or 30)
	m:Destroy()
	setCameraSubject(nil)
end

local function doCast(charge: number)
	state = "Busy"
	UI.SetCharge(false)
	-- хлёсткий замах вперёд
	armTarget = math.rad(75)
	local res = Remotes.Get("Cast"):InvokeServer(charge)
	if not res or not res.ok then
		finish()
		local reason = res and res.reason
		if reason == "far" then
			UI.Toast("🎣 Go to the end of YOUR pier to cast!", Color3.fromRGB(255, 200, 80))
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
	local from = tip and tip.WorldPosition or ((root() :: BasePart).Position + Vector3.new(0, 3, 0))
	local bobber, att = Effects.MakeBobber()
	local line = tip and Effects.MakeLine(tip, att) or nil
	local landing: Vector3 = res.land
	local height = 6 + res.dist * 0.2
	local top = bobber.PrimaryPart :: BasePart

	-- полёт
	setCameraSubject(top)
	if line then
		line.CurveSize0 = 0
		line.CurveSize1 = 0
	end
	local t0 = os.clock()
	while os.clock() - t0 < res.flight do
		local t = (os.clock() - t0) / res.flight
		Effects.PlaceBobber(bobber, Effects.Arc(from, landing, height, t))
		RunService.RenderStepped:Wait()
	end
	Effects.PlaceBobber(bobber, landing)
	Effects.Splash(landing, 1)
	armTarget = math.rad(35)
	local zone = GameData.Zones[res.zone]
	UI.Toast("🌊 " .. zone.Name .. "  •  " .. math.floor(res.dist) .. "m", zone.Color, 2)
	if line then
		line.CurveSize0 = -2
		line.CurveSize1 = 3
	end

	-- ожидание поклёвки
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

	-- клюёт!
	local bb = exclamation(top, res.rarity)
	Effects.Splash(landing, 0.7)
	cameraShake(res.rarity >= GameData.RarityIndex.Legendary and 0.8 or 0.35, 0.3)
	reelProgress = 0
	reeling = true
	armShake = 0.06
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
		local jitter = Vector3.new(math.random() - 0.5, -0.3, math.random() - 0.5) * 0.5
		Effects.PlaceBobber(bobber, landing + jitter)
		if os.clock() > nextSplash then
			nextSplash = os.clock() + 0.35
			Effects.Ripple(landing, 3)
		end
	end
	reeling = false
	UI.SetReel(false)
	armTarget = math.rad(-40)
	armShake = 0
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
		flyFishToPlayer(catch, landing)
		UI.ShowCatch(catch)
	else
		UI.Toast("The fish got away... 🐟", Color3.fromRGB(200, 200, 220))
	end
	finish()
end

-- ===== Ввод =====
local function beginCharge()
	if state ~= "Idle" then
		return
	end
	if player:GetAttribute("Training") then
		return
	end
	if not ClientState.Data then
		return
	end
	if not nearSpot() then
		UI.Toast("🎣 Go to the end of YOUR pier to cast!", Color3.fromRGB(255, 200, 80))
		showGuide()
		UI.FlashPier()
		return
	end
	state = "Charging"
	chargeStart = os.clock()
end

local function releaseCharge()
	if state ~= "Charging" then
		return
	end
	local charge = math.clamp((os.clock() - chargeStart) / Config.ChargeTime, 0.05, 1)
	task.spawn(doCast, charge)
end

local function reelClick()
	if reeling then
		reelProgress += 0.12
		armShake = 0.12
		task.delay(0.08, function()
			if reeling then
				armShake = 0.06
			end
		end)
	end
end

function Fishing.Init()
	-- клики во время вываживания ловит UserInputService ниже (в т.ч. по кнопке), здесь только заряд
	UI.Callbacks.CastDown = beginCharge
	UI.Callbacks.CastUp = releaseCharge

	UserInputService.InputBegan:Connect(function(input, processed)
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
		if not isClick then
			if input.KeyCode == Enum.KeyCode.E and not processed then
				if reeling then
					reelClick()
				else
					beginCharge()
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
		-- клик мышью по миру: заброс только если стоим у своего причала (чтобы не мешать ходить)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and nearSpot() then
			beginCharge()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.E then
			releaseCharge()
		end
	end)

	player.CharacterAdded:Connect(function()
		shoulder = nil
		shoulderC0 = nil
		armAngle = 0
		armTarget = 0
		if state == "Charging" then
			state = "Idle"
			UI.SetCharge(false)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		updateArm(dt)
		if state == "Charging" then
			local charge = math.clamp((os.clock() - chargeStart) / Config.ChargeTime, 0, 1)
			-- замах назад, пока заряжаем
			armTarget = math.rad(-150) * charge
			UI.SetCharge(true, charge, Config.MaxDistance(ClientState.Power()))
		end
	end)

	-- Автозаброс (геймпасс)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if UI.AutoCast and ClientState.HasPass("AutoCast") and state == "Idle" and not player:GetAttribute("Training") and nearSpot() then
				state = "Charging"
				chargeStart = os.clock()
				task.wait(Config.ChargeTime + 0.1)
				if state == "Charging" then
					releaseCharge()
				end
			end
		end
	end)
end

return Fishing
