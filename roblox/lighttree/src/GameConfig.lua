-- «Маяк»: дерево улучшений на парящих островах. Баланс и формулы (общие для сервера и клиента).
local Config = {}

--------------------------------------------------------------------------------
-- Валюты и острова (слои прогресса)
--------------------------------------------------------------------------------
export type Island = {
	index: number,
	id: string, -- валюта острова
	name: string,
	icon: string,
	color: Color3,
	dark: Color3,
	center: Vector3,
	radius: number,
	tag: string, -- тег над головой, когда слой открыт
}

Config.Islands = {
	{ index = 1, id = "L", name = "Маяк", icon = "💡", color = Color3.fromRGB(255, 205, 90), dark = Color3.fromRGB(70, 60, 45), center = Vector3.new(0, 0, 0), radius = 70, tag = "" },
	{ index = 2, id = "Z", name = "Заря", icon = "🌅", color = Color3.fromRGB(255, 120, 80), dark = Color3.fromRGB(75, 45, 45), center = Vector3.new(0, 25, -230), radius = 58, tag = "Заря" },
	{ index = 3, id = "S", name = "Звёзды", icon = "✦", color = Color3.fromRGB(150, 140, 255), dark = Color3.fromRGB(45, 45, 80), center = Vector3.new(-230, 50, -230), radius = 54, tag = "Звёзды" },
	{ index = 4, id = "E", name = "Затмение", icon = "🌑", color = Color3.fromRGB(235, 235, 255), dark = Color3.fromRGB(25, 25, 35), center = Vector3.new(-230, 75, 0), radius = 50, tag = "Затмение" },
} :: { Island }

Config.IslandById = {} :: { [string]: Island }
for _, isl in ipairs(Config.Islands) do
	Config.IslandById[isl.id] = isl
end

Config.LIGHTHOUSE_POS = Vector3.new(-46, 0, -18) -- на острове Маяк
Config.TILE_STEP = 12 -- расстояние между плитками дерева
Config.TILE_SIZE = 9

--------------------------------------------------------------------------------
-- Данные игрока
--------------------------------------------------------------------------------
export type Data = {
	cur: { [string]: number }, -- L, Z, S, E — сколько есть
	run: { [string]: number }, -- сколько заработано с последнего сброса этого слоя
	total: { [string]: number }, -- за всё время
	nodes: { [string]: number }, -- уровни узлов
	resets: { [string]: number }, -- сколько раз сделан каждый сброс (Z, S, E)
	golden: number,
	playTime: number,
	lastOnline: number?,
}

function Config.newData(): Data
	return {
		cur = { L = 0, Z = 0, S = 0, E = 0 },
		run = { L = 0, Z = 0, S = 0, E = 0 },
		total = { L = 0, Z = 0, S = 0, E = 0 },
		nodes = {},
		resets = { Z = 0, S = 0, E = 0 },
		golden = 0,
		playTime = 0,
		lastOnline = nil,
	}
end

--------------------------------------------------------------------------------
-- Узлы дерева
--------------------------------------------------------------------------------
export type Node = {
	id: string,
	island: string, -- валюта, за которую покупается
	name: string,
	icon: string,
	desc: string,
	x: number, -- координаты на сетке острова
	z: number,
	parents: { string }, -- хватит любого купленного родителя
	cost: number,
	growth: number,
	max: number,
	kind: string,
	value: number,
}

local N: { Node } = {}
local function node(t: Node)
	table.insert(N, t)
end

