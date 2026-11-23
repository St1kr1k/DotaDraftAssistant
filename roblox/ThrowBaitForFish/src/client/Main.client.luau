-- Точка входа клиента.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

while not workspace:GetAttribute("WorldReady") do
	task.wait(0.2)
end

local ClientState = require(script.Parent.ClientState)
local UI = require(script.Parent.UI)
local Effects = require(script.Parent.Effects)
local Fishing = require(script.Parent.Fishing)
local Training = require(script.Parent.Training)

ClientState.Init()
UI.Init()
Effects.Init()
Fishing.Init()
Training.Init()

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- подсказка новичку
task.delay(4, function()
	local data = ClientState.Data
	if data and (data.TotalCaught or 0) == 0 then
		UI.Toast("👋 Walk to the end of your pier and HOLD the CAST button!", Color3.fromRGB(120, 240, 255), 7)
		task.wait(2)
		UI.Toast("💪 Train on the pull-up bars to throw farther!", Color3.fromRGB(255, 220, 90), 7)
	end
end)

local _ = player
