-- Сервер «Кристальной империи»: экономика, участки, бонусы, перерождение, сохранение, топ.
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
		store = DataStoreService:GetDataStore("CrystalEmpire_v1")
		topStore = DataStoreService:GetOrderedDataStore("CrystalEmpire_Top_v1")
	end)
	if not ok then
		warn("DataStore недоступен (в Studio включите API Services):", err)
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
	Click = remote("Click"),
	BuyGen = remote("BuyGen"),
	BuyUp = remote("BuyUp"),
	BuyAllUps = remote("BuyAllUps"),
	BuyPUp = remote("BuyPUp"),
	Rebirth = remote("Rebirth"),
	ClaimGolden = remote("ClaimGolden"),
	ToggleAuto = remote("ToggleAuto"),
	GoHome = remote("GoHome"),
	State = remote("State"), -- сервер -> клиент: снимок данных
	Event = remote("Event"), -- сервер -> клиент: всплывашки, сообщения
}
remotes.Parent = ReplicatedStorage

--------------------------------------------------------------------------------
-- Мир
--------------------------------------------------------------------------------
local plots = World.build()

--------------------------------------------------------------------------------
-- Сессии
--------------------------------------------------------------------------------
type Session = {
	player: Player,
	data: Data,
	plot: World.Plot?,
	perSec: number, -- без временных бонусов
	clickValue: number,
	frenzyLeft: number,
	stormLeft: number,
	clickBudget: number,
	goldenToken: string?,
	goldenExpire: number,
	nextGolden: number,
	autoTimer: number,
	dirty: boolean, -- нужно пересчитать доход и обновить участок
	loaded: boolean,
}

local sessions: { [Player]: Session } = {}
local MAX_CLICKS_PER_SEC = 16

local function sanitize(saved: any): Data
	local d = Config.newData()
	if type(saved) ~= "table" then
		return d
	end
	local function num(v: any): number
		local n = tonumber(v)
		if n == nil or n ~= n or n == math.huge then
			return 0
		end
		return math.max(0, n)
	end
	d.crystals = num(saved.crystals)
	d.runTotal = num(saved.runTotal)
	d.allTotal = num(saved.allTotal)
	d.dust = num(saved.dust)
	d.dustEver = num(saved.dustEver)
	d.rebirths = num(saved.rebirths)
	d.clicks = num(saved.clicks)
	d.goldens = num(saved.goldens)
	d.playTime = num(saved.playTime)
	d.autobuy = saved.autobuy ~= false
	d.lastOnline = tonumber(saved.lastOnline)
	if type(saved.gens) == "table" then
		for id, lvl in pairs(saved.gens) do
			if Config.GenById[id] then
				d.gens[id] = math.floor(num(lvl))
			end
		end
	end
	if type(saved.ups) == "table" then
		for id, v in pairs(saved.ups) do
			if Config.UpById[id] and v then
				d.ups[id] = true
			end
		end
	end
	if type(saved.pups) == "table" then
		for id, lvl in pairs(saved.pups) do
			local p = Config.PUpById[id]
			if p then
				d.pups[id] = math.min(p.maxLevel, math.floor(num(lvl)))
			end
		end
	end
	if type(saved.ach) == "table" then
		for id, v in pairs(saved.ach) do
			if Config.AchById[id] and v then
				d.ach[id] = true
			end
		end
	end
	return d
end

local function recompute(s: Session)
	s.perSec = Config.basePerSecond(s.data)
	s.clickValue = Config.baseClick(s.data, s.perSec)
end

local function currentMult(s: Session): number
	return s.frenzyLeft > 0 and Config.FrenzyMult or 1
end

local function scheduleGolden(s: Session)
	local base = math.random(Config.GoldenMinInterval, Config.GoldenMaxInterval)
	s.nextGolden = os.clock() + base * Config.goldenIntervalMult(s.data)
end

local function setLeaderstats(s: Session)
	local ls = s.player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local c = ls:FindFirstChild("💎 Кристаллы") :: StringValue?
	if c then
		c.Value = Config.format(s.data.crystals)
	end
	local d = ls:FindFirstChild("✨ Пыль") :: IntValue?
	if d then
		d.Value = s.data.dustEver
	end
end

local function sendState(s: Session)
	local d = s.data
	R.State:FireClient(s.player, {
		crystals = d.crystals,
		runTotal = d.runTotal,
		allTotal = d.allTotal,
		dust = d.dust,
		dustEver = d.dustEver,
		rebirths = d.rebirths,
		gens = d.gens,
		ups = d.ups,
		pups = d.pups,
		ach = d.ach,
		clicks = d.clicks,
		goldens = d.goldens,
		playTime = d.playTime,
		autobuy = d.autobuy,
		perSec = s.perSec,
		clickValue = s.clickValue,
		frenzyLeft = s.frenzyLeft,
		stormLeft = s.stormLeft,
	})
