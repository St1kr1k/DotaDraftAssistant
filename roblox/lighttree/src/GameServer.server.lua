-- Сервер: экономика, покупка узлов, перерождения, автопокупка, падающие звёзды, сохранение.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local World = require(script:WaitForChild("World"))

type Data = Config.Data

local store: DataStore? = nil
local topStore: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore("LightTree_v1")
		topStore = DataStoreService:GetOrderedDataStore("LightTree_Top_v1")
	end)
	if not ok then
		warn("DataStore недоступен:", err)
	end
end

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local R = {
	Buy = remote("Buy"),
	Teleport = remote("Teleport"),
	Claim = remote("Claim"),
	State = remote("State"),
	Event = remote("Event"),
}
remotes.Parent = ReplicatedStorage

local world = World.build()

--------------------------------------------------------------------------------
-- Сессии
--------------------------------------------------------------------------------
type Session = {
	player: Player,
	data: Data,
	lps: number,
	golden: string?,
	goldenPos: Vector3?,
	goldenExpire: number,
	nextGolden: number,
	autoTimer: number,
	lastAction: number,
	actions: number,
	loaded: boolean,
	ready: boolean,
	bestLayer: string,
}
local sessions: { [Player]: Session } = {}

local function num(v: any): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge then
		return 0
	end
	return math.max(0, n)
end

local CUR = { "L", "Z", "S", "E" }

local function sanitize(saved: any): Data
	local d = Config.newData()
	if type(saved) ~= "table" then
		return d
	end
	for _, key in ipairs({ "cur", "run", "total" }) do
		local src = saved[key]
		if type(src) == "table" then
			for _, c in ipairs(CUR) do
				(d :: any)[key][c] = num(src[c])
			end
		end
	end
	if type(saved.nodes) == "table" then
		for id, lvl in pairs(saved.nodes) do
			local n = Config.NodeById[id]
			if n then
				local v = math.min(n.max, math.floor(num(lvl)))
				if v > 0 then
					d.nodes[id] = v
				end
			end
		end
	end
	if type(saved.resets) == "table" then
		for _, c in ipairs({ "Z", "S", "E" }) do
			d.resets[c] = math.floor(num(saved.resets[c]))
		end
	end
	d.golden = math.floor(num(saved.golden))
	d.playTime = num(saved.playTime)
	d.lastOnline = tonumber(saved.lastOnline)
	return d
end

local function event(s: Session, kind: string, ...)
	R.Event:FireClient(s.player, kind, ...)
end

local function recompute(s: Session)
	s.lps = Config.Lps(s.data)
end

local function sendState(s: Session)
	local d = s.data
	R.State:FireClient(s.player, {
		cur = d.cur,
		run = d.run,
		total = d.total,
		nodes = d.nodes,
		resets = d.resets,
		golden = d.golden,
		playTime = d.playTime,
		lps = s.lps,
	})
end

local function add(s: Session, c: string, amount: number)
	if amount ~= amount or amount <= 0 then
		return
	end
	local d = s.data
	d.cur[c] += amount
	d.run[c] += amount
	d.total[c] += amount
end

local function highestLayer(d: Data): string
	if (d.resets.E or 0) > 0 then
		return "E"
	elseif (d.resets.S or 0) > 0 then
		return "S"
	elseif (d.resets.Z or 0) > 0 then
		return "Z"
	end
	return "L"
end

local function updateTag(s: Session)
	local char = s.player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local bb = head:FindFirstChild("LayerTag") :: BillboardGui?
	if not bb then
		local nb = Instance.new("BillboardGui")
		nb.Name = "LayerTag"
		nb.Size = UDim2.fromOffset(200, 30)
		nb.StudsOffset = Vector3.new(0, 2.7, 0)
		nb.MaxDistance = 90
		nb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextStrokeTransparency = 0.2
		t.Parent = nb
		nb.Parent = head
		bb = nb
	end
	local label = (bb :: BillboardGui):FindFirstChild("Text") :: TextLabel
	local layer = highestLayer(s.data)
	local isl = Config.IslandById[layer]
	if layer == "L" then
		label.Text = ""
	else
		label.Text = string.format("[%s %s ×%d]", isl.icon, isl.tag, s.data.resets[layer])
		label.TextColor3 = isl.color
	end
	s.bestLayer = layer
end

local function setLeaderstats(s: Session)
	local ls = s.player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local l = ls:FindFirstChild("💡 Свет") :: StringValue?
	if l then
		l.Value = Config.format(s.data.total.L)
	end
	local layer = ls:FindFirstChild("Слой") :: StringValue?
	if layer then
		local h = highestLayer(s.data)
		layer.Value = h == "L" and "—" or Config.IslandById[h].tag
	end
