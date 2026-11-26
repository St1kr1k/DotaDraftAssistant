-- Сетевые события. Сервер создаёт, клиент ждёт.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}
local NAMES = {
	"Action", -- клиент -> сервер: (имя приёма, параметры)
	"Play", -- сервер -> все: (модель, клип, скорость)
	"Stop", -- сервер -> все: (модель)
	"Fx", -- сервер -> все: (эффект, ...)
	"Cine", -- сервер -> игроку: (сцена камеры, ...)
	"Cooldown", -- сервер -> игроку: (приём, секунды)
}

function Net.Init()
	assert(RunService:IsServer())
	local f = Instance.new("Folder")
	f.Name = "Net"
	for _, n in ipairs(NAMES) do
		local e = Instance.new("RemoteEvent")
		e.Name = n
		e.Parent = f
	end
	f.Parent = ReplicatedStorage
end

function Net.Get(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Net"):WaitForChild(name) :: RemoteEvent
end

return Net
