-- Общие настройки игры: апгрейды, цены, формулы. Используется и сервером, и клиентом.
local Config = {}

Config.Upgrades = {
	{ id = "pickaxe", name = "Кирка", desc = "+1 за клик", baseCost = 10, growth = 1.15, kind = "click", amount = 1, color = Color3.fromRGB(160, 160, 170) },
	{ id = "gnome", name = "Гном-шахтёр", desc = "+1 в секунду", baseCost = 25, growth = 1.15, kind = "auto", amount = 1, color = Color3.fromRGB(220, 120, 80) },
	{ id = "drill", name = "Бур", desc = "+8 в секунду", baseCost = 300, growth = 1.15, kind = "auto", amount = 8, color = Color3.fromRGB(240, 200, 60) },
	{ id = "luck", name = "Удача", desc = "+2% шанс крита ×10", baseCost = 750, growth = 1.6, kind = "crit", amount = 0.02, maxLevel = 25, color = Color3.fromRGB(90, 220, 110) },
	{ id = "gloves", name = "Перчатки силы", desc = "+15 за клик", baseCost = 2000, growth = 1.17, kind = "click", amount = 15, color = Color3.fromRGB(230, 80, 90) },
	{ id = "mine", name = "Шахта", desc = "+60 в секунду", baseCost = 5000, growth = 1.15, kind = "auto", amount = 60, color = Color3.fromRGB(150, 100, 60) },
	{ id = "laser", name = "Лазерный резак", desc = "+250 за клик", baseCost = 40000, growth = 1.18, kind = "click", amount = 250, color = Color3.fromRGB(255, 60, 200) },
	{ id = "portal", name = "Портал в недра", desc = "+600 в секунду", baseCost = 80000, growth = 1.15, kind = "auto", amount = 600, color = Color3.fromRGB(150, 90, 255) },
	{ id = "dragon", name = "Кристальный дракон", desc = "+5000 в секунду", baseCost = 1200000, growth = 1.15, kind = "auto", amount = 5000, color = Color3.fromRGB(60, 200, 255) },
}

Config.CritMultiplier = 10
Config.RebirthBaseCost = 1e6 -- сколько кристаллов нужно для первого перерождения
Config.RebirthCostGrowth = 5 -- каждое следующее дороже в 5 раз
Config.RebirthBonus = 0.5 -- +50% ко всей добыче за каждое перерождение
Config.OfflineRate = 0.5 -- оффлайн копится половина дохода
Config.OfflineMaxSeconds = 2 * 60 * 60 -- максимум 2 часа

Config.ById = {}
for _, up in ipairs(Config.Upgrades) do
	Config.ById[up.id] = up
end

function Config.getCost(up, level: number): number
	return math.floor(up.baseCost * up.growth ^ level)
end

function Config.getMultiplier(rebirths: number): number
	return 1 + rebirths * Config.RebirthBonus
end

function Config.getRebirthCost(rebirths: number): number
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths
end

-- levels: { [id] = уровень }. Возвращает за клик, в секунду, шанс крита.
function Config.compute(levels, rebirths: number)
	local click, auto, crit = 1, 0, 0
	for _, up in ipairs(Config.Upgrades) do
		local lvl = levels[up.id] or 0
		if up.kind == "click" then
			click += up.amount * lvl
		elseif up.kind == "auto" then
			auto += up.amount * lvl
		elseif up.kind == "crit" then
			crit += up.amount * lvl
		end
	end
	local mult = Config.getMultiplier(rebirths)
	return click * mult, auto * mult, math.min(crit, 0.5)
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Config.format(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	if v >= 100 then
		return string.format("%d%s", math.floor(v), SUFFIXES[i])
	elseif v >= 10 then
		return string.format("%.1f%s", math.floor(v * 10) / 10, SUFFIXES[i])
	end
	return string.format("%.2f%s", math.floor(v * 100) / 100, SUFFIXES[i])
end

return Config
