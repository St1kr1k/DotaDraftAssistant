-- Приёмы на сервере: цель, двойники, перемещения, урон. Анимации и эффекты играют клиенты по командам отсюда.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Moves = require(Shared.Moves)
local Clips = require(Shared.Clips)

local Combat = {}

local cooldowns = {} :: { [Player]: { [string]: number } }
local busy = {} :: { [Model]: boolean }
local clonesFolder: Folder

local function clipLen(name: string): number
	return Clips[name].Length
end

local function marker(clip: string, name: string): number
	for _, m in ipairs(Clips[clip].Markers) do
		if m.name == name then
			return m.t
		end
	end
	return 0
end

local function play(model: Model, clip: string, speed: number?)
	Net.Get("Play"):FireAllClients(model, clip, speed or 1)
end

local function stopAnim(model: Model)
	Net.Get("Stop"):FireAllClients(model)
end

local function fx(name: string, ...)
	Net.Get("Fx"):FireAllClients(name, ...)
end

local function root(model: Model): BasePart?
	return model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function alive(model: Model?): boolean
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and model.Parent ~= nil
end

local function groundY(pos: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or 0
end

local function hipOffset(model: Model): number
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = root(model)
	if hum and hrp then
		return hum.HipHeight + hrp.Size.Y / 2
	end
	return 3
end

-- Заморозить модель (якорь), чтобы сервер двигал её сам
local function lock(model: Model, on: boolean)
	local hrp = root(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hrp then
		hrp.Anchored = on
	end
	if hum then
		hum.AutoRotate = not on
	end
	model:SetAttribute("Locked", on)
end

local function moveTo(model: Model, cf: CFrame, time: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local hrp = root(model)
	if not hrp then
		return
	end
	if time <= 0 then
		hrp.CFrame = cf
		return
	end
	TweenService:Create(hrp, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), { CFrame = cf }):Play()
end

local function damage(model: Model, amount: number, by: Model?)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum:TakeDamage(amount)
		local hrp = root(model)
		if hrp then
			fx("Damage", hrp.Position + Vector3.new(0, 3, 0), amount)
		end
		if by then
			local attacker = Players:GetPlayerFromCharacter(by)
			if attacker then
				Net.Get("Fx"):FireClient(attacker, "Combo", 1)
			end
		end
	end
end

-- Ближайшая цель впереди
local function findTarget(attacker: Model): Model?
	local hrp = root(attacker)
	if not hrp then
		return nil
	end
	local best, bestScore = nil, math.huge
	local candidates = CollectionService:GetTagged("Fighter")
	for _, m in ipairs(candidates) do
		if m ~= attacker and alive(m) and not busy[m] and not CollectionService:HasTag(m, "Clone") then
			local r = root(m)
			if r then
				local d = r.Position - hrp.Position
				local dist = d.Magnitude
				if dist <= Moves.Range then
					local facing = hrp.CFrame.LookVector:Dot(d.Unit)
					local score = dist - facing * 8
					if score < bestScore then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	return best
end

-- Двойник: копия внешности бойца
local function makeClone(char: Model, cf: CFrame): Model
	char.Archivable = true
	local c = char:Clone()
	char.Archivable = false
	c.Name = "ShadowClone"
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	local hrp = c:FindFirstChild("HumanoidRootPart") :: BasePart
	hrp.Anchored = true
	c:PivotTo(cf)
	CollectionService:AddTag(c, "Clone")
	c.Parent = clonesFolder
	return c
end

local function poof(c: Model)
	local hrp = root(c)
	if hrp then
		fx("Smoke", hrp.Position, 1)
	end
	task.delay(0.08, function()
		c:Destroy()
	end)
end

local function faceTo(model: Model, target: Vector3)
	local hrp = root(model)
	if hrp then
		local p = hrp.Position
		local flat = Vector3.new(target.X, p.Y, target.Z)
		if (flat - p).Magnitude > 0.1 then
			hrp.CFrame = CFrame.lookAt(p, flat)
		end
	end
end

-- ===================== Уклонение =====================
local function dodge(player: Player, char: Model, dir: Vector3?)
	local hrp = root(char)
	if not hrp then
		return
	end
	local d = (typeof(dir) == "Vector3" and dir.Magnitude > 0.1) and Vector3.new(dir.X, 0, dir.Z).Unit or -hrp.CFrame.LookVector
	busy[char] = true
	lock(char, true)
	play(char, "Dodge")
	task.wait(marker("Dodge", "vanish"))
	fx("Vanish", char, true)
	fx("Dust", hrp.Position - Vector3.new(0, hipOffset(char) - 0.5, 0), 1)
	local target = hrp.Position + d * 8
	moveTo(char, CFrame.lookAt(target, target + hrp.CFrame.LookVector), 0)
	task.wait(marker("Dodge", "appear") - marker("Dodge", "vanish"))
	fx("Vanish", char, false)
	fx("Afterimage", char)
	fx("Dust", target - Vector3.new(0, hipOffset(char) - 0.5, 0), 1.2)
	task.wait(clipLen("Dodge") - marker("Dodge", "appear"))
	lock(char, false)
	busy[char] = nil
	stopAnim(char)
end

-- ===================== Комбо двойников =====================
local function cloneCombo(player: Player, char: Model, target: Model)
	local hrp, thrp = root(char), root(target)
	if not hrp or not thrp then
		return
	end
	busy[char], busy[target] = true, true
	lock(char, true)
	lock(target, true)
	faceTo(char, thrp.Position)
	faceTo(target, hrp.Position)
	local dmg = Moves.CloneCombo.Damage
	fx("Aura", char, true)
	play(char, "HandSeal", 1.4)
	task.wait(0.15)
	fx("ChakraBurst", hrp.Position + hrp.CFrame.LookVector * 1.5 + Vector3.new(0, 1, 0), 0.8)
	task.wait(0.25)
	-- два двойника у врага
	local tpos = thrp.Position
	local toAttacker = (hrp.Position - tpos) * Vector3.new(1, 0, 1)
	toAttacker = toAttacker.Magnitude > 0.1 and toAttacker.Unit or Vector3.new(0, 0, 1)
	local side = toAttacker:Cross(Vector3.yAxis).Unit
	local spots = { tpos + toAttacker * 3 + side * 2.6, tpos + toAttacker * 3 - side * 2.6 }
	local clones = {}
	for i, p in ipairs(spots) do
		local c = makeClone(char, CFrame.lookAt(p, Vector3.new(tpos.X, p.Y, tpos.Z)))
		fx("Smoke", p, 1)
		fx("Trails", c, true)
		play(c, "FightIdle")
		clones[i] = c
	end
	task.wait(0.2)
	local sequence = {
		{ clones[1], "CloneRushPunch" },
		{ clones[2], "CloneSpinKick" },
		{ clones[1], "CloneSweep" },
		{ clones[2], "CloneRushPunch" },
	}
	for i, step in ipairs(sequence) do
		local c, clip = step[1], step[2]
		local cr = root(c)
		if not alive(target) or not cr then
			break
		end
		-- двойник подскакивает вплотную
		local flatDir = (cr.Position - thrp.Position) * Vector3.new(1, 0, 1)
		flatDir = flatDir.Magnitude > 0.1 and flatDir.Unit or toAttacker
		local close = thrp.Position + flatDir * 2.6
		moveTo(c, CFrame.lookAt(close, Vector3.new(thrp.Position.X, close.Y, thrp.Position.Z)), 0.08)
		play(c, clip)
		task.wait(marker(clip, "hit"))
		local hitDir = (thrp.Position - cr.Position).Unit
		fx("Impact", thrp.Position + Vector3.new(0, 1, 0) - hitDir, hitDir, 1.1)
		fx("HitStop", c, target, 0.06)
		play(target, "Hurt")
		damage(target, dmg[i], char)
		moveTo(target, thrp.CFrame + hitDir * 0.6, 0.1)
		task.wait(math.max(0.05, clipLen(clip) - marker(clip, "hit") - 0.12))
	end
	-- добивание: рывок и удар, отбрасывающий врага
	if alive(target) then
		local dirIn = (thrp.Position - hrp.Position) * Vector3.new(1, 0, 1)
		dirIn = dirIn.Magnitude > 0.1 and dirIn.Unit or hrp.CFrame.LookVector
		local strikePos = thrp.Position - dirIn * 3.2
		strikePos = Vector3.new(strikePos.X, hrp.Position.Y, strikePos.Z)
		fx("Afterimage", char)
		fx("Trails", char, true)
		moveTo(char, CFrame.lookAt(strikePos, strikePos + dirIn), 0.12, Enum.EasingStyle.Quint)
		play(char, "FinisherPunch")
		for _, c in ipairs(clones) do
			poof(c)
		end
		task.wait(marker("FinisherPunch", "charge"))
		fx("ChakraBurst", strikePos + dirIn * 1.2 + Vector3.new(0, 1, 0), 0.6)
		task.wait(marker("FinisherPunch", "hit") - marker("FinisherPunch", "charge"))
		fx("Impact", thrp.Position + Vector3.new(0, 1, 0) - dirIn, dirIn, 2.6)
		fx("HitStop", char, target, 0.12)
		fx("Flash", 0.25)
		damage(target, dmg[5], char)
		play(target, "KnockBack")
		local back = thrp.Position + dirIn * 26
		back = Vector3.new(back.X, groundY(back, { target, char }) + hipOffset(target), back.Z)
		moveTo(target, CFrame.lookAt(back, back - dirIn), 0.55, Enum.EasingStyle.Quart)
		fx("DustTrail", target, 0.55)
		task.wait(clipLen("FinisherPunch") - marker("FinisherPunch", "hit"))
	end
	for _, c in ipairs(clones) do
		if c.Parent then
			poof(c)
		end
	end
	fx("Aura", char, false)
	fx("Trails", char, false)
	lock(char, false)
	busy[char] = nil
	stopAnim(char)
	task.wait(0.4)
	if target.Parent then
		play(target, "GetUp")
		task.wait(clipLen("GetUp"))
		lock(target, false)
		stopAnim(target)
	end
	busy[target] = nil
end

-- ===================== Суперудар: знак -> 4 подката -> удар пяткой =====================
local function super(player: Player, char: Model, target: Model)
	local hrp, thrp = root(char), root(target)
	if not hrp or not thrp then
		return
	end
	busy[char], busy[target] = true, true
	lock(char, true)
	lock(target, true)
	faceTo(char, thrp.Position)
	faceTo(target, hrp.Position)
	local dmg = Moves.Super.Damage
	Net.Get("Cine"):FireClient(player, "Super", char, target)
	-- 1) знак руками
	play(char, "HandSeal")
	task.wait(marker("HandSeal", "seal"))
	fx("Aura", char, true)
	fx("ChakraBurst", hrp.Position + hrp.CFrame.LookVector * 1.4 + Vector3.new(0, 1.2, 0), 1.2)
	fx("Flash", 0.2)
	task.wait(clipLen("HandSeal") - marker("HandSeal", "seal"))

	-- 2) четыре двойника по очереди подкатываются и бьют вверх
	local base = thrp.Position
	local floor = groundY(base, { target, char })
	local hip = hipOffset(target)
	local toAttacker = (hrp.Position - base) * Vector3.new(1, 0, 1)
	toAttacker = toAttacker.Magnitude > 0.1 and toAttacker.Unit or Vector3.new(0, 0, 1)
	local height = 0
	for i = 1, 4 do
		if not alive(target) then
			break
		end
		local a = math.rad(i * 90 + 45)
		local out = CFrame.Angles(0, a, 0):VectorToWorldSpace(toAttacker)
		local startPos = Vector3.new(base.X, floor + hipOffset(char), base.Z) + out * 9
		local c = makeClone(char, CFrame.lookAt(startPos, Vector3.new(base.X, startPos.Y, base.Z)))
		fx("Smoke", startPos, 0.9)
		fx("Trails", c, true)
		play(c, "CloneKickUp")
		-- подкат под врага (тело низко над землёй — смещение в клипе)
		local under = Vector3.new(base.X, startPos.Y, base.Z) + out * 1.6
		moveTo(c, CFrame.lookAt(under, Vector3.new(base.X, under.Y, base.Z) - out * 5), 0.2, Enum.EasingStyle.Quad)
		fx("DustTrail", c, 0.2)
		task.wait(marker("CloneKickUp", "hit"))
		-- удар вверх
		height += 4.5
		local up = Vector3.new(base.X, floor + hip + height, base.Z)
		fx("Impact", thrp.Position, Vector3.yAxis, 1.3)
		fx("UpStreak", thrp.Position)
		fx("HitStop", c, target, 0.05)
		play(target, "Launched")
		damage(target, dmg[i], char)
		moveTo(target, CFrame.lookAt(up, up + toAttacker), 0.22, Enum.EasingStyle.Quart)
		local cc = c
		task.delay(0.35, function()
			poof(cc)
		end)
		task.wait(0.16)
	end

	-- 3) трамплин из двойника и удар пяткой
	if alive(target) then
		local boostPos = Vector3.new(base.X, floor + hipOffset(char), base.Z) + toAttacker * 5
		local boost = makeClone(char, CFrame.lookAt(boostPos, Vector3.new(base.X, boostPos.Y, base.Z)))
		fx("Smoke", boostPos, 1)
		play(boost, "CloneBoost")
		-- боец исчезает и появляется у спины двойника
		fx("Smoke", hrp.Position, 1)
		local onBack = boostPos + toAttacker * 1.8 + Vector3.new(0, 2.2, 0)
		moveTo(char, CFrame.lookAt(onBack, Vector3.new(base.X, onBack.Y, base.Z)), 0)
		fx("Trails", char, true)
		play(char, "HeelDrop")
		task.wait(marker("HeelDrop", "jump"))
		fx("Dust", boostPos, 1.4)
		poof(boost)
		-- прыжок над врагом
		local above = thrp.Position + Vector3.new(0, 6, 0) + toAttacker * 1.2
		moveTo(char, CFrame.lookAt(above, Vector3.new(base.X, above.Y, base.Z)), 0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.wait(marker("HeelDrop", "hit") - marker("HeelDrop", "jump"))
		-- удар пяткой — враг летит в землю
		fx("Impact", thrp.Position + Vector3.new(0, 1.5, 0), -Vector3.yAxis, 2.8)
		fx("HitStop", char, target, 0.14)
		damage(target, dmg[5], char)
		local slamPos = Vector3.new(base.X, floor + 0.2, base.Z)
		play(target, "Slammed")
		moveTo(target, CFrame.lookAt(slamPos + Vector3.new(0, hip, 0), slamPos + Vector3.new(0, hip, 0) + toAttacker), 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.12)
		fx("Crater", slamPos, 10)
		-- приземление рядом с кратером
		local land = Vector3.new(base.X, floor + hipOffset(char), base.Z) + toAttacker * 5
		moveTo(char, CFrame.lookAt(land, Vector3.new(base.X, land.Y, base.Z)), marker("HeelDrop", "land") - marker("HeelDrop", "hit") - 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(marker("HeelDrop", "land") - marker("HeelDrop", "hit") - 0.12)
		fx("Dust", land - Vector3.new(0, hipOffset(char) - 0.5, 0), 1.5)
		task.wait(clipLen("HeelDrop") - marker("HeelDrop", "land"))
	end
	fx("Aura", char, false)
	fx("Trails", char, false)
	lock(char, false)
	busy[char] = nil
	stopAnim(char)
	task.wait(0.8)
	if target.Parent then
		play(target, "GetUp")
		task.wait(clipLen("GetUp"))
		lock(target, false)
		stopAnim(target)
	end
	busy[target] = nil
end

-- ===================== Манекены =====================
local dummySpots = { Vector3.new(-14, 0, 0), Vector3.new(0, 0, -6), Vector3.new(14, 0, 0) }

local function spawnDummy(pos: Vector3)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = Color3.fromRGB(200, 180, 160)
	desc.TorsoColor = Color3.fromRGB(90, 70, 60)
	desc.LeftArmColor = desc.HeadColor
	desc.RightArmColor = desc.HeadColor
	desc.LeftLegColor = Color3.fromRGB(60, 50, 45)
	desc.RightLegColor = Color3.fromRGB(60, 50, 45)
	local ok, dummy = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not dummy then
		warn("[Combat] dummy: " .. tostring(dummy))
		return
	end
	dummy.Name = "Training Dummy"
	local hum = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.MaxHealth = 600
	hum.Health = 600
	hum.WalkSpeed = 0
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	dummy:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 4, 0), Vector3.new(0, 4, 40)))
	dummy.Parent = workspace
	CollectionService:AddTag(dummy, "Fighter")
	CollectionService:AddTag(dummy, "Dummy")
	hum.Died:Connect(function()
		task.wait(3)
		dummy:Destroy()
		spawnDummy(pos)
	end)
	-- медленное восстановление здоровья
	task.spawn(function()
		while dummy.Parent do
			task.wait(1)
			if hum.Health > 0 and hum.Health < hum.MaxHealth and not busy[dummy] then
				hum.Health = math.min(hum.MaxHealth, hum.Health + 20)
			end
		end
	end)
