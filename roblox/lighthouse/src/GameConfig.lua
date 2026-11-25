-- «Маяк во Тьме»: баланс и формулы. Общий модуль сервера и клиента.
local Config = {}

export type Data = {
	coins: number, -- 💡 сияние (валюта)
	totalCoins: number,
	light: number, -- уровень света (радиус) в этом забеге
	bestLight: number,
	bosses: number, -- сколько теней изгнано в этом забеге
	ups: { [string]: number },
	relics: { [string]: { n: number, s: number } },
	titles: { [string]: number }, -- созвездия: сколько раз выпало
	title: string?, -- зажжённое созвездие
	dust: number, -- ✦ звёздная пыль
	dustEver: number,
	rebirths: number,
	rups: { [string]: number },
	picks: number,
	rolls: number,
	playTime: number,
	autoLight: boolean,
	autoPick: boolean,
	lastOnline: number?,
}

function Config.newData(): Data
	return {
		coins = 0,
		totalCoins = 0,
		light = 0,
		bestLight = 0,
		bosses = 0,
		ups = {},
		relics = {},
		titles = {},
		title = nil,
		dust = 0,
		dustEver = 0,
		rebirths = 0,
		rups = {},
		picks = 0,
		rolls = 0,
		playTime = 0,
		autoLight = true,
		autoPick = true,
		lastOnline = nil,
	}
end

--------------------------------------------------------------------------------
-- Земли и радиус света
--------------------------------------------------------------------------------
Config.LEVELS_PER_ZONE = 50
Config.BASE_RADIUS = 34 -- радиус света в самом начале
Config.STUDS_PER_LEVEL = 1.2
Config.GROUND_Y = 0

export type Zone = {
	index: number,
	name: string,
	ground: Color3,
	accent: Color3,
	material: Enum.Material,
	boss: string,
}

local ZONE_LIST = {
	{ "Тихий луг", Color3.fromRGB(70, 110, 60), Color3.fromRGB(255, 240, 150), Enum.Material.Grass, "Тенекрыл" },
	{ "Лес светлячков", Color3.fromRGB(40, 80, 50), Color3.fromRGB(180, 255, 120), Enum.Material.LeafyGrass, "Морок чащи" },
	{ "Туманное болото", Color3.fromRGB(55, 70, 55), Color3.fromRGB(120, 255, 200), Enum.Material.Mud, "Болотный шептун" },
	{ "Забытые руины", Color3.fromRGB(110, 100, 90), Color3.fromRGB(255, 200, 130), Enum.Material.Cobblestone, "Каменная тень" },
	{ "Кристальное поле", Color3.fromRGB(60, 55, 100), Color3.fromRGB(170, 130, 255), Enum.Material.Slate, "Кристальный жнец" },
	{ "Грибная чаща", Color3.fromRGB(45, 60, 75), Color3.fromRGB(90, 230, 255), Enum.Material.Ground, "Грибная хмарь" },
	{ "Пепельная пустошь", Color3.fromRGB(60, 50, 50), Color3.fromRGB(255, 120, 60), Enum.Material.Basalt, "Пепельный волк" },
	{ "Ледяной берег", Color3.fromRGB(150, 180, 205), Color3.fromRGB(170, 230, 255), Enum.Material.Snow, "Ледяная вдова" },
	{ "Звёздные дюны", Color3.fromRGB(120, 105, 150), Color3.fromRGB(255, 230, 255), Enum.Material.Sand, "Звездоед" },
	{ "Край мира", Color3.fromRGB(30, 28, 40), Color3.fromRGB(255, 255, 255), Enum.Material.Glass, "Сама Тьма" },
}

Config.Zones = {} :: { Zone }
for i, z in ipairs(ZONE_LIST) do
	table.insert(Config.Zones, { index = i, name = z[1], ground = z[2], accent = z[3], material = z[4], boss = z[5] })
end
Config.MAX_LIGHT = #Config.Zones * Config.LEVELS_PER_ZONE

function Config.radius(light: number): number
	return Config.BASE_RADIUS + light * Config.STUDS_PER_LEVEL
end

