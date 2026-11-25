-- Сервер «Маяк во Тьме»: экономика, свет, тени, находки, созвездия, новая заря, сохранение.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local World = require(script:WaitForChild("World"))

type Data = Config.Data

--------------------------------------------------------------------------------
-- Хранилища
--------------------------------------------------------------------------------
local store: DataStore? = nil
local topStore: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore("Lighthouse_v1")
		topStore = DataStoreService:GetOrderedDataStore("Lighthouse_Top_v1")
	end)
	if not ok then
		warn("DataStore недоступен:", err)
	end
end

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local R = {
	Ignite = remote("Ignite"),
	BuyUp = remote("BuyUp"),
	BuyRUp = remote("BuyRUp"),
	Roll = remote("Roll"),
	Rebirth = remote("Rebirth"),
	Toggle = remote("Toggle"),
	Teleport = remote("Teleport"),
	Fight = remote("Fight"),
	Collect = remote("Collect"),
	State = remote("State"),
	Event = remote("Event"),
}
remotes.Parent = ReplicatedStorage

local world = World.build()

--------------------------------------------------------------------------------
-- Сессии
--------------------------------------------------------------------------------
type Fight = { zone: number, hp: number, maxHp: number, timeLeft: number }
type Pickup = { zone: number, pos: Vector3 }

type Session = {
	player: Player,
	data: Data,
	income: number,
	fight: Fight?,
	pickups: { [string]: Pickup },
	pickupCount: number,
	pickupTimer: number,
	autoLightTimer: number,
	autoPickTimer: number,
	lastAction: number,
	actions: number,
	loaded: boolean,
	ready: boolean,
}

local sessions: { [Player]: Session } = {}

local function num(v: any): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge then
		return 0
	end
	return math.max(0, n)
end

