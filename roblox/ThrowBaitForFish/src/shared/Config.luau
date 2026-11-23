-- Все настройки игры в одном месте: баланс, донат, тайминги.
-- Id = 0 значит «ещё не создано в Creator Dashboard»: в Studio такие покупки выдаются бесплатно для теста.

local Config = {}

-- ===== Мир =====
Config.PlotCount = 8
Config.WaterY = 0

-- ===== Заброс =====
-- Зоны: дальность (studs от края причала) и сила, с которой до неё добиваешь.
-- Между точками дальность растёт плавно (по логарифму силы).
Config.ZoneDist = { 0, 55, 120, 200, 300, 420, 560 }
Config.ZonePower = { 0, 40, 600, 6000, 50000, 400000, 2500000 }
-- Опорные точки кривой «сила -> дальность»
local CURVE = {
	{ 0, 25 },
	{ 40, 55 },
	{ 600, 120 },
	{ 6000, 200 },
	{ 50000, 300 },
	{ 400000, 420 },
	{ 2500000, 560 },
	{ 6000000, 660 },
}
Config.MaxCastDistance = 660
Config.ChargeTime = 1.1 -- секунд на полный заряд
Config.CastCooldown = 0.4
Config.CastSpotRadius = 16 -- насколько близко к краю своего причала нужно стоять

local function lg(p: number): number
	return math.log(1 + math.max(0, p))
end

function Config.MaxDistance(power: number): number
	for i = 1, #CURVE - 1 do
		local a, b = CURVE[i], CURVE[i + 1]
		if power < b[1] then
			local f = (lg(power) - lg(a[1])) / (lg(b[1]) - lg(a[1]))
			return a[2] + (b[2] - a[2]) * math.clamp(f, 0, 1)
		end
	end
	return Config.MaxCastDistance
end

-- Сколько силы нужно для дальности d (для подсказок в интерфейсе)
function Config.PowerForDistance(d: number): number
	for i = 1, #CURVE - 1 do
		local a, b = CURVE[i], CURVE[i + 1]
		if d <= b[2] then
			if d <= a[2] then
				return a[1]
			end
			local f = (d - a[2]) / (b[2] - a[2])
			return math.ceil(math.exp(lg(a[1]) + (lg(b[1]) - lg(a[1])) * f) - 1 - 1e-6)
		end
	end
	return CURVE[#CURVE][1]
end

-- ===== Тренировка (турник) =====
Config.AfkRepInterval = 1.5 -- без кликов: 1 повтор раз в 1.5 с
Config.ClickRepInterval = 0.18 -- кликами: не чаще ~5.5 повторов в секунду
Config.PowerPerRep = 1

-- ===== Аквариум =====
Config.BaseTankSlots = 8
Config.SlotsPerUpgrade = 2
Config.MaxTankUpgrades = 16
function Config.TankUpgradeCost(level: number): number
	return math.floor(150 * 2.25 ^ level)
end
Config.SellSeconds = 25 -- рыба продаётся за 25 секунд своего дохода

-- Доход, пока игрок не в игре
Config.OfflineMaxSeconds = 8 * 3600
Config.OfflineRate = 0.5

-- ===== Удача =====
-- Вес редкости t (1..7) умножается на Luck^((t-1)·LuckExponent)
Config.LuckExponent = 0.3
Config.DistanceLuckPer100 = 0.08 -- +8% удачи за каждые 100 studs дальности
Config.LuckyCastLuck = 10

-- ===== Монетизация =====
-- Лесенка тренировки: дёшево зайти, дальше дороже. Действует самый большой купленный множитель.
Config.TrainingPasses = {
	{ Key = "Train2", Id = 0, Price = 5, Mult = 2 },
	{ Key = "Train4", Id = 0, Price = 19, Mult = 4 },
	{ Key = "Train8", Id = 0, Price = 49, Mult = 8 },
	{ Key = "Train16", Id = 0, Price = 99, Mult = 16 },
	{ Key = "Train32", Id = 0, Price = 199, Mult = 32 },
}

Config.Passes = {
	Cash2 = { Id = 0, Price = 99, Name = "x2 Cash", Desc = "All fish earn double money forever" },
	Luck2 = { Id = 0, Price = 129, Name = "x2 Luck", Desc = "Double luck on every cast" },
	AutoCast = { Id = 0, Price = 149, Name = "Auto Cast", Desc = "Fish automatically while AFK on the pier" },
	BigTank = { Id = 0, Price = 79, Name = "+10 Tank Slots", Desc = "Your aquarium holds 10 more fish" },
}

Config.Products = {
	LuckyCast1 = { Id = 0, Price = 9, Name = "Lucky Cast", Desc = "x10 luck on your next cast", Order = 1 },
	LuckyCast10 = { Id = 0, Price = 69, Name = "10 Lucky Casts", Desc = "x10 luck on 10 casts", Order = 2 },
	TrainBoost = { Id = 0, Price = 15, Name = "Training Potion", Desc = "x3 training for 10 minutes", Order = 3 },
	ServerLuck2 = { Id = 0, Price = 19, Name = "Server Luck x2", Desc = "x2 luck for EVERYONE, 15 min", Order = 4 },
	ServerLuck4 = { Id = 0, Price = 49, Name = "Server Luck x4", Desc = "x4 luck for EVERYONE, 15 min", Order = 5 },
	ServerLuck8 = { Id = 0, Price = 99, Name = "Server Luck x8", Desc = "x8 luck for EVERYONE, 15 min", Order = 6 },
}

Config.ServerLuckSeconds = 15 * 60
Config.TrainBoostSeconds = 10 * 60
Config.TrainBoostMult = 3

-- ===== События =====
Config.EventMinGap = 6 * 60
Config.EventMaxGap = 10 * 60

-- ===== Сохранение =====
Config.DataStoreName = "ThrowBaitForFish_v1"
Config.AutosaveSeconds = 90

return Config