-- Остров 1: Маяк (💡)
node({ id = "spark", island = "L", name = "Искра", icon = "✨", desc = "+1 💡/с", x = 0, z = 0, parents = {}, cost = 5, growth = 1.6, max = 25, kind = "addL", value = 1 })
node({ id = "wick", island = "L", name = "Фитиль", icon = "🕯", desc = "💡 ×1.3", x = -1, z = 1, parents = { "spark" }, cost = 100, growth = 3.5, max = 8, kind = "multL", value = 1.3 })
node({ id = "flint", island = "L", name = "Кремень", icon = "🔥", desc = "+3 💡/с", x = 1, z = 1, parents = { "spark" }, cost = 50, growth = 1.7, max = 25, kind = "addL", value = 3 })
node({ id = "oil", island = "L", name = "Масло", icon = "🛢", desc = "💡 ×2", x = -2, z = 2, parents = { "wick" }, cost = 3000, growth = 1, max = 1, kind = "multL", value = 2 })
node({ id = "lamplighter", island = "L", name = "Фонарщик", icon = "🏮", desc = "+2% 💡 за каждый уровень на Маяке", x = 0, z = 2, parents = { "wick", "flint" }, cost = 8000, growth = 1, max = 1, kind = "synergyL", value = 0.02 })
node({ id = "bellows", island = "L", name = "Меха", icon = "💨", desc = "+15 💡/с", x = 2, z = 2, parents = { "flint" }, cost = 800, growth = 1.8, max = 25, kind = "addL", value = 15 })
node({ id = "lens", island = "L", name = "Линза", icon = "🔍", desc = "💡 ×1.2", x = -1, z = 3, parents = { "oil", "lamplighter" }, cost = 30000, growth = 3.5, max = 10, kind = "multL", value = 1.2 })
node({ id = "mirror", island = "L", name = "Зеркала", icon = "🪞", desc = "💡 ×2", x = 1, z = 3, parents = { "lamplighter", "bellows" }, cost = 1e5, growth = 1, max = 1, kind = "multL", value = 2 })
node({ id = "glow", island = "L", name = "Отсвет", icon = "🌟", desc = "💡 растёт от самого 💡", x = 0, z = 4, parents = { "lens", "mirror" }, cost = 1e6, growth = 1, max = 1, kind = "selfL", value = 0.3 })
node({ id = "prism", island = "L", name = "Призма", icon = "🔷", desc = "💡 ×1.25", x = -2, z = 4, parents = { "lens" }, cost = 1.5e6, growth = 4, max = 10, kind = "multL", value = 1.25 })
node({ id = "beacon", island = "L", name = "Ярче маяка", icon = "🗼", desc = "💡 ×3", x = 2, z = 4, parents = { "mirror" }, cost = 8e6, growth = 1, max = 1, kind = "multL", value = 3 })
node({ id = "dawnkey", island = "L", name = "Мост к Заре", icon = "🌉", desc = "Открывает остров Заря", x = 0, z = 5, parents = { "glow" }, cost = 2.5e7, growth = 1, max = 1, kind = "unlock", value = 2 })
node({ id = "twin", island = "L", name = "Двойной фитиль", icon = "🕯", desc = "💡 ×1.6", x = -1, z = 6, parents = { "dawnkey" }, cost = 1e9, growth = 5, max = 5, kind = "multL", value = 1.6 })
node({ id = "comet", island = "L", name = "Комета", icon = "☄", desc = "Падающие звёзды дают ×3", x = 1, z = 6, parents = { "dawnkey" }, cost = 5e9, growth = 1, max = 1, kind = "golden", value = 3 })
node({ id = "dawnwick", island = "L", name = "Фитиль зари", icon = "🌄", desc = "💡 растёт от 🌅", x = 0, z = 7, parents = { "twin", "comet" }, cost = 5e10, growth = 1, max = 1, kind = "fromZ", value = 0.15})
node({ id = "flood", island = "L", name = "Половодье света", icon = "🌊", desc = "💡 ×1.4", x = 0, z = 8, parents = { "dawnwick" }, cost = 5e11, growth = 4, max = 20, kind = "multL", value = 1.4 })