local function sanitize(saved: any): Data
	local d = Config.newData()
	if type(saved) ~= "table" then
		return d
	end
	d.coins = num(saved.coins)
	d.totalCoins = num(saved.totalCoins)
	d.light = math.clamp(math.floor(num(saved.light)), 0, Config.MAX_LIGHT)
	d.bestLight = math.clamp(math.floor(num(saved.bestLight)), 0, Config.MAX_LIGHT)
	d.bosses = math.clamp(math.floor(num(saved.bosses)), 0, #Config.Zones)
	d.dust = math.floor(num(saved.dust))
	d.dustEver = math.floor(num(saved.dustEver))
	d.rebirths = math.floor(num(saved.rebirths))
	d.picks = math.floor(num(saved.picks))
	d.rolls = math.floor(num(saved.rolls))
	d.playTime = num(saved.playTime)
	d.autoLight = saved.autoLight ~= false
	d.autoPick = saved.autoPick ~= false
	d.lastOnline = tonumber(saved.lastOnline)
	if type(saved.title) == "string" and Config.TitleById[saved.title] then
		d.title = saved.title
	end
	if type(saved.ups) == "table" then
		for id, lvl in pairs(saved.ups) do
			local u = Config.UpById[id]
			if u then
				d.ups[id] = math.min(u.maxLevel, math.floor(num(lvl)))
			end
		end
	end
	if type(saved.rups) == "table" then
		for id, lvl in pairs(saved.rups) do
			local r = Config.RUpById[id]
			if r then
				d.rups[id] = math.min(r.maxLevel, math.floor(num(lvl)))
			end
		end
	end
	if type(saved.relics) == "table" then
		for id, e in pairs(saved.relics) do
			if Config.RelicById[id] and type(e) == "table" then
				d.relics[id] = { n = math.floor(num(e.n)), s = math.floor(num(e.s)) }
			end
		end
	end
	if type(saved.titles) == "table" then
		for id, n in pairs(saved.titles) do
			if Config.TitleById[id] then
				d.titles[id] = math.floor(num(n))
			end
		end
	end
	return d
end

local function recompute(s: Session)
	s.income = Config.income(s.data)
end

local function event(s: Session, kind: string, ...)
	R.Event:FireClient(s.player, kind, ...)
end

local function sendState(s: Session)
	local d = s.data
	local f = s.fight
	R.State:FireClient(s.player, {
		coins = d.coins,
		totalCoins = d.totalCoins,
		light = d.light,
		bestLight = d.bestLight,
		bosses = d.bosses,
		ups = d.ups,
		relics = d.relics,
		titles = d.titles,
		title = d.title,
		dust = d.dust,
		dustEver = d.dustEver,
		rebirths = d.rebirths,
		rups = d.rups,
		picks = d.picks,
		rolls = d.rolls,
		playTime = d.playTime,
		autoLight = d.autoLight,
		autoPick = d.autoPick,
		income = s.income,
		fight = f and { zone = f.zone, hp = f.hp, maxHp = f.maxHp, timeLeft = f.timeLeft } or nil,
	})
end

local function addCoins(s: Session, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	s.data.coins += amount
	s.data.totalCoins += amount
end

local function setLeaderstats(s: Session)
	local ls = s.player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local l = ls:FindFirstChild("💡 Свет") :: IntValue?
	if l then
		l.Value = s.data.light
	end
	local r = ls:FindFirstChild("🌅 Зори") :: IntValue?
	if r then
		r.Value = s.data.rebirths
	end
end

local function updateNameplate(s: Session)
	local char = s.player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = head:FindFirstChild("TitleTag") :: BillboardGui?
	if not bb then
		local newBB = Instance.new("BillboardGui")
		newBB.Name = "TitleTag"
		newBB.Size = UDim2.fromOffset(220, 30)
		newBB.StudsOffset = Vector3.new(0, 2.6, 0)
		newBB.MaxDistance = 80
		newBB.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextStrokeTransparency = 0.2
		t.Parent = newBB
		newBB.Parent = head
		bb = newBB
	end
	local label = (bb :: BillboardGui):FindFirstChild("Text") :: TextLabel
	local title = s.data.title and Config.TitleById[s.data.title]
	if title then
		label.Text = "✦ " .. title.name
		label.TextColor3 = title.color
	else
		label.Text = ""
	end
end

--------------------------------------------------------------------------------
-- Сохранение и топ
--------------------------------------------------------------------------------
local function save(player: Player)
	local s = sessions[player]
	if not s or not s.loaded or not store then
		return
	end
	local d = s.data
	local payload = {
		coins = d.coins,
		totalCoins = d.totalCoins,
		light = d.light,
		bestLight = d.bestLight,
		bosses = d.bosses,
		ups = d.ups,
		relics = d.relics,
		titles = d.titles,
		title = d.title,
		dust = d.dust,
		dustEver = d.dustEver,
		rebirths = d.rebirths,
		rups = d.rups,
		picks = d.picks,
		rolls = d.rolls,
		playTime = d.playTime,
		autoLight = d.autoLight,
		autoPick = d.autoPick,
		lastOnline = os.time(),
	}
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("p_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Не удалось сохранить", player.Name, err)
	end
	if topStore and d.bestLight > 0 then
		pcall(function()
			(topStore :: OrderedDataStore):SetAsync("u_" .. player.UserId, d.bestLight)
		end)
	end
end

local nameCache: { [number]: string } = {}
local function refreshLeaderboard()
	if not topStore then
		World.setLeaderboard({})
		return
	end
	local ok, pages = pcall(function()
		return (topStore :: OrderedDataStore):GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		return
	end
	local rows = {}
	for _, entry in ipairs((pages :: DataStorePages):GetCurrentPage()) do
		local uid = tonumber(string.sub(entry.key, 3))
		if uid then
			local name = nameCache[uid]
			if not name then
				local okName, n = pcall(function()
					return Players:GetNameFromUserIdAsync(uid)
				end)
				name = okName and n or ("Игрок " .. uid)
				nameCache[uid] = name
			end
			table.insert(rows, { name = name :: string, value = entry.value })
		end
	end
	World.setLeaderboard(rows)
end

--------------------------------------------------------------------------------
-- Телепорты
--------------------------------------------------------------------------------
local function edgeCFrame(d: Data, angle: number): CFrame
	local r = math.max(Config.radius(d.light) - 8, 14)
	local pos = Vector3.new(math.cos(angle) * r, 4, math.sin(angle) * r)
	local out = Vector3.new(math.cos(angle) * (r + 10), 4, math.sin(angle) * (r + 10))
	return CFrame.lookAt(pos, out)
end

local function teleport(s: Session, where: string)
	local char = s.player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end
	if where == "edge" then
		local zone = math.min(s.data.bosses + 1, #Config.Zones)
		char:PivotTo(edgeCFrame(s.data, Config.bossAngle(zone)))
	else
		char:PivotTo(world.spawnCFrame)
	end
end

--------------------------------------------------------------------------------
-- Вход / выход
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local lv = Instance.new("IntValue")
	lv.Name = "💡 Свет"
	lv.Parent = ls
	local rv = Instance.new("IntValue")
	rv.Name = "🌅 Зори"
	rv.Parent = ls
	ls.Parent = player

	local s: Session = {
		player = player,
		data = Config.newData(),
		income = 1,
		fight = nil,
		pickups = {},
		pickupCount = 0,
		pickupTimer = 3,
		autoLightTimer = 0,
		autoPickTimer = 0,
		lastAction = 0,
		actions = 0,
		loaded = false,
		ready = false,
	}
	sessions[player] = s

	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 10)
		updateNameplate(s)
	end)

	local saved = nil
	local loadedOk = true
	if store then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync("p_" .. player.UserId)
		end)
		if ok then
			saved = result
		else
			loadedOk = false
			warn("Не удалось загрузить", player.Name, result)
		end
	end
	if not player.Parent then
		return
	end
	s.data = sanitize(saved)
	s.loaded = loadedOk
	recompute(s)
	s.ready = true
	setLeaderstats(s)
	updateNameplate(s)

	local d = s.data
	if d.lastOnline then
		local away = os.time() - d.lastOnline
		local earned = s.income * math.clamp(away, 0, Config.OFFLINE_MAX) * Config.OFFLINE_RATE
		if away >= 60 and earned >= 1 then
			addCoins(s, earned)
			task.delay(2, function()
				if player.Parent then
					event(s, "offline", earned, away)
				end
			end)
		end
	else
		task.delay(2, function()
			if player.Parent then
				event(s, "welcome")
			end
		end)
	end
	if not loadedOk then
		event(s, "message", "⚠ Не удалось загрузить сохранение. Прогресс этой сессии не сохранится — перезайди позже.")
	end
	sendState(s)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			save(player)
			pending -= 1
		end)
	end
	local t = os.clock()
	while pending > 0 and os.clock() - t < 25 do
		task.wait(0.1)
	end
