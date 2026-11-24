-- «В Бездну»: баланс и формулы. Общий модуль сервера и клиента.
local Config = {}

export type Data = {
	coins: number,
	totalCoins: number,
	step: number, -- сколько ступеней куплено в этом забеге
	bestStep: number, -- рекорд глубины за всё время
	bosses: number, -- сколько стражей побеждено в этом забеге
	ups: { [string]: number },
	relics: { [string]: { n: number, s: number } }, -- n — копий, s — из них сияющих
	titles: { [string]: number },
	title: string?, -- надетое звание
	tokens: number, -- осколки перерождения (валюта)
	tokensEver: number,
	rebirths: number,
	rups: { [string]: number },
	digs: number,
	rolls: number,
	playTime: number,
	autoStep: boolean,
	autoDig: boolean,
	lastOnline: number?,
}

function Config.newData(): Data
	return {
		coins = 0,
		totalCoins = 0,
		step = 0,
		bestStep = 0,
		bosses = 0,
		ups = {},
		relics = {},
		titles = {},
		title = nil,
		tokens = 0,
		tokensEver = 0,
		rebirths = 0,
		rups = {},
		digs = 0,
		rolls = 0,
		playTime = 0,
		autoStep = true,
		autoDig = true,
		lastOnline = nil,
	}
end

--------------------------------------------------------------------------------
-- Слои
--------------------------------------------------------------------------------
Config.STEPS_PER_LAYER = 50
Config.STEP_DROP = 1.2 -- на сколько ниже каждая ступень
Config.STEPS_PER_TURN = 30 -- ступеней на полный виток спирали
Config.SURFACE_Y = 700

export type Layer = {
	index: number,
	name: string,
	wall: Color3,
	step: Color3,
	glow: Color3,
	material: Enum.Material,
	boss: string,
	bossColor: Color3,
}

local LAYER_LIST = {
	{ "Дёрн", Color3.fromRGB(86, 120, 60), Color3.fromRGB(120, 95, 65), Color3.fromRGB(180, 255, 120), Enum.Material.Grass, "Корнегрыз", Color3.fromRGB(110, 80, 50) },
	{ "Глина", Color3.fromRGB(160, 95, 60), Color3.fromRGB(190, 130, 90), Color3.fromRGB(255, 170, 110), Enum.Material.Sand, "Глиняный голем", Color3.fromRGB(170, 100, 60) },
	{ "Известняк", Color3.fromRGB(190, 185, 160), Color3.fromRGB(215, 210, 190), Color3.fromRGB(255, 250, 200), Enum.Material.Limestone, "Костяной червь", Color3.fromRGB(230, 225, 200) },
	{ "Гранит", Color3.fromRGB(110, 105, 115), Color3.fromRGB(140, 135, 145), Color3.fromRGB(200, 200, 255), Enum.Material.Granite, "Гранитный страж", Color3.fromRGB(90, 90, 100) },
	{ "Кристальные пещеры", Color3.fromRGB(60, 50, 110), Color3.fromRGB(90, 80, 150), Color3.fromRGB(150, 110, 255), Enum.Material.Slate, "Кристальный паук", Color3.fromRGB(140, 100, 255) },
	{ "Грибной грот", Color3.fromRGB(40, 70, 70), Color3.fromRGB(60, 100, 95), Color3.fromRGB(80, 255, 220), Enum.Material.Mud, "Грибной владыка", Color3.fromRGB(70, 220, 190) },
	{ "Магма", Color3.fromRGB(70, 25, 20), Color3.fromRGB(100, 40, 30), Color3.fromRGB(255, 110, 40), Enum.Material.Basalt, "Лавовый змей", Color3.fromRGB(255, 90, 30) },
	{ "Обсидиан", Color3.fromRGB(25, 20, 35), Color3.fromRGB(45, 35, 60), Color3.fromRGB(200, 80, 255), Enum.Material.Glass, "Обсидиановый рыцарь", Color3.fromRGB(60, 40, 90) },
	{ "Ледяное сердце", Color3.fromRGB(120, 170, 210), Color3.fromRGB(170, 210, 240), Color3.fromRGB(150, 230, 255), Enum.Material.Ice, "Ледяной титан", Color3.fromRGB(160, 220, 255) },
	{ "Пустота", Color3.fromRGB(10, 8, 18), Color3.fromRGB(25, 20, 40), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, "Пожиратель пустоты", Color3.fromRGB(20, 10, 30) },
}

