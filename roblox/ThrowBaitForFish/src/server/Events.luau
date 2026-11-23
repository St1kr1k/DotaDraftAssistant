-- Случайные события сервера: шторм, золотой час, кормёжка, кровавая луна, метеоритный дождь.
-- Освещение меняет сервер (видят все), дождь/метеоры рисует клиент по атрибуту workspace.Event.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)

local PlayerService = require(script.Parent.PlayerService)

local Events = {}

local rng = Random.new()
local defaults = nil
local running = false

local function lightingTargets(id: string?)
	local d = defaults
	if id == "Storm" then
		return { ClockTime = 15, Brightness = 1.1, OutdoorAmbient = Color3.fromRGB(95, 105, 125), Density = 0.45, AtmColor = Color3.fromRGB(150, 160, 175), Cover = 0.9, CloudColor = Color3.fromRGB(110, 115, 130), Saturation = -0.15 }
	elseif id == "GoldenHour" then
		return { ClockTime = 17.7, Brightness = 2.4, OutdoorAmbient = Color3.fromRGB(190, 150, 110), Density = 0.32, AtmColor = Color3.fromRGB(255, 200, 150), Cover = 0.5, CloudColor = Color3.fromRGB(255, 210, 170), Saturation = 0.3 }
	elseif id == "BloodMoon" then
		return { ClockTime = 0.5, Brightness = 1.5, OutdoorAmbient = Color3.fromRGB(150, 50, 60), Density = 0.35, AtmColor = Color3.fromRGB(150, 40, 50), Cover = 0.4, CloudColor = Color3.fromRGB(120, 40, 50), Saturation = 0.25 }
	elseif id == "MeteorShower" then
		return { ClockTime = 21.5, Brightness = 1.6, OutdoorAmbient = Color3.fromRGB(90, 90, 150), Density = 0.3, AtmColor = Color3.fromRGB(120, 110, 200), Cover = 0.3, CloudColor = Color3.fromRGB(150, 140, 220), Saturation = 0.25 }
	elseif id == "Frenzy" then
		return { ClockTime = 12.5, Brightness = 3, OutdoorAmbient = Color3.fromRGB(150, 165, 180), Density = 0.25, AtmColor = Color3.fromRGB(190, 235, 255), Cover = 0.4, CloudColor = Color3.fromRGB(255, 255, 255), Saturation = 0.3 }
	end
	return d
end

local function applyLighting(id: string?)
	local t = lightingTargets(id)
	local info = TweenInfo.new(4, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = t.ClockTime, Brightness = t.Brightness, OutdoorAmbient = t.OutdoorAmbient }):Play()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		TweenService:Create(atm, info, { Density = t.Density, Color = t.AtmColor }):Play()
	end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		TweenService:Create(clouds, info, { Cover = t.Cover, Color = t.CloudColor }):Play()
	end
	local cc = Lighting:FindFirstChild("MainColor")
	if cc then
		TweenService:Create(cc, info, { Saturation = t.Saturation }):Play()
	end
end

local function announce(text: string, color: Color3)
	for _, p in ipairs(Players:GetPlayers()) do
		PlayerService.Notify(p, text, color)
	end
end

function Events.Start(id: string)
	local ev = GameData.Events[id]
	if not ev or running then
		return false
	end
	running = true
	workspace:SetAttribute("Event", id)
	workspace:SetAttribute("EventEnds", os.time() + ev.Duration)
	applyLighting(id)
	announce(ev.Icon .. " " .. string.upper(ev.Name) .. "! " .. ev.Desc, Color3.fromRGB(255, 230, 120))
	task.delay(ev.Duration, function()
		workspace:SetAttribute("Event", "")
		applyLighting(nil)
		running = false
	end)
	return true
end

local function pickEvent(): string
	local total = 0
	for _, ev in pairs(GameData.Events) do
		total += ev.Weight
	end
	local r = rng:NextNumber() * total
	for id, ev in pairs(GameData.Events) do
		r -= ev.Weight
		if r <= 0 then
			return id
		end
	end
	return "Storm"
end

local function setupCommand()
	-- /event Storm — для теста в Studio (и для создателя игры)
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "EventCommand"
	cmd.PrimaryAlias = "/event"
	cmd.Parent = TextChatService
	cmd.Triggered:Connect(function(source, text)
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player then
			return
		end
		local allowed = RunService:IsStudio() or player.UserId == game.CreatorId
		if not allowed then
			return
		end
		local arg = string.match(text, "^%S+%s+(%S+)")
		if arg and GameData.Events[arg] then
			Events.Start(arg)
		else
			local names = {}
			for k in pairs(GameData.Events) do
				table.insert(names, k)
			end
			PlayerService.Notify(player, "Events: " .. table.concat(names, ", "), Color3.fromRGB(200, 200, 255))
		end
	end)
end

function Events.Init()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	local cc = Lighting:FindFirstChild("MainColor") :: ColorCorrectionEffect?
	defaults = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Density = atm and atm.Density or 0.3,
		AtmColor = atm and atm.Color or Color3.new(1, 1, 1),
		Cover = clouds and clouds.Cover or 0.5,
		CloudColor = clouds and clouds.Color or Color3.new(1, 1, 1),
		Saturation = cc and cc.Saturation or 0,
	}
	workspace:SetAttribute("Event", "")
	workspace:SetAttribute("ServerLuck", 1)
	workspace:SetAttribute("ServerLuckEnds", 0)
	pcall(setupCommand)
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.EventMinGap, Config.EventMaxGap))
			if #Players:GetPlayers() > 0 then
				Events.Start(pickEvent())
			end
		end
	end)
end

return Events
