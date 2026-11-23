-- Последний снимок данных игрока с сервера + сигнал об изменении.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local ClientState = {}
ClientState.Data = nil :: any

local changed = Instance.new("BindableEvent")
ClientState.Changed = changed.Event

function ClientState.Init()
	Remotes.Get("State").OnClientEvent:Connect(function(snap)
		ClientState.Data = snap
		changed:Fire(snap)
	end)
	task.spawn(function()
		for _ = 1, 20 do
			local ok, snap = pcall(function()
				return Remotes.Get("GetState"):InvokeServer()
			end)
			if ok and snap then
				if not ClientState.Data then
					ClientState.Data = snap
					changed:Fire(snap)
				end
				return
			end
			task.wait(1)
		end
	end)
end

function ClientState.Cash(): number
	return Players.LocalPlayer:GetAttribute("Cash") or (ClientState.Data and ClientState.Data.Cash) or 0
end

function ClientState.Power(): number
	return Players.LocalPlayer:GetAttribute("Power") or (ClientState.Data and ClientState.Data.Power) or 0
end

function ClientState.HasPass(key: string): boolean
	return Players.LocalPlayer:GetAttribute("Pass_" .. key) == true
end

-- Мой участок (модель) или nil
function ClientState.MyPlot(): Model?
	local idx = Players.LocalPlayer:GetAttribute("PlotIndex")
	local plots = workspace:FindFirstChild("Plots")
	if idx and plots then
		return plots:FindFirstChild("Plot" .. idx) :: Model?
	end
	return nil
end

-- Общий пирс
function ClientState.Pier(): Model?
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Pier") :: Model?
end

function ClientState.CastZone(): BasePart?
	local pier = ClientState.Pier()
	return pier and pier:FindFirstChild("CastZone") :: BasePart?
end

function ClientState.InCastZone(pos: Vector3): boolean
	local zone = ClientState.CastZone()
	if not zone then
		return false
	end
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + 1 and math.abs(rel.Z) <= half.Z
end

-- Ближайшее светящееся место для заброса
function ClientState.NearestSpot(pos: Vector3): BasePart?
	local pier = ClientState.Pier()
	if not pier then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, c in ipairs(pier:GetChildren()) do
		if c.Name == "CastSpot" and c:IsA("BasePart") then
			local d = (c.Position - pos).Magnitude
			if d < bestD then
				best, bestD = c, d
			end
		end
	end
	return best
end

return ClientState
