-- Серверная логика: данные игрока, клики, покупки, перерождение, сохранение, постройка мира.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local STORE_NAME = "CrystalClicker_v1"
local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("DataStore недоступен (в Studio включите API Services): ", result)
	end
end

-- Remotes ---------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local ClickRemote = remote("Click")
local BuyRemote = remote("Buy")
local RebirthRemote = remote("Rebirth")
local FeedbackRemote = remote("Feedback") -- сервер -> клиент: всплывающие числа и сообщения
remotes.Parent = ReplicatedStorage

-- Мир --------------------------------------------------------------------
local CRYSTAL_POS = Vector3.new(0, 11, -28)

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

local function buildWorld()
	local world = Instance.new("Folder")
	world.Name = "CrystalWorld"

	-- Пьедестал
	makePart({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 18, 18),
		CFrame = CFrame.new(CRYSTAL_POS.X, 1.5, CRYSTAL_POS.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(45, 40, 60),
		Material = Enum.Material.Slate,
		Parent = world,
	})
	makePart({
		Name = "PedestalGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 19, 19),
		CFrame = CFrame.new(CRYSTAL_POS.X, 3.1, CRYSTAL_POS.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 220, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = world,
	})

	-- Главный кристалл: куб, поставленный на вершину (выглядит как самоцвет)
	local crystal = makePart({
		Name = "BigCrystal",
		Size = Vector3.new(8, 8, 8),
		CFrame = CFrame.new(CRYSTAL_POS) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)),
		Color = Color3.fromRGB(70, 210, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.2,
		Parent = world,
	})
	local core = makePart({
		Name = "Core",
		Size = Vector3.new(5, 5, 5),
		CFrame = crystal.CFrame,
		Color = Color3.fromRGB(150, 240, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = crystal,
	})
	core.Name = "Core"
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(100, 220, 255)
	light.Range = 30
	light.Brightness = 3
	light.Parent = crystal

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 120
	click.Parent = crystal

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(150, 240, 255))
	sparkles.Size = NumberSequence.new(0.6, 0)
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Rate = 8
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.LightEmission = 1
	sparkles.Parent = crystal

	local bb = Instance.new("BillboardGui")
	bb.Name = "Hint"
	bb.Size = UDim2.fromOffset(260, 50)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = crystal
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromScale(1, 1)
	hint.BackgroundTransparency = 1
	hint.Text = "⛏ Кликай по кристаллу!"
	hint.TextScaled = true
	hint.Font = Enum.Font.FredokaOne
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextStrokeTransparency = 0.3
	hint.Parent = bb
	bb.Parent = crystal

	-- Россыпь маленьких кристаллов вокруг
	local rng = Random.new(42)
	local palette = {
		Color3.fromRGB(255, 90, 200),
		Color3.fromRGB(90, 255, 150),
		Color3.fromRGB(255, 210, 70),
		Color3.fromRGB(140, 110, 255),
		Color3.fromRGB(70, 210, 255),
	}
	for i = 1, 40 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(22, 70)
		local s = rng:NextNumber(1.5, 4.5)
		local pos = Vector3.new(CRYSTAL_POS.X + math.cos(angle) * dist, s * 0.4, CRYSTAL_POS.Z + math.sin(angle) * dist)
		if (pos - Vector3.new(0, 0, 0)).Magnitude > 10 then
			makePart({
				Name = "Shard" .. i,
				Size = Vector3.new(s * 0.6, s * 1.8, s * 0.6),
				CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
				Color = palette[rng:NextInteger(1, #palette)],
				Material = Enum.Material.Neon,
				Transparency = 0.1,
				Parent = world,
			})
		end
	end

	world.Parent = workspace
	return crystal
end

local crystal = buildWorld()

-- Вечернее освещение, чтобы неон светился
local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 19.2
Lighting.Brightness = 1.5
Lighting.OutdoorAmbient = Color3.fromRGB(90, 80, 130)
Lighting.Ambient = Color3.fromRGB(60, 55, 90)
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.6
bloom.Size = 30
bloom.Threshold = 1.5
bloom.Parent = Lighting

-- Данные игроков ----------------------------------------------------------
type Data = {
	crystals: number,
	total: number,
	rebirths: number,
	levels: { [string]: number },
	lastOnline: number?,
}

local sessions: { [Player]: Data } = {}
local clickBudget: { [Player]: number } = {}
local MAX_CLICKS_PER_SEC = 15

local function defaultData(): Data
	return { crystals = 0, total = 0, rebirths = 0, levels = {}, lastOnline = nil }
end

local function syncStats(player: Player, data: Data)
	local perClick, perSec, crit = Config.compute(data.levels, data.rebirths)
	player:SetAttribute("Crystals", data.crystals)
	player:SetAttribute("Total", data.total)
	player:SetAttribute("Rebirths", data.rebirths)
	player:SetAttribute("PerClick", perClick)
	player:SetAttribute("PerSecond", perSec)
	player:SetAttribute("Crit", crit)
	for _, up in ipairs(Config.Upgrades) do
		player:SetAttribute("Lvl_" .. up.id, data.levels[up.id] or 0)
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls :: any)["💎 Кристаллы"].Value = Config.format(data.crystals);
		(ls :: any)["🔁 Перерождения"].Value = data.rebirths
	end
end

local function addCrystals(player: Player, data: Data, amount: number)
	data.crystals += amount
	data.total += amount
	player:SetAttribute("Crystals", data.crystals)
	player:SetAttribute("Total", data.total)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls :: any)["💎 Кристаллы"].Value = Config.format(data.crystals)
	end