end

local function event(s: Session, kind: string, ...)
	R.Event:FireClient(s.player, kind, ...)
end

local function addCrystals(s: Session, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local d = s.data
	d.crystals += amount
	d.runTotal += amount
	d.allTotal += amount
end

-- Обновить станции и надписи на участке игрока
local function refreshPlot(s: Session)
	local plot = s.plot
	if not plot then
		return
	end
	local g = Config.globalMult(s.data)
	for _, gen in ipairs(Config.Generators) do
		local lvl = s.data.gens[gen.id] or 0
		World.updateStation(plot, gen.id, lvl, Config.genProduction(s.data, gen, g) * currentMult(s))
	end
	local sparkles = plot.crystal:FindFirstChild("Sparkles") :: ParticleEmitter?
	if sparkles then
		sparkles.Rate = math.clamp(4 + math.log10(s.perSec + 1) * 3, 4, 60)
	end
	plot.ownerLabel.Text = string.format("Империя %s\n💎 %s/с", s.player.DisplayName, Config.format(s.perSec * currentMult(s)))
end

local function checkAchievements(s: Session)
	local newOnes = {}
	for _, a in ipairs(Config.Achievements) do
		if not s.data.ach[a.id] and a.check(s.data) then
			s.data.ach[a.id] = true
			table.insert(newOnes, a.id)
		end
	end
	if #newOnes > 0 then
		s.dirty = true
		for _, id in ipairs(newOnes) do
			event(s, "achievement", id)
		end
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
		crystals = d.crystals,
		runTotal = d.runTotal,
		allTotal = d.allTotal,
		dust = d.dust,
		dustEver = d.dustEver,
		rebirths = d.rebirths,
		gens = d.gens,
		ups = d.ups,
		pups = d.pups,
		ach = d.ach,
		clicks = d.clicks,
		goldens = d.goldens,
		playTime = d.playTime,
		autobuy = d.autobuy,
		lastOnline = os.time(),
	}
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("p_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Не удалось сохранить", player.Name, err)
	end
	if topStore and d.allTotal > 0 then
		-- В OrderedDataStore только целые: храним log10 × 1000
		local score = math.floor(math.log10(d.allTotal + 1) * 1000)
		pcall(function()
			(topStore :: OrderedDataStore):SetAsync("u_" .. player.UserId, score)
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
			table.insert(rows, { name = name :: string, value = 10 ^ (entry.value / 1000) })
		end
	end
	World.setLeaderboard(rows)
end

--------------------------------------------------------------------------------
-- Вход / выход
--------------------------------------------------------------------------------
local function teleportHome(s: Session)
	local plot = s.plot
	local char = s.player.Character
	if not plot or not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		char:PivotTo(plot.spawnCFrame)
	end
end

local function claimPlot(s: Session)
	for _, plot in ipairs(plots) do
		if plot.owner == nil then
			plot.owner = s.player
			s.plot = plot
			s.player:SetAttribute("Plot", plot.index)
			return
		end
	end
end

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local c = Instance.new("StringValue")
	c.Name = "💎 Кристаллы"
	c.Value = "0"
	c.Parent = ls
	local dv = Instance.new("IntValue")
	dv.Name = "✨ Пыль"
	dv.Parent = ls
	ls.Parent = player

	local s: Session = {
		player = player,
		data = Config.newData(),
		plot = nil,
		perSec = 0,
		clickValue = 1,
		frenzyLeft = 0,
		stormLeft = 0,
		clickBudget = MAX_CLICKS_PER_SEC,
		goldenToken = nil,
		goldenExpire = 0,
		nextGolden = 0,
		autoTimer = 0,
		dirty = true,
		loaded = false,
	}
	sessions[player] = s
	claimPlot(s)

	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.1)
		teleportHome(s)
	end)
	if player.Character then
		task.spawn(teleportHome, s)
	end

	-- Загрузка
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
	-- Если загрузка упала, не сохраняем поверх (чтобы не затереть прогресс пустым)
	s.loaded = loadedOk
	recompute(s)
	scheduleGolden(s)
	s.nextGolden = os.clock() + 25 -- первый сверкающий кристалл пораньше
	refreshPlot(s)
	setLeaderstats(s)
	player:SetAttribute("Loaded", true)

	-- Оффлайн-доход
	local d = s.data
	if d.lastOnline and s.perSec > 0 then
		local away = os.time() - d.lastOnline
		local counted = math.clamp(away, 0, Config.offlineMaxSeconds(d))
		local earned = s.perSec * counted * Config.offlineRate(d)
		if away >= 60 and earned >= 1 then
			addCrystals(s, earned)
			task.delay(2, function()
				if player.Parent then
					event(s, "offline", earned, away)
				end
			end)
		end
	elseif not d.lastOnline then
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
	local s = sessions[player]
	if s and s.plot then
		s.plot.owner = nil
		World.resetPlot(s.plot)
	end
	sessions[player] = nil