end

--------------------------------------------------------------------------------
-- Сохранение
--------------------------------------------------------------------------------
local function save(player: Player)
	local s = sessions[player]
	if not s or not s.loaded or not store then
		return
	end
	local d = s.data
	local payload = {
		cur = d.cur,
		run = d.run,
		total = d.total,
		nodes = d.nodes,
		resets = d.resets,
		golden = d.golden,
		playTime = d.playTime,
		lastOnline = os.time(),
	}
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("p_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Не удалось сохранить", player.Name, err)
	end
	if topStore and d.total.L > 0 then
		local score = math.floor(math.log10(d.total.L + 1) * 100)
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
			table.insert(rows, { name = name :: string, value = 10 ^ (entry.value / 100) })
		end
	end
	World.setLeaderboard(rows)
end

--------------------------------------------------------------------------------
-- Вход / выход
--------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local l = Instance.new("StringValue")
	l.Name = "💡 Свет"
	l.Parent = ls
	local layer = Instance.new("StringValue")
	layer.Name = "Слой"
	layer.Parent = ls
	ls.Parent = player

	local s: Session = {
		player = player,
		data = Config.newData(),
		lps = 1,
		golden = nil,
		goldenPos = nil,
		goldenExpire = 0,
		nextGolden = os.clock() + 30,
		autoTimer = 0,
		lastAction = 0,
		actions = 0,
		loaded = false,
		ready = false,
		bestLayer = "L",
	}
	sessions[player] = s
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 10)
		updateTag(s)
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
	updateTag(s)
	setLeaderstats(s)

	local d = s.data
	if d.lastOnline then
		local away = math.clamp(os.time() - d.lastOnline, 0, Config.OFFLINE_MAX)
		if away >= 60 then
			local earned = s.lps * away * Config.OFFLINE_RATE
			add(s, "L", earned)
			local z = Config.passiveZ(d) * Config.gainZ(d) * away * Config.OFFLINE_RATE
			add(s, "Z", z)
			task.delay(2, function()
				if player.Parent then
					event(s, "offline", earned, os.time() - (d.lastOnline or os.time()), z)
				end
			end)
		end
	else
		task.delay(1.5, function()
			if player.Parent then
				event(s, "welcome")
			end
		end)
	end
	if not loadedOk then
		event(s, "message", "⚠ Не удалось загрузить сохранение — прогресс этой сессии не сохранится. Перезайди позже.")
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
	return s.actions <= 30
end

--------------------------------------------------------------------------------
-- Покупка узлов
--------------------------------------------------------------------------------
local function buyNode(s: Session, n: Config.Node): boolean
	local d = s.data
	if not Config.canBuy(d, n) then
		return false
	end
	d.cur[n.island] -= Config.nodeCost(d, n)
	d.nodes[n.id] = Config.lvl(d, n.id) + 1
	return true
end

R.Buy.OnServerEvent:Connect(function(player, id)
	local s = sessions[player]
	local n = type(id) == "string" and Config.NodeById[id] or nil
	if not allow(s) or not n then
		return
	end
	local ses = s :: Session
	-- покупать можно, только стоя у плитки
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - Config.nodePosition(n)).Magnitude > 14 then
		return
	end
	if buyNode(ses, n) then
		recompute(ses)
		event(ses, "bought", n.id, Config.lvl(ses.data, n.id))
		if n.kind == "unlock" then
			event(ses, "islandOpen", Config.Islands[n.value].id)
		end
		sendState(ses)
	end
end)

-- Автопокупка: уровень 1 — Маяк, 2 — Заря, 3 — Звёзды
local AUTO_ISLANDS = { "L", "Z", "S" }
local function autobuy(s: Session)
	local level = Config.autoLevel(s.data)
	if level <= 0 then
		return
	end
	local any = false
	for i = 1, level do
		local island = AUTO_ISLANDS[i]
		for _ = 1, 30 do
			local best, bestCost = nil, math.huge
			for _, n in ipairs(Config.Nodes) do
				if n.island == island and n.kind ~= "unlock" and Config.canBuy(s.data, n) then
					local c = Config.nodeCost(s.data, n)
					if c < bestCost then
						best, bestCost = n, c
					end
				end
			end
			if not best or not buyNode(s, best) then
				break
			end
			any = true
		end
	end
	if any then
		recompute(s)
	end
end

--------------------------------------------------------------------------------
-- Перерождения
--------------------------------------------------------------------------------
local GAIN = { Z = Config.gainZ, S = Config.gainS, E = Config.gainE }