end

local function load(player: Player): Data
	local data = defaultData()
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("p_" .. player.UserId)
		end)
		if ok and type(saved) == "table" then
			data.crystals = tonumber(saved.crystals) or 0
			data.total = tonumber(saved.total) or 0
			data.rebirths = tonumber(saved.rebirths) or 0
			data.lastOnline = tonumber(saved.lastOnline)
			if type(saved.levels) == "table" then
				for id, lvl in pairs(saved.levels) do
					if Config.ById[id] then
						data.levels[id] = tonumber(lvl) or 0
					end
				end
			end
		elseif not ok then
			warn("Не удалось загрузить данные", player.Name, saved)
		end
	end
	return data
end

local function save(player: Player)
	local data = sessions[player]
	if not data or not store then
		return
	end
	local payload = {
		crystals = data.crystals,
		total = data.total,
		rebirths = data.rebirths,
		levels = data.levels,
		lastOnline = os.time(),
	}
	local ok, err = pcall(function()
		store:SetAsync("p_" .. player.UserId, payload)
	end)
	if not ok then
		warn("Не удалось сохранить", player.Name, err)
	end
end

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local c = Instance.new("StringValue")
	c.Name = "💎 Кристаллы"
	c.Value = "0"
	c.Parent = ls
	local r = Instance.new("IntValue")
	r.Name = "🔁 Перерождения"
	r.Parent = ls
	ls.Parent = player

	local data = load(player)
	if not player.Parent then
		return
	end
	sessions[player] = data
	clickBudget[player] = MAX_CLICKS_PER_SEC
	syncStats(player, data)
	player:SetAttribute("Loaded", true)

	-- Оффлайн-доход
	if data.lastOnline then
		local away = math.clamp(os.time() - data.lastOnline, 0, Config.OfflineMaxSeconds)
		local _, perSec = Config.compute(data.levels, data.rebirths)
		local earned = math.floor(perSec * away * Config.OfflineRate)
		if earned > 0 and away >= 60 then
			addCrystals(player, data, earned)
			task.delay(3, function()
				if player.Parent then
					FeedbackRemote:FireClient(player, "message", string.format("Пока тебя не было, гномы добыли 💎 %s", Config.format(earned)))
				end
			end)
		end
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	save(player)
	sessions[player] = nil
	clickBudget[player] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(save, player)
	end
	task.wait(3)
end)

-- Действия -----------------------------------------------------------------
local function doClick(player: Player)
	local data = sessions[player]
	if not data then
		return
	end
	local budget = clickBudget[player] or 0
	if budget < 1 then
		return -- автокликер / спам
	end
	clickBudget[player] = budget - 1

	local perClick, _, crit = Config.compute(data.levels, data.rebirths)
	local isCrit = math.random() < crit
	local amount = isCrit and perClick * Config.CritMultiplier or perClick
	addCrystals(player, data, amount)
	FeedbackRemote:FireClient(player, "click", amount, isCrit)
end

ClickRemote.OnServerEvent:Connect(doClick)
local detector = crystal:FindFirstChildOfClass("ClickDetector")
if detector then
	detector.MouseClick:Connect(doClick)
end

BuyRemote.OnServerEvent:Connect(function(player, id)
	local data = sessions[player]
	local up = type(id) == "string" and Config.ById[id] or nil
	if not data or not up then
		return
	end
	local lvl = data.levels[up.id] or 0
	if up.maxLevel and lvl >= up.maxLevel then
		return
	end
	local cost = Config.getCost(up, lvl)
	if data.crystals < cost then
		return
	end
	data.crystals -= cost
	data.levels[up.id] = lvl + 1
	syncStats(player, data)
	FeedbackRemote:FireClient(player, "bought", up.id)
end)

RebirthRemote.OnServerEvent:Connect(function(player)
	local data = sessions[player]
	if not data then
		return
	end
	local cost = Config.getRebirthCost(data.rebirths)
	if data.crystals < cost then
		return
	end
	data.rebirths += 1
	data.crystals = 0
	data.levels = {}
	syncStats(player, data)
	FeedbackRemote:FireClient(
		player,
		"message",
		string.format("Перерождение %d! Вся добыча ×%s", data.rebirths, tostring(Config.getMultiplier(data.rebirths)))
	)
	task.spawn(save, player)
end)

-- Пассивный доход и восстановление лимита кликов ---------------------------
local TICK = 0.25
task.spawn(function()
	while true do
		task.wait(TICK)
		for player, data in pairs(sessions) do
			clickBudget[player] = math.min(MAX_CLICKS_PER_SEC, (clickBudget[player] or 0) + MAX_CLICKS_PER_SEC * TICK)
			local _, perSec = Config.compute(data.levels, data.rebirths)
			if perSec > 0 then
				addCrystals(player, data, perSec * TICK)
			end
		end
	end
end)

-- Автосохранение раз в минуту
task.spawn(function()
	while true do
		task.wait(60)
		for player in pairs(sessions) do
			task.spawn(save, player)
		end
	end
end)
