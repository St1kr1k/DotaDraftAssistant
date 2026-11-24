-- «Кристальная империя»: весь баланс и формулы. Общий для сервера и клиента.
local Config = {}

export type Data = {
	crystals: number,
	runTotal: number, -- добыто с последнего перерождения
	allTotal: number, -- добыто за всё время
	dust: number, -- звёздная пыль (валюта перерождения)
	dustEver: number, -- пыли получено всего (даёт бонус к добыче)
	rebirths: number,
	gens: { [string]: number },
	ups: { [string]: boolean },
	pups: { [string]: number },
	ach: { [string]: boolean },
	clicks: number,
	goldens: number,
	playTime: number,
	autobuy: boolean,
	lastOnline: number?,
}

function Config.newData(): Data
	return {
		crystals = 0,
		runTotal = 0,
		allTotal = 0,
		dust = 0,
		dustEver = 0,
		rebirths = 0,
		gens = {},
		ups = {},
		pups = {},
		ach = {},
		clicks = 0,
		goldens = 0,
		playTime = 0,
		autobuy = true,
		lastOnline = nil,
	}
end

--------------------------------------------------------------------------------
-- Генераторы
--------------------------------------------------------------------------------
export type Generator = {
	id: string,
	index: number,
	name: string,
	icon: string,
	baseCost: number,
	baseProd: number,
	growth: number,
	color: Color3,
}

local GEN_LIST = {
	{ "gnome", "Гном-шахтёр", "⛏", 15, 0.5, 1.07, Color3.fromRGB(230, 130, 80) },
	{ "cart", "Вагонетка", "🛒", 150, 2.5, 1.08, Color3.fromRGB(170, 120, 70) },
	{ "drill", "Бур", "🔩", 2000, 20, 1.09, Color3.fromRGB(240, 200, 60) },
	{ "mine", "Шахта", "🏔", 30000, 176.471, 1.10, Color3.fromRGB(150, 150, 165) },
	{ "smelter", "Плавильня", "🔥", 500000, 1785.71, 1.11, Color3.fromRGB(255, 100, 40) },
	{ "laser", "Лазерная установка", "🔴", 8e6, 17777.8, 1.12, Color3.fromRGB(255, 60, 120) },
	{ "portal", "Портал в недра", "🌀", 1.5e8, 214286, 1.13, Color3.fromRGB(150, 90, 255) },
	{ "dragon", "Кристальный дракон", "🐉", 3e9, 2.72727e6, 1.14, Color3.fromRGB(60, 220, 160) },
	{ "forge", "Звёздная кузница", "⭐", 8e10, 4.70588e7, 1.15, Color3.fromRGB(255, 230, 120) },
	{ "hole", "Чёрная дыра", "🕳", 3e12, 1.15385e9, 1.15, Color3.fromRGB(120, 60, 200) },
}

Config.Generators = {} :: { Generator }
Config.GenById = {} :: { [string]: Generator }
for i, g in ipairs(GEN_LIST) do
	local gen: Generator = {
		id = g[1],
		index = i,
		name = g[2],
		icon = g[3],
		baseCost = g[4],
		baseProd = g[5],
		growth = g[6],
		color = g[7],
	}
	table.insert(Config.Generators, gen)
	Config.GenById[gen.id] = gen
end

-- На этих уровнях генератор удваивает добычу
Config.Milestones = { 10, 25, 50, 100, 150, 200, 250, 300, 400, 500, 600, 700, 800, 900, 1000 }

function Config.milestonesReached(level: number): number
	local n = 0
	for _, m in ipairs(Config.Milestones) do
		if level >= m then
			n += 1
		else
			break
		end
	end
	return n
end

function Config.nextMilestone(level: number): (number?, number)
	local prev = 0
	for _, m in ipairs(Config.Milestones) do
		if level < m then
			return m, prev
		end
		prev = m
	end
	return nil, prev
end