local function prestige(s: Session, layer: string)
	local d = s.data
	local fn = GAIN[layer]
	if not fn then
		return
	end
	local gain = fn(d)
	if gain < 1 then
		event(s, "message", "Пока слишком мало — копи дальше")
		return
	end
	local before = highestLayer(d)
	d.resets[layer] += 1
	add(s, layer, gain)
	Config.applyReset(d, layer)
	recompute(s)
	event(s, "prestige", layer, gain)
	if highestLayer(d) ~= before then
		event(s, "newLayer", layer)
	end
	updateTag(s)
	setLeaderstats(s)
	sendState(s)
	task.spawn(save, s.player)
end

for _, altar in ipairs(world.altars) do
	altar.prompt.Triggered:Connect(function(player)
		local s = sessions[player]
		if allow(s) then
			prestige(s :: Session, altar.layer)
		end
	end)
end

--------------------------------------------------------------------------------
-- Телепорт
--------------------------------------------------------------------------------
R.Teleport.OnServerEvent:Connect(function(player, id)
	local s = sessions[player]
	if not allow(s) or type(id) ~= "string" or not Config.IslandById[id] then
		return
	end
	if not Config.islandOpen((s :: Session).data, id) then
		return
	end
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char:PivotTo(World.islandSpawn(id))
	end
end)

--------------------------------------------------------------------------------
-- Падающие звёзды
--------------------------------------------------------------------------------
local function nearestIsland(pos: Vector3): Config.Island
	local best, bd = Config.Islands[1], math.huge
	for _, isl in ipairs(Config.Islands) do
		local dist = (isl.center - pos).Magnitude
		if dist < bd then
			best, bd = isl, dist
		end
	end
	return best
end

local function spawnGolden(s: Session)
	local char = s.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local isl = nearestIsland(root.Position)
	local a = math.random() * math.pi * 2
	local r = math.random(10, math.floor(isl.radius * 0.8))
	local pos = isl.center + Vector3.new(math.cos(a) * r, 2.5, math.sin(a) * r)
	s.golden = HttpService:GenerateGUID(false)
	s.goldenPos = pos
	s.goldenExpire = os.clock() + 25
	event(s, "goldenSpawn", s.golden, pos)
end

R.Claim.OnServerEvent:Connect(function(player, token)
	local s = sessions[player]
	if not allow(s) then
		return
	end
	local ses = s :: Session
	if not ses.golden or token ~= ses.golden or os.clock() > ses.goldenExpire or not ses.goldenPos then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - (ses.goldenPos :: Vector3)).Magnitude > 14 then
		return
	end
	ses.golden = nil
	ses.data.golden += 1
	local amount = ses.lps * Config.GOLDEN_SECONDS * Config.goldenMult(ses.data)
	add(ses, "L", amount)
	ses.nextGolden = os.clock() + math.random(Config.GOLDEN_MIN, Config.GOLDEN_MAX)
	event(ses, "golden", amount)
	sendState(ses)
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
		local now = os.clock()
		for _, s in pairs(sessions) do
			if s.ready then
				local d = s.data
				d.playTime += dt
				recompute(s) -- 💡/с зависит от текущих 💡, 🌅 и ✦
				add(s, "L", s.lps * dt)
				local pz = Config.passiveZ(d)
				if pz > 0 then
					add(s, "Z", pz * Config.gainZ(d) * dt)
				end
				local psv = Config.passiveS(d)
				if psv > 0 then
					add(s, "S", psv * Config.gainS(d) * dt)
				end
				s.autoTimer += dt
				if s.autoTimer >= 0.5 then
					s.autoTimer = 0
					autobuy(s)
				end
				if s.golden and now > s.goldenExpire then
					s.golden = nil
					s.nextGolden = now + math.random(Config.GOLDEN_MIN, Config.GOLDEN_MAX)
					event(s, "goldenGone")
				elseif not s.golden and now >= s.nextGolden then
					spawnGolden(s)
				end
			end
		end
		if stateTimer >= 0.25 then
			stateTimer = 0
			for _, s in pairs(sessions) do
				if s.ready then
					sendState(s)
				end
			end
		end
		if slowTimer >= 60 then
			slowTimer = 0
			for player, s in pairs(sessions) do
				setLeaderstats(s)
				task.spawn(save, player)
			end
			task.spawn(refreshLeaderboard)
		end
	end
end)
task.delay(5, refreshLeaderboard)
task.spawn(function()
	while true do
		task.wait(3)
		for _, s in pairs(sessions) do
			if s.ready then
				setLeaderstats(s)
			end
		end
	end
end)