end

-- ===================== Вход =====================
local ACTIONS = {
	Dodge = function(player, char, arg)
		dodge(player, char, arg)
	end,
	CloneCombo = function(player, char)
		local target = findTarget(char)
		if not target then
			Net.Get("Fx"):FireClient(player, "Toast", "No target in range")
			return false
		end
		cloneCombo(player, char, target)
	end,
	Super = function(player, char)
		local target = findTarget(char)
		if not target then
			Net.Get("Fx"):FireClient(player, "Toast", "No target in range")
			return false
		end
		super(player, char, target)
	end,
}

function Combat.Init()
	clonesFolder = Instance.new("Folder")
	clonesFolder.Name = "Clones"
	clonesFolder.Parent = workspace

	Players.PlayerAdded:Connect(function(player)
		cooldowns[player] = {}
		player.CharacterAdded:Connect(function(char)
			CollectionService:AddTag(char, "Fighter")
			busy[char] = nil
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)

	Net.Get("Action").OnServerEvent:Connect(function(player, name, arg)
		local move = type(name) == "string" and Moves[name]
		local fn = type(name) == "string" and ACTIONS[name]
		local char = player.Character
		if not move or not fn or not char or not alive(char) or busy[char] then
			return
		end
		local cd = cooldowns[player] or {}
		cooldowns[player] = cd
		local now = os.clock()
		if (cd[name] or 0) > now then
			return
		end
		cd[name] = now + move.Cooldown
		Net.Get("Cooldown"):FireClient(player, name, move.Cooldown)
		task.spawn(function()
			local ok, res = pcall(fn, player, char, arg)
			if not ok then
				warn("[Combat] " .. name .. ": " .. tostring(res))
				lock(char, false)
				busy[char] = nil
				fx("Aura", char, false)
			elseif res == false then
				cd[name] = 0
				Net.Get("Cooldown"):FireClient(player, name, 0)
			end
		end)
	end)

	for _, p in ipairs(dummySpots) do
		task.spawn(spawnDummy, p)
	end
end

return Combat
