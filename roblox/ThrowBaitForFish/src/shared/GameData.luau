-- Справочник игры: редкости, зоны, рыбы, мутации, размеры, наживки, события.

local GameData = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- ===== Редкости =====
GameData.Rarities = {
	{ Name = "Common", Color = rgb(205, 210, 215), Weight = 60, Income = 1 },
	{ Name = "Uncommon", Color = rgb(95, 225, 95), Weight = 25, Income = 2.5 },
	{ Name = "Rare", Color = rgb(70, 160, 255), Weight = 10, Income = 6 },
	{ Name = "Epic", Color = rgb(185, 95, 255), Weight = 4, Income = 15 },
	{ Name = "Legendary", Color = rgb(255, 195, 40), Weight = 0.9, Income = 40 },
	{ Name = "Mythic", Color = rgb(255, 60, 95), Weight = 0.1, Income = 120 },
	{ Name = "Secret", Color = rgb(255, 255, 255), Weight = 0.012, Income = 600 },
}
GameData.RarityIndex = {}
for i, r in ipairs(GameData.Rarities) do
	GameData.RarityIndex[r.Name] = i
end

-- ===== Зоны (дальность от края причала) =====
GameData.Zones = {
	{ Name = "Shallows", Dist = 0, Color = rgb(120, 235, 220), Income = 1 },
	{ Name = "Coral Reef", Dist = 55, Color = rgb(255, 130, 170), Income = 4 },
	{ Name = "Kelp Forest", Dist = 120, Color = rgb(90, 200, 90), Income = 16 },
	{ Name = "Open Sea", Dist = 200, Color = rgb(60, 150, 255), Income = 70 },
	{ Name = "Deep Blue", Dist = 300, Color = rgb(40, 80, 220), Income = 320 },
	{ Name = "Abyss", Dist = 420, Color = rgb(140, 60, 220), Income = 1500 },
	{ Name = "Megalodon Trench", Dist = 560, Color = rgb(255, 80, 40), Income = 8000 },
}

function GameData.ZoneForDistance(d: number): number
	local z = 1
	for i, zone in ipairs(GameData.Zones) do
		if d >= zone.Dist then
			z = i
		end
	end
	return z
end

