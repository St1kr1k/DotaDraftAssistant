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

function ClientState.CastSpot(): BasePart?
	local plot = ClientState.MyPlot()
	local pier = plot and plot:FindFirstChild("Pier")
	return pier and pier:FindFirstChild("CastSpot") :: BasePart?
end

return ClientState
