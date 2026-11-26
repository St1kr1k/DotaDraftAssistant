-- Проигрыватель анимаций для R15 на любых аватарах.
-- Клип = ключевые позы (Clips.luau). Поза применяется через Motor6D.C0 = C0_исходный * поворот,
-- корень: Root.C0 = T * C0_исходный. Стандартные анимации Roblox на время клипа глушатся.
-- Работает на клиенте для всех персонажей (каждый клиент анимирует сам — плавно и без задержки).

local RunService = game:GetService("RunService")

local Clips = require(script.Parent.Clips)

local Anim = {}

local JOINTS = {
	root = { "LowerTorso", "Root" },
	waist = { "UpperTorso", "Waist" },
	head = { "Head", "Neck" },
	armR = { "RightUpperArm", "RightShoulder" },
	elbowR = { "RightLowerArm", "RightElbow" },
	armL = { "LeftUpperArm", "LeftShoulder" },
	elbowL = { "LeftLowerArm", "LeftElbow" },
	legR = { "RightUpperLeg", "RightHip" },
	kneeR = { "RightLowerLeg", "RightKnee" },
	legL = { "LeftUpperLeg", "LeftHip" },
	kneeL = { "LeftLowerLeg", "LeftKnee" },
}
local FIELDS = {
	root = { "x", "y", "z", "pitch", "yaw", "roll" },
	waist = { "pitch", "yaw", "roll" },
	head = { "pitch", "yaw", "roll" },
	armR = { "pitch", "out", "twist" },
	armL = { "pitch", "out", "twist" },
	elbowR = { "bend" },
	elbowL = { "bend" },
	legR = { "pitch", "out", "twist" },
	legL = { "pitch", "out", "twist" },
	kneeR = { "bend" },
	kneeL = { "bend" },
}
local REF_HEIGHT = 3.6 -- высота HRP над землёй у модели, по которой ставились позы

local rad = math.rad

local function ease(name: string, t: number): number
	if name == "in" then
		return t * t * t
	elseif name == "out" then
		return 1 - (1 - t) ^ 3
	elseif name == "snap" then
		return 1 - (1 - t) ^ 6
	elseif name == "linear" then
		return t
	end
	return t * t * (3 - 2 * t)
end

local function value(pose, part: string, field: string): number
	local p = pose[part]
	return p and p[field] or 0
end