-- ===== Рыбы =====
-- Shape: fish, puffer, shark, ray, jelly, squid, octopus, eel, whale, turtle, angler
-- C1 — основной цвет, C2 — живот/второй, C3 — плавники/акцент.
-- Флаги: Stripes, Sword, Hammer, Teeth, Glow, Spikes, Tall, Spots, Big
local R = GameData.RarityIndex
GameData.Fish = {
	-- Shallows
	{ Id = "Guppy", Zone = 1, Rarity = R.Common, Shape = "fish", C1 = rgb(255, 150, 60), C2 = rgb(255, 225, 170), C3 = rgb(255, 205, 70) },
	{ Id = "Clownfish", Zone = 1, Rarity = R.Uncommon, Shape = "fish", C1 = rgb(255, 120, 30), C2 = rgb(255, 255, 255), C3 = rgb(30, 30, 30), Stripes = true },
	{ Id = "Pufferfish", Zone = 1, Rarity = R.Rare, Shape = "puffer", C1 = rgb(250, 215, 90), C2 = rgb(255, 250, 220), C3 = rgb(170, 130, 50), Spikes = true },
	{ Id = "Angelfish", Zone = 1, Rarity = R.Epic, Shape = "fish", C1 = rgb(60, 120, 255), C2 = rgb(255, 230, 60), C3 = rgb(255, 230, 60), Tall = true, Stripes = true },
	{ Id = "Golden Koi", Zone = 1, Rarity = R.Legendary, Shape = "fish", C1 = rgb(255, 200, 40), C2 = rgb(255, 255, 255), C3 = rgb(255, 120, 40), Spots = true },
	{ Id = "Baby Shark", Zone = 1, Rarity = R.Mythic, Shape = "shark", C1 = rgb(255, 215, 60), C2 = rgb(255, 250, 230), C3 = rgb(255, 170, 40), Cute = true },

	-- Coral Reef
	{ Id = "Blue Tang", Zone = 2, Rarity = R.Common, Shape = "fish", C1 = rgb(40, 110, 255), C2 = rgb(30, 60, 150), C3 = rgb(255, 225, 40) },
	{ Id = "Parrotfish", Zone = 2, Rarity = R.Uncommon, Shape = "fish", C1 = rgb(40, 210, 190), C2 = rgb(255, 130, 200), C3 = rgb(255, 130, 200) },
	{ Id = "Lionfish", Zone = 2, Rarity = R.Rare, Shape = "fish", C1 = rgb(220, 60, 50), C2 = rgb(255, 240, 230), C3 = rgb(255, 240, 230), Stripes = true, Spikes = true },
	{ Id = "Sea Turtle", Zone = 2, Rarity = R.Epic, Shape = "turtle", C1 = rgb(120, 85, 45), C2 = rgb(235, 220, 170), C3 = rgb(110, 180, 110) },
	{ Id = "Manta Ray", Zone = 2, Rarity = R.Legendary, Shape = "ray", C1 = rgb(35, 50, 90), C2 = rgb(240, 245, 255), C3 = rgb(35, 50, 90) },
	{ Id = "Rainbow Puffer", Zone = 2, Rarity = R.Mythic, Shape = "puffer", C1 = rgb(255, 80, 200), C2 = rgb(120, 230, 255), C3 = rgb(255, 230, 60), Spikes = true, Glow = true },

	-- Kelp Forest
	{ Id = "Kelp Bass", Zone = 3, Rarity = R.Common, Shape = "fish", C1 = rgb(90, 140, 70), C2 = rgb(210, 220, 170), C3 = rgb(70, 110, 50) },
	{ Id = "Moray Eel", Zone = 3, Rarity = R.Uncommon, Shape = "eel", C1 = rgb(120, 160, 40), C2 = rgb(200, 210, 80), C3 = rgb(60, 90, 20), Spots = true },
	{ Id = "Reef Squid", Zone = 3, Rarity = R.Rare, Shape = "squid", C1 = rgb(255, 150, 160), C2 = rgb(255, 210, 215), C3 = rgb(220, 90, 120) },
	{ Id = "Octopus", Zone = 3, Rarity = R.Epic, Shape = "octopus", C1 = rgb(230, 90, 70), C2 = rgb(255, 170, 150), C3 = rgb(200, 60, 50) },
	{ Id = "Hammerhead", Zone = 3, Rarity = R.Legendary, Shape = "shark", C1 = rgb(120, 135, 150), C2 = rgb(235, 240, 245), C3 = rgb(100, 115, 130), Hammer = true },
	{ Id = "Ghost Ray", Zone = 3, Rarity = R.Mythic, Shape = "ray", C1 = rgb(220, 245, 255), C2 = rgb(255, 255, 255), C3 = rgb(150, 220, 255), Glow = true, Ghost = true },

	-- Open Sea
	{ Id = "Tuna", Zone = 4, Rarity = R.Common, Shape = "fish", C1 = rgb(50, 70, 120), C2 = rgb(215, 225, 235), C3 = rgb(255, 215, 60) },
	{ Id = "Mahi-Mahi", Zone = 4, Rarity = R.Uncommon, Shape = "fish", C1 = rgb(40, 190, 120), C2 = rgb(255, 230, 60), C3 = rgb(40, 140, 220), Tall = true },
	{ Id = "Swordfish", Zone = 4, Rarity = R.Rare, Shape = "fish", C1 = rgb(60, 80, 140), C2 = rgb(205, 215, 230), C3 = rgb(60, 80, 140), Sword = true },
	{ Id = "Blue Shark", Zone = 4, Rarity = R.Epic, Shape = "shark", C1 = rgb(50, 110, 220), C2 = rgb(235, 240, 250), C3 = rgb(40, 90, 190) },
	{ Id = "Orca", Zone = 4, Rarity = R.Legendary, Shape = "whale", C1 = rgb(25, 25, 30), C2 = rgb(250, 250, 250), C3 = rgb(25, 25, 30), Orca = true },
	{ Id = "Ocean Sunfish", Zone = 4, Rarity = R.Mythic, Shape = "fish", C1 = rgb(170, 185, 200), C2 = rgb(235, 240, 245), C3 = rgb(140, 155, 170), Tall = true, Big = true },

	-- Deep Blue
	{ Id = "Lanternfish", Zone = 5, Rarity = R.Common, Shape = "fish", C1 = rgb(30, 50, 110), C2 = rgb(80, 120, 200), C3 = rgb(120, 255, 255), Spots = true, Glow = true },
	{ Id = "Giant Squid", Zone = 5, Rarity = R.Uncommon, Shape = "squid", C1 = rgb(200, 60, 50), C2 = rgb(240, 140, 120), C3 = rgb(160, 40, 40), Big = true },
	{ Id = "Electric Eel", Zone = 5, Rarity = R.Rare, Shape = "eel", C1 = rgb(40, 70, 160), C2 = rgb(90, 220, 255), C3 = rgb(140, 240, 255), Glow = true },
	{ Id = "Sea Dragon", Zone = 5, Rarity = R.Epic, Shape = "eel", C1 = rgb(60, 170, 110), C2 = rgb(255, 210, 80), C3 = rgb(255, 170, 60), Spikes = true },
	{ Id = "Blue Whale", Zone = 5, Rarity = R.Legendary, Shape = "whale", C1 = rgb(70, 110, 170), C2 = rgb(190, 210, 230), C3 = rgb(60, 95, 150), Big = true },
	{ Id = "Crystal Jelly", Zone = 5, Rarity = R.Mythic, Shape = "jelly", C1 = rgb(180, 240, 255), C2 = rgb(255, 255, 255), C3 = rgb(130, 220, 255), Glow = true },
	{ Id = "Leviathan", Zone = 5, Rarity = R.Secret, Shape = "eel", C1 = rgb(40, 30, 90), C2 = rgb(120, 70, 255), C3 = rgb(0, 255, 200), Glow = true, Spikes = true, Big = true },

	-- Abyss
	{ Id = "Gulper Eel", Zone = 6, Rarity = R.Common, Shape = "eel", C1 = rgb(30, 25, 35), C2 = rgb(70, 60, 80), C3 = rgb(255, 60, 120), Glow = true },
	{ Id = "Anglerfish", Zone = 6, Rarity = R.Uncommon, Shape = "angler", C1 = rgb(60, 45, 70), C2 = rgb(100, 80, 110), C3 = rgb(140, 255, 200), Teeth = true, Glow = true },
	{ Id = "Vampire Squid", Zone = 6, Rarity = R.Rare, Shape = "squid", C1 = rgb(120, 20, 40), C2 = rgb(60, 10, 20), C3 = rgb(80, 180, 255), Glow = true },
	{ Id = "Abyss Jelly", Zone = 6, Rarity = R.Epic, Shape = "jelly", C1 = rgb(170, 60, 255), C2 = rgb(255, 120, 255), C3 = rgb(200, 100, 255), Glow = true },
	{ Id = "Frilled Shark", Zone = 6, Rarity = R.Legendary, Shape = "shark", C1 = rgb(90, 70, 60), C2 = rgb(150, 130, 115), C3 = rgb(70, 55, 45), Teeth = true },
	{ Id = "Kraken", Zone = 6, Rarity = R.Mythic, Shape = "octopus", C1 = rgb(120, 30, 90), C2 = rgb(200, 80, 150), C3 = rgb(255, 230, 80), Big = true, Glow = true },
	{ Id = "Void Whale", Zone = 6, Rarity = R.Secret, Shape = "whale", C1 = rgb(15, 10, 30), C2 = rgb(60, 30, 120), C3 = rgb(180, 120, 255), Glow = true, Big = true },

	-- Megalodon Trench
	{ Id = "Bone Fish", Zone = 7, Rarity = R.Common, Shape = "fish", C1 = rgb(235, 230, 215), C2 = rgb(200, 195, 180), C3 = rgb(160, 150, 130), Stripes = true },
	{ Id = "Lava Puffer", Zone = 7, Rarity = R.Uncommon, Shape = "puffer", C1 = rgb(60, 30, 25), C2 = rgb(255, 120, 30), C3 = rgb(255, 80, 20), Spikes = true, Glow = true },
	{ Id = "Coelacanth", Zone = 7, Rarity = R.Rare, Shape = "fish", C1 = rgb(40, 60, 110), C2 = rgb(90, 110, 160), C3 = rgb(230, 230, 230), Spots = true, Big = true },
	{ Id = "Magma Eel", Zone = 7, Rarity = R.Epic, Shape = "eel", C1 = rgb(50, 20, 15), C2 = rgb(255, 100, 20), C3 = rgb(255, 200, 40), Glow = true, Spikes = true },
	{ Id = "Megalodon", Zone = 7, Rarity = R.Legendary, Shape = "shark", C1 = rgb(95, 105, 115), C2 = rgb(225, 230, 235), C3 = rgb(80, 90, 100), Teeth = true, Big = true },
	{ Id = "Ancient Megalodon", Zone = 7, Rarity = R.Mythic, Shape = "shark", C1 = rgb(40, 35, 40), C2 = rgb(120, 40, 30), C3 = rgb(255, 60, 30), Teeth = true, Big = true, Glow = true },
	{ Id = "Cosmic Whale", Zone = 7, Rarity = R.Secret, Shape = "whale", C1 = rgb(40, 20, 100), C2 = rgb(255, 120, 230), C3 = rgb(120, 220, 255), Glow = true, Big = true, Galaxy = true },
}

