-- 몸(캐릭터) 모델 생성. 전부 Humanoid + HumanoidRootPart 구조라서
-- player.Character 로 바로 넣으면 플레이어가 조종할 수 있음 (= 빙의)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GD = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local BodyFactory = {}
local rng = Random.new()

local SKINS = { Color3.fromRGB(255, 220, 185), Color3.fromRGB(240, 195, 150), Color3.fromRGB(200, 150, 110), Color3.fromRGB(140, 100, 70) }
local SHIRTS = { "#e85a5a", "#4f8fe0", "#f0b030", "#5cc05a", "#a070e0", "#f070b0", "#40c0b0", "#ff8a40" }
local PANTS = { "#3b4a6b", "#4a3a2a", "#2a2a3a", "#5a5a6a", "#2f4f3f" }
local HAIRS = { "#3a2a20", "#5b3a22", "#1e1e1e", "#c99a4c", "#8a4a2a", "#d9d0c4" }
local CARS = { "#e04a4a", "#f0b030", "#3f7fe0", "#4cb86a", "#e8e8e8", "#9a60e0", "#ff8a40" }

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local BLACK = Color3.fromRGB(25, 25, 30)
local WHITE = Color3.fromRGB(240, 240, 240)

-- root에 붙는 장식 파트
local function adder(model: Model, root: BasePart)
	return function(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, name: string?, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name or "Part"
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = root.CFrame * offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
end

local function eyes(add, y: number, z: number, spread: number, size: number?)
	local s = size or 1
	for _, sx in ipairs({ -1, 1 }) do
		add(Vector3.new(0.18 * s, 0.26 * s, 0.05), CFrame.new(sx * spread, y, z), BLACK)
	end
end

local function human(add, s: number, o)
	local skin = o.Skin or pick(SKINS)
	-- 몸통
	add(Vector3.new(2, 2, 1) * s, CFrame.new(), o.Shirt, o.ShirtMat)
	-- 머리
	add(Vector3.new(1.2, 1.2, 1.2) * s, CFrame.new(0, 1.65 * s, 0), skin, nil, "Head")
	eyes(add, 1.75 * s, -0.61 * s, 0.28 * s, s)
	if o.Hair then
		add(Vector3.new(1.3, 0.4, 1.3) * s, CFrame.new(0, 2.35 * s, 0.05 * s), o.Hair)
		if o.LongHair then
			add(Vector3.new(1.3, 1.1, 0.3) * s, CFrame.new(0, 1.8 * s, 0.6 * s), o.Hair)
		end
	end
	-- 팔, 다리
	for _, sx in ipairs({ -1, 1 }) do
		add(Vector3.new(0.7, o.ArmLen or 1.9, 0.8) * s, CFrame.new(sx * 1.35 * s, 0.05 * s - ((o.ArmLen or 1.9) - 1.9) / 2 * s, 0), o.Arm or o.Shirt, o.ShirtMat)
		add(Vector3.new(0.9, 2, 0.95) * s, CFrame.new(sx * 0.5 * s, -2 * s, 0), o.Pants)
	end
	-- 모자류
	if o.Hat == "police" then
		add(Vector3.new(1.4, 0.4, 1.4) * s, CFrame.new(0, 2.4 * s, 0), hex("#23325a"))
		add(Vector3.new(1.4, 0.12, 0.6) * s, CFrame.new(0, 2.22 * s, -0.8 * s), BLACK)
		add(Vector3.new(0.3, 0.3, 0.05) * s, CFrame.new(0, 2.45 * s, -0.72 * s), hex("#ffd23a"), Enum.Material.Neon)
	elseif o.Hat == "soldier" then
		add(Vector3.new(1.5, 0.6, 1.5) * s, CFrame.new(0, 2.4 * s, 0), hex("#4f5a35"))
	elseif o.Hat == "hazmat" then
		add(Vector3.new(1.4, 1.4, 1.4) * s, CFrame.new(0, 1.7 * s, 0), hex("#f2d43a"), Enum.Material.Fabric)
		add(Vector3.new(1, 0.5, 0.1) * s, CFrame.new(0, 1.8 * s, -0.71 * s), hex("#9fe0ff"), Enum.Material.Glass)
	elseif o.Hat == "exorcist" then
		add(Vector3.new(1.6, 0.25, 1.6) * s, CFrame.new(0, 2.35 * s, 0), BLACK)
		add(Vector3.new(0.9, 0.9, 0.9) * s, CFrame.new(0, 2.8 * s, 0), BLACK)
		add(Vector3.new(2.3, 2.6, 1.3) * s, CFrame.new(0, -1.5 * s, 0), hex("#6a3ab0"), Enum.Material.Fabric)
		add(Vector3.new(0.5, 0.8, 0.05) * s, CFrame.new(0.5 * s, 0.2 * s, -0.53 * s), hex("#fff2a0"), Enum.Material.Neon)
	elseif o.Hat == "robot" then
		add(Vector3.new(1.1, 0.3, 0.1) * s, CFrame.new(0, 1.75 * s, -0.62 * s), hex("#ff3a3a"), Enum.Material.Neon)
		add(Vector3.new(0.12, 0.8, 0.12) * s, CFrame.new(0, 2.6 * s, 0), Color3.fromRGB(120, 120, 130), Enum.Material.Metal)
		add(Vector3.new(0.3, 0.3, 0.3) * s, CFrame.new(0, 3.05 * s, 0), hex("#ff3a3a"), Enum.Material.Neon, nil, Enum.PartType.Ball)
	end
	if o.Coat then
		add(Vector3.new(2.1, 1.2, 1.1) * s, CFrame.new(0, -1.4 * s, 0), WHITE, Enum.Material.Fabric)
	end
	if o.Vest then
		add(Vector3.new(2.05, 1.4, 1.05) * s, CFrame.new(0, 0.2 * s, 0), o.Vest, Enum.Material.Fabric)
	end
end

-- 타입별 모양 정의: { RootSize, HipHeight, Build(add) }
local SHAPES = {}

SHAPES.ghost = {
	Root = Vector3.new(2, 2, 2),
	Hip = 1.6,
	Build = function(add)
		local lav = hex("#d9ccff")
		add(Vector3.new(2.8, 2.8, 2.8), CFrame.new(0, 0.2, 0), lav, Enum.Material.SmoothPlastic, "Head", Enum.PartType.Ball).Transparency = 0.1
		add(Vector3.new(0.35, 0.55, 0.1), CFrame.new(-0.45, 0.4, -1.32), BLACK)
		add(Vector3.new(0.35, 0.55, 0.1), CFrame.new(0.45, 0.4, -1.32), BLACK)
		add(Vector3.new(0.4, 0.2, 0.1), CFrame.new(-0.85, -0.05, -1.2), hex("#ff9ab8"))
		add(Vector3.new(0.4, 0.2, 0.1), CFrame.new(0.85, -0.05, -1.2), hex("#ff9ab8"))
		add(Vector3.one * 1.6, CFrame.new(0, -0.9, 1), lav, nil, nil, Enum.PartType.Ball).Transparency = 0.25
		add(Vector3.one * 1, CFrame.new(0, -1.3, 1.8), lav, nil, nil, Enum.PartType.Ball).Transparency = 0.4
	end,
}

local function humanShape(scale: number, opts: () -> any)
	return {
		Root = Vector3.new(2, 2, 1) * scale,
		Hip = 2 * scale,
		Build = function(add)
			human(add, scale, opts())
		end,
	}
end

SHAPES.citizen = humanShape(1, function()
	return { Shirt = hex(pick(SHIRTS)), Pants = hex(pick(PANTS)), Hair = hex(pick(HAIRS)), LongHair = rng:NextNumber() < 0.4 }
end)
SHAPES.scientist = humanShape(1, function()
	return { Shirt = WHITE, Pants = hex("#4a5a7a"), Hair = hex(pick(HAIRS)), Coat = true }
end)
SHAPES.police = humanShape(1, function()
	return { Shirt = hex("#3a5aa0"), Pants = hex("#23325a"), Hat = "police" }
end)
SHAPES.hazmat = humanShape(1, function()
	return { Shirt = hex("#f2d43a"), Pants = hex("#e0c030"), Hat = "hazmat", ShirtMat = Enum.Material.Fabric }
end)
SHAPES.soldier = humanShape(1, function()
	return { Shirt = hex("#6b7a45"), Pants = hex("#4f5a35"), Hat = "soldier", Vest = hex("#3f4a2a") }
end)
SHAPES.robot = humanShape(1.3, function()
	return { Shirt = Color3.fromRGB(150, 155, 165), ShirtMat = Enum.Material.Metal, Pants = Color3.fromRGB(90, 95, 105), Skin = Color3.fromRGB(170, 175, 185), Hat = "robot" }
end)
SHAPES.mutant = humanShape(1.15, function()
	return { Shirt = hex("#6fd06a"), Skin = hex("#8fe08a"), Pants = hex("#5a3a7a"), Arm = hex("#4fbf2e"), ArmLen = 2.8 }
end)
SHAPES.exorcist = humanShape(1.6, function()
	return { Shirt = hex("#6a3ab0"), Pants = hex("#3a1a60"), Hat = "exorcist", Hair = hex("#d9d0c4") }
end)

SHAPES.mouse = {
	Root = Vector3.new(1.2, 0.8, 2),
	Hip = 0.2,
	Build = function(add)
		local c = Color3.fromRGB(150, 150, 155)
		add(Vector3.new(1.2, 0.8, 2), CFrame.new(), c)
		add(Vector3.new(0.9, 0.7, 0.8), CFrame.new(0, 0.1, -1.2), c, nil, "Head")
		for _, sx in ipairs({ -1, 1 }) do
			add(Vector3.new(0.5, 0.5, 0.15), CFrame.new(sx * 0.35, 0.6, -1.2), hex("#ff9ab8"))
		end
		eyes(add, 0.2, -1.62, 0.22, 0.7)
		add(Vector3.new(0.15, 0.15, 1.6), CFrame.new(0, 0, 1.7), hex("#ff9ab8"))
	end,
}

SHAPES.cat = {
	Root = Vector3.new(1.2, 1.1, 2.6),
	Hip = 1,
	Build = function(add)
		local c = pick({ hex("#f0a040"), hex("#9a9aa0"), hex("#3a3a40"), hex("#f4efe2") })
		add(Vector3.new(1.2, 1.1, 2.6), CFrame.new(), c)
		add(Vector3.new(1.3, 1.2, 1.2), CFrame.new(0, 0.7, -1.6), c, nil, "Head")
		for _, sx in ipairs({ -1, 1 }) do
			add(Vector3.new(0.4, 0.5, 0.2), CFrame.new(sx * 0.4, 1.45, -1.6), c)
			for _, sz in ipairs({ -1, 1 }) do
				add(Vector3.new(0.4, 1, 0.4), CFrame.new(sx * 0.4, -1.05, sz * 0.9), c)
			end
		end
		eyes(add, 0.85, -2.22, 0.3, 0.9)
		add(Vector3.new(0.3, 0.3, 1.8), CFrame.new(0, 0.9, 1.9) * CFrame.Angles(math.rad(35), 0, 0), c)
	end,
}

SHAPES.pigeon = {
	Root = Vector3.new(1, 1, 1.6),
	Hip = 4.5,
	Build = function(add)
		local c = hex("#8a94a8")
		add(Vector3.new(1, 1, 1.6), CFrame.new(), c)
		add(Vector3.new(0.75, 0.75, 0.75), CFrame.new(0, 0.6, -0.9), hex("#6a7488"), nil, "Head")
		add(Vector3.new(0.25, 0.2, 0.4), CFrame.new(0, 0.55, -1.4), hex("#f0b030"))
		eyes(add, 0.75, -1.28, 0.2, 0.6)
		for _, sx in ipairs({ -1, 1 }) do
			add(Vector3.new(1.6, 0.15, 1), CFrame.new(sx * 1.1, 0.2, 0.1) * CFrame.Angles(0, 0, sx * math.rad(15)), c)
		end
	end,
}

SHAPES.dog = {
	Root = Vector3.new(1.4, 1.4, 3),
	Hip = 1.2,
	Build = function(add)
		local c = hex("#7a5232")
		add(Vector3.new(1.4, 1.4, 3), CFrame.new(), c)
		add(Vector3.new(1.45, 1, 1.6), CFrame.new(0, 0.1, -0.2), hex("#2a3a6a"), Enum.Material.Fabric)
		add(Vector3.new(1.2, 1.2, 1.4), CFrame.new(0, 0.8, -1.9), c, nil, "Head")
		add(Vector3.new(0.7, 0.6, 0.6), CFrame.new(0, 0.5, -2.7), hex("#5a3a22"))
		for _, sx in ipairs({ -1, 1 }) do
			add(Vector3.new(0.35, 0.7, 0.3), CFrame.new(sx * 0.55, 1.3, -1.7), hex("#3a2412"))
			for _, sz in ipairs({ -1, 1 }) do
				add(Vector3.new(0.45, 1.2, 0.45), CFrame.new(sx * 0.45, -1.2, sz * 1.1), c)
			end
		end
		eyes(add, 1, -2.62, 0.3, 0.9)
		add(Vector3.new(0.25, 0.25, 1.2), CFrame.new(0, 0.7, 1.9) * CFrame.Angles(math.rad(40), 0, 0), c)
	end,
}

local function carShape(kind: string)
	return {
		Root = Vector3.new(5, 2, 9.5),
		Hip = 1,
		Build = function(add)
			local body = if kind == "pcar" then WHITE else hex(pick(CARS))
			add(Vector3.new(5, 2, 9.5), CFrame.new(), body, Enum.Material.SmoothPlastic)
			add(Vector3.new(4.4, 1.6, 4.8), CFrame.new(0, 1.8, 0.6), Color3.fromRGB(40, 50, 70), Enum.Material.Glass, "Head")
			add(Vector3.new(4.5, 0.3, 4.4), CFrame.new(0, 2.65, 0.6), body)
			for _, sx in ipairs({ -1, 1 }) do
				add(Vector3.new(1, 0.5, 0.1), CFrame.new(sx * 1.7, 0.2, -4.76), hex("#fff6c8"), Enum.Material.Neon)
				add(Vector3.new(1, 0.5, 0.1), CFrame.new(sx * 1.7, 0.2, 4.76), hex("#e04040"), Enum.Material.Neon)
				for _, sz in ipairs({ -1, 1 }) do
					add(Vector3.new(0.9, 2, 2), CFrame.new(sx * 2.4, -0.9, sz * 3), BLACK, nil, nil, Enum.PartType.Cylinder)
				end
			end
			if kind == "pcar" then
				add(Vector3.new(5.05, 0.9, 4.2), CFrame.new(0, -0.3, 0.3), Color3.fromRGB(30, 30, 40))
				add(Vector3.new(1.4, 0.4, 0.8), CFrame.new(-0.8, 3, 0.6), hex("#ff3a3a"), Enum.Material.Neon)
				add(Vector3.new(1.4, 0.4, 0.8), CFrame.new(0.8, 3, 0.6), hex("#3a7aff"), Enum.Material.Neon)
			end
		end,
	}
end
SHAPES.car = carShape("car")
SHAPES.pcar = carShape("pcar")

SHAPES.tank = {
	Root = Vector3.new(7, 2.4, 10.5),
	Hip = 0.8,
	Build = function(add)
		local olive = hex("#5f6b3a")
		add(Vector3.new(7, 2.4, 10.5), CFrame.new(), olive, Enum.Material.Metal)
		for _, sx in ipairs({ -1, 1 }) do
			add(Vector3.new(1.6, 2.2, 11), CFrame.new(sx * 3.7, -0.5, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
		end
		add(Vector3.new(4.6, 1.8, 4.6), CFrame.new(0, 2.1, 0.8), hex("#6f7b45"), Enum.Material.Metal, "Head")
		add(Vector3.new(0.8, 0.8, 7), CFrame.new(0, 2.2, -4.2), hex("#4f5a2a"), Enum.Material.Metal)
	end,
}

function BodyFactory.Make(bodyType: string, pos: Vector3, parent: Instance): Model
	local shape = SHAPES[bodyType] or SHAPES.citizen
	local def = GD.Bodies[bodyType]

	local model = Instance.new("Model")
	model.Name = bodyType

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = shape.Root
	root.Transparency = 1
	root.CanCollide = true
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.CollisionGroup = if bodyType == "ghost" then "Ghost" else "Bodies"
	local y = 0.4 + shape.Hip + shape.Root.Y / 2 + 0.1
	root.CFrame = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	root.Parent = model
	model.PrimaryPart = root

	shape.Build(adder(model, root))

	if not model:FindFirstChild("Head") then
		local head = adder(model, root)(Vector3.one * 0.5, CFrame.new(0, shape.Root.Y / 2, 0), Color3.new(), nil, "Head")
		head.Transparency = 1
	end

	if bodyType == "ghost" then
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CollisionGroup = "Ghost"
			end
		end
		local light = Instance.new("PointLight")
		light.Color = hex("#cfc0ff")
		light.Range = 10
		light.Brightness = 1
		light.Parent = root
	end

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = shape.Hip
	hum.WalkSpeed = def and def.Speed or 16
	hum.UseJumpPower = true
	hum.JumpPower = if def and (def.Vehicle or bodyType == "ghost") then 0 else 40
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.MaxSlopeAngle = 60
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum.Parent = model

	model:SetAttribute("Type", bodyType)
	model.Parent = parent
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return model
end

return BodyFactory
