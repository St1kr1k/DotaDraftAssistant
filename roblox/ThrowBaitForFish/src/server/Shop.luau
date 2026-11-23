-- Покупки за игровые деньги: наживки, расширение аквариума, продажа рыбы.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local Data = require(script.Parent.Data)
local PlayerService = require(script.Parent.PlayerService)
local World = require(script.Parent.World)

local Shop = {}

local function fail(msg: string)
	return { ok = false, msg = msg }
end

local function sellPrice(f): number
	return math.floor(GameData.FishIncome(f.Id, f.M, f.S) * Config.SellSeconds)
end
Shop.SellPrice = sellPrice

function Shop.Init()
	Remotes.Get("BuyBait").OnServerInvoke = function(player, baitId)
		local profile = Data.Get(player)
		local bait = type(baitId) == "string" and GameData.BaitById[baitId]
		if not profile or not bait then
			return fail("Unknown bait")
		end
		if profile.Baits[bait.Id] then
			profile.Bait = bait.Id
			PlayerService.Push(player)
			return { ok = true }
		end
		-- покупать по порядку
		local prev = GameData.Baits[bait.Index - 1]
		if prev and not profile.Baits[prev.Id] then
			return fail("Buy " .. prev.Name .. " first!")
		end
		if profile.Cash < bait.Price then
			return fail("Need " .. Format.Money(bait.Price - profile.Cash) .. " more")
		end
		profile.Cash -= bait.Price
		profile.Baits[bait.Id] = true
		profile.Bait = bait.Id
		PlayerService.UpdateAttributes(player)
		PlayerService.Push(player)
		return { ok = true, bought = true }
	end

	Remotes.Get("EquipBait").OnServerInvoke = function(player, baitId)
		local profile = Data.Get(player)
		if profile and type(baitId) == "string" and profile.Baits[baitId] then
			profile.Bait = baitId
			PlayerService.Push(player)
			return { ok = true }
		end
		return fail("Not owned")
	end

	Remotes.Get("UpgradeTank").OnServerInvoke = function(player)
		return Shop.UpgradeTank(player)
	end
	Remotes.Get("BuyGear").OnServerInvoke = function(player)
		return Shop.BuyGear(player)
	end

	-- кнопки улучшения прямо на базе
	local function bindPlot(plot)
		if plot.TankPrompt and not plot.TankPrompt:GetAttribute("Bound") then
			plot.TankPrompt:SetAttribute("Bound", true)
			plot.TankPrompt.Triggered:Connect(function(player)
				if plot.Owner ~= player then
					PlayerService.Notify(player, "This is not your base!", Color3.fromRGB(255, 120, 90))
					return
				end
				local res = Shop.UpgradeTank(player)
				PlayerService.Notify(player, res.ok and "🐠 Aquarium upgraded!" or res.msg, res.ok and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 120, 90))
			end)
		end
	end
	for _, plot in ipairs(World.Plots) do
		bindPlot(plot)
		if plot.BarPrompt then
			plot.BarPrompt.Triggered:Connect(function(player)
				if plot.Owner ~= player then
					PlayerService.Notify(player, "This is not your base!", Color3.fromRGB(255, 120, 90))
					return
				end
				local res = Shop.BuyGear(player)
				PlayerService.Notify(player, res.ok and ("🏋️ Got " .. tostring(res.name) .. "!") or res.msg, res.ok and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 120, 90))
			end)
		end
	end
	World.OnTankPrompt = bindPlot
	Shop.InitSelling()
end

function Shop.UpgradeTank(player: Player)
	do
		local profile = Data.Get(player)
		if not profile then
			return fail("Loading")
		end
		if profile.TankLevel >= Config.MaxTankUpgrades then
			return fail("Aquarium is maxed!")
		end
		local cost = Config.TankUpgradeCost(profile.TankLevel)
		if profile.Cash < cost then
			return fail("Need " .. Format.Money(cost - profile.Cash) .. " more")
		end
		profile.Cash -= cost
		profile.TankLevel += 1
		PlayerService.UpdateAttributes(player)
		PlayerService.UpdateBase(player)
		PlayerService.SyncTank(player)
		PlayerService.Push(player)
		return { ok = true }
	end
end

function Shop.BuyGear(player: Player)
	do
		local profile = Data.Get(player)
		if not profile then
			return fail("Loading")
		end
		local nextGear = GameData.Gear[(profile.Gear or 1) + 1]
		if not nextGear then
			return fail("You have the best gear!")
		end
		if profile.Cash < nextGear.Price then
			return fail("Need " .. Format.Money(nextGear.Price - profile.Cash) .. " more")
		end
		profile.Cash -= nextGear.Price
		profile.Gear = (profile.Gear or 1) + 1
		PlayerService.UpdateAttributes(player)
		PlayerService.UpdateBase(player)
		PlayerService.Push(player)
		return { ok = true, name = nextGear.Id }
	end
end

function Shop.InitSelling()
	Remotes.Get("SellFish").OnServerInvoke = function(player, uid)
		local profile = Data.Get(player)
		if not profile or type(uid) ~= "number" then
			return fail("Bad request")
		end
		for i, f in ipairs(profile.Fish) do
			if f.U == uid then
				local price = sellPrice(f)
				table.remove(profile.Fish, i)
				profile.Cash += price
				PlayerService.SyncTank(player)
				PlayerService.UpdateAttributes(player)
				PlayerService.Push(player)
				return { ok = true, cash = price }
			end
		end
		return fail("Fish not found")
	end

	-- Продать всех рыб редкости не выше maxRarity (Legendary+ никогда не продаём оптом)
	Remotes.Get("SellBulk").OnServerInvoke = function(player, maxRarity)
		local profile = Data.Get(player)
		if not profile or type(maxRarity) ~= "number" then
			return fail("Bad request")
		end
		maxRarity = math.clamp(math.floor(maxRarity), 1, GameData.RarityIndex.Epic)
		local keep, total, count = {}, 0, 0
		for _, f in ipairs(profile.Fish) do
			local def = GameData.FishById[f.Id]
			if def and def.Rarity <= maxRarity and f.M == "None" then
				total += sellPrice(f)
				count += 1
			else
				table.insert(keep, f)
			end
		end
		if count == 0 then
			return fail("Nothing to sell")
		end
		profile.Fish = keep
		profile.Cash += total
		PlayerService.SyncTank(player)
		PlayerService.UpdateAttributes(player)
		PlayerService.Push(player)
		return { ok = true, cash = total, count = count }
	end

	Remotes.Get("GetState").OnServerInvoke = function(player)
		return PlayerService.Snapshot(player)
	end
end

return Shop