--------------------------------------------------------------------------------
-- Улучшения (разовые, за кристаллы)
--------------------------------------------------------------------------------
export type Upgrade = {
	id: string,
	name: string,
	desc: string,
	cost: number,
	kind: string, -- "gen" | "global" | "click" | "golden" | "brigade"
	target: string?,
	value: number,
	needGen: string?,
	needLevel: number?,
	color: Color3,
}

Config.Upgrades = {} :: { Upgrade }
Config.UpById = {} :: { [string]: Upgrade }

local function addUp(u: Upgrade)
	table.insert(Config.Upgrades, u)
	Config.UpById[u.id] = u
end

local GEN_UP_STEPS = {
	{ 10, 2, "Закалка" },
	{ 25, 2, "Ускорение" },
	{ 50, 2, "Мастерство" },
	{ 100, 3, "Легенда" },
	{ 200, 3, "Миф" },
}

for _, gen in ipairs(Config.Generators) do
	for step, s in ipairs(GEN_UP_STEPS) do
		local need, mult, title = s[1], s[2], s[3]
		addUp({
			id = gen.id .. "_" .. step,
			name = gen.name .. ": " .. title,
			desc = string.format("%s добывает ×%d", gen.name, mult),
			cost = gen.baseCost * gen.growth ^ need * 12,
			kind = "gen",
			target = gen.id,
			value = mult,
			needGen = gen.id,
			needLevel = need,
			color = gen.color,
		})
	end
end

local GOLD = Color3.fromRGB(255, 205, 60)
local CYAN = Color3.fromRGB(70, 210, 255)
local PINK = Color3.fromRGB(255, 100, 200)

for _, u in
	ipairs({
		{ "click1", "Тяжёлая кирка", "Клик даёт +2% дохода в секунду", 500, "click", 0.02 },
		{ "click2", "Алмазная кирка", "Клик даёт ещё +3% дохода в секунду", 2e5, "click", 0.03 },
		{ "click3", "Кирка бури", "Клик даёт ещё +5% дохода в секунду", 5e8, "click", 0.05 },
		{ "click4", "Кирка вечности", "Клик даёт ещё +10% дохода в секунду", 5e12, "click", 0.10 },
		{ "glob1", "Кристальная смазка", "Вся добыча ×1.5", 1e4, "global", 1.5 },
		{ "glob2", "Резонанс", "Вся добыча ×1.5", 1e7, "global", 1.5 },
		{ "glob3", "Квантовая огранка", "Вся добыча ×1.5", 1e10, "global", 1.5 },
		{ "glob4", "Песнь кристаллов", "Вся добыча ×2", 1e13, "global", 2 },
		{ "glob5", "Сердце горы", "Вся добыча ×3", 1e16, "global", 3 },
		{ "gold1", "Зоркий глаз", "Сверкающие кристаллы появляются на 20% чаще", 5e4, "golden", 0.8 },
		{ "gold2", "Золотые руки", "Сверкающие кристаллы появляются ещё на 20% чаще", 5e7, "golden", 0.8 },
		{ "brig1", "Бригада", "+0.5% к добыче за каждые 10 уровней всех генераторов", 1e6, "brigade", 0.005 },
		{ "brig2", "Профсоюз", "Ещё +0.5% за каждые 10 уровней всех генераторов", 1e11, "brigade", 0.005 },
	})
do
	local kind = u[5]
	addUp({
		id = u[1],
		name = u[2],
		desc = u[3],
		cost = u[4],
		kind = kind,
		value = u[6],
		color = kind == "click" and PINK or kind == "golden" and GOLD or CYAN,
	})
end

function Config.isUpgradeUnlocked(data: Data, up: Upgrade): boolean
	if data.ups[up.id] then
		return false
	end
	if up.needGen then
		return (data.gens[up.needGen] or 0) >= (up.needLevel or 0)
	end
	if up.kind == "click" then
		return data.clicks >= 10 and data.runTotal >= up.cost * 0.2
	end
	return data.runTotal >= up.cost * 0.2
end

