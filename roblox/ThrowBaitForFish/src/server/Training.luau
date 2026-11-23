-- Турник: игрок висит, повторы идут сами (АФК) и быстрее — по кликам. Каждый повтор = +Power × множитель.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Data = require(script.Parent.Data)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)
local PlayerService = require(script.Parent.PlayerService)

local Training = {}

local occupied = {} :: { [BasePart]: Player }

-- Суставы R15 для позы на турнике: имя части -> имя сустава
local JOINTS = {
	{ Part = "RightUpperLeg", Joint = "RightHip", Kind = "Hip", Side = 1 },
	{ Part = "LeftUpperLeg", Joint = "LeftHip", Kind = "Hip", Side = -1 },
	{ Part = "RightLowerLeg", Joint = "RightKnee", Kind = "Knee", Side = 1 },
	{ Part = "LeftLowerLeg", Joint = "LeftKnee", Kind = "Knee", Side = -1 },
}

-- Руки держатся за перекладину через IK: кисти прибиты к точкам на перекладине,
-- локти сгибаются сами, когда тело поднимается. Работает на любом R15-аватаре.
local function setupIK(character: Model, bar: BasePart)
	local created = {}
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return created
	end
	for _, side in ipairs({ "Right", "Left" }) do
		local upper = character:FindFirstChild(side .. "UpperArm")
		local hand = character:FindFirstChild(side .. "Hand")
		if upper and hand then
			local x = side == "Right" and 1.35 or -1.35
			local target = Instance.new("Attachment")
			target.Name = "IKTarget_" .. side
			-- ось цилиндра-перекладины = локальная X; игрок смотрит в -Z
			target.Position = Vector3.new(x, -0.25, 0)
			target.Parent = bar
			local pole = Instance.new("Attachment")
			pole.Name = "IKPole_" .. side
			-- локти уходят в стороны и назад
			pole.Position = Vector3.new(x * 2.6, -3.5, 2.5)
			pole.Parent = bar
			local ik = Instance.new("IKControl")
			ik.Name = "PullUpIK_" .. side
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upper
			ik.EndEffector = hand
			ik.Target = target
			ik.Pole = pole
			ik.Weight = 1
			ik.SmoothTime = 0.05
			ik.Parent = hum
			table.insert(created, ik)
			table.insert(created, target)
			table.insert(created, pole)
		end
	end
	return created
end

-- Поза: top = false — вис на прямых руках, true — подбородок над перекладиной
local function poseOffset(kind: string, side: number, top: boolean): CFrame
	local _ = side
	if kind == "Hip" then
		return top and CFrame.Angles(math.rad(40), 0, 0) or CFrame.Angles(math.rad(12), 0, 0)
	elseif kind == "Knee" then
		return top and CFrame.Angles(math.rad(-85), 0, 0) or CFrame.Angles(math.rad(-40), 0, 0)
	end
	return CFrame.identity
end

local function collectJoints(character: Model)
	local saved = {}
	for _, j in ipairs(JOINTS) do
		local part = character:FindFirstChild(j.Part)
		local joint = part and part:FindFirstChild(j.Joint)
		if joint and joint:IsA("Motor6D") then
			saved[joint] = { C0 = joint.C0, Kind = j.Kind, Side = j.Side }
		end
	end
	return saved
end

local function applyPose(saved, top: boolean, duration: number, style: Enum.EasingStyle?)
	for joint, info in pairs(saved) do
		if joint.Parent then
			local goal = info.C0 * poseOffset(info.Kind, info.Side, top)
			if duration <= 0 then
				joint.C0 = goal
			else
				TweenService:Create(joint, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = goal }):Play()
			end
		end
	end
end

local function stop(player: Player)
	local _, session = Data.Get(player)
	local state = session and session.Training
	if not state then
		return
	end
	session.Training = nil
	occupied[state.Bar] = nil
	player:SetAttribute("Training", false)
	local character = player.Character
	if character then
		for joint, info in pairs(state.SavedC0) do
			if joint.Parent then
				-- новый твин отменяет недоигранный твин позы
				TweenService:Create(joint, TweenInfo.new(0.08), { C0 = info.C0 }):Play()
			end
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
			root.CFrame = state.Bar.CFrame * CFrame.new(0, -6.5, 3.5)
		end
		PlayerService.SetRodVisible(character, true)
	end
	for _, inst in ipairs(state.IK or {}) do
		inst:Destroy()
	end
