-- Арена: каменная площадка в долине на закате, скалы, деревья, разрушенные стены, манекены.

local Lighting = game:GetService("Lighting")

local World = {}
local rng = Random.new(42)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function P(props: { [string]: any }): BasePart
	local p = Instance.new(props.Class or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Class" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function lighting()
	Lighting.ClockTime = 17.3
	Lighting.Brightness = 2.4
	Lighting.Ambient = rgb(70, 60, 75)
	Lighting.OutdoorAmbient = rgb(150, 125, 130)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.35
	atm.Offset = 0.1
	atm.Color = rgb(255, 200, 165)
	atm.Decay = rgb(120, 90, 140)
	atm.Glare = 0.5
	atm.Haze = 1.8
	atm.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.1
	cc.TintColor = rgb(255, 240, 228)
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.1
	rays.Parent = Lighting
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.45
	clouds.Color = rgb(255, 210, 190)
	clouds.Parent = workspace.Terrain
end

local function terrain()
	local t = workspace.Terrain
	t:FillBlock(CFrame.new(0, -6, 0), Vector3.new(900, 12, 900), Enum.Material.Ground)
	t:SetMaterialColor(Enum.Material.Ground, rgb(125, 105, 85))
	t:SetMaterialColor(Enum.Material.Grass, rgb(105, 130, 70))
	t:SetMaterialColor(Enum.Material.Rock, rgb(120, 110, 105))
	t:FillBlock(CFrame.new(0, -0.5, 0), Vector3.new(900, 1, 900), Enum.Material.Grass)
	-- кольцо скал вокруг долины
	for i = 0, 35 do
		local a = i / 36 * math.pi * 2
		local r = rng:NextNumber(230, 280)
		local h = rng:NextNumber(40, 90)
		t:FillBall(Vector3.new(math.cos(a) * r, h * 0.3, math.sin(a) * r), rng:NextNumber(30, 55), Enum.Material.Rock)
		t:FillBlock(CFrame.new(math.cos(a) * (r + 30), h / 2, math.sin(a) * (r + 30)) * CFrame.Angles(0, a, 0), Vector3.new(60, h, 60), Enum.Material.Rock)
	end
end

local function rockCluster(parent: Instance, pos: Vector3, k: number)
	for _ = 1, 3 do
		local s = Vector3.new(rng:NextNumber(3, 7), rng:NextNumber(2, 5), rng:NextNumber(3, 7)) * k
		P({ Size = s, CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-3, 3) * k, s.Y * 0.35, rng:NextNumber(-3, 3) * k)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
			Color = rgb(130, 120, 115):Lerp(rgb(160, 150, 140), rng:NextNumber()), Material = Enum.Material.Slate, Parent = parent })
	end
end

local function tree(parent: Instance, pos: Vector3, h: number)
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 2, 2), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(95, 70, 50), Material = Enum.Material.Wood, Parent = parent })
	for i = 1, 4 do
		local s = rng:NextNumber(8, 12)
		P({ Shape = Enum.PartType.Ball, Size = Vector3.one * s, Position = pos + Vector3.new(rng:NextNumber(-3, 3), h + rng:NextNumber(-1, 3) + i * 0.5, rng:NextNumber(-3, 3)),
			Color = rgb(70, 115, 60):Lerp(rgb(110, 140, 70), rng:NextNumber()), Material = Enum.Material.Grass, Parent = parent })
	end
end

local function brokenWall(parent: Instance, cf: CFrame)
	local w = 24
	for i = 0, 5 do
		local h = rng:NextNumber(4, 12)
		P({ Size = Vector3.new(w / 6, h, 2), CFrame = cf * CFrame.new(-w / 2 + (i + 0.5) * w / 6, h / 2, 0), Color = rgb(175, 160, 140), Material = Enum.Material.Brick, Parent = parent })
	end
	for _ = 1, 5 do
		local s = rng:NextNumber(1.5, 3)
		P({ Size = Vector3.new(s, s * 0.6, s), CFrame = cf * CFrame.new(rng:NextNumber(-w / 2, w / 2), s * 0.3, rng:NextNumber(2, 6)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0.2),
			Color = rgb(165, 150, 130), Material = Enum.Material.Brick, Parent = parent })
	end
end

function World.Build()
	lighting()
	terrain()
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	-- круглая каменная арена
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 170, 170), CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(150, 140, 130), Material = Enum.Material.Cobblestone, Parent = map })
	P({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 60, 60), CFrame = CFrame.new(0, 0.02, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(170, 158, 145), Material = Enum.Material.Slate, Parent = map })
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local h = rng:NextNumber(3, 8)
		P({ Size = Vector3.new(3, h, 3), CFrame = CFrame.new(math.cos(a) * 87, h / 2, math.sin(a) * 87) * CFrame.Angles(0, a, rng:NextNumber(-0.1, 0.1)), Color = rgb(140, 130, 120), Material = Enum.Material.Slate, Parent = map })
	end
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		brokenWall(map, CFrame.lookAt(Vector3.new(math.cos(a) * 120, 0, math.sin(a) * 120), Vector3.zero))
		rockCluster(map, Vector3.new(math.cos(a + 0.5) * 105, 0, math.sin(a + 0.5) * 105), rng:NextNumber(1, 1.8))
	end
	for _ = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(135, 210)
		tree(map, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng:NextNumber(14, 24))
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 1, 40)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = map
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
end

return World