--------------------------------------------------------------------------------
-- Перерождение и звёздные улучшения (за пыль)
--------------------------------------------------------------------------------
Config.DustPerBonus = 0.04 -- +4% к добыче за каждую полученную пыль
Config.DustDivider = 1e9

export type PrestigeUp = {
	id: string,
	name: string,
	desc: string,
	baseCost: number,
	growth: number,
	maxLevel: number,
}

Config.PrestigeUps = {
	{ id = "prod", name = "Благословение", desc = "Вся добыча ×2 за уровень", baseCost = 3, growth = 3, maxLevel = 15 },
	{ id = "start", name = "Стартовый капитал", desc = "После перерождения сразу 💎 ×10 за уровень (1K, 10K…)", baseCost = 1, growth = 3, maxLevel = 8 },
	{ id = "auto", name = "Прораб", desc = "Сам докупает генераторы, когда хватает (можно выключить)", baseCost = 5, growth = 1, maxLevel = 1 },
	{ id = "click", name = "Звёздная кирка", desc = "Клик ×3 за уровень", baseCost = 2, growth = 2.5, maxLevel = 6 },
	{ id = "golden", name = "Золотая жила", desc = "Сверкающие кристаллы на 15% чаще за уровень", baseCost = 3, growth = 3, maxLevel = 4 },
	{ id = "frenzy", name = "Долгая лихорадка", desc = "Бонусы сверкающих кристаллов длятся +10 с за уровень", baseCost = 4, growth = 2.5, maxLevel = 4 },
	{ id = "offline", name = "Сон шахтёра", desc = "Оффлайн-доход +25% и +3 ч за уровень", baseCost = 4, growth = 4, maxLevel = 2 },
	{ id = "discount", name = "Скидка гильдии", desc = "Генераторы дешевле на 5% за уровень", baseCost = 10, growth = 3, maxLevel = 6 },
	{ id = "dust", name = "Звёздный магнит", desc = "Пыли за перерождение +25% за уровень", baseCost = 15, growth = 3, maxLevel = 6 },
} :: { PrestigeUp }

Config.PUpById = {} :: { [string]: PrestigeUp }
for _, p in ipairs(Config.PrestigeUps) do
	Config.PUpById[p.id] = p
end

function Config.pupLevel(data: Data, id: string): number
	return data.pups[id] or 0
end

function Config.pupCost(p: PrestigeUp, level: number): number
	return math.floor(p.baseCost * p.growth ^ level)
end

function Config.dustOnRebirth(data: Data): number
	local mult = 1 + 0.25 * Config.pupLevel(data, "dust")
	return math.floor((data.runTotal / Config.DustDivider) ^ (1 / 3) * mult)
end

-- Сколько нужно добыть за забег, чтобы получить хотя бы n пыли
function Config.runTotalForDust(data: Data, n: number): number
	local mult = 1 + 0.25 * Config.pupLevel(data, "dust")
	return (n / mult) ^ 3 * Config.DustDivider
end

function Config.startCrystals(data: Data): number
	local lvl = Config.pupLevel(data, "start")
	if lvl <= 0 then
		return 0
	end
	return 10 ^ (lvl + 2)
end

--------------------------------------------------------------------------------
-- Достижения
--------------------------------------------------------------------------------
export type Achievement = {
	id: string,
	name: string,
	desc: string,
	check: (Data) -> boolean,
}

Config.AchievementBonus = 0.02 -- +2% к добыче за каждое
Config.Achievements = {} :: { Achievement }

local function addAch(id: string, name: string, desc: string, check: (Data) -> boolean)
	table.insert(Config.Achievements, { id = id, name = name, desc = desc, check = check })
end

for _, t in
	ipairs({
		{ 1e3, "Первая тысяча", "1K" },
		{ 1e6, "Миллионер", "1M" },
		{ 1e9, "Миллиардер", "1B" },
		{ 1e12, "Триллионер", "1T" },
		{ 1e15, "Кристальный магнат", "1Qa" },
		{ 1e18, "Повелитель недр", "1Qi" },
		{ 1e21, "Владыка самоцветов", "1Sx" },
		{ 1e24, "Бог кристаллов", "1Sp" },
	})