Config.Layers = {} :: { Layer }
for i, l in ipairs(LAYER_LIST) do
	table.insert(Config.Layers, {
		index = i,
		name = l[1],
		wall = l[2],
		step = l[3],
		glow = l[4],
		material = l[5],
		boss = l[6],
		bossColor = l[7],
	})
end
Config.MAX_STEP = #Config.Layers * Config.STEPS_PER_LAYER

-- Слой, в котором находится ступень (1..10)
function Config.layerOfStep(step: number): number
	return math.clamp(math.floor((math.max(step, 1) - 1) / Config.STEPS_PER_LAYER) + 1, 1, #Config.Layers)
end

-- Ступень, на которой стоит страж слоя L (последняя ступень слоя)
function Config.bossStep(layer: number): number
	return layer * Config.STEPS_PER_LAYER
end

-- Положение ступени n в мире (0 — край ямы на поверхности)
Config.PIT_INNER = 20 -- радиус центрального столба
Config.PIT_OUTER = 36 -- радиус стены ямы
Config.STEP_RADIUS = 28

function Config.stepPosition(n: number): Vector3
	local a = n / Config.STEPS_PER_TURN * math.pi * 2
	return Vector3.new(
		math.cos(a) * Config.STEP_RADIUS,
		Config.SURFACE_Y - n * Config.STEP_DROP,
		math.sin(a) * Config.STEP_RADIUS
	)
end

function Config.stepAngle(n: number): number
	return n / Config.STEPS_PER_TURN * math.pi * 2
end

--------------------------------------------------------------------------------
-- Улучшения за монеты
--------------------------------------------------------------------------------
export type Upgrade = {
	id: string,
	tree: string, -- "coins" | "luck" | "power"
	name: string,
	desc: string,
	baseCost: number,
	growth: number,
	maxLevel: number,
	needBoss: number, -- сколько стражей нужно победить, чтобы открылось
}

Config.Upgrades = {
	{ id = "pick", tree = "coins", name = "Кирка", desc = "+2 монеты/с за уровень", baseCost = 15, growth = 1.32, maxLevel = 100, needBoss = 0 },
	{ id = "cart", tree = "coins", name = "Тележка", desc = "Доход ×1.2 за уровень", baseCost = 300, growth = 2.6, maxLevel = 50, needBoss = 0 },
	{ id = "tamp", tree = "coins", name = "Утрамбовка", desc = "Ступени дешевле на 4% за уровень", baseCost = 1500, growth = 2.6, maxLevel = 20, needBoss = 1 },
	{ id = "echo", tree = "coins", name = "Эхо глубины", desc = "Бонус глубины +0.1% за ступень за уровень", baseCost = 50000, growth = 4, maxLevel = 10, needBoss = 2 },
	{ id = "horse", tree = "luck", name = "Подкова", desc = "Удача +15% за уровень", baseCost = 400, growth = 1.9, maxLevel = 40, needBoss = 0 },
	{ id = "lens", tree = "luck", name = "Лупа", desc = "Шанс сияющей находки +15% за уровень", baseCost = 3000, growth = 2.2, maxLevel = 25, needBoss = 1 },
	{ id = "shovel", tree = "luck", name = "Лопата", desc = "Раскопки дешевле на 6% за уровень", baseCost = 2000, growth = 2.3, maxLevel = 12, needBoss = 1 },
	{ id = "fist", tree = "power", name = "Кулак", desc = "Урон по стражам ×1.4 за уровень", baseCost = 60, growth = 1.85, maxLevel = 100, needBoss = 0 },
	{ id = "stamina", tree = "power", name = "Выносливость", desc = "Бой длится +3 с за уровень", baseCost = 1000, growth = 3, maxLevel = 10, needBoss = 1 },
	{ id = "aim", tree = "power", name = "Меткость", desc = "Шанс крита ×5 +5% за уровень", baseCost = 5000, growth = 2.5, maxLevel = 10, needBoss = 2 },
} :: { Upgrade }

Config.UpById = {} :: { [string]: Upgrade }
for _, u in ipairs(Config.Upgrades) do
	Config.UpById[u.id] = u
end

function Config.lvl(data: Data, id: string): number
	return data.ups[id] or 0
end

function Config.upCost(u: Upgrade, level: number): number
	return math.ceil(u.baseCost * u.growth ^ level)
end

--------------------------------------------------------------------------------
-- Перерождение
--------------------------------------------------------------------------------
Config.REBIRTH_NEED_BOSSES = 2
Config.TOKEN_BONUS = 0.1 -- +10% дохода за каждый полученный осколок

export type RebirthUp = {
	id: string,
	name: string,
	desc: string,
	baseCost: number,
	growth: number,
	maxLevel: number,
}

Config.RebirthUps = {
	{ id = "r_income", name = "Жила предков", desc = "Доход ×1.5 за уровень", baseCost = 2, growth = 2, maxLevel = 20 },
	{ id = "r_power", name = "Сила предков", desc = "Урон по стражам ×2 за уровень", baseCost = 2, growth = 2.2, maxLevel = 20 },
	{ id = "r_luck", name = "Чутьё", desc = "Удача ×1.25 за уровень", baseCost = 3, growth = 2.5, maxLevel = 10 },
	{ id = "r_start", name = "Фора", desc = "Начинать забег сразу с +10 ступеней за уровень", baseCost = 3, growth = 2, maxLevel = 4 },
	{ id = "r_autostep", name = "Ноги сами идут", desc = "Ступени покупаются сами, когда хватает монет (можно выключить)", baseCost = 4, growth = 1, maxLevel = 1 },
	{ id = "r_autodig", name = "Крот-помощник", desc = "Сам копает на самом глубоком раскопе каждые 4 с (можно выключить)", baseCost = 8, growth = 1, maxLevel = 1 },
} :: { RebirthUp }

Config.RUpById = {} :: { [string]: RebirthUp }
for _, r in ipairs(Config.RebirthUps) do
	Config.RUpById[r.id] = r
end

function Config.rlvl(data: Data, id: string): number
	return data.rups[id] or 0
end

function Config.rupCost(r: RebirthUp, level: number): number
	return math.floor(r.baseCost * r.growth ^ level)
end

function Config.tokensOnRebirth(data: Data): number
	if data.bosses < Config.REBIRTH_NEED_BOSSES then
		return 0
	end
	return math.floor((data.step / 25) ^ 1.6)
end

--------------------------------------------------------------------------------
-- Находки (раскопки)
--------------------------------------------------------------------------------
export type Rarity = { id: string, name: string, weight: number, bonus: number, color: Color3 }
Config.Rarities = {
	{ id = "common", name = "Обычная", weight = 60, bonus = 0.02, color = Color3.fromRGB(200, 200, 210) },
	{ id = "uncommon", name = "Необычная", weight = 25, bonus = 0.04, color = Color3.fromRGB(100, 230, 120) },
	{ id = "rare", name = "Редкая", weight = 10, bonus = 0.08, color = Color3.fromRGB(80, 170, 255) },
	{ id = "epic", name = "Эпическая", weight = 4, bonus = 0.16, color = Color3.fromRGB(190, 100, 255) },
	{ id = "legend", name = "Легендарная", weight = 1, bonus = 0.4, color = Color3.fromRGB(255, 200, 50) },
} :: { Rarity }

export type Relic = { id: string, name: string, layer: number, rarity: Rarity, rarityIndex: number }

local RELIC_NAMES = {
	{ "Ржавый гвоздь", "Старая монета", "Корень-талисман", "Окаменевший жук", "Золотой жёлудь" },
	{ "Глиняный черепок", "Ракушка", "Зуб ящера", "Глиняный идол", "Яйцо раптора" },
	{ "Аммонит", "Трилобит", "Череп саблезуба", "Позвонок кита", "Коготь титана" },
	{ "Кварц", "Слюда", "Гранат", "Сапфир", "Сердце горы" },
	{ "Аметист", "Изумруд", "Поющий кристалл", "Призма", "Звёздный осколок" },
	{ "Светящийся гриб", "Спора", "Шляпка-фонарь", "Мицелиевая корона", "Древний гриб" },
	{ "Вулканическое стекло", "Огненный опал", "Саламандра", "Лавовое сердце", "Перо феникса" },
	{ "Обсидиановый клинок", "Чёрная жемчужина", "Руна", "Маска древних", "Око бездны" },
	{ "Ледяной кристалл", "Бивень мамонта", "Замёрзшая слеза", "Снежное сердце", "Вечный лёд" },
	{ "Осколок тьмы", "Эхо", "Шёпот", "Корона пустоты", "Ядро мира" },
}

Config.Relics = {} :: { Relic }
Config.RelicById = {} :: { [string]: Relic }
Config.RelicsByLayer = {} :: { { Relic } }
for layer, names in ipairs(RELIC_NAMES) do
	Config.RelicsByLayer[layer] = {}
	for r, name in ipairs(names) do
		local relic: Relic = { id = string.format("L%d_%d", layer, r), name = name, layer = layer, rarity = Config.Rarities[r], rarityIndex = r }
		table.insert(Config.Relics, relic)
		table.insert(Config.RelicsByLayer[layer], relic)
		Config.RelicById[relic.id] = relic
	end
end

Config.SHINY_BASE = 1 / 40
Config.SHINY_MULT = 3
Config.DIG_SITE_OFFSET = 25 -- раскоп — на 25-й ступени каждого слоя

function Config.digSiteStep(layer: number): number
	return (layer - 1) * Config.STEPS_PER_LAYER + Config.DIG_SITE_OFFSET
end

-- Бонус одной находки к доходу (доля)
function Config.relicBonus(relic: Relic, entry: { n: number, s: number }): number
	if entry.n <= 0 then
		return 0
	end
	local layerMult = 1 + 0.6 * (relic.layer - 1)
	local base = relic.rarity.bonus * layerMult * (1 + 0.35 * math.log(entry.n, 2))
	return base * (1 + (Config.SHINY_MULT - 1) * math.min(entry.s, 1))
end

function Config.relicMult(data: Data): number
	local total = 0
	for id, entry in pairs(data.relics) do
		local relic = Config.RelicById[id]
		if relic then
			total += Config.relicBonus(relic, entry)
		end
	end
	return 1 + total
end

--------------------------------------------------------------------------------
-- Звания (рулетка)
--------------------------------------------------------------------------------
export type Title = { id: string, name: string, chance: number, mult: number, color: Color3 }
Config.Titles = {
	{ id = "t1", name = "Новичок", chance = 2, mult = 1.1, color = Color3.fromRGB(200, 200, 210) },
	{ id = "t2", name = "Копатель", chance = 5, mult = 1.25, color = Color3.fromRGB(180, 140, 90) },
	{ id = "t3", name = "Спелеолог", chance = 12, mult = 1.5, color = Color3.fromRGB(100, 230, 120) },
	{ id = "t4", name = "Исследователь", chance = 30, mult = 2, color = Color3.fromRGB(80, 200, 255) },
	{ id = "t5", name = "Бывалый", chance = 80, mult = 3, color = Color3.fromRGB(80, 140, 255) },
	{ id = "t6", name = "Глубинный", chance = 200, mult = 4.5, color = Color3.fromRGB(150, 110, 255) },
	{ id = "t7", name = "Хранитель тьмы", chance = 600, mult = 7, color = Color3.fromRGB(200, 80, 255) },
	{ id = "t8", name = "Легенда шахт", chance = 2000, mult = 12, color = Color3.fromRGB(255, 200, 50) },
	{ id = "t9", name = "Повелитель бездны", chance = 8000, mult = 20, color = Color3.fromRGB(255, 120, 40) },
	{ id = "t10", name = "Сердце мира", chance = 40000, mult = 40, color = Color3.fromRGB(255, 60, 90) },
	{ id = "t11", name = "Безднорождённый", chance = 250000, mult = 100, color = Color3.fromRGB(255, 255, 255) },
} :: { Title }
Config.TitleById = {} :: { [string]: Title }
for _, t in ipairs(Config.Titles) do
	Config.TitleById[t.id] = t
end

function Config.titleMult(data: Data): number
	local t = data.title and Config.TitleById[data.title]
	return t and t.mult or 1
end

-- Бросок: идём от самого редкого, шанс каждого = удача / N
function Config.rollTitle(luck: number, rng: () -> number): Title
	for i = #Config.Titles, 2, -1 do
		local t = Config.Titles[i]
		if rng() < math.min(1, luck / t.chance) then
			return t
		end
	end
	return Config.Titles[1]
end

--------------------------------------------------------------------------------
-- Формулы
--------------------------------------------------------------------------------
Config.DEPTH_BONUS = 0.06 -- +6% дохода за каждую ступень (сложный процент)

function Config.luck(data: Data): number
	return (1 + 0.15 * Config.lvl(data, "horse")) * 1.25 ^ Config.rlvl(data, "r_luck")
end

function Config.depthMult(data: Data): number
	local per = Config.DEPTH_BONUS + 0.001 * Config.lvl(data, "echo")
	return (1 + per) ^ data.step
end

function Config.income(data: Data): number
	local base = 1 + 2 * Config.lvl(data, "pick")
	local m = 1.2 ^ Config.lvl(data, "cart")
	m *= Config.depthMult(data)
	m *= Config.relicMult(data)
	m *= Config.titleMult(data)
	m *= 1 + Config.TOKEN_BONUS * data.tokensEver
	m *= 1.5 ^ Config.rlvl(data, "r_income")
	return base * m
end

function Config.stepCost(data: Data, n: number): number
	-- n — номер покупаемой ступени (1..MAX_STEP)
	local layer = Config.layerOfStep(n)
	return math.ceil(8 * 1.15 ^ (n - 1) * 10 ^ (layer - 1) * 0.96 ^ Config.lvl(data, "tamp"))
end

function Config.canBuyStep(data: Data): (boolean, string?)
	local n = data.step + 1
	if n > Config.MAX_STEP then
		return false, "Дно достигнуто!"
	end
	-- Пройти дальше последней ступени слоя можно только победив стража
	local layer = Config.layerOfStep(n)
	if data.bosses < layer - 1 then
		return false, "Сначала победи стража слоя"
	end
	return true, nil
end

function Config.bossHP(layer: number): number
	return 120 * 16 ^ (layer - 1)
end

function Config.damagePerSec(data: Data): number
	return 10 * 1.4 ^ Config.lvl(data, "fist") * 2 ^ Config.rlvl(data, "r_power") * (1 + 0.04 * data.step)
end

function Config.fightDuration(data: Data): number
	return 15 + 3 * Config.lvl(data, "stamina")
end

function Config.critChance(data: Data): number
	return 0.05 * Config.lvl(data, "aim")
end

function Config.digCost(data: Data, layer: number): number
	return math.ceil(40 * 6 ^ (layer - 1) * 0.94 ^ Config.lvl(data, "shovel") * (1 + data.step * 0.02) ^ 2)
end

function Config.titleRollCost(data: Data): number
	return math.max(100, math.ceil(Config.income(data) * 45 / Config.titleMult(data)))
end

function Config.shinyChance(data: Data): number
	return Config.SHINY_BASE * (1 + 0.15 * Config.lvl(data, "lens")) * Config.luck(data) ^ 0.5
end

-- Случайная находка слоя с учётом удачи
function Config.rollRelic(layer: number, luck: number, rng: () -> number): Relic
	local list = Config.RelicsByLayer[layer]
	local weights = {}
	local total = 0
	for i, relic in ipairs(list) do
		-- удача усиливает редкие: вес × удача^(индекс редкости − 1)
		local w = relic.rarity.weight * luck ^ (i - 1)
		weights[i] = w
		total += w
	end
	local x = rng() * total
	for i, w in ipairs(weights) do
		x -= w
		if x <= 0 then
			return list[i]
		end
	end
	return list[#list]
end

Config.OFFLINE_RATE = 0.4
Config.OFFLINE_MAX = 3 * 3600

--------------------------------------------------------------------------------
-- Форматирование
--------------------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc", "Vg" }

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

function Config.formatChance(n: number): string
	if n >= 1000 then
		return "1/" .. Config.format(n)
	end
	return "1/" .. tostring(n)
end

return Config