end)

local function allow(s: Session?): boolean
	if not s or not s.ready then
		return false
	end
	local now = os.clock()
	if now - s.lastAction > 1 then
		s.lastAction = now
		s.actions = 0
	end
	s.actions += 1
	return s.actions <= 25
end

--------------------------------------------------------------------------------
-- Свет
--------------------------------------------------------------------------------
local function setLight(s: Session, n: number)
	s.data.light = n
	if n > s.data.bestLight then
		s.data.bestLight = n
	end
end

local function buyLight(s: Session, limit: number): number
	local bought = 0
	local d = s.data
	while bought < limit do
		local ok = Config.canBuyLight(d)
		if not ok then
			break
		end
		local cost = Config.lightCost(d, d.light + 1)
		if d.coins < cost then
			break
		end
		d.coins -= cost
		setLight(s, d.light + 1)
		bought += 1
		local n = d.light
		if n % Config.LEVELS_PER_ZONE == 0 then
			event(s, "bossReached", Config.zoneOfLevel(n))
		elseif n % Config.LEVELS_PER_ZONE == 1 then
			event(s, "newZone", Config.zoneOfLevel(n))
		end
	end
	if bought > 0 then
		recompute(s)
	end
	return bought
end

R.Ignite.OnServerEvent:Connect(function(player, mode)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	if buyLight(ses, mode == "max" and 1000 or 1) > 0 then
		sendState(ses)
	end
end)

--------------------------------------------------------------------------------
-- Постройки
--------------------------------------------------------------------------------
R.BuyUp.OnServerEvent:Connect(function(player, id, mode)
	local s = sessions[player]
	local u = type(id) == "string" and Config.UpById[id] or nil
	if not allow(s) or not u then
		return
	end
	local ses = s :: Session
	local d = ses.data
	if d.bosses < u.needBoss then
		return
	end
	local count = 0
	local limit = mode == "max" and 1000 or 1
	while count < limit do
		local lvl = Config.lvl(d, u.id)
		if lvl >= u.maxLevel then
			break
		end
		local cost = Config.upCost(u, lvl)
		if d.coins < cost then
			break
		end
		d.coins -= cost
		d.ups[u.id] = lvl + 1
		count += 1
	end
	if count > 0 then
		recompute(ses)
		event(ses, "upgraded", u.id, Config.lvl(d, u.id))
		sendState(ses)
	end
end)