-- Остров 2: Заря (🌅)
node({ id = "morning", island = "Z", name = "Утро", icon = "🌄", desc = "💡 ×1.6", x = 0, z = 0, parents = {}, cost = 1, growth = 2.2, max = 15, kind = "multL", value = 1.6 })
node({ id = "warmth", island = "Z", name = "Тепло", icon = "☀", desc = "💡 растёт от 🌅", x = -1, z = 1, parents = { "morning" }, cost = 4, growth = 1, max = 1, kind = "fromZ", value = 0.25})
node({ id = "autospark", island = "Z", name = "Сам горит", icon = "🤖", desc = "Сам покупает узлы Маяка", x = 1, z = 1, parents = { "morning" }, cost = 2, growth = 1, max = 1, kind = "auto", value = 1 })
node({ id = "zpower", island = "Z", name = "Сила зари", icon = "🔥", desc = "🌅 за сброс ×1.4", x = 0, z = 2, parents = { "warmth", "autospark" }, cost = 6, growth = 3, max = 12, kind = "gainZ", value = 1.4 })
node({ id = "embers", island = "Z", name = "Угли", icon = "🪵", desc = "После Зари сразу 💡 ×1000 стартом", x = 2, z = 2, parents = { "autospark" }, cost = 15, growth = 5, max = 4, kind = "startL", value = 1 })
node({ id = "sunrise", island = "Z", name = "Рассвет", icon = "🌅", desc = "Каждую секунду +1% от 🌅 за сброс", x = -1, z = 3, parents = { "zpower" }, cost = 60, growth = 1, max = 1, kind = "passiveZ", value = 0.01 })
node({ id = "heat", island = "Z", name = "Жар", icon = "♨", desc = "💡 ×2", x = 1, z = 3, parents = { "zpower" }, cost = 150, growth = 3.5, max = 8, kind = "multL", value = 2 })
node({ id = "noon", island = "Z", name = "Полдень", icon = "🌞", desc = "Узлы Маяка дешевле в 10 раз", x = -2, z = 4, parents = { "sunrise" }, cost = 1000, growth = 1, max = 1, kind = "discountL", value = 10 })
node({ id = "starkey", island = "Z", name = "Мост к Звёздам", icon = "🌉", desc = "Открывает остров Звёзды", x = 0, z = 4, parents = { "sunrise", "heat" }, cost = 5000, growth = 1, max = 1, kind = "unlock", value = 3 })
node({ id = "blaze", island = "Z", name = "Зарево", icon = "🔆", desc = "🌅 за сброс ×1.6", x = 0, z = 5, parents = { "starkey" }, cost = 200000, growth = 5, max = 10, kind = "gainZ", value = 1.6 })

-- Остров 3: Звёзды (✦)
node({ id = "starlight", island = "S", name = "Звёздный свет", icon = "⭐", desc = "💡 ×3", x = 0, z = 0, parents = {}, cost = 1, growth = 2.8, max = 15, kind = "multL", value = 3 })
node({ id = "stardawn", island = "S", name = "Звёздная заря", icon = "🌠", desc = "🌅 за сброс ×1.6", x = -1, z = 1, parents = { "starlight" }, cost = 2, growth = 3.5, max = 12, kind = "gainZ", value = 1.6 })
node({ id = "autodawn", island = "S", name = "Вечный рассвет", icon = "🤖", desc = "Сам покупает узлы Зари", x = 1, z = 1, parents = { "starlight" }, cost = 4, growth = 1, max = 1, kind = "auto", value = 2 })
node({ id = "memory", island = "S", name = "Память", icon = "🧠", desc = "Узлы «Сам горит» и «Рассвет» не сбрасываются", x = 0, z = 2, parents = { "stardawn", "autodawn" }, cost = 8, growth = 1, max = 1, kind = "keep", value = 1 })
node({ id = "constellation", island = "S", name = "Созвездие", icon = "✦", desc = "💡 растёт от ✦", x = -2, z = 2, parents = { "stardawn" }, cost = 20, growth = 1, max = 1, kind = "fromS", value = 0.25})
node({ id = "galaxy", island = "S", name = "Галактика", icon = "🌌", desc = "Каждую секунду +0.5% от ✦ за сброс", x = 2, z = 2, parents = { "autodawn" }, cost = 50, growth = 1, max = 1, kind = "passiveS", value = 0.005 })
node({ id = "supernova", island = "S", name = "Сверхновая", icon = "💥", desc = "✦ за сброс ×1.6", x = 0, z = 3, parents = { "memory" }, cost = 100, growth = 3.5, max = 10, kind = "gainS", value = 1.6 })
node({ id = "eclipsekey", island = "S", name = "Мост к Затмению", icon = "🌉", desc = "Открывает остров Затмение", x = 0, z = 4, parents = { "supernova" }, cost = 3000, growth = 1, max = 1, kind = "unlock", value = 4 })