do
	local amount = t[1]
	addAch("total_" .. amount, t[2], "Добыть всего 💎 " .. t[3], function(d)
		return d.allTotal >= amount
	end)
end

for _, gen in ipairs(Config.Generators) do
	for _, lvl in ipairs({ 1, 50, 100, 200 }) do
		local id = gen.id
		local name = lvl == 1 and ("Первый: " .. gen.name) or string.format("%s ×%d", gen.name, lvl)
		addAch("gen_" .. id .. "_" .. lvl, name, string.format("%s: уровень %d", gen.name, lvl), function(d)
			return (d.gens[id] or 0) >= lvl
		end)
	end
end

for _, t in ipairs({ { 100, "Разминка" }, { 1000, "Мозоли" }, { 10000, "Железный палец" } }) do
	local n = t[1]
	addAch("clicks_" .. n, t[2], string.format("Кликнуть по кристаллу %d раз", n), function(d)
		return d.clicks >= n
	end)
end

for _, t in ipairs({ { 1, "Что это блестит?" }, { 10, "Ловец бликов" }, { 50, "Золотая лихорадка" } }) do
	local n = t[1]
	addAch("gold_" .. n, t[2], string.format("Поймать %d сверкающих кристаллов", n), function(d)
		return d.goldens >= n
	end)
end

for _, t in ipairs({ { 1, "Новое начало" }, { 5, "Круговорот" }, { 20, "Вечный шахтёр" } }) do
	local n = t[1]
	addAch("reb_" .. n, t[2], string.format("Переродиться %d раз", n), function(d)
		return d.rebirths >= n
	end)
end

for _, t in ipairs({ { 10, "Модернизация" }, { 30, "Технократ" }, { 60, "Всё куплено" } }) do
	local n = t[1]
	addAch("ups_" .. n, t[2], string.format("Купить %d улучшений", n), function(d)
		local c = 0
		for _ in pairs(d.ups) do
			c += 1
		end
		return c >= n
	end)
end

Config.AchById = {} :: { [string]: Achievement }
for _, a in ipairs(Config.Achievements) do
	Config.AchById[a.id] = a
end