-- Поза клипа в момент t (линейная смесь соседних ключей с плавностью)
function Anim.Sample(clip, t: number)
	local keys = clip.Keys
	local out = {}
	local a, b, k = keys[1], keys[1], 0
	if t >= keys[#keys].t then
		a, b, k = keys[#keys], keys[#keys], 0
	elseif t > keys[1].t then
		for i = 1, #keys - 1 do
			if t >= keys[i].t and t <= keys[i + 1].t then
				a, b = keys[i], keys[i + 1]
				k = ease(b.ease, (t - a.t) / math.max(1e-6, b.t - a.t))
				break
			end
		end
	end
	for part, fields in pairs(FIELDS) do
		local o = {}
		for _, f in ipairs(fields) do
			local va = value(a.pose, part, f)
			o[f] = va + (value(b.pose, part, f) - va) * k
		end
		out[part] = o
	end
	return out
end

local function blendPose(p1, p2, k: number)
	local out = {}
	for part, fields in pairs(FIELDS) do
		local o = {}
		for _, f in ipairs(fields) do
			local v1 = p1 and p1[part] and p1[part][f] or 0
			local v2 = p2 and p2[part] and p2[part][f] or 0
			o[f] = v1 + (v2 - v1) * k
		end
		out[part] = o
	end
	return out
end

local function jointRot(key: string, p): CFrame
	local side = string.sub(key, -1) == "L" and -1 or 1
	if key == "waist" or key == "head" then
		return CFrame.Angles(-rad(p.pitch), rad(p.yaw), rad(p.roll))
	elseif key == "elbowR" or key == "elbowL" then
		return CFrame.Angles(rad(p.bend), 0, 0)
	elseif key == "kneeR" or key == "kneeL" then
		return CFrame.Angles(-rad(p.bend), 0, 0)
	end
	return CFrame.Angles(rad(p.pitch), side * rad(p.twist), side * rad(p.out))
end

-- ===== состояние по моделям =====
type State = {
	model: Model,
	motors: { [string]: Motor6D },
	base: { [string]: CFrame },
	scale: number,
	clip: any?,
	clipName: string?,
	t: number,
	speed: number,
	from: any?, -- поза, из которой плавно входим
	blend: number,
	blendTime: number,
	releasing: boolean,
	firedMarkers: { [number]: boolean },
	onEnd: (() -> ())?,
	lastPose: any?,
	frozenUntil: number,
}

local states = {} :: { [Model]: State }
local markerListeners = {} :: { (Model, string, string) -> () }

function Anim.OnMarker(fn: (Model, string, string) -> ())
	table.insert(markerListeners, fn)
end

local function bind(model: Model): State?
	local st = states[model]
	if st then
		return st
	end
	local motors, base = {}, {}
	for key, pair in pairs(JOINTS) do
		local part = model:FindFirstChild(pair[1])
		local m = part and part:FindFirstChild(pair[2])
		if m and m:IsA("Motor6D") then
			motors[key] = m
			base[key] = m.C0
		end
	end
	if not motors.root then
		return nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local scale = 1
	if hum and hrp then
		scale = math.clamp((hum.HipHeight + hrp.Size.Y / 2) / REF_HEIGHT, 0.5, 2)
	end
	st = {
		model = model,
		motors = motors,
		base = base,
		scale = scale,
		clip = nil,
		clipName = nil,
		t = 0,
		speed = 1,
		from = nil,
		blend = 1,
		blendTime = 0.08,
		releasing = false,
		firedMarkers = {},
		onEnd = nil,
		lastPose = nil,
		frozenUntil = 0,
	}
	states[model] = st
	model.Destroying:Connect(function()
		states[model] = nil
	end)
	return st
end

local function apply(st: State, pose)
	for key, motor in pairs(st.motors) do
		if motor.Parent then
			local p = pose[key]
			if key == "root" then
				local s = st.scale
				local T = CFrame.new(p.x * s, p.y * s, p.z * s) * CFrame.Angles(-rad(p.pitch), rad(p.yaw), rad(p.roll))
				motor.C0 = T * st.base.root
			else
				motor.C0 = st.base[key] * jointRot(key, p)
			end
		end
	end
	st.lastPose = pose
end

-- Стандартные анимации не останавливаем (иначе Animate «забудет» про ходьбу), а убираем им вес
local function setDefaultWeight(model: Model, w: number, fade: number)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:AdjustWeight(w, fade)
		end
	end
end

local function restore(st: State)
	for key, motor in pairs(st.motors) do
		if motor.Parent then
			motor.C0 = st.base[key]
		end
	end
	st.lastPose = nil
	setDefaultWeight(st.model, 1, 0.15)
end

local function muteDefault(model: Model)
	setDefaultWeight(model, 0.0001, 0.05)
end

-- Играть клип. blend — время плавного входа из текущей позы.
function Anim.Play(model: Model, clipName: string, opts: { speed: number?, blend: number?, onEnd: (() -> ())? }?)
	local clip = Clips[clipName]
	local st = bind(model)
	if not clip or not st then
		return
	end
	st.from = st.lastPose
	st.blend = 0
	st.blendTime = opts and opts.blend or 0.08
	st.clip = clip
	st.clipName = clipName
	st.t = 0
	st.speed = opts and opts.speed or 1
	st.releasing = false
	st.firedMarkers = {}
	st.onEnd = opts and opts.onEnd or nil
	st.frozenUntil = 0
end

function Anim.Stop(model: Model, fade: number?)
	local st = states[model]
	if st and st.clip then
		st.clip = nil
		st.clipName = nil
		st.releasing = true
		st.from = st.lastPose
		st.blend = 0
		st.blendTime = fade or 0.15
	end
end

function Anim.Current(model: Model): string?
	local st = states[model]
	return st and st.clipName or nil
end

-- Стоп-кадр при попадании (hit stop)
function Anim.Freeze(model: Model, seconds: number)
	local st = states[model]
	if st then
		st.frozenUntil = os.clock() + seconds
	end
end

local function step(dt: number)
	local now = os.clock()
	for model, st in pairs(states) do
		if not model.Parent then
			states[model] = nil
			continue
		end
		if st.clip then
			if now >= st.frozenUntil then
				st.t += dt * st.speed
			end
			local clip = st.clip
			local t = st.t
			if clip.Loop then
				t = t % clip.Length
			end
			-- метки (удар, исчезновение и т.д.)
			for i, mk in ipairs(clip.Markers) do
				if not st.firedMarkers[i] and st.t >= mk.t then
					st.firedMarkers[i] = true
					for _, fn in ipairs(markerListeners) do
						task.spawn(fn, model, st.clipName :: string, mk.name)
					end
				end
			end
			if clip.Loop and st.t >= clip.Length then
				st.t -= clip.Length
				st.firedMarkers = {}
			end
			local pose = Anim.Sample(clip, math.min(t, clip.Length))
			if st.blend < 1 then
				st.blend = math.min(1, st.blend + dt / math.max(0.001, st.blendTime))
				if st.from then
					pose = blendPose(st.from, pose, ease("smooth", st.blend))
				end
			end
			muteDefault(model)
			apply(st, pose)
			if not clip.Loop and st.t >= clip.Length then
				local cb = st.onEnd
				st.onEnd = nil
				if cb then
					task.spawn(cb)
				end
			end
		elseif st.releasing then
			st.blend = math.min(1, st.blend + dt / math.max(0.001, st.blendTime))
			if st.from and st.blend < 1 then
				apply(st, blendPose(st.from, nil, ease("smooth", st.blend)))
			else
				restore(st)
				st.releasing = false
				st.from = nil
			end
		end
	end
end

if RunService:IsClient() then
	RunService.RenderStepped:Connect(step)
end

Anim.Clips = Clips
return Anim