end)

game:BindToClose(function()
	local threads = 0
	for _, player in ipairs(Players:GetPlayers()) do
		threads += 1
		task.spawn(function()
			save(player)
			threads -= 1
		end)
	end
	local t = os.clock()
	while threads > 0 and os.clock() - t < 25 do
		task.wait(0.1)
	end
end)

--------------------------------------------------------------------------------
-- Действия игрока
--------------------------------------------------------------------------------
local function doClick(player: Player)
	local s = sessions[player]
	if not s or s.clickBudget < 1 then
		return
	end
	s.clickBudget -= 1
	local amount = s.clickValue * currentMult(s)
	if s.stormLeft > 0 then
		amount *= Config.ClickStormMult
	end
	addCrystals(s, amount)
	s.data.clicks += 1
	event(s, "click", amount)
end

R.Click.OnServerEvent:Connect(doClick)
for _, plot in ipairs(plots) do
	local detector = plot.crystal:FindFirstChildOfClass("ClickDetector")
	if detector then
		detector.MouseClick:Connect(function(player)
			if plot.owner == player then
				doClick(player)
			end
		end)
	end
end

local function buyGen(s: Session, gen: Config.Generator, limit: number): number
	local n = Config.maxAffordable(s.data, gen, s.data.crystals, limit)
	if n <= 0 then
		return 0
	end
	local cost = Config.genCost(s.data, gen, n)
	if cost > s.data.crystals then
		return 0
	end
	local before = s.data.gens[gen.id] or 0
	s.data.crystals -= cost
	s.data.gens[gen.id] = before + n
	if Config.milestonesReached(before + n) > Config.milestonesReached(before) then
		event(s, "milestone", gen.id, before + n)
	end
	s.dirty = true
	return n
end

R.BuyGen.OnServerEvent:Connect(function(player, id, mode)
	local s = sessions[player]
	local gen = type(id) == "string" and Config.GenById[id] or nil
	if not s or not gen then
		return
	end
	local limit = 1
	if mode == 10 or mode == 100 then
		limit = mode
	elseif mode == "max" then
		limit = 100000
	end
	if buyGen(s, gen, limit) > 0 then
		recompute(s)
		checkAchievements(s)
		sendState(s)
	end
end)

local function buyUp(s: Session, up: Config.Upgrade): boolean
	if not Config.isUpgradeUnlocked(s.data, up) or s.data.crystals < up.cost then
		return false
	end
	s.data.crystals -= up.cost
	s.data.ups[up.id] = true
	s.dirty = true
	return true
end

R.BuyUp.OnServerEvent:Connect(function(player, id)
	local s = sessions[player]
	local up = type(id) == "string" and Config.UpById[id] or nil
	if not s or not up then
		return
	end
	if buyUp(s, up) then
		recompute(s)
		checkAchievements(s)
		event(s, "bought", up.id)
		sendState(s)
	end
end)

R.BuyAllUps.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not s then
		return
	end
	local list = {}
	for _, up in ipairs(Config.Upgrades) do
		if Config.isUpgradeUnlocked(s.data, up) then
			table.insert(list, up)
		end
	end
	table.sort(list, function(a, b)
		return a.cost < b.cost
	end)
	local count = 0
	for _, up in ipairs(list) do
		if buyUp(s, up) then
			count += 1
		end
	end
	if count > 0 then
		recompute(s)
		checkAchievements(s)
		event(s, "message", string.format("Куплено улучшений: %d", count))
		sendState(s)
	end
end)

R.BuyPUp.OnServerEvent:Connect(function(player, id)
	local s = sessions[player]
	local p = type(id) == "string" and Config.PUpById[id] or nil
	if not s or not p then
		return
	end
	local lvl = Config.pupLevel(s.data, p.id)
	if lvl >= p.maxLevel then
		return
	end
	local cost = Config.pupCost(p, lvl)
	if s.data.dust < cost then
		return
	end
	s.data.dust -= cost
	s.data.pups[p.id] = lvl + 1
	s.dirty = true
	recompute(s)
	event(s, "message", string.format("✨ %s — уровень %d", p.name, lvl + 1))
	sendState(s)
end)

R.Rebirth.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not s then
		return
	end
	local d = s.data
	local gain = Config.dustOnRebirth(d)
	if gain < 1 then
		return
	end
	d.dust += gain
	d.dustEver += gain
	d.rebirths += 1
	d.runTotal = 0
	d.gens = {}
	d.ups = {}
	d.crystals = Config.startCrystals(d)
	s.frenzyLeft = 0
	s.stormLeft = 0
	s.dirty = true
	recompute(s)
	checkAchievements(s)
	event(s, "rebirth", gain, d.rebirths)
	sendState(s)
	task.spawn(save, player)
