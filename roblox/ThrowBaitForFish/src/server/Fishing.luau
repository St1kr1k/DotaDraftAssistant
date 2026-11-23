-- Заброс и улов. Всё решает сервер: клиент присылает только силу заряда (0..1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local Remotes = require(Shared.Remotes)

local Data = require(script.Parent.Data)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)
local PlayerService = require(script.Parent.PlayerService)

local Fishing = {}

local rng = Random.new()

local function weightedPick(weights: { number }): number
	local total = 0
	for _, w in ipairs(weights) do
		total += w
	end
	local r = rng:NextNumber() * total
	for i, w in ipairs(weights) do
		r -= w
		if r <= 0 then
			return i
		end
	end
	return #weights
end

-- Выбор рыбы в зоне с учётом удачи
local function rollFish(zone: number, luck: number)
	local list = GameData.FishByZone[zone]
	local weights = {}
	for i, f in ipairs(list) do
		local rarity = GameData.Rarities[f.Rarity]
		weights[i] = rarity.Weight * luck ^ ((f.Rarity - 1) * Config.LuckExponent)
	end
	return list[weightedPick(weights)]
end

local function rollMutation(mutLuck: number): string
	-- от самой редкой к обычной
	for i = #GameData.Mutations, 2, -1 do
		local m = GameData.Mutations[i]
		if rng:NextNumber() < math.min(0.5, m.Chance * mutLuck) then
			return m.Id
		end
	end
	return "None"
end

local function rollSize(luck: number): number
	local weights = {}
	for i, s in ipairs(GameData.Sizes) do
		weights[i] = s.Weight * (i >= 3 and luck ^ 0.25 or 1)
	end
	return weightedPick(weights)
end

local function nearCastSpot(player: Player, plot): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local d = (root.Position - plot.CastSpot.Position) * Vector3.new(1, 0, 1)
	return d.Magnitude <= Config.CastSpotRadius and math.abs(root.Position.Y - plot.CastSpot.Position.Y) < 8
end

local function onCast(player: Player, charge: any)
	local profile, session = Data.Get(player)
	if not profile or not session then
		return { ok = false, reason = "loading" }
	end
	if type(charge) ~= "number" or charge ~= charge then
		return { ok = false, reason = "bad" }
	end
	charge = math.clamp(charge, 0.05, 1)
	local now = os.clock()
	if session.Training then
		return { ok = false, reason = "training" }
	end
	if session.Pending and now < session.Pending.Expires then
		return { ok = false, reason = "busy" }
	end
	if now - session.LastCast < Config.CastCooldown then
		return { ok = false, reason = "cooldown" }
	end
	local plot = World.PlotOf(player)
	if not plot then
		return { ok = false, reason = "noplot" }
	end
	if not nearCastSpot(player, plot) then
		return { ok = false, reason = "far" }
	end
	session.LastCast = now

	local maxD = Stats.MaxDistance(profile)
	local dist = math.max(8, maxD * charge)
	local zone = GameData.ZoneForDistance(dist)
	local luck = Stats.Luck(player, profile) * (1 + Config.DistanceLuckPer100 * dist / 100)
	local lucky = false
	if (profile.LuckyCasts or 0) > 0 then
		profile.LuckyCasts -= 1
		luck *= Config.LuckyCastLuck
		lucky = true
	end
	local ev = Stats.CurrentEvent()
	local mutLuck = math.sqrt(luck) * (ev and ev.Mutation or 1)

	local fish = rollFish(zone, luck)
	local mutation = rollMutation(mutLuck)
	local size = rollSize(luck)

	local flight = 0.55 + dist / 420
	local bite = rng:NextNumber(1.1, 2.6) * (ev and ev.Bite or 1)
	local reel = 0.9 + fish.Rarity * 0.22
	local landing = plot.CastSpot.Position + plot.Dir * dist
	landing = Vector3.new(landing.X, Config.WaterY, landing.Z)

	session.Pending = {
		Fish = fish.Id,
		Mutation = mutation,
		Size = size,
		ReadyAt = now + flight + bite + reel * 0.7,
		Expires = now + flight + bite + reel + 25,
	}

	-- показать заброс остальным игрокам
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			Remotes.Get("CastFx"):FireClient(other, player.UserId, landing, flight, flight + bite + reel)
		end
	end
	if lucky then
		PlayerService.Push(player)
	end

	return {
		ok = true,
		land = landing,
		dist = dist,
		zone = zone,
		flight = flight,
		bite = bite,
		reel = reel,
		rarity = fish.Rarity, -- для «подсказки» цветом поплавка во время клёва
		lucky = lucky,
	}
end

local function onReel(player: Player)
	local profile, session = Data.Get(player)
	if not profile or not session or not session.Pending then
		return { ok = false, reason = "nothing" }
	end
	local now = os.clock()
	local pending = session.Pending
	if now < pending.ReadyAt - 0.25 then
		return { ok = false, reason = "early", wait = pending.ReadyAt - now }
	end
	session.Pending = nil
	if now > pending.Expires then
		return { ok = false, reason = "expired" }
	end
	local outcome = PlayerService.AddFish(player, pending.Fish, pending.Mutation, pending.Size)
	local def = GameData.FishById[pending.Fish]
	if def.Rarity >= GameData.RarityIndex.Legendary or (GameData.MutationById[pending.Mutation].Index >= 5) then
		Remotes.Get("BigCatch"):FireAllClients(player.DisplayName, pending.Fish, pending.Mutation, pending.Size)
	end
	return {
		ok = true,
		fish = pending.Fish,
		mutation = pending.Mutation,
		size = pending.Size,
		outcome = outcome,
	}
end

function Fishing.Init()
	Remotes.Get("Cast").OnServerInvoke = onCast
	Remotes.Get("Reel").OnServerInvoke = onReel
	Remotes.Get("GoToPier").OnServerInvoke = function(player)
		local _, session = Data.Get(player)
		if session and session.Training then
			return false
		end
		PlayerService.TeleportToPier(player)
		return true
	end
end

return Fishing
