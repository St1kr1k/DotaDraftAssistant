-- Вход/выход игроков, участки, удочка в руке, доход каждую секунду, синхронизация аквариума.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameData = require(Shared.GameData)
local Format = require(Shared.Format)
local FishBuilder = require(Shared.FishBuilder)
local Remotes = require(Shared.Remotes)

local Data = require(script.Parent.Data)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)

local PlayerService = {}

local rng = Random.new()

function PlayerService.Notify(player: Player, text: string, color: Color3?)
	Remotes.Get("Notify"):FireClient(player, text, color)
end

-- ===== Снимок данных для клиента =====
function PlayerService.Snapshot(player: Player)
	local profile = Data.Profiles[player]
	if not profile then
		return nil
	end
	local plot = World.PlotOf(player)
	return {
		Cash = profile.Cash,
		Power = profile.Power,
		TotalCaught = profile.TotalCaught,
		Baits = profile.Baits,
		Bait = profile.Bait,
		TankLevel = profile.TankLevel,
		Gear = profile.Gear,
		Fish = profile.Fish,
		Index = profile.Index,
		LuckyCasts = profile.LuckyCasts,
		TrainBoostEnds = profile.TrainBoostEnds,
		Capacity = Stats.Capacity(player, profile),
		BaseIncome = Stats.BaseIncome(player, profile),
		MaxDist = Stats.MaxDistance(profile),
		TrainMult = Stats.TrainMult(player, profile),
		PlotIndex = plot and plot.Index or 0,
		NoSave = Data.Session[player] and Data.Session[player].NoSave or false,
	}
end

-- Отправить снимок (не чаще раза за кадр)
function PlayerService.Push(player: Player)
	local session = Data.Session[player]
	if not session or session.PushQueued then
		return
	end
	session.PushQueued = true
	task.defer(function()
		if Data.Session[player] then
			Data.Session[player].PushQueued = false
			local snap = PlayerService.Snapshot(player)
			if snap then
				Remotes.Get("State"):FireClient(player, snap)
			end
		end
	end)
end

function PlayerService.UpdateAttributes(player: Player)
	local profile = Data.Profiles[player]
	if not profile then
		return
	end
	player:SetAttribute("Cash", profile.Cash)
	player:SetAttribute("Power", profile.Power)
	player:SetAttribute("Income", Stats.Income(player, profile))
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls :: any).Cash.Value = Format.Money(profile.Cash)
		;(ls :: any).Power.Value = Format.Number(profile.Power)
	end
end

function PlayerService.AddCash(player: Player, amount: number)
	local profile = Data.Profiles[player]
	if profile then
		profile.Cash = math.max(0, profile.Cash + amount)
		PlayerService.UpdateAttributes(player)
	end
end

-- ===== Аквариум: модели рыб =====
local function randomPointIn(water: BasePart, margin: number): Vector3
	local s = water.Size / 2 - Vector3.new(margin, margin * 0.6, margin * 0.6)
	s = Vector3.new(math.max(0.2, s.X), math.max(0.2, s.Y), math.max(0.2, s.Z))
	return (water.CFrame * CFrame.new(rng:NextNumber(-s.X, s.X), rng:NextNumber(-s.Y, s.Y), rng:NextNumber(-s.Z, s.Z))).Position
end

function PlayerService.SyncTank(player: Player)
	local plot = World.PlotOf(player)
	local profile = Data.Profiles[player]
	if not plot or not profile then
		return
	end
	local want = {}
	for _, f in ipairs(profile.Fish) do
		want[tostring(f.U)] = f
	end
	for _, m in ipairs(plot.FishFolder:GetChildren()) do
		local uid = m:GetAttribute("Uid")
		if not uid or not want[tostring(uid)] then
			m:Destroy()
		else
			want[tostring(uid)] = nil
		end
	end
	for uidStr, f in pairs(want) do
		local len = FishBuilder.DisplayLength(f.Id, f.S)
		local m = FishBuilder.Build(f.Id, f.M, len)
		m:SetAttribute("Uid", tonumber(uidStr))
		m:SetAttribute("Size", f.S)
		m:SetAttribute("Length", len)
		local pos = randomPointIn(plot.Water, len * 0.6)
		m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
		m.Parent = plot.FishFolder
	end
	PlayerService.UpdateSign(player)
end

function PlayerService.UpdateSign(player: Player)
	local plot = World.PlotOf(player)
	local profile = Data.Profiles[player]
	if plot and profile then
		plot.OwnerLabel.Text = #profile.Fish .. "/" .. Stats.Capacity(player, profile) .. " 🐟"
		plot.IncomeLabel.Text = Format.Money(Stats.Income(player, profile)) .. "/s"
	end