end)

R.ClaimGolden.OnServerEvent:Connect(function(player, token)
	local s = sessions[player]
	if not s or not s.goldenToken or token ~= s.goldenToken or os.clock() > s.goldenExpire then
		return
	end
	s.goldenToken = nil
	scheduleGolden(s)
	s.data.goldens += 1
	local roll = math.random()
	if roll < 0.5 then
		-- Удача: мгновенная награда
		local amount = math.max(s.perSec * 60, math.min(s.data.crystals * 0.15, s.perSec * 900)) + 25
		addCrystals(s, amount)
		event(s, "golden", "lucky", amount)
	elseif roll < 0.85 then
		s.frenzyLeft = Config.frenzyDuration(s.data)
		event(s, "golden", "frenzy", s.frenzyLeft)
	else
		s.stormLeft = Config.stormDuration(s.data)
		event(s, "golden", "storm", s.stormLeft)
	end
	s.dirty = true
	checkAchievements(s)
	sendState(s)
end)

R.ToggleAuto.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if not s then
		return
	end
	s.data.autobuy = not s.data.autobuy
	sendState(s)
end)

R.GoHome.OnServerEvent:Connect(function(player)
	local s = sessions[player]
	if s then
		teleportHome(s)
	end
end)

--------------------------------------------------------------------------------
-- Прораб (автопокупка генераторов)
--------------------------------------------------------------------------------
local function autobuy(s: Session)
	local d = s.data
	if Config.pupLevel(d, "auto") < 1 or not d.autobuy then
		return
	end
	local bought = 0
	for _ = 1, 25 do
		-- Выбираем самый выгодный генератор: прирост дохода / цена
		local best, bestScore = nil, 0
		local g = Config.globalMult(d)
		for _, gen in ipairs(Config.Generators) do
			local cost = Config.genCost(d, gen, 1)
			if cost <= d.crystals then
				local lvl = d.gens[gen.id] or 0
				local now = Config.genProduction(d, gen, g)
				d.gens[gen.id] = lvl + 1
				local after = Config.genProduction(d, gen, g)
				d.gens[gen.id] = lvl
				local score = (after - now) / cost
				if score > bestScore then
					best, bestScore = gen, score
				end
			end
		end
		if not best then
			break
		end
		if buyGen(s, best, 1) == 0 then
			break
		end
		bought += 1
	end
	if bought > 0 then
		recompute(s)
		checkAchievements(s)
	end
end

--------------------------------------------------------------------------------
-- Главный цикл
--------------------------------------------------------------------------------
local TICK = 0.2
local stateTimer = 0
local plotTimer = 0
local slowTimer = 0

task.spawn(function()
	while true do
		local dt = task.wait(TICK)
		stateTimer += dt
		plotTimer += dt
		slowTimer += dt
		local now = os.clock()
		for _, s in pairs(sessions) do
			if s.player:GetAttribute("Loaded") then
				s.clickBudget = math.min(MAX_CLICKS_PER_SEC, s.clickBudget + MAX_CLICKS_PER_SEC * dt)
				s.data.playTime += dt
				if s.frenzyLeft > 0 then
					s.frenzyLeft = math.max(0, s.frenzyLeft - dt)
					if s.frenzyLeft == 0 then
						s.dirty = true
					end
				end
				if s.stormLeft > 0 then
					s.stormLeft = math.max(0, s.stormLeft - dt)
				end
				addCrystals(s, s.perSec * currentMult(s) * dt)

				s.autoTimer += dt
				if s.autoTimer >= 1 then
					s.autoTimer = 0
					autobuy(s)
				end

				-- Сверкающий кристалл
				if not s.goldenToken and now >= s.nextGolden then
					s.goldenToken = HttpService:GenerateGUID(false)
					s.goldenExpire = now + Config.GoldenLifetime + 1
					event(s, "goldenSpawn", s.goldenToken, Config.GoldenLifetime)
				elseif s.goldenToken and now > s.goldenExpire then
					s.goldenToken = nil
					scheduleGolden(s)
				end
			end
		end

		if stateTimer >= 0.5 then
			stateTimer = 0
			for _, s in pairs(sessions) do
				if s.player:GetAttribute("Loaded") then
					sendState(s)
					setLeaderstats(s)
				end
			end
		end

		if plotTimer >= 1 then
			plotTimer = 0
			for _, s in pairs(sessions) do
				if s.player:GetAttribute("Loaded") then
					checkAchievements(s)
					if s.dirty then
						s.dirty = false
						recompute(s)
					end
					refreshPlot(s)
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