GameData.FishById = {}
GameData.FishByZone = {}
for _, f in ipairs(GameData.Fish) do
	f.Name = f.Id
	f.Income = GameData.Zones[f.Zone].Income * GameData.Rarities[f.Rarity].Income
	GameData.FishById[f.Id] = f
	GameData.FishByZone[f.Zone] = GameData.FishByZone[f.Zone] or {}
	table.insert(GameData.FishByZone[f.Zone], f)
end

-- ===== Мутации =====
-- Chance — базовый шанс (в долях), Mult — множитель дохода.
GameData.Mutations = {
	{ Id = "None", Name = "", Mult = 1, Chance = 0, Color = rgb(255, 255, 255) },
	{ Id = "Golden", Name = "Golden", Mult = 2, Chance = 0.04, Color = rgb(255, 205, 50) },
	{ Id = "Crystal", Name = "Crystal", Mult = 3, Chance = 0.02, Color = rgb(150, 235, 255) },
	{ Id = "Neon", Name = "Neon", Mult = 5, Chance = 0.008, Color = rgb(60, 255, 150) },
	{ Id = "Galaxy", Name = "Galaxy", Mult = 10, Chance = 0.003, Color = rgb(170, 90, 255) },
	{ Id = "Rainbow", Name = "Rainbow", Mult = 25, Chance = 0.001, Color = rgb(255, 120, 200) },
}
GameData.MutationById = {}
for i, m in ipairs(GameData.Mutations) do
	m.Index = i
	GameData.MutationById[m.Id] = m
