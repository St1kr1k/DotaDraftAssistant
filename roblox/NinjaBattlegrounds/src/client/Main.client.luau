-- Клиент: управление, анимации всех бойцов, эффекты, HUD, кинокамера суперудара.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Moves = require(Shared.Moves)
local Anim = require(Shared.Anim)
local VFX = require(script.Parent.VFX)

local player = Players.LocalPlayer

while not workspace:GetAttribute("Ready") do
	task.wait(0.2)
end

-- ===================== HUD =====================
local gui = Instance.new("ScreenGui")
gui.Name = "BattleHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function label(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.LuckiestGuy
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do
		if k ~= "Stroke" then
			(t :: any)[k] = v
		end
	end
	local s = Instance.new("UIStroke")
	s.Thickness = props.Stroke or 3
	s.Color = Color3.fromRGB(10, 10, 20)
	s.Parent = t
	return t
end

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -24)
bar.Size = UDim2.fromOffset(3 * 96 + 2 * 12, 96)
bar.BackgroundTransparency = 1
bar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 12)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = bar

local slots = {} :: { [string]: { button: TextButton, shade: Frame, timer: TextLabel, ends: number, total: number } }

local function keyName(code: Enum.KeyCode): string
	local map = { [Enum.KeyCode.One] = "1", [Enum.KeyCode.Q] = "Q", [Enum.KeyCode.G] = "G" }
	return map[code] or code.Name
end

local fire -- объявлено ниже

for i, id in ipairs(Moves.Order) do
	local m = Moves[id]
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(96, 96)
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = id == "Super" and Color3.fromRGB(255, 170, 40) or Color3.fromRGB(40, 120, 230)
	b.LayoutOrder = i
	b.Parent = bar
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = b
	local st = Instance.new("UIStroke")
	st.Thickness = 3.5
	st.Color = Color3.fromRGB(10, 10, 20)
	st.Parent = b
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(160, 170, 200))
	g.Rotation = 90
	g.Parent = b
	label({ Text = m.Icon, Size = UDim2.new(1, -16, 0.55, 0), Position = UDim2.fromOffset(8, 6), Stroke = 0, Parent = b })
	label({ Text = m.Name, Size = UDim2.new(1, -8, 0.22, 0), Position = UDim2.new(0, 4, 0.62, 0), Font = Enum.Font.FredokaOne, Stroke = 2, Parent = b })
	label({ Text = keyName(m.Key), Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(-6, -10), TextColor3 = Color3.fromRGB(255, 230, 80), Parent = b })
	local shade = Instance.new("Frame")
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.ZIndex = 3
	shade.Parent = b
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 16)
	sc.Parent = shade
	local timer = label({ Text = "", Size = UDim2.fromScale(0.6, 0.4), Position = UDim2.fromScale(0.2, 0.3), ZIndex = 4, Parent = b })
	slots[id] = { button = b, shade = shade, timer = timer, ends = 0, total = 1 }
	b.Activated:Connect(function()
		fire(id)
	end)
end

local comboLabel = label({ Text = "", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.4, 0), Size = UDim2.fromOffset(260, 90),
	TextColor3 = Color3.fromRGB(255, 220, 70), Rotation = -6, Stroke = 4, Parent = gui })
local combo, comboAt = 0, 0

local toastLabel = label({ Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -140), Size = UDim2.fromOffset(420, 40),
	Font = Enum.Font.FredokaOne, Parent = gui })

local function toast(text: string)
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	task.delay(1.6, function()
		if toastLabel.Text == text then
			TweenService:Create(toastLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end)
end

local hint = label({ Text = "1 — Clone Combo    G — Super    Q — Dodge", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.fromOffset(520, 30), Font = Enum.Font.FredokaOne, Parent = gui })
task.delay(12, function()
	TweenService:Create(hint, TweenInfo.new(1), { TextTransparency = 1 }):Play()
end)

-- ===================== Действия =====================
fire = function(id: string)
	local char = player.Character
	if not char or char:GetAttribute("Locked") then
		return
	end
	local s = slots[id]
	if s and os.clock() < s.ends then
		return
	end
	local arg = nil
	if id == "Dodge" then
		local hum = char:FindFirstChildOfClass("Humanoid")
		arg = hum and hum.MoveDirection or nil
	end
	Net.Get("Action"):FireServer(id, arg)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	for id, m in pairs(Moves) do
		if type(m) == "table" and m.Key == input.KeyCode then
			fire(id)
		end
	end
end)

Net.Get("Cooldown").OnClientEvent:Connect(function(id, seconds)
	local s = slots[id]
	if not s then
		return
	end
	s.total = math.max(0.01, seconds)
	s.ends = os.clock() + seconds
end)

-- ===================== Анимации =====================
local ATTACK_CLIPS = { CloneRushPunch = true, CloneSpinKick = true, CloneSweep = true, FinisherPunch = true, CloneKickUp = true, HeelDrop = true }

Net.Get("Play").OnClientEvent:Connect(function(model, clip, speed)
	if typeof(model) == "Instance" and model:IsA("Model") then
		Anim.Play(model, clip, { speed = speed, blend = ATTACK_CLIPS[clip] and 0.05 or 0.1 })
	end
end)
Net.Get("Stop").OnClientEvent:Connect(function(model)
	if typeof(model) == "Instance" and model:IsA("Model") then
		Anim.Stop(model, 0.2)
	end
end)