-- Зона, к которой относится уровень света (1..10)
function Config.zoneOfLevel(light: number): number
	return math.clamp(math.floor((math.max(light, 1) - 1) / Config.LEVELS_PER_ZONE) + 1, 1, #Config.Zones)
end

-- Внутренний и внешний радиус зоны
function Config.zoneRange(zone: number): (number, number)
	local inner = zone == 1 and 0 or Config.radius((zone - 1) * Config.LEVELS_PER_ZONE)
	return inner, Config.radius(zone * Config.LEVELS_PER_ZONE)
end

function Config.bossLevel(zone: number): number
	return zone * Config.LEVELS_PER_ZONE
end

-- Где у стены тьмы стоит тень зоны (угол в радианах)
function Config.bossAngle(zone: number): number
	return zone * 2.4
end

-- Сколько зон уже освещено хоть немного
function Config.litZones(light: number): number
	if light <= 0 then
		return 1
	end
	return Config.zoneOfLevel(light)
end

--------------------------------------------------------------------------------
-- Постройки-улучшения у маяка
--------------------------------------------------------------------------------
export type Upgrade = {
	id: string,
	name: string,
	desc: string,
	baseCost: number,
	growth: number,
	maxLevel: number,
	needBoss: number,
	angle: number, -- где стоит постройка вокруг маяка (градусы)
	color: Color3,
}

Config.Upgrades = {
	{ id = "lamps", name = "Фонарщик", desc = "+2 сияния/с за каждый фонарь", baseCost = 15, growth = 1.32, maxLevel = 100, needBoss = 0, angle = 20, color = Color3.fromRGB(255, 210, 120) },
	{ id = "lens", name = "Линза маяка", desc = "Всё сияние ×1.2 за уровень", baseCost = 300, growth = 2.6, maxLevel = 50, needBoss = 0, angle = 0, color = Color3.fromRGB(255, 250, 200) },
	{ id = "hive", name = "Улей светлячков", desc = "Удача +15%, находки появляются чаще", baseCost = 400, growth = 1.9, maxLevel = 40, needBoss = 0, angle = 56, color = Color3.fromRGB(200, 255, 120) },
	{ id = "search", name = "Прожектор", desc = "Урон по теням ×1.4 за уровень", baseCost = 60, growth = 1.85, maxLevel = 100, needBoss = 0, angle = 92, color = Color3.fromRGB(255, 120, 90) },
	{ id = "mirror", name = "Зеркала", desc = "Свет дешевле на 4% за уровень", baseCost = 1500, growth = 2.6, maxLevel = 20, needBoss = 1, angle = 128, color = Color3.fromRGB(190, 230, 255) },
	{ id = "prism", name = "Призма", desc = "Шанс сияющей находки +15%", baseCost = 3000, growth = 2.2, maxLevel = 25, needBoss = 1, angle = 164, color = Color3.fromRGB(230, 150, 255) },
	{ id = "net", name = "Сачок", desc = "+1 находка одновременно на земле", baseCost = 2000, growth = 3, maxLevel = 6, needBoss = 1, angle = 200, color = Color3.fromRGB(150, 255, 220) },
	{ id = "battery", name = "Аккумулятор", desc = "Бой с тенью длится +3 с", baseCost = 1000, growth = 3, maxLevel = 10, needBoss = 1, angle = 236, color = Color3.fromRGB(120, 255, 140) },
	{ id = "focus", name = "Фокусировка", desc = "Шанс крита ×5 +5% за уровень", baseCost = 5000, growth = 2.5, maxLevel = 10, needBoss = 2, angle = 272, color = Color3.fromRGB(255, 160, 220) },
	{ id = "relay", name = "Ретрансляторы", desc = "Бонус света +0.1% за уровень света", baseCost = 50000, growth = 4, maxLevel = 10, needBoss = 2, angle = 308, color = Color3.fromRGB(120, 200, 255) },
} :: { Upgrade }

Config.UpById = {} :: { [string]: Upgrade }
for _, u in ipairs(Config.Upgrades) do
	Config.UpById[u.id] = u
end
Config.BUILDING_RING = 21 -- радиус, на котором стоят постройки

function Config.lvl(data: Data, id: string): number
	return data.ups[id] or 0
end

function Config.upCost(u: Upgrade, level: number): number
	return math.ceil(u.baseCost * u.growth ^ level)
end

--------------------------------------------------------------------------------
-- Новая заря (перерождение)
--------------------------------------------------------------------------------
Config.REBIRTH_NEED_BOSSES = 2
Config.DUST_BONUS = 0.1

export type RebirthUp = { id: string, name: string, desc: string, baseCost: number, growth: number, maxLevel: number }
Config.RebirthUps = {
	{ id = "r_income", name = "Вечное пламя", desc = "Всё сияние ×1.5 за уровень", baseCost = 2, growth = 2, maxLevel = 20 },
	{ id = "r_power", name = "Солнечный луч", desc = "Урон по теням ×2 за уровень", baseCost = 2, growth = 2.2, maxLevel = 20 },
	{ id = "r_luck", name = "Звёздное чутьё", desc = "Удача ×1.25 за уровень", baseCost = 3, growth = 2.5, maxLevel = 10 },
	{ id = "r_start", name = "Тлеющие угли", desc = "Начинать с +10 уровней света за уровень", baseCost = 3, growth = 2, maxLevel = 4 },
	{ id = "r_autolight", name = "Сам горит", desc = "Свет разжигается сам, когда хватает сияния", baseCost = 4, growth = 1, maxLevel = 1 },
	{ id = "r_autopick", name = "Светлячки-сборщики", desc = "Находки собираются сами", baseCost = 8, growth = 1, maxLevel = 1 },
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

function Config.dustOnRebirth(data: Data): number
	if data.bosses < Config.REBIRTH_NEED_BOSSES then
		return 0
	end
	return math.floor((data.light / 25) ^ 1.6)
end

--------------------------------------------------------------------------------
-- Находки
--------------------------------------------------------------------------------
export type Rarity = { id: string, name: string, weight: number, bonus: number, color: Color3 }
Config.Rarities = {
	{ id = "common", name = "Обычная", weight = 60, bonus = 0.02, color = Color3.fromRGB(210, 210, 220) },
	{ id = "uncommon", name = "Необычная", weight = 25, bonus = 0.04, color = Color3.fromRGB(110, 235, 130) },
	{ id = "rare", name = "Редкая", weight = 10, bonus = 0.08, color = Color3.fromRGB(90, 175, 255) },
	{ id = "epic", name = "Эпическая", weight = 4, bonus = 0.16, color = Color3.fromRGB(195, 110, 255) },
	{ id = "legend", name = "Легендарная", weight = 1, bonus = 0.4, color = Color3.fromRGB(255, 205, 60) },
} :: { Rarity }

export type Relic = { id: string, name: string, zone: number, rarity: Rarity, rarityIndex: number }
local RELIC_NAMES = {
	{ "Светящийся одуванчик", "Медный колокольчик", "Четырёхлистник", "Лунный камешек", "Серебряное перо совы" },
	{ "Шишка-фонарик", "Светлячок в банке", "Резной жёлудь", "Кора древнего дуба", "Сердце леса" },
	{ "Болотный огонёк", "Кувшинка", "Лягушачья корона", "Туманный жемчуг", "Глаз трясины" },
	{ "Обломок колонны", "Старая монета", "Каменная руна", "Маска стража", "Ключ от врат" },
	{ "Кварц", "Аметист", "Поющий кристалл", "Призма", "Звёздный осколок" },
	{ "Спора-светлячок", "Шляпка-фонарь", "Гриб-колокол", "Мицелиевая корона", "Древний гриб" },
	{ "Тлеющий уголь", "Пепельная роза", "Огненный опал", "Перо феникса", "Сердце вулкана" },
	{ "Снежинка", "Бивень мамонта", "Замёрзшая слеза", "Сияние в бутылке", "Вечный лёд" },
	{ "Звёздный песок", "Метеорит", "Компас странника", "Осколок луны", "Падшая звезда" },
	{ "Осколок тьмы", "Эхо", "Шёпот", "Корона рассвета", "Первый луч" },
}
Config.Relics = {} :: { Relic }
Config.RelicById = {} :: { [string]: Relic }
Config.RelicsByZone = {} :: { { Relic } }
for zone, names in ipairs(RELIC_NAMES) do
	Config.RelicsByZone[zone] = {}
	for r, name in ipairs(names) do
		local relic: Relic = { id = string.format("Z%d_%d", zone, r), name = name, zone = zone, rarity = Config.Rarities[r], rarityIndex = r }
		table.insert(Config.Relics, relic)
		table.insert(Config.RelicsByZone[zone], relic)
		Config.RelicById[relic.id] = relic
	end
end

Config.SHINY_BASE = 1 / 40
Config.SHINY_MULT = 3

function Config.relicBonus(relic: Relic, entry: { n: number, s: number }): number
	if entry.n <= 0 then
		return 0
	end
	local zoneMult = 1 + 0.6 * (relic.zone - 1)
	local base = relic.rarity.bonus * zoneMult * (1 + 0.35 * math.log(entry.n, 2))
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

function Config.pickupInterval(data: Data): number
	return math.max(2, 9 * 0.95 ^ Config.lvl(data, "hive"))
end

function Config.maxPickups(data: Data): number
	return 4 + Config.lvl(data, "net")
end

--------------------------------------------------------------------------------
-- Созвездия (рулетка)
--------------------------------------------------------------------------------
export type Title = { id: string, name: string, chance: number, mult: number, color: Color3, stars: number }
Config.Titles = {
	{ id = "c1", name = "Светлячок", chance = 2, mult = 1.1, color = Color3.fromRGB(220, 220, 230), stars = 4 },
	{ id = "c2", name = "Фонарик", chance = 5, mult = 1.25, color = Color3.fromRGB(255, 220, 150), stars = 5 },
	{ id = "c3", name = "Свеча", chance = 12, mult = 1.5, color = Color3.fromRGB(150, 240, 140), stars = 5 },
	{ id = "c4", name = "Компас", chance = 30, mult = 2, color = Color3.fromRGB(100, 210, 255), stars = 6 },
	{ id = "c5", name = "Сова", chance = 80, mult = 3, color = Color3.fromRGB(110, 150, 255), stars = 7 },
	{ id = "c6", name = "Олень", chance = 200, mult = 4.5, color = Color3.fromRGB(160, 120, 255), stars = 8 },
	{ id = "c7", name = "Кит", chance = 600, mult = 7, color = Color3.fromRGB(210, 100, 255), stars = 9 },
	{ id = "c8", name = "Феникс", chance = 2000, mult = 12, color = Color3.fromRGB(255, 200, 60), stars = 10 },
	{ id = "c9", name = "Дракон", chance = 8000, mult = 20, color = Color3.fromRGB(255, 130, 50), stars = 11 },
	{ id = "c10", name = "Корона", chance = 40000, mult = 40, color = Color3.fromRGB(255, 80, 100), stars = 12 },
	{ id = "c11", name = "Рассвет", chance = 250000, mult = 100, color = Color3.fromRGB(255, 255, 255), stars = 14 },
} :: { Title }
Config.TitleById = {} :: { [string]: Title }
for _, t in ipairs(Config.Titles) do
	Config.TitleById[t.id] = t
end

function Config.titleMult(data: Data): number
	local t = data.title and Config.TitleById[data.title]
	return t and t.mult or 1
end

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
Config.LIGHT_BONUS = 0.06

function Config.luck(data: Data): number
	return (1 + 0.15 * Config.lvl(data, "hive")) * 1.25 ^ Config.rlvl(data, "r_luck")
end

function Config.lightMult(data: Data): number
	local per = Config.LIGHT_BONUS + 0.001 * Config.lvl(data, "relay")
	return (1 + per) ^ data.light
end

function Config.income(data: Data): number
	local base = 1 + 2 * Config.lvl(data, "lamps")
	local m = 1.2 ^ Config.lvl(data, "lens")
	m *= Config.lightMult(data)
	m *= Config.relicMult(data)
	m *= Config.titleMult(data)
	m *= 1 + Config.DUST_BONUS * data.dustEver
	m *= 1.5 ^ Config.rlvl(data, "r_income")
	return base * m
end

function Config.lightCost(data: Data, n: number): number
	local zone = Config.zoneOfLevel(n)
	return math.ceil(8 * 1.15 ^ (n - 1) * 10 ^ (zone - 1) * 0.96 ^ Config.lvl(data, "mirror"))
end

function Config.canBuyLight(data: Data): (boolean, string?)
	local n = data.light + 1
	if n > Config.MAX_LIGHT then
		return false, "Тьма рассеяна полностью!"
	end
	if data.bosses < Config.zoneOfLevel(n) - 1 then
		return false, "Сначала изгони тень"
	end
	return true, nil
end

function Config.bossHP(zone: number): number
	return 120 * 16 ^ (zone - 1)
end

function Config.damagePerSec(data: Data): number
	return 10 * 1.4 ^ Config.lvl(data, "search") * 2 ^ Config.rlvl(data, "r_power") * (1 + 0.04 * data.light)
end

function Config.fightDuration(data: Data): number
	return 15 + 3 * Config.lvl(data, "battery")
end

function Config.critChance(data: Data): number
	return 0.05 * Config.lvl(data, "focus")
end

function Config.titleRollCost(data: Data): number
	return math.max(100, math.ceil(Config.income(data) * 45 / Config.titleMult(data)))
end

function Config.shinyChance(data: Data): number
	return Config.SHINY_BASE * (1 + 0.15 * Config.lvl(data, "prism")) * Config.luck(data) ^ 0.5
end

function Config.rollRelic(zone: number, luck: number, rng: () -> number): Relic
	local list = Config.RelicsByZone[zone]
	local weights = {}
	local total = 0
	for i, relic in ipairs(list) do
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