end

-- ===== Размеры =====
GameData.Sizes = {
	{ Name = "Tiny", Mult = 0.8, Weight = 15, Scale = 0.8 },
	{ Name = "Normal", Mult = 1, Weight = 60, Scale = 1 },
	{ Name = "Big", Mult = 1.5, Weight = 18, Scale = 1.12 },
	{ Name = "Huge", Mult = 2.5, Weight = 6, Scale = 1.25 },
	{ Name = "Giant", Mult = 5, Weight = 1, Scale = 1.4 },
}

-- ===== Наживки (покупаются за игровые деньги, дают удачу) =====
GameData.Baits = {
	{ Id = "Worm", Name = "Worm", Price = 0, Luck = 1, Color = rgb(230, 130, 140) },
	{ Id = "Shrimp", Name = "Shrimp", Price = 400, Luck = 1.25, Color = rgb(255, 150, 110) },
	{ Id = "Squid Bait", Name = "Squid Bait", Price = 6000, Luck = 1.5, Color = rgb(240, 200, 220) },
	{ Id = "Glow Lure", Name = "Glow Lure", Price = 90000, Luck = 1.8, Color = rgb(120, 255, 200) },
	{ Id = "Golden Lure", Name = "Golden Lure", Price = 1500000, Luck = 2.1, Color = rgb(255, 210, 60) },
	{ Id = "Abyss Lure", Name = "Abyss Lure", Price = 25000000, Luck = 2.5, Color = rgb(170, 90, 255) },
	{ Id = "Cosmic Lure", Name = "Cosmic Lure", Price = 450000000, Luck = 3, Color = rgb(255, 120, 230) },
	{ Id = "Megalodon Chum", Name = "Megalodon Chum", Price = 9000000000, Luck = 3.6, Color = rgb(255, 70, 40) },
}
GameData.BaitById = {}
for i, b in ipairs(GameData.Baits) do
	b.Index = i
	GameData.BaitById[b.Id] = b