end

local function doRep(player: Player, fromClick: boolean)
	local profile, session = Data.Get(player)
	local state = session and session.Training
	if not profile or not state then
		return
	end
	local gain = Config.PowerPerRep * Stats.TrainMult(player, profile)
	profile.Power += gain
	PlayerService.UpdateAttributes(player)
	Remotes.Get("Rep"):FireClient(player, gain)
	-- анимация подтягивания (видят все)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and not state.Animating then
		state.Animating = true
		-- рывок вверх: руки сгибаются, ноги поджимаются, тело поднимается
		local upTime = fromClick and 0.17 or 0.32
		local downTime = fromClick and 0.22 or 0.45
		applyPose(state.SavedC0, true, upTime)
		local up = TweenService:Create(root, TweenInfo.new(upTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = state.HangCf * CFrame.new(0, 1.9, 0) })
		up:Play()
		up.Completed:Connect(function()
			if not session.Training then
				return
			end
			applyPose(state.SavedC0, false, downTime, Enum.EasingStyle.Sine)
			local down = TweenService:Create(root, TweenInfo.new(downTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = state.HangCf })
			down:Play()
			down.Completed:Connect(function()
				state.Animating = false
			end)
		end)
	end
	local _ = fromClick
end

local function start(player: Player, bar: BasePart)
	local profile, session = Data.Get(player)
	if not profile or not session or session.Training then
		return
	end
	if occupied[bar] and occupied[bar].Parent then
		PlayerService.Notify(player, "This bar is taken!", Color3.fromRGB(255, 120, 90))
		return
	end
	if session.Pending and os.clock() < session.Pending.Expires then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local hangCf = bar.CFrame * CFrame.new(0, -3.6, 0) -- ориентация турника: смотрим наружу
	hangCf = CFrame.lookAt(hangCf.Position, hangCf.Position + bar.CFrame.LookVector)
	local plot = World.PlotOf(player)
	if not plot or plot.Bars[1] ~= bar then
		PlayerService.Notify(player, "💪 Train on the bar at YOUR base!", Color3.fromRGB(255, 200, 90))
		return
	end
	local saved = collectJoints(character)
	applyPose(saved, false, 0.2)
	local ik = setupIK(character, bar)
	root.Anchored = true
	root.CFrame = hangCf
	PlayerService.SetRodVisible(character, false)
	occupied[bar] = player
	session.Training = { Bar = bar, HangCf = hangCf, SavedC0 = saved, IK = ik, NextAfk = os.clock() + Config.AfkRepInterval }
	player:SetAttribute("Training", true)
end

function Training.Init()
	local bars = {}
	for _, plot in ipairs(World.Plots) do
		for _, b in ipairs(plot.Bars) do
			table.insert(bars, b)
		end
	end
	for _, b in ipairs(World.GymBars or {}) do
		table.insert(bars, b)
	end
	for _, bar in ipairs(bars) do
		local prompt = bar:FindFirstChild("TrainPrompt", true)
		if prompt then
			prompt.Triggered:Connect(function(player)
				start(player, bar)
			end)
		end
	end

	Remotes.Get("StopTraining").OnServerInvoke = function(player)
		stop(player)
		return true
	end

	Remotes.Get("Rep").OnServerEvent:Connect(function(player)
		local _, session = Data.Get(player)
		if not session or not session.Training then
			return
		end
		local now = os.clock()
		if now - session.LastClickRep >= Config.ClickRepInterval then
			session.LastClickRep = now
			session.Training.NextAfk = now + Config.AfkRepInterval
			doRep(player, true)
		end
	end)

	-- АФК-повторы
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local _, session = Data.Get(player)
				local state = session and session.Training
				if state then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if not humanoid or humanoid.Health <= 0 then
						stop(player)
					elseif now >= state.NextAfk then
						state.NextAfk = now + Config.AfkRepInterval
						doRep(player, false)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for bar, p in pairs(occupied) do
			if p == player then
				occupied[bar] = nil
			end
		end
	end)
end

Training.Stop = stop

return Training
