-- Сохранение прогресса (DataStore) + временное состояние сессии.
-- Если DataStore недоступен (в Studio не включён доступ к API), игра работает, но НЕ сохраняет,
-- чтобы случайно не затереть настоящий прогресс пустым.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Data = {}
Data.Profiles = {} :: { [Player]: any }
Data.Session = {} :: { [Player]: any }

local loadedEvent = Instance.new("BindableEvent")
Data.ProfileLoaded = loadedEvent.Event -- (player, profile)

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStore недоступен: " .. tostring(result))
	end
end

local function defaultProfile()
	return {
		Version = 1,
		Cash = 0,
		Power = 0,
		TotalCaught = 0,
		Baits = { Worm = true },
		Bait = "Worm",
		TankLevel = 0,
		Gear = 1,
		Fish = {},
		Index = {},
		LuckyCasts = 0,
		TrainBoostEnds = 0,
		NextUid = 1,
		LastOnline = 0,
		Receipts = {},
	}
end

local function reconcile(target, template)
	for k, v in pairs(template) do
		if target[k] == nil then
			if type(v) == "table" then
				local copy = {}
				for k2, v2 in pairs(v) do
					copy[k2] = v2
				end
				target[k] = copy
			else
				target[k] = v
			end
		end
	end
	return target
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

function Data.Load(player: Player)
	local profile = nil
	local noSave = false
	if store then
		local ok, result
		for attempt = 1, 3 do
			ok, result = pcall(function()
				return (store :: DataStore):GetAsync(key(player))
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
		if ok then
			profile = type(result) == "table" and result or nil
		else
			warn("[Data] Не удалось загрузить " .. player.Name .. ": " .. tostring(result))
			noSave = true
		end
	else
		noSave = true
	end
	profile = reconcile(profile or defaultProfile(), defaultProfile())
	if not player.Parent then
		return nil
	end
	Data.Profiles[player] = profile
	Data.Session[player] = {
		NoSave = noSave,
		Busy = false,
		Pending = nil,
		LastCast = 0,
		Training = nil,
		LastClickRep = 0,
		JoinedAt = os.time(),
	}
	loadedEvent:Fire(player, profile)
	return profile
end

function Data.Save(player: Player)
	local profile = Data.Profiles[player]
	local session = Data.Session[player]
	if not profile or not session or session.NoSave or not store then
		return
	end
	profile.LastOnline = os.time()
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function()
			return profile
		end)
	end)
	if not ok then
		warn("[Data] Ошибка сохранения " .. player.Name .. ": " .. tostring(err))
	end
end

function Data.Release(player: Player)
	Data.Save(player)
	Data.Profiles[player] = nil
	Data.Session[player] = nil
end

function Data.Get(player: Player)
	return Data.Profiles[player], Data.Session[player]
end

function Data.StartAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(Data.Save, player)
			end
		end
	end)
	game:BindToClose(function()
		local threads = 0
		for _, player in ipairs(Players:GetPlayers()) do
			threads += 1
			task.spawn(function()
				Data.Save(player)
				threads -= 1
			end)
		end
		local t = os.clock()
		while threads > 0 and os.clock() - t < 25 do
			task.wait(0.1)
		end
	end)
end

return Data