end

-- Вид базы: табличка на воротах, уровень аквариума и турника, цены на кнопках улучшения
function PlayerService.UpdateBase(player: Player)
	local plot = World.PlotOf(player)
	local profile = Data.Profiles[player]
	if not plot or not profile then
		return
	end
	for _, l in ipairs(plot.GateLabels) do
		l.Text = string.upper(player.DisplayName) .. "'S BASE"
		l.TextColor3 = plot.Color
	end
	local tier = math.min(4, profile.TankLevel or 0)
	if tier ~= plot.TankTier then
		World.RebuildTank(plot, tier)
	end
	World.SetBarTier(plot.BarModel, profile.Gear or 1)
	PlayerService.UpdateSign(player)
end

function PlayerService.ResetBase(plot)
	for _, l in ipairs(plot.GateLabels) do
		l.Text = "EMPTY BASE"
		l.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
	if plot.TankTier ~= 0 then
		World.RebuildTank(plot, 0)
	end
	World.SetBarTier(plot.BarModel, 1)
end

-- ===== Удочка в руке =====
local function giveRod(character: Model)
	local hand = character:WaitForChild("RightHand", 5) :: BasePart? or character:FindFirstChild("Right Arm") :: BasePart?
	if not hand then
		return
	end
	local old = character:FindFirstChild("Rod")
	if old then
		old:Destroy()
	end
	local rod = Instance.new("Model")
	rod.Name = "Rod"
	local isR15 = hand.Name == "RightHand"
	local handCf = hand.CFrame * (isR15 and CFrame.new(0, -0.15, 0) or CFrame.new(0, -0.9, 0))
	local dir = (handCf.RightVector * 0 + handCf.LookVector * 1 + handCf.UpVector * 0.65).Unit
	local base = CFrame.lookAt(handCf.Position, handCf.Position + dir)
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = base * offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Anchored = false
		p.Parent = rod
		local w = Instance.new("WeldConstraint")
		w.Part0 = hand
		w.Part1 = p
		w.Parent = p
		return p
	end
	part("Handle", Vector3.new(0.32, 0.32, 1.6), CFrame.new(0, 0, 0.2), Color3.fromRGB(60, 40, 30), Enum.Material.Fabric)
	part("Reel", Vector3.new(0.5, 0.5, 0.35), CFrame.new(0, -0.3, -0.2), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
	local shaft = part("Shaft", Vector3.new(0.14, 0.14, 7), CFrame.new(0, 0, -3.8), Color3.fromRGB(230, 120, 50))
	part("Ring", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0.1, -5), Color3.fromRGB(240, 240, 240), Enum.Material.Metal)
	local tip = Instance.new("Attachment")
	tip.Name = "RodTip"
	tip.Position = Vector3.new(0, 0, -3.5)
	tip.Parent = shaft
	rod.PrimaryPart = shaft
	rod.Parent = character
end

