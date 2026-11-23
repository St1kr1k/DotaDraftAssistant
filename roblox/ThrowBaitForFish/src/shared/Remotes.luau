-- Все сетевые вызовы между клиентом и сервером. Сервер создаёт, клиент ждёт.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- RemoteFunction: клиент спрашивает — сервер отвечает
Remotes.Functions = {
	"Cast", -- (charge 0..1) -> результат заброса
	"Reel", -- () -> пойманная рыба
	"BuyBait", -- (baitId)
	"EquipBait", -- (baitId)
	"UpgradeTank", -- ()
	"BuyGear", -- () — следующий снаряд
	"SellFish", -- (uid)
	"SellBulk", -- (maxRarity)
	"StopTraining", -- ()
	"GoToPier", -- ()
	"GoToBase", -- ()
	"DevGrant", -- (key) — только в Studio, для теста доната без Id
	"GetState", -- () -> снимок данных игрока
}

-- RemoteEvent
Remotes.Events = {
	"State", -- сервер -> клиент: снимок данных игрока
	"Notify", -- сервер -> клиент: (text, color?)
	"CastFx", -- сервер -> всем: чужой заброс (userId, from, to, flight, total)
	"Rep", -- клиент -> сервер: клик на турнике; сервер -> клиент: (+power)
	"Offline", -- сервер -> клиент: (cash, seconds)
	"BigCatch", -- сервер -> всем: (playerName, fishId, mutation, size)
}

local folder: Folder? = nil

function Remotes.Init()
	assert(RunService:IsServer())
	local f = Instance.new("Folder")
	f.Name = "Remotes"
	for _, name in ipairs(Remotes.Functions) do
		local rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = f
	end
	for _, name in ipairs(Remotes.Events) do
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = f
	end
	f.Parent = ReplicatedStorage
	folder = f
end

function Remotes.Get(name: string): any
	if not folder then
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return (folder :: Folder):WaitForChild(name)
end

return Remotes
