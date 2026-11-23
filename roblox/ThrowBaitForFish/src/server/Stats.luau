-- Производные характеристики игрока: вместимость, доход, удача, множитель тренировки.
-- Покупки (геймпассы) лежат в атрибутах игрока: Pass_Cash2 = true и т.п.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)

local Stats = {}

-- Текущее событие и удача сервера (их выставляет Events)
function Stats.CurrentEvent()
	local id = workspace:GetAttribute("Event")
	local ends = workspace:GetAttribute("EventEnds") or 0
	if id and id ~= "" and os.time() < ends then
		return GameData.Events[id], id
	end
	return nil, nil
end

function Stats.ServerLuck(): number
	local mult = workspace:GetAttribute("ServerLuck") or 1
	local ends = workspace:GetAttribute("ServerLuckEnds") or 0
	if os.time() < ends then
		return mult
	end
	return 1
end

function Stats.HasPass(player: Player, key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true
end

function Stats.Capacity(player: Player, profile): number
	local slots = Config.BaseTankSlots + Config.SlotsPerUpgrade * (profile.TankLevel or 0)
	if Stats.HasPass(player, "BigTank") then
		slots += 10
	end
	return slots
end

function Stats.IncomeMult(player: Player): number
	local m = 1
	if Stats.HasPass(player, "Cash2") then
		m *= 2
	end
	local ev = Stats.CurrentEvent()
	if ev then
		m *= ev.Income
	end
	return m
end

-- Базовый доход аквариума (без событий), за секунду
function Stats.BaseIncome(player: Player, profile): number
	local total = 0
	for _, f in ipairs(profile.Fish) do
		total += GameData.FishIncome(f.Id, f.M, f.S)
	end
	if Stats.HasPass(player, "Cash2") then
		total *= 2
	end
	return total
end

function Stats.Income(player: Player, profile): number
	local total = 0
	for _, f in ipairs(profile.Fish) do
		total += GameData.FishIncome(f.Id, f.M, f.S)
	end
	return total * Stats.IncomeMult(player)
end

function Stats.TrainPassMult(player: Player): number
	local best = 1
	for _, pass in ipairs(Config.TrainingPasses) do
		if Stats.HasPass(player, pass.Key) then
			best = math.max(best, pass.Mult)
		end
	end
	return best
end

function Stats.GearMult(profile): number
	local gear = GameData.Gear[profile.Gear or 1]
	return gear and gear.Mult or 1
end

function Stats.TrainMult(player: Player, profile): number
	local m = Stats.TrainPassMult(player) * Stats.GearMult(profile)
	if (profile.TrainBoostEnds or 0) > os.time() then
		m *= Config.TrainBoostMult
	end
	return m
end

function Stats.BaitLuck(profile): number
	local bait = GameData.BaitById[profile.Bait]
	return bait and bait.Luck or 1
end

-- Удача без учёта дальности и «счастливого заброса»
function Stats.Luck(player: Player, profile): number
	local luck = Stats.BaitLuck(profile) * Stats.ServerLuck()
	if Stats.HasPass(player, "Luck2") then
		luck *= 2
	end
	local ev = Stats.CurrentEvent()
	if ev then
		luck *= ev.Luck
	end
	return luck
end

function Stats.MaxDistance(profile): number
	return Config.MaxDistance(profile.Power)
end

return Stats