function PlayerService.SetRodVisible(character: Model?, visible: boolean)
	local rod = character and character:FindFirstChild("Rod")
	if rod then
		for _, p in ipairs(rod:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Transparency = visible and 0 or 1
			end
		end
	end
end

function PlayerService.TeleportToPlot(player: Player)
	local plot = World.PlotOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if plot and root then
		root.CFrame = plot.SpawnCf
	end
end

function PlayerService.TeleportToPier(player: Player)
	local pier = World.Pier
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if pier and root then
		-- свободное место (дальше всех от других игроков)
		local best, bestScore = pier.Spots[1], -1
		for _, spot in ipairs(pier.Spots) do
			local nearest = math.huge
			for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
				local orRoot = other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if orRoot then
					nearest = math.min(nearest, (orRoot.Position - spot.Position).Magnitude)
				end
			end
			if nearest > bestScore then
				best, bestScore = spot, nearest
			end
		end
		local p = best.Position + Vector3.new(0, 3.2, 0)
		root.CFrame = CFrame.lookAt(p, p + pier.Dir)
	end
end

local function onCharacter(player: Player, character: Model)
	task.spawn(giveRod, character)
	task.defer(function()
		character:WaitForChild("HumanoidRootPart", 5)
		task.wait(0.1)
		PlayerService.TeleportToPlot(player)
	end)
end

-- ===== Вход / выход =====
local function assignPlot(player: Player)
	for _, plot in ipairs(World.Plots) do
		if plot.Owner == nil then
			plot.Owner = player
			player:SetAttribute("PlotIndex", plot.Index)
			plot.Model:SetAttribute("OwnerId", player.UserId)
			return plot
		end
	end
	return nil
end

local function makeLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = "$0"
	cash.Parent = ls
	local power = Instance.new("StringValue")
	power.Name = "Power"
	power.Value = "0"
	power.Parent = ls
	ls.Parent = player
end

function PlayerService.OnJoin(player: Player, applyPasses: (Player) -> ())
	makeLeaderstats(player)
	local plot = assignPlot(player)
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
	applyPasses(player)
	local profile = Data.Load(player)
	if not profile then
		return
	end
	-- старые уровни аквариума (было 16 мелких) -> новые 4 больших
	profile.TankLevel = math.clamp(profile.TankLevel or 0, 0, Config.MaxTankUpgrades)
	-- старые записи без Uid
	for _, f in ipairs(profile.Fish) do
		if not f.U then
			f.U = profile.NextUid
			profile.NextUid += 1
		end
	end
	-- доход оффлайн
	if (profile.LastOnline or 0) > 0 then
		local elapsed = math.min(os.time() - profile.LastOnline, Config.OfflineMaxSeconds)
		local earned = math.floor(Stats.BaseIncome(player, profile) * elapsed * Config.OfflineRate)
		if earned > 0 and elapsed > 60 then
			profile.Cash += earned
			task.delay(3, function()
				if player.Parent then
					Remotes.Get("Offline"):FireClient(player, earned, elapsed)
				end
			end)
		end
	end
	profile.LastOnline = os.time()
	if not plot then
		PlayerService.Notify(player, "Server is full of plots — rejoin another server!", Color3.fromRGB(255, 90, 90))
	end
	PlayerService.UpdateAttributes(player)
	PlayerService.UpdateBase(player)
	PlayerService.SyncTank(player)
	PlayerService.Push(player)
	if player.Character then
		onCharacter(player, player.Character)
	end
	if Data.Session[player] and Data.Session[player].NoSave then
		task.delay(4, function()
			if player.Parent then
				PlayerService.Notify(player, "⚠️ Saving is OFF (Studio: enable API Services in Game Settings)", Color3.fromRGB(255, 170, 60))
			end
		end)
	end
end

function PlayerService.OnLeave(player: Player)
	local plot = World.PlotOf(player)
	Data.Release(player)
	if plot then
		plot.Owner = nil
		plot.Model:SetAttribute("OwnerId", nil)
		plot.FishFolder:ClearAllChildren()
		plot.OwnerLabel.Text = ""
		plot.IncomeLabel.Text = ""
		PlayerService.ResetBase(plot)
	end
end

-- ===== Доход каждую секунду =====
function PlayerService.StartIncomeLoop()
	task.spawn(function()
		local signTimer = 0
		while true do
			task.wait(1)
			signTimer += 1
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = Data.Profiles[player]
				if profile then
					local inc = Stats.Income(player, profile)
					if inc > 0 then
						profile.Cash += inc
					end
					PlayerService.UpdateAttributes(player)
					if signTimer % 5 == 0 then
						PlayerService.UpdateSign(player)
					end
				end
			end
		end
	end)
end

-- Добавить рыбу; если аквариум полон — заменить самую слабую (если новая лучше), иначе продать новую
function PlayerService.AddFish(player: Player, fishId: string, mutation: string, sizeIndex: number)
	local profile = Data.Profiles[player]
	local entry = { U = profile.NextUid, Id = fishId, M = mutation, S = sizeIndex }
	profile.NextUid += 1
	local isNew = not profile.Index[fishId]
	profile.Index[fishId] = true
	profile.TotalCaught += 1
	local cap = Stats.Capacity(player, profile)
	local newIncome = GameData.FishIncome(fishId, mutation, sizeIndex)
	local outcome = { Kind = "added", IsNew = isNew, Uid = entry.U }
	if #profile.Fish < cap then
		table.insert(profile.Fish, entry)
	else
		local worstIdx, worstIncome = nil, math.huge
		for i, f in ipairs(profile.Fish) do
			local inc = GameData.FishIncome(f.Id, f.M, f.S)
			if inc < worstIncome then
				worstIdx, worstIncome = i, inc
			end
		end
		if worstIdx and newIncome > worstIncome then
			local old = profile.Fish[worstIdx]
			local price = math.floor(worstIncome * Config.SellSeconds)
			profile.Cash += price
			profile.Fish[worstIdx] = entry
			outcome = { Kind = "swapped", IsNew = isNew, Uid = entry.U, Old = GameData.FullName(old.Id, old.M, old.S), Cash = price }
		else
			local price = math.floor(newIncome * Config.SellSeconds)
			profile.Cash += price
			outcome = { Kind = "sold", IsNew = isNew, Cash = price }
		end
	end
	PlayerService.SyncTank(player)
	PlayerService.UpdateAttributes(player)
	PlayerService.Push(player)
	return outcome
end

return PlayerService
