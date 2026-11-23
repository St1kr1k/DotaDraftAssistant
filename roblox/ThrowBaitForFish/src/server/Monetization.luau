-- Донат: геймпассы (навсегда) и товары разработчика (расходники).
-- Id берутся из Config. Пока Id = 0, в Studio покупка выдаётся бесплатно через DevGrant (для теста).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Data = require(script.Parent.Data)
local PlayerService = require(script.Parent.PlayerService)

local Monetization = {}

-- все геймпассы одним списком: key -> id
local function allPasses(): { [string]: number }
	local list = {}
	for _, p in ipairs(Config.TrainingPasses) do
		list[p.Key] = p.Id
	end
	for key, p in pairs(Config.Passes) do
		list[key] = p.Id
	end
	return list
end

local function passKeyById(id: number): string?
	for key, pid in pairs(allPasses()) do
		if pid == id and pid ~= 0 then
			return key
		end
	end
	return nil
end

local function productKeyById(id: number): string?
	for key, p in pairs(Config.Products) do
		if p.Id == id and p.Id ~= 0 then
			return key
		end
	end
	return nil
end

local function grantPass(player: Player, key: string)
	player:SetAttribute("Pass_" .. key, true)
	PlayerService.UpdateAttributes(player)
	PlayerService.UpdateSign(player)
	PlayerService.Push(player)
end

-- Применить товар. Возвращает true, если выдан.
local function grantProduct(player: Player, key: string): boolean
	local profile = Data.Get(player)
	if not profile then
		return false
	end
	if key == "LuckyCast1" then
		profile.LuckyCasts += 1
	elseif key == "LuckyCast10" then
		profile.LuckyCasts += 10
	elseif key == "TrainBoost" then
		profile.TrainBoostEnds = math.max(os.time(), profile.TrainBoostEnds or 0) + Config.TrainBoostSeconds
	elseif key == "ServerLuck2" or key == "ServerLuck4" or key == "ServerLuck8" then
		local mult = tonumber(string.sub(key, -1)) or 2
		local now = os.time()
		local curMult = workspace:GetAttribute("ServerLuck") or 1
		local curEnds = workspace:GetAttribute("ServerLuckEnds") or 0
		if curEnds > now and curMult >= mult then
			workspace:SetAttribute("ServerLuckEnds", curEnds + Config.ServerLuckSeconds)
		else
			workspace:SetAttribute("ServerLuck", mult)
			workspace:SetAttribute("ServerLuckEnds", now + Config.ServerLuckSeconds)
		end
		local text = "🍀 " .. player.DisplayName .. " activated SERVER LUCK x" .. mult .. "!"
		for _, p in ipairs(Players:GetPlayers()) do
			PlayerService.Notify(p, text, Color3.fromRGB(120, 255, 120))
		end
	else
		return false
	end
	PlayerService.Push(player)
	return true
end

function Monetization.ApplyPasses(player: Player)
	for key, id in pairs(allPasses()) do
		if id ~= 0 then
			task.spawn(function()
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
				if ok and owns and player.Parent then
					grantPass(player, key)
				end
			end)
		end
	end
end

function Monetization.Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local key = passKeyById(passId)
			if key then
				grantPass(player, key)
				PlayerService.Notify(player, "✅ Thanks for the support!", Color3.fromRGB(120, 255, 120))
			end
		end
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local profile = player and Data.Get(player)
		if not player or not profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		profile.Receipts = profile.Receipts or {}
		for _, id in ipairs(profile.Receipts) do
			if id == receipt.PurchaseId then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end
		local key = productKeyById(receipt.ProductId)
		if not key or not grantProduct(player, key) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(profile.Receipts, receipt.PurchaseId)
		while #profile.Receipts > 50 do
			table.remove(profile.Receipts, 1)
		end
		task.spawn(Data.Save, player)
		PlayerService.Notify(player, "✅ Purchase received!", Color3.fromRGB(120, 255, 120))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Тест доната в Studio без настоящих Id
	Remotes.Get("DevGrant").OnServerInvoke = function(player, key)
		if not RunService:IsStudio() or type(key) ~= "string" then
			return false
		end
		if Config.Products[key] then
			grantProduct(player, key)
			return true
		end
		if allPasses()[key] ~= nil then
			grantPass(player, key)
			return true
		end
		return false
	end
end

return Monetization