-- Остров 4: Затмение (🌑)
node({ id = "umbra", island = "E", name = "Тень луны", icon = "🌑", desc = "💡 ×20", x = 0, z = 0, parents = {}, cost = 1, growth = 3.5, max = 10, kind = "multL", value = 20 })
node({ id = "corona", island = "E", name = "Корона", icon = "💫", desc = "✦ за сброс ×2", x = -1, z = 1, parents = { "umbra" }, cost = 2, growth = 3.5, max = 10, kind = "gainS", value = 2 })
node({ id = "autostar", island = "E", name = "Звездопад", icon = "🤖", desc = "Сам покупает узлы Звёзд", x = 1, z = 1, parents = { "umbra" }, cost = 3, growth = 1, max = 1, kind = "auto", value = 3 })
node({ id = "totality", island = "E", name = "Полное затмение", icon = "⚫", desc = "🌅 и ✦ за сброс ×4", x = 0, z = 2, parents = { "corona", "autostar" }, cost = 20, growth = 5, max = 5, kind = "gainZS", value = 4 })
node({ id = "lastlight", island = "E", name = "Последний свет", icon = "🌟", desc = "💡 ×1e6. Ты победил тьму!", x = 0, z = 3, parents = { "totality" }, cost = 1000, growth = 1, max = 1, kind = "multL", value = 1e6 })

Config.Nodes = N
Config.NodeById = {} :: { [string]: Node }
for _, n in ipairs(N) do
	Config.NodeById[n.id] = n
end

-- Мировые координаты плитки
function Config.nodePosition(n: Node): Vector3
	local isl = Config.IslandById[n.island]
	local start = isl.radius * -0.55 -- дерево растёт от дальнего края к ближнему
	return isl.center + Vector3.new(n.x * Config.TILE_STEP, 0, start + n.z * Config.TILE_STEP)
end

function Config.lvl(d: Data, id: string): number
	return d.nodes[id] or 0
end

function Config.isAvailable(d: Data, n: Node): boolean
	if #n.parents == 0 then
		return Config.islandOpen(d, n.island)
	end
	for _, p in ipairs(n.parents) do
		if Config.lvl(d, p) > 0 then
			return true
		end
	end
	return false
end

function Config.islandOpen(d: Data, id: string): boolean
	if id == "L" then
		return true
	elseif id == "Z" then
		return Config.lvl(d, "dawnkey") > 0 or (d.resets.Z or 0) > 0 or (d.resets.S or 0) > 0 or (d.resets.E or 0) > 0
	elseif id == "S" then
		return Config.lvl(d, "starkey") > 0 or (d.resets.S or 0) > 0 or (d.resets.E or 0) > 0
	elseif id == "E" then
		return Config.lvl(d, "eclipsekey") > 0 or (d.resets.E or 0) > 0
	end
	return false
end

function Config.nodeCost(d: Data, n: Node): number
	local c = n.cost * n.growth ^ Config.lvl(d, n.id)
	if n.island == "L" and Config.lvl(d, "noon") > 0 then
		c /= 10
	end
	return math.ceil(c)
end

function Config.canBuy(d: Data, n: Node): boolean
	return Config.isAvailable(d, n) and Config.lvl(d, n.id) < n.max and (d.cur[n.island] or 0) >= Config.nodeCost(d, n)
end

--------------------------------------------------------------------------------
-- Формулы
--------------------------------------------------------------------------------
local function sumKind(d: Data, kind: string, island: string?): number
	local s = 0
	for _, n in ipairs(Config.Nodes) do
		if n.kind == kind and (island == nil or n.island == island) then
			s += n.value * Config.lvl(d, n.id)
		end
	end
	return s
end

local function prodKind(d: Data, kind: string): number
	local m = 1
	for _, n in ipairs(Config.Nodes) do
		if n.kind == kind then
			local l = Config.lvl(d, n.id)
			if l > 0 then
				m *= n.value ^ l
			end
		end
	end
	return m
end

