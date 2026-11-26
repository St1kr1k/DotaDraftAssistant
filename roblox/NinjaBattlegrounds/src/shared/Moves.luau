-- Приёмы: клавиши, перезарядка, урон. Тайминги берутся из клипов (Clips.luau).
local Moves = {
	Dodge = { Key = Enum.KeyCode.Q, Cooldown = 2, Name = "Dodge", Icon = "💨" },
	CloneCombo = { Key = Enum.KeyCode.One, Cooldown = 8, Name = "Clone Combo", Icon = "👥", Damage = { 6, 6, 6, 6, 22 } },
	Super = { Key = Enum.KeyCode.G, Cooldown = 20, Name = "Super: Heel Drop", Icon = "⚡", Damage = { 5, 5, 5, 5, 30 } },
}
Moves.Order = { "CloneCombo", "Super", "Dodge" }
Moves.Range = 30 -- на каком расстоянии ищем цель
return Moves