R.BuyRUp.OnServerEvent:Connect(function(player, id)
	local s = sessions[player]
	local r = type(id) == "string" and Config.RUpById[id] or nil
	if not allow(s) or not r then
		return
	end
	local ses = s :: Session
	local d = ses.data
	local lvl = Config.rlvl(d, r.id)
	if lvl >= r.maxLevel then
		return
	end
	local cost = Config.rupCost(r, lvl)
	if d.dust < cost then
		return
	end
	d.dust -= cost
	d.rups[r.id] = lvl + 1
	recompute(ses)
	event(ses, "message", string.format("✦ %s — уровень %d", r.name, lvl + 1))
	sendState(ses)
end)

R.Toggle.OnServerEvent:Connect(function(player, which)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	if which == "autoLight" then
		ses.data.autoLight = not ses.data.autoLight
	elseif which == "autoPick" then
		ses.data.autoPick = not ses.data.autoPick
	end
	sendState(ses)
end)

R.Teleport.OnServerEvent:Connect(function(player, where)
	local s = sessions[player]
	if allow(s) and type(where) == "string" then
		teleport(s :: Session, where)
	end
end)

--------------------------------------------------------------------------------
-- Созвездия
--------------------------------------------------------------------------------
local lastRoll: { [Player]: number } = {}
local function tryRoll(player: Player)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local now = os.clock()
	if now - (lastRoll[player] or 0) < 0.6 then
		return
	end
	lastRoll[player] = now
	local ses = s :: Session
	local d = ses.data
	local cost = Config.titleRollCost(d)
	if d.coins < cost then
		event(ses, "message", "Не хватает сияния: нужно 💡 " .. Config.format(cost))
		return
	end
	d.coins -= cost
	d.rolls += 1
	local t = Config.rollTitle(Config.luck(d), math.random)
	d.titles[t.id] = (d.titles[t.id] or 0) + 1
	local better = Config.titleMult(d) < t.mult
	if better then
		d.title = t.id
		updateNameplate(ses)
		recompute(ses)
	end
	event(ses, "title", t.id, better)
	sendState(ses)
end
R.Roll.OnServerEvent:Connect(tryRoll)
world.rollPrompt.Triggered:Connect(tryRoll)

--------------------------------------------------------------------------------
-- Находки на земле
--------------------------------------------------------------------------------
local function clearPickups(s: Session)
	s.pickups = {}
	s.pickupCount = 0
	event(s, "pickupsClear")
end

local function spawnPickup(s: Session)
	local d = s.data
	local radius = Config.radius(d.light)
	local deepest = Config.litZones(d.light)
	-- половина находок — в самой дальней освещённой зоне, остальные — в любой
	local zone = math.random() < 0.5 and deepest or math.random(1, deepest)
	local inner, outer = Config.zoneRange(zone)
	inner = math.max(inner + 2, 26)
	outer = math.min(outer - 2, radius - 4)
	if outer <= inner then
		zone = math.max(1, zone - 1)
		inner, outer = Config.zoneRange(zone)
		inner = math.max(inner + 2, 26)
		outer = math.min(outer - 2, radius - 4)
		if outer <= inner then
			return
		end
	end
	local a = math.random() * math.pi * 2
	local r = inner + math.random() * (outer - inner)
	local pos = Vector3.new(math.cos(a) * r, 2.2, math.sin(a) * r)
	local token = HttpService:GenerateGUID(false)
	s.pickups[token] = { zone = zone, pos = pos }
	s.pickupCount += 1
	event(s, "pickupSpawn", token, pos, zone)
end

local function collect(s: Session, token: string, auto: boolean): boolean
	local p = s.pickups[token]
	if not p then
		return false
	end
	if not auto then
		local char = s.player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - p.pos).Magnitude > 16 then
			return false
		end
	end
	s.pickups[token] = nil
	s.pickupCount -= 1
	local d = s.data
	d.picks += 1
	local relic = Config.rollRelic(p.zone, Config.luck(d), math.random)
	local shiny = math.random() < Config.shinyChance(d)
	local entry = d.relics[relic.id]
	local isNew = entry == nil
	if not entry then
		entry = { n = 0, s = 0 }
		d.relics[relic.id] = entry
	end
	local e = entry :: { n: number, s: number }
	e.n += 1
	if shiny then
		e.s += 1
	end
	recompute(s)
	event(s, "relic", relic.id, shiny, isNew, auto, token)
	return true