function Config.islandLevels(d: Data, island: string): number
	local s = 0
	for _, n in ipairs(Config.Nodes) do
		if n.island == island then
			s += Config.lvl(d, n.id)
		end
	end
	return s
end

function Config.Lps(d: Data): number
	local base = 1 + sumKind(d, "addL")
	local m = prodKind(d, "multL")
	local syn = sumKind(d, "synergyL")
	if syn > 0 then
		m *= 1 + syn * Config.islandLevels(d, "L")
	end
	local selfL = sumKind(d, "selfL")
	if selfL > 0 then
		m *= 1 + math.log10((d.cur.L or 0) + 1) * selfL
	end
	local fz = sumKind(d, "fromZ")
	if fz > 0 then
		m *= (1 + (d.cur.Z or 0)) ^ fz
	end
	local fs = sumKind(d, "fromS")
	if fs > 0 then
		m *= (1 + (d.cur.S or 0)) ^ fs
	end
	-- каждая Заря/Звезда/Затмение за всё время немного усиливают свет
	m *= 1 + 0.1 * (d.total.Z or 0) ^ 0.5
	return base * m
end

function Config.goldenMult(d: Data): number
	return prodKind(d, "golden")
end

-- Сколько валюты даст сброс
function Config.gainZ(d: Data): number
	if not Config.islandOpen(d, "Z") then
		return 0
	end
	local g = (d.run.L / 2e6) ^ 0.4
	g *= prodKind(d, "gainZ") * prodKind(d, "gainZS")
	return math.floor(g)
end

function Config.gainS(d: Data): number
	if not Config.islandOpen(d, "S") then
		return 0
	end
	local g = (d.run.Z / 3000) ^ 0.4
	g *= prodKind(d, "gainS") * prodKind(d, "gainZS")
	return math.floor(g)
end

function Config.gainE(d: Data): number
	if not Config.islandOpen(d, "E") then
		return 0
	end
	return math.floor((d.run.S / 500) ^ 0.4)
end

function Config.passiveZ(d: Data): number
	return sumKind(d, "passiveZ")
end

function Config.passiveS(d: Data): number
	return sumKind(d, "passiveS")
end

function Config.autoLevel(d: Data): number
	local a = 0
	for _, n in ipairs(Config.Nodes) do
		if n.kind == "auto" and Config.lvl(d, n.id) > 0 then
			a = math.max(a, n.value)
		end
	end
	return a
end

function Config.startL(d: Data): number
	local l = sumKind(d, "startL")
	return l > 0 and 1000 ^ l or 0
end

-- Что остаётся при сбросе слоя: возвращает новые уровни узлов
function Config.applyReset(d: Data, layer: string)
	local wipe: { [string]: boolean } = { L = true }
	if layer == "S" or layer == "E" then
		wipe.Z = true
	end
	if layer == "E" then
		wipe.S = true
	end
	local keep = Config.lvl(d, "memory") > 0
	for _, n in ipairs(Config.Nodes) do
		if wipe[n.island] then
			local saved = keep and (n.id == "autospark" or n.id == "sunrise")
			-- мосты к уже открытым островам не теряются
			if not saved and n.kind ~= "unlock" then
				d.nodes[n.id] = nil
			end
		end
	end
	d.cur.L = 0
	d.run.L = 0
	if wipe.Z then
		d.cur.Z = 0
		d.run.Z = 0
	end
	if wipe.S then
		d.cur.S = 0
		d.run.S = 0
	end
	d.cur.L = Config.startL(d)
end

--------------------------------------------------------------------------------
-- Падающие звёзды (бонус, который ловишь ногами)
--------------------------------------------------------------------------------
Config.GOLDEN_MIN = 35
Config.GOLDEN_MAX = 70
Config.GOLDEN_SECONDS = 60 -- сколько секунд дохода даёт звезда

Config.OFFLINE_RATE = 0.5
Config.OFFLINE_MAX = 4 * 3600

--------------------------------------------------------------------------------
-- Форматирование
--------------------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "De", "UDe", "DDe", "TDe", "QaDe", "QiDe", "SxDe", "SpDe", "OcDe", "NoDe", "Vg" }

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
