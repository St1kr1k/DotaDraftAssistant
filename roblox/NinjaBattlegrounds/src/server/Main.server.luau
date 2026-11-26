-- Точка входа сервера.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
Net.Init()

local World = require(script.Parent.World)
local Combat = require(script.Parent.Combat)

World.Build()
Combat.Init()
workspace:SetAttribute("Ready", true)