end

R.Collect.OnServerEvent:Connect(function(player, token)
	local s = sessions[player]
	if not allow(s) or type(token) ~= "string" then
		return
	end
	if collect(s :: Session, token, false) then
		sendState(s :: Session)
	end
end)

--------------------------------------------------------------------------------
-- Бои с тенями
--------------------------------------------------------------------------------
R.Fight.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	local d = ses.data
	local zone = d.bosses + 1
	if ses.fight or zone > #Config.Zones then
		return
	end
	if d.light < Config.bossLevel(zone) then
		event(ses, "message", "Сначала дотяни свет до тени")
		return
	end
	local hp = Config.bossHP(zone)
	ses.fight = { zone = zone, hp = hp, maxHp = hp, timeLeft = Config.fightDuration(d) }
	event(ses, "fightStart", zone)
	sendState(ses)
end)

local function tickFight(s: Session, dt: number)
	local f = s.fight
	if not f then
		return
	end
	local d = s.data
	local dmg = Config.damagePerSec(d) * dt
	if math.random() < Config.critChance(d) then
		dmg *= 5
	end
	f.hp -= dmg
	f.timeLeft -= dt
	if f.hp <= 0 then
		s.fight = nil
		d.bosses = math.max(d.bosses, f.zone)
		local reward = Config.lightCost(d, Config.bossLevel(f.zone)) * 3
		addCoins(s, reward)
		recompute(s)
		event(s, "fightWon", f.zone, reward)
		sendState(s)
	elseif f.timeLeft <= 0 then
		s.fight = nil
		event(s, "fightLost", f.zone, f.hp / f.maxHp)
		sendState(s)
	end
end

--------------------------------------------------------------------------------
-- Новая заря
--------------------------------------------------------------------------------
R.Rebirth.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	local d = ses.data
	local gain = Config.dustOnRebirth(d)
	if gain < 1 then
		return
	end
	d.dust += gain
	d.dustEver += gain
	d.rebirths += 1
	d.coins = 0
	d.ups = {}
	d.bosses = 0
	ses.fight = nil
	setLight(ses, math.min(10 * Config.rlvl(d, "r_start"), Config.LEVELS_PER_ZONE - 1))
	recompute(ses)
	clearPickups(ses)
	setLeaderstats(ses)
	event(ses, "rebirth", gain)
	sendState(ses)
	teleport(ses, "home")
	task.spawn(save, player)
end)

--------------------------------------------------------------------------------
-- Главный цикл
--------------------------------------------------------------------------------
local TICK = 0.2
local stateTimer, slowTimer = 0, 0

task.spawn(function()
	while true do
		local dt = task.wait(TICK)
		stateTimer += dt
		slowTimer += dt
		for _, s in pairs(sessions) do
			if s.ready then
				local d = s.data
				d.playTime += dt
				addCoins(s, s.income * dt)
				tickFight(s, dt)

				s.pickupTimer -= dt
				if s.pickupTimer <= 0 then
					s.pickupTimer = Config.pickupInterval(d)
					if s.pickupCount < Config.maxPickups(d) then
						spawnPickup(s)
					end
				end

				s.autoLightTimer += dt
				if s.autoLightTimer >= 1 then
					s.autoLightTimer = 0
					if Config.rlvl(d, "r_autolight") >= 1 and d.autoLight then
						buyLight(s, 50)
					end
				end
				s.autoPickTimer += dt
				if s.autoPickTimer >= 3 then
					s.autoPickTimer = 0
					if Config.rlvl(d, "r_autopick") >= 1 and d.autoPick then
						local token = next(s.pickups)
						if token then
							collect(s, token, true)
						end
					end
				end
			end
		end
		if stateTimer >= 0.5 then
			stateTimer = 0
			for _, s in pairs(sessions) do
				if s.ready then
					sendState(s)
					setLeaderstats(s)
				end
			end
		end
		if slowTimer >= 90 then
			slowTimer = 0
			for player in pairs(sessions) do
				task.spawn(save, player)
			end
			task.spawn(refreshLeaderboard)
		end
	end
end)

task.delay(5, refreshLeaderboard)