end

-- ===== Спортинвентарь (за игровые деньги, множитель силы за повтор) =====
GameData.Gear = {
	{ Id = "Rusty Bar", Price = 0, Mult = 1, Color = rgb(150, 110, 90) },
	{ Id = "Steel Bar", Price = 1500, Mult = 2, Color = rgb(200, 205, 215) },
	{ Id = "Gold Bar", Price = 40000, Mult = 4, Color = rgb(255, 205, 60) },
	{ Id = "Diamond Bar", Price = 500000, Mult = 8, Color = rgb(120, 230, 255) },
	{ Id = "Cosmic Bar", Price = 10000000, Mult = 16, Color = rgb(200, 110, 255) },
	{ Id = "Mega Bar", Price = 200000000, Mult = 32, Color = rgb(255, 90, 90) },
	{ Id = "Titan Bar", Price = 5000000000, Mult = 64, Color = rgb(60, 255, 170) },
}

-- ===== События сервера =====
GameData.Events = {
	Storm = { Name = "Storm", Icon = "⛈️", Desc = "Luck x2", Duration = 180, Weight = 30, Luck = 2, Mutation = 1, Income = 1, Bite = 1 },
	GoldenHour = { Name = "Golden Hour", Icon = "🌅", Desc = "Mutations x3", Duration = 180, Weight = 25, Luck = 1, Mutation = 3, Income = 1, Bite = 1 },
	Frenzy = { Name = "Feeding Frenzy", Icon = "🐟", Desc = "Instant bites + Cash x2", Duration = 150, Weight = 25, Luck = 1, Mutation = 1, Income = 2, Bite = 0.25 },
	BloodMoon = { Name = "Blood Moon", Icon = "🌕", Desc = "Luck x3 + Mutations x2", Duration = 150, Weight = 12, Luck = 3, Mutation = 2, Income = 1, Bite = 1 },
	MeteorShower = { Name = "Meteor Shower", Icon = "☄️", Desc = "Luck x5!", Duration = 120, Weight = 8, Luck = 5, Mutation = 2, Income = 1, Bite = 1 },
}

-- ===== Помощники =====
function GameData.FishIncome(fishId: string, mutation: string, sizeIndex: number): number
	local def = GameData.FishById[fishId]
	if not def then
		return 0
	end
	local mut = GameData.MutationById[mutation] or GameData.Mutations[1]
	local size = GameData.Sizes[sizeIndex] or GameData.Sizes[2]
	return def.Income * mut.Mult * size.Mult
end

function GameData.FullName(fishId: string, mutation: string, sizeIndex: number): string
	local mut = GameData.MutationById[mutation]
	local size = GameData.Sizes[sizeIndex]
	local parts = {}
	if size and size.Name ~= "Normal" then
		table.insert(parts, size.Name)
	end
	if mut and mut.Id ~= "None" then
		table.insert(parts, mut.Name)
	end
	table.insert(parts, fishId)
	return table.concat(parts, " ")
end

return GameData
