-- Сервер «В Бездну»: экономика, ступени, стражи, раскопки, звания, перерождение, сохранение.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

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
		store = DataStoreService:GetDataStore("Abyss_v1")
		topStore = DataStoreService:GetOrderedDataStore("Abyss_Top_v1")
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
	BuyStep = remote("BuyStep"),
	BuyUp = remote("BuyUp"),
	BuyRUp = remote("BuyRUp"),
	Roll = remote("Roll"),
	Rebirth = remote("Rebirth"),
	Toggle = remote("Toggle"),
	Teleport = remote("Teleport"),
	Fight = remote("Fight"),
	Dig = remote("Dig"),
	State = remote("State"),
	Event = remote("Event"),
}
remotes.Parent = ReplicatedStorage

local world = World.build()

--------------------------------------------------------------------------------
-- Сессии
--------------------------------------------------------------------------------
type Fight = { layer: number, hp: number, maxHp: number, timeLeft: number }

type Session = {
	player: Player,
	data: Data,
	income: number,
	fight: Fight?,
	lastAction: number,
	actions: number,
	autoStepTimer: number,
	autoDigTimer: number,
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
	d.step = math.clamp(math.floor(num(saved.step)), 0, Config.MAX_STEP)
	d.bestStep = math.clamp(math.floor(num(saved.bestStep)), 0, Config.MAX_STEP)
	d.bosses = math.clamp(math.floor(num(saved.bosses)), 0, #Config.Layers)
	d.tokens = math.floor(num(saved.tokens))
	d.tokensEver = math.floor(num(saved.tokensEver))
	d.rebirths = math.floor(num(saved.rebirths))
	d.digs = math.floor(num(saved.digs))
	d.rolls = math.floor(num(saved.rolls))
	d.playTime = num(saved.playTime)
	d.autoStep = saved.autoStep ~= false
	d.autoDig = saved.autoDig ~= false
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
		step = d.step,
		bestStep = d.bestStep,
		bosses = d.bosses,
		ups = d.ups,
		relics = d.relics,
		titles = d.titles,
		title = d.title,
		tokens = d.tokens,
		tokensEver = d.tokensEver,
		rebirths = d.rebirths,
		rups = d.rups,
		digs = d.digs,
		rolls = d.rolls,
		playTime = d.playTime,
		autoStep = d.autoStep,
		autoDig = d.autoDig,
		income = s.income,
		fight = f and { layer = f.layer, hp = f.hp, maxHp = f.maxHp, timeLeft = f.timeLeft } or nil,
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
	local st = ls:FindFirstChild("⬇ Глубина") :: IntValue?
	if st then
		st.Value = s.data.step
	end
	local rb = ls:FindFirstChild("🔁 Перерожд.") :: IntValue?
	if rb then
		rb.Value = s.data.rebirths
	end
end

-- Звание над головой
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
		label.Text = "🎖 " .. title.name
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
		step = d.step,
		bestStep = d.bestStep,
		bosses = d.bosses,
		ups = d.ups,
		relics = d.relics,
		titles = d.titles,
		title = d.title,
		tokens = d.tokens,
		tokensEver = d.tokensEver,
		rebirths = d.rebirths,
		rups = d.rups,
		digs = d.digs,
		rolls = d.rolls,
		playTime = d.playTime,
		autoStep = d.autoStep,
		autoDig = d.autoDig,
		lastOnline = os.time(),
	}
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("p_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Не удалось сохранить", player.Name, err)
	end
	if topStore and d.bestStep > 0 then
		pcall(function()
			(topStore :: OrderedDataStore):SetAsync("u_" .. player.UserId, d.bestStep)
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
-- Вход / выход
--------------------------------------------------------------------------------
local function teleport(s: Session, where: string)
	local char = s.player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end
	if where == "edge" and s.data.step > 0 then
		char:PivotTo(World.standCFrame(s.data.step))
	elseif where == "boss" then
		local layer = s.data.bosses + 1
		if layer <= #Config.Layers and s.data.step >= Config.bossStep(layer) then
			char:PivotTo(World.standCFrame(Config.bossStep(layer)))
		end
	elseif where == "dig" then
		local layer = Config.layerOfStep(s.data.step)
		if s.data.step < Config.digSiteStep(layer) then
			layer -= 1
		end
		if layer >= 1 then
			char:PivotTo(World.standCFrame(Config.digSiteStep(layer) - 1))
		end
	else
		char:PivotTo(world.spawnCFrame)
	end
end

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local depth = Instance.new("IntValue")
	depth.Name = "⬇ Глубина"
	depth.Parent = ls
	local reb = Instance.new("IntValue")
	reb.Name = "🔁 Перерожд."
	reb.Parent = ls
	ls.Parent = player

	local s: Session = {
		player = player,
		data = Config.newData(),
		income = 1,
		fight = nil,
		lastAction = 0,
		actions = 0,
		autoStepTimer = 0,
		autoDigTimer = 0,
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
	player:SetAttribute("Step", s.data.step)

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

--------------------------------------------------------------------------------
-- Защита от спама
--------------------------------------------------------------------------------
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
-- Ступени
--------------------------------------------------------------------------------
local function setStep(s: Session, n: number)
	s.data.step = n
	if n > s.data.bestStep then
		s.data.bestStep = n
	end
	s.player:SetAttribute("Step", n)
end

local function buySteps(s: Session, limit: number): number
	local bought = 0
	local d = s.data
	while bought < limit do
		local ok = Config.canBuyStep(d)
		if not ok then
			break
		end
		local cost = Config.stepCost(d, d.step + 1)
		if d.coins < cost then
			break
		end
		d.coins -= cost
		setStep(s, d.step + 1)
		bought += 1
		local n = d.step
		if n % Config.STEPS_PER_LAYER == 0 then
			event(s, "bossReached", Config.layerOfStep(n))
		elseif n % Config.STEPS_PER_LAYER == 1 and n > 1 then
			event(s, "newLayer", Config.layerOfStep(n))
		elseif n == Config.digSiteStep(Config.layerOfStep(n)) then
			event(s, "digUnlocked", Config.layerOfStep(n))
		end
	end
	if bought > 0 then
		recompute(s)
	end
	return bought
end

R.BuyStep.OnServerEvent:Connect(function(player, mode)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	if buySteps(ses, mode == "max" and 1000 or 1) > 0 then
		sendState(ses)
	end
end)

--------------------------------------------------------------------------------
-- Улучшения
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
		event(ses, "upgraded", u.id, count)
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
	if d.tokens < cost then
		return
	end
	d.tokens -= cost
	d.rups[r.id] = lvl + 1
	recompute(ses)
	event(ses, "message", string.format("💠 %s — уровень %d", r.name, lvl + 1))
	sendState(ses)
end)

R.Toggle.OnServerEvent:Connect(function(player, which)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	if which == "autoStep" then
		ses.data.autoStep = not ses.data.autoStep
	elseif which == "autoDig" then
		ses.data.autoDig = not ses.data.autoDig
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
-- Звания
--------------------------------------------------------------------------------
local function roll(s: Session)
	local d = s.data
	local cost = Config.titleRollCost(d)
	if d.coins < cost then
		event(s, "message", "Не хватает монет на бросок: нужно 💰 " .. Config.format(cost))
		return
	end
	d.coins -= cost
	d.rolls += 1
	local t = Config.rollTitle(Config.luck(d), math.random)
	d.titles[t.id] = (d.titles[t.id] or 0) + 1
	local better = Config.titleMult(d) < t.mult
	if better then
		d.title = t.id
		updateNameplate(s)
		recompute(s)
	end
	event(s, "title", t.id, better)
	sendState(s)
end

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
	roll(s :: Session)
end
R.Roll.OnServerEvent:Connect(tryRoll)
local altarPrompt = world.altar:FindFirstChildOfClass("ProximityPrompt")
if altarPrompt then
	altarPrompt.Triggered:Connect(tryRoll)
end

--------------------------------------------------------------------------------
-- Раскопки
--------------------------------------------------------------------------------
local function dig(s: Session, layer: number, auto: boolean): boolean
	local d = s.data
	if layer < 1 or layer > #Config.Layers or d.step < Config.digSiteStep(layer) then
		return false
	end
	local cost = Config.digCost(d, layer)
	if d.coins < cost then
		if not auto then
			event(s, "message", "Не хватает монет на раскопки: нужно 💰 " .. Config.format(cost))
		end
		return false
	end
	d.coins -= cost
	d.digs += 1
	local relic = Config.rollRelic(layer, Config.luck(d), math.random)
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
	event(s, "relic", relic.id, shiny, isNew, auto)
	return true
end

local function deepestDigLayer(d: Data): number
	local layer = Config.layerOfStep(d.step)
	if d.step < Config.digSiteStep(layer) then
		layer -= 1
	end
	return layer
end

for _, site in ipairs(world.digs) do
	site.prompt.Triggered:Connect(function(player)
		local s = sessions[player]
		if not allow(s) then
			return
		end
		local ses = s :: Session
		if ses.data.step < Config.digSiteStep(site.layer) then
			event(ses, "message", "Этот раскоп откроется, когда дойдёшь до ступени " .. Config.digSiteStep(site.layer))
			return
		end
		if dig(ses, site.layer, false) then
			sendState(ses)
		end
	end)
end

R.Dig.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	local layer = deepestDigLayer(ses.data)
	if layer < 1 then
		event(ses, "message", "Первый раскоп — на ступени " .. Config.digSiteStep(1))
		return
	end
	if dig(ses, layer, false) then
		sendState(ses)
	end
end)

--------------------------------------------------------------------------------
-- Бои со стражами
--------------------------------------------------------------------------------
local function startFight(s: Session, layer: number)
	local d = s.data
	if s.fight then
		return
	end
	if d.bosses ~= layer - 1 or d.step < Config.bossStep(layer) then
		event(s, "message", "Сначала дойди до стража этого слоя")
		return
	end
	local hp = Config.bossHP(layer)
	s.fight = { layer = layer, hp = hp, maxHp = hp, timeLeft = Config.fightDuration(d) }
	event(s, "fightStart", layer)
	sendState(s)
end

for _, boss in ipairs(world.bosses) do
	boss.prompt.Triggered:Connect(function(player)
		local s = sessions[player]
		if allow(s) then
			startFight(s :: Session, boss.layer)
		end
	end)
end

R.Fight.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	startFight(ses, ses.data.bosses + 1)
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
		d.bosses = math.max(d.bosses, f.layer)
		local reward = Config.stepCost(d, Config.bossStep(f.layer)) * 3
		addCoins(s, reward)
		recompute(s)
		event(s, "fightWon", f.layer, reward)
		sendState(s)
	elseif f.timeLeft <= 0 then
		s.fight = nil
		event(s, "fightLost", f.layer, f.hp / f.maxHp)
		sendState(s)
	end
end

--------------------------------------------------------------------------------
-- Перерождение
--------------------------------------------------------------------------------
R.Rebirth.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	local d = ses.data
	local gain = Config.tokensOnRebirth(d)
	if gain < 1 then
		return
	end
	d.tokens += gain
	d.tokensEver += gain
	d.rebirths += 1
	d.coins = 0
	d.ups = {}
	d.bosses = 0
	ses.fight = nil
	setStep(ses, math.min(10 * Config.rlvl(d, "r_start"), Config.STEPS_PER_LAYER - 1))
	recompute(ses)
	setLeaderstats(ses)
	event(ses, "rebirth", gain)
	sendState(ses)
	teleport(ses, "edge")
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

				s.autoStepTimer += dt
				if s.autoStepTimer >= 1 then
					s.autoStepTimer = 0
					if Config.rlvl(d, "r_autostep") >= 1 and d.autoStep then
						buySteps(s, 50)
					end
				end
				s.autoDigTimer += dt
				if s.autoDigTimer >= 4 then
					s.autoDigTimer = 0
					if Config.rlvl(d, "r_autodig") >= 1 and d.autoDig then
						local layer = deepestDigLayer(d)
						if layer >= 1 and Config.digCost(d, layer) <= d.coins * 0.25 then
							dig(s, layer, true)
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
