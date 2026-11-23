-- Турник на клиенте: панель, клики для ускорения, «+N 💪», выход прыжком.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)

local player = Players.LocalPlayer
local Training = {}

local lastClick = 0

function Training.Init()
	local function onChanged()
		UI.SetTraining(player:GetAttribute("Training") == true)
	end
	player:GetAttributeChangedSignal("Training"):Connect(onChanged)
	onChanged()

	Remotes.Get("Rep").OnClientEvent:Connect(function(gain)
		UI.RepPop(gain)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not player:GetAttribute("Training") then
			return
		end
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.E
		if isClick and not processed then
			local now = os.clock()
			if now - lastClick > 0.12 then
				lastClick = now
				Remotes.Get("Rep"):FireServer()
			end
		end
	end)

	UserInputService.JumpRequest:Connect(function()
		if player:GetAttribute("Training") then
			Remotes.Get("StopTraining"):InvokeServer()
		end
	end)
end

return Training
