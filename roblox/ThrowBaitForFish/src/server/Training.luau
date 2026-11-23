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

local function shoulders(character: Model)
	local list = {}
	for _, name in ipairs({ "RightUpperArm", "LeftUpperArm" }) do
		local arm = character:FindFirstChild(name)
		local joint = arm and arm:FindFirstChild(name == "RightUpperArm" and "RightShoulder" or "LeftShoulder")
		if joint and joint:IsA("Motor6D") then
			table.insert(list, joint)
		end
	end
	return list
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
		for joint, c0 in pairs(state.SavedC0) do
			if joint.Parent then
				joint.C0 = c0
			end
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
			root.CFrame = state.Bar.CFrame * CFrame.new(0, -6.5, 3.5)
		end
		PlayerService.SetRodVisible(character, true)
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
		local up = TweenService:Create(root, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = state.HangCf * CFrame.new(0, 1.6, 0) })
		up:Play()
		up.Completed:Connect(function()
			local down = TweenService:Create(root, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = state.HangCf })
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
	local hangCf = bar.CFrame * CFrame.new(0, -3.1, 0) -- ориентация турника: смотрим наружу
	hangCf = CFrame.lookAt(hangCf.Position, hangCf.Position + bar.CFrame.LookVector)
	local saved = {}
	for _, joint in ipairs(shoulders(character)) do
		saved[joint] = joint.C0
		joint.C0 = joint.C0 * CFrame.Angles(math.rad(175), 0, 0)
	end
	root.Anchored = true
	root.CFrame = hangCf
	PlayerService.SetRodVisible(character, false)
	occupied[bar] = player
	session.Training = { Bar = bar, HangCf = hangCf, SavedC0 = saved, NextAfk = os.clock() + Config.AfkRepInterval }
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
		local prompt = bar:FindFirstChildOfClass("ProximityPrompt")
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