--------------------------------------------------------------------------------
-- Формулы добычи
--------------------------------------------------------------------------------
local function countKeys(t: { [string]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end
Config.countKeys = countKeys

function Config.genUpgradeMult(data: Data, genId: string): number
	local m = 1
	for step, s in ipairs(GEN_UP_STEPS) do
		if data.ups[genId .. "_" .. step] then
			m *= s[2]
		end
	end
	return m
end

function Config.totalGenLevels(data: Data): number
	local n = 0
	for _, lvl in pairs(data.gens) do
		n += lvl
	end
	return n
end

-- Множитель ко всей добыче (без временных бонусов)
function Config.globalMult(data: Data): number
	local m = 1
	local brigade = 0
	for _, up in ipairs(Config.Upgrades) do
		if data.ups[up.id] then
			if up.kind == "global" then
				m *= up.value
			elseif up.kind == "brigade" then
				brigade += up.value
			end
		end
	end
	m *= 1 + brigade * math.floor(Config.totalGenLevels(data) / 10)
	m *= 1 + Config.DustPerBonus * data.dustEver
	m *= 1 + Config.AchievementBonus * countKeys(data.ach)
	m *= 2 ^ Config.pupLevel(data, "prod")
	return m
end

function Config.genProduction(data: Data, gen: Generator, globalMult: number?): number
	local level = data.gens[gen.id] or 0
	if level <= 0 then
		return 0
	end
	local g = globalMult or Config.globalMult(data)
	return gen.baseProd * level * 2 ^ Config.milestonesReached(level) * Config.genUpgradeMult(data, gen.id) * g
end

-- Доход в секунду без временных бонусов
function Config.basePerSecond(data: Data): number
	local g = Config.globalMult(data)
	local total = 0
	for _, gen in ipairs(Config.Generators) do
		total += Config.genProduction(data, gen, g)
	end
	return total
end

Config.FrenzyMult = 7
Config.ClickStormMult = 50

function Config.clickPercent(data: Data): number
	local p = 0
	for _, up in ipairs(Config.Upgrades) do
		if up.kind == "click" and data.ups[up.id] then
			p += up.value
		end
	end
	return p
end

-- Сколько даёт один клик (без временных бонусов)
function Config.baseClick(data: Data, basePerSec: number): number
	local base = (1 + basePerSec * Config.clickPercent(data)) * (1 + Config.DustPerBonus * data.dustEver)
	return base * 3 ^ Config.pupLevel(data, "click")
end

--------------------------------------------------------------------------------
-- Цены генераторов
--------------------------------------------------------------------------------
function Config.discount(data: Data): number
	return 0.95 ^ Config.pupLevel(data, "discount")
end

-- Цена n уровней начиная с текущего
function Config.genCost(data: Data, gen: Generator, n: number): number
	local level = data.gens[gen.id] or 0
	local first = gen.baseCost * gen.growth ^ level * Config.discount(data)
	if n == 1 then
		return math.ceil(first)
	end
	return math.ceil(first * (gen.growth ^ n - 1) / (gen.growth - 1))
end

-- Сколько уровней можно купить на bank (не больше limit)
function Config.maxAffordable(data: Data, gen: Generator, bank: number, limit: number?): number
	local level = data.gens[gen.id] or 0
	local first = gen.baseCost * gen.growth ^ level * Config.discount(data)
	if bank < first then
		return 0
	end
	local n = math.floor(math.log(bank * (gen.growth - 1) / first + 1) / math.log(gen.growth))
	if limit then
		n = math.min(n, limit)
	end
	n = math.max(n, 0)
	while n > 0 and Config.genCost(data, gen, n) > bank do
		n -= 1
	end
	return n
end

--------------------------------------------------------------------------------
-- Сверкающие кристаллы (золотые бонусы)
--------------------------------------------------------------------------------
Config.GoldenMinInterval = 50
Config.GoldenMaxInterval = 110
Config.GoldenLifetime = 13

function Config.goldenIntervalMult(data: Data): number
	local m = 1
	for _, up in ipairs(Config.Upgrades) do
		if up.kind == "golden" and data.ups[up.id] then
			m *= up.value
		end
	end
	return m * 0.85 ^ Config.pupLevel(data, "golden")
end

function Config.frenzyDuration(data: Data): number
	return 30 + 10 * Config.pupLevel(data, "frenzy")
end

function Config.stormDuration(data: Data): number
	return 15 + 10 * Config.pupLevel(data, "frenzy")
end

--------------------------------------------------------------------------------
-- Оффлайн
--------------------------------------------------------------------------------
function Config.offlineRate(data: Data): number
	return 0.5 + 0.25 * Config.pupLevel(data, "offline")
end

function Config.offlineMaxSeconds(data: Data): number
	return (2 + 3 * Config.pupLevel(data, "offline")) * 3600
end

--------------------------------------------------------------------------------
-- Форматирование
--------------------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "UDc", "DDc", "TDc", "QaDc", "QiDc" }

function Config.format(n: number): string
	if n ~= n then
		return "0"
	end
	if n < 1000 then
		if n < 10 and n ~= math.floor(n) then
			return string.format("%.1f", math.floor(n * 10) / 10)
		end
		return tostring(math.floor(n))
	end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	if v >= 1000 then
		return string.format("%.2e", n)
	elseif v >= 100 then
		return string.format("%d%s", math.floor(v), SUFFIXES[i])
	elseif v >= 10 then
		return string.format("%.1f%s", math.floor(v * 10) / 10, SUFFIXES[i])
	end
	return string.format("%.2f%s", math.floor(v * 100) / 100, SUFFIXES[i])
end

function Config.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d ч %02d мин", h, m)
	elseif m > 0 then
		return string.format("%d мин %02d с", m, s)
	end
	return string.format("%d с", s)
end

return Config
