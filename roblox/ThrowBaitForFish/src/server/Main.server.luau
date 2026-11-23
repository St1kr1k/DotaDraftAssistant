-- Точка входа сервера.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

Remotes.Init()

local World = require(script.Parent.World)
local Data = require(script.Parent.Data)
local PlayerService = require(script.Parent.PlayerService)
local Fishing = require(script.Parent.Fishing)
local Training = require(script.Parent.Training)
local Shop = require(script.Parent.Shop)
local Monetization = require(script.Parent.Monetization)
local Events = require(script.Parent.Events)

World.Build()
workspace:SetAttribute("WorldReady", true)

Fishing.Init()
Training.Init()
Shop.Init()
Monetization.Init()
Events.Init()

local function onJoin(player: Player)
	PlayerService.OnJoin(player, Monetization.ApplyPasses)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, p)
end

Players.PlayerRemoving:Connect(function(player)
	Training.Stop(player)
	PlayerService.OnLeave(player)
end)

PlayerService.StartIncomeLoop()
Data.StartAutosave()