-- Боевая стойка, когда боец стоит на месте
RunService.Heartbeat:Connect(function()
	for _, m in ipairs(CollectionService:GetTagged("Fighter")) do
		if m:IsA("Model") and not m:GetAttribute("Locked") and not CollectionService:HasTag(m, "Dummy") then
			local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local cur = Anim.Current(m)
				local moving = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 1.5 or hum.FloorMaterial == Enum.Material.Air
				if moving then
					if cur == "FightIdle" then
						Anim.Stop(m, 0.12)
					end
				elseif cur == nil then
					Anim.Play(m, "FightIdle", { blend = 0.25 })
				end
			end
		end
	end
end)

-- ===================== Эффекты =====================
local function damageNumber(pos: Vector3, amount: number)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.Transparency = 1
	a.Size = Vector3.one * 0.2
	a.Position = pos + Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1)
	a.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 50)
	bb.AlwaysOnTop = true
	bb.Parent = a
	local t = label({ Text = tostring(math.floor(amount)), Size = UDim2.fromScale(1, 1), TextColor3 = amount >= 20 and Color3.fromRGB(255, 120, 60) or Color3.new(1, 1, 1), Parent = bb })
	local sc = Instance.new("UIScale")
	sc.Scale = 1.8
	sc.Parent = t
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(a, TweenInfo.new(0.8), { Position = a.Position + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(a, 0.9)
end

local FX = {}
FX.Smoke = VFX.Smoke
FX.ChakraBurst = VFX.ChakraBurst
FX.Impact = VFX.Impact
FX.UpStreak = VFX.UpStreak
FX.Crater = VFX.Crater
FX.Dust = VFX.Dust
FX.Afterimage = VFX.Afterimage
FX.Aura = VFX.Aura
FX.Trails = function(model, on)
	VFX.Trails(model, on, Color3.fromRGB(200, 235, 255))
end
FX.Flash = function(strength)
	VFX.Flash(Color3.new(1, 1, 1), strength)
end
FX.Vanish = function(model, invisible)
	VFX.SetVisible(model, not invisible)
end
FX.HitStop = function(a, b, seconds)
	if a then
		Anim.Freeze(a, seconds)
	end
	if b then
		Anim.Freeze(b, seconds)
	end
end
FX.Damage = damageNumber
FX.Combo = function(n)
	if os.clock() - comboAt > 2 then
		combo = 0
	end
	combo += n
	comboAt = os.clock()
	comboLabel.Text = combo .. " HITS!"
	comboLabel.TextTransparency = 0
	local sc = comboLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", comboLabel)
	sc.Scale = 1.5
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end
FX.DustTrail = function(model, duration)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration and model.Parent do
			local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				VFX.Dust(hrp.Position - Vector3.new(0, 2.5, 0), 0.7)
			end
			task.wait(0.06)
		end
	end)
end
FX.Toast = toast

Net.Get("Fx").OnClientEvent:Connect(function(name, ...)
	local fn = FX[name]
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[FX] " .. tostring(name) .. ": " .. tostring(err))
		end
	end
end)

-- ===================== Кинокамера суперудара =====================
local function cineSuper(char: Model, target: Model)
	local cam = workspace.CurrentCamera
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local thrp = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not cam or not hrp or not thrp then
		return
	end
	local base = thrp.Position
	local toA = (hrp.Position - base) * Vector3.new(1, 0, 1)
	toA = toA.Magnitude > 0.1 and toA.Unit or Vector3.new(0, 0, 1)
	local side = toA:Cross(Vector3.yAxis).Unit
	cam.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	local total = 4.2
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local goal: CFrame
		local fov = 70
		if t < 0.6 then
			-- крупно: знак руками
			local p = hrp.Position
			goal = CFrame.lookAt(p + hrp.CFrame.LookVector * 7 + Vector3.new(0, 1.5, 0) + side * 2, p + Vector3.new(0, 1, 0))
			fov = 55
		elseif t < 2.7 then
			-- общий план сбоку: враг взлетает от подкатов
			local look = thrp.Position
			goal = CFrame.lookAt(base + side * 24 + toA * 6 + Vector3.new(0, 6 + (look.Y - base.Y) * 0.5, 0), look)
			fov = 62
		else
			-- снизу: прыжок и удар пяткой
			local mid = (hrp.Position + thrp.Position) / 2
			goal = CFrame.lookAt(base + side * 14 + toA * 10 + Vector3.new(0, 2, 0), mid)
			fov = 72
		end
		cam.CFrame = cam.CFrame:Lerp(goal, 1 - math.exp(-dt * 8))
		cam.FieldOfView += (fov - cam.FieldOfView) * (1 - math.exp(-dt * 6))
		if t > total or not char.Parent then
			conn:Disconnect()
			cam.CameraType = Enum.CameraType.Custom
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				cam.CameraSubject = hum
			end
			TweenService:Create(cam, TweenInfo.new(0.4), { FieldOfView = 70 }):Play()
		end
	end)
end

Net.Get("Cine").OnClientEvent:Connect(function(name, a, b)
	if name == "Super" then
		cineSuper(a, b)
	end
end)

-- ===================== Перезарядки на кнопках =====================
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for _, s in pairs(slots) do
		local left = s.ends - now
		if left > 0 then
			s.shade.Size = UDim2.fromScale(1, left / s.total)
			s.timer.Text = string.format("%.1f", left)
		else
			s.shade.Size = UDim2.fromScale(1, 0)
			s.timer.Text = ""
		end
	end
	if combo > 0 and now - comboAt > 2 then
		combo = 0
		TweenService:Create(comboLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	end
end)
