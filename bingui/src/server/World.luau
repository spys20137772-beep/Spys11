-- 도시 생성: 도로, 블록, 건물(부서짐/재건), 소품(부서짐/상호작용), 연구소·군사기지 담과 문
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GD = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local World = {}
local G

local BS, RW, NB, WS = GD.BS, GD.RW, GD.NB, GD.WS
local HALF = WS / 2
local BLOCK = BS - RW -- 블록 한 변 (48)

World.Buildings = {} -- [id] = building
World.Props = {} -- [id] = prop
World.Gates = {} -- [key] = gate
World.Blocks = {} -- { I, J, Zone, Center }
World.Fountains = {}

local folders = {}
local rng = Random.new(7)

---------------------------------------------------------------------
-- 좌표
---------------------------------------------------------------------
function World.ToWorld(x: number, z: number, y: number?): Vector3
	return Vector3.new(x - HALF, y or 0, z - HALF)
end

function World.ToCity(pos: Vector3): (number, number)
	return pos.X + HALF, pos.Z + HALF
end

function World.Intersection(ix: number, iy: number): Vector3
	return World.ToWorld(ix * BS + RW / 2, iy * BS + RW / 2)
end

function World.BlockIndexAt(pos: Vector3): number
	local x, z = World.ToCity(pos)
	local i = math.clamp(math.floor((x - RW / 2) / BS), 0, NB - 1)
	local j = math.clamp(math.floor((z - RW / 2) / BS), 0, NB - 1)
	return j * NB + i + 1 -- 1..81
end

function World.ZoneAt(pos: Vector3): string
	local idx = World.BlockIndexAt(pos) - 1
	return GD.ZoneMap[idx // NB + 1][idx % NB + 1]
end

local LAB = { x = 6 * BS + RW, y = RW, w = 2 * BS - RW, h = 2 * BS - RW }
local BASE = { x = 7 * BS + RW, y = 5 * BS + RW, w = 2 * BS - RW, h = 2 * BS - RW }
World.LAB, World.BASE = LAB, BASE

local function inRect(x, z, R)
	return x >= R.x and x <= R.x + R.w and z >= R.y and z <= R.y + R.h
end

function World.InCompound(pos: Vector3): string?
	local x, z = World.ToCity(pos)
	if inRect(x, z, LAB) then
		return "lab"
	elseif inRect(x, z, BASE) then
		return "base"
	end
	return nil
end

function World.InWorld(pos: Vector3): boolean
	return math.abs(pos.X) < HALF + 40 and math.abs(pos.Z) < HALF + 40
end

---------------------------------------------------------------------
-- 파트 헬퍼
---------------------------------------------------------------------
local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		for k, v in pairs(props) do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end
World.Part = part

local function cylinder(parent, height, diameter, cf: CFrame, color, material, props)
	local p = part(parent, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent, diameter, cf, color, material)
	local p = part(parent, Vector3.one * diameter, cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function setGroup(model: Instance, group: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	if model:IsA("BasePart") then
		model.CollisionGroup = group
	end
end

local function hsv(h, s, v)
	return Color3.fromHSV(h, s, v)
end

---------------------------------------------------------------------
-- 이펙트용 간단 파편
---------------------------------------------------------------------
function World.Debris(pos: Vector3, count: number, colors: { Color3 }, size: number?, speed: number?)
	for _ = 1, count do
		local s = (size or 1) * rng:NextNumber(0.5, 1.2)
		local p = Instance.new("Part")
		p.Size = Vector3.new(s, s, s)
		p.CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 1.5), rng:NextNumber(-1, 1)))
		p.Color = colors[rng:NextInteger(1, #colors)]
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CollisionGroup = "Effects"
		p.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1.4), rng:NextNumber(-1, 1)) * (speed or 25)
		p.Parent = folders.Effects
		game:GetService("Debris"):AddItem(p, 1.2)
	end
end

---------------------------------------------------------------------
-- 소품 (Props)
---------------------------------------------------------------------
local PROP_HP = {
	stall = 30, bin = 10, hydrant = 40, barrel = 20, pump = 40, crate = 25, statue = 80, specimen = 40,
	fridge = 40, tv = 15, pc = 15, ppc = 20, bed = 40, sofa = 30, lamp = 10, atm = 40, vending = 30,
	coffee = 20, shelf = 25, desk = 20, bench = 20,
}
local PROP_INTERACT = {
	fridge = "🍗 냉장고 털기",
	ppc = "🖥️ 수배 기록 지우기",
	bed = "💤 잠자기",
	coffee = "☕ 커피 마시기",
	specimen = "🧪 수조 깨기",
	atm = "💸 ATM 털기",
}
local nextPropId = 0

local function buildPropVisual(kind: string, model: Model, cf: CFrame, color: Color3?)
	local WHITE = Color3.fromRGB(240, 240, 240)
	local DARK = Color3.fromRGB(50, 50, 58)
	if kind == "fridge" then
		part(model, Vector3.new(3, 6, 2.4), cf * CFrame.new(0, 3, 0), WHITE)
		part(model, Vector3.new(0.3, 2, 0.3), cf * CFrame.new(1.1, 3.6, -1.3), DARK, Enum.Material.Metal)
		return 2
	elseif kind == "tv" then
		part(model, Vector3.new(4, 1.6, 1.6), cf * CFrame.new(0, 0.8, 0), Color3.fromRGB(120, 85, 60), Enum.Material.Wood)
		part(model, Vector3.new(4.4, 2.6, 0.4), cf * CFrame.new(0, 3, 0), Color3.fromRGB(20, 20, 25))
		part(model, Vector3.new(3.9, 2.1, 0.1), cf * CFrame.new(0, 3, -0.25), Color3.fromRGB(80, 160, 255), Enum.Material.Neon)
		return 2.2
	elseif kind == "bed" then
		part(model, Vector3.new(4, 1.2, 7), cf * CFrame.new(0, 0.6, 0), Color3.fromRGB(110, 80, 60), Enum.Material.Wood)
		part(model, Vector3.new(3.8, 0.5, 6.6), cf * CFrame.new(0, 1.4, 0), color or Color3.fromRGB(120, 160, 230), Enum.Material.Fabric)
		part(model, Vector3.new(2.6, 0.5, 1.2), cf * CFrame.new(0, 1.8, -2.6), WHITE, Enum.Material.Fabric)
		return 3
	elseif kind == "sofa" then
		local c = color or Color3.fromRGB(180, 90, 90)
		part(model, Vector3.new(6, 1.4, 2.6), cf * CFrame.new(0, 0.7, 0), c, Enum.Material.Fabric)
		part(model, Vector3.new(6, 1.8, 0.7), cf * CFrame.new(0, 2, 1), c, Enum.Material.Fabric)
		return 3
	elseif kind == "pc" or kind == "ppc" or kind == "desk" then
		part(model, Vector3.new(4.5, 0.4, 2.5), cf * CFrame.new(0, 2.6, 0), Color3.fromRGB(150, 110, 75), Enum.Material.Wood)
		for _, sx in ipairs({ -1, 1 }) do
			part(model, Vector3.new(0.4, 2.4, 2.3), cf * CFrame.new(sx * 2, 1.2, 0), Color3.fromRGB(130, 95, 65), Enum.Material.Wood)
		end
		if kind ~= "desk" then
			part(model, Vector3.new(2.2, 1.6, 0.3), cf * CFrame.new(0, 3.7, 0.4), DARK)
			part(model, Vector3.new(1.9, 1.3, 0.1), cf * CFrame.new(0, 3.7, 0.22), if kind == "ppc" then Color3.fromRGB(90, 140, 255) else Color3.fromRGB(120, 255, 170), Enum.Material.Neon)
		end
		return 2.3
	elseif kind == "stall" then
		local c = color or hsv(rng:NextNumber(), 0.6, 0.95)
		part(model, Vector3.new(6, 2.6, 3.4), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(150, 110, 75), Enum.Material.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			part(model, Vector3.new(0.4, 5.5, 0.4), cf * CFrame.new(sx * 2.8, 2.75, 1.5), DARK)
		end
		part(model, Vector3.new(7, 0.4, 4.6), cf * CFrame.new(0, 5.6, 0.4) * CFrame.Angles(math.rad(-10), 0, 0), c, Enum.Material.Fabric)
		for k = -1, 1 do
			ball(model, 1, cf * CFrame.new(k * 1.8, 3.1, 0), hsv(rng:NextNumber(), 0.7, 0.95))
		end
		return 3.2
	elseif kind == "bin" then
		cylinder(model, 3, 2, cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(70, 130, 70), Enum.Material.Metal)
		return 1.1
	elseif kind == "hydrant" then
		cylinder(model, 2.4, 1, cf * CFrame.new(0, 1.2, 0), Color3.fromRGB(220, 50, 50), Enum.Material.Metal)
		ball(model, 1.1, cf * CFrame.new(0, 2.5, 0), Color3.fromRGB(220, 50, 50), Enum.Material.Metal)
		return 0.7
	elseif kind == "barrel" then
		cylinder(model, 3, 2, cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(120, 220, 60), Enum.Material.Neon)
		cylinder(model, 0.3, 2.1, cf * CFrame.new(0, 2.2, 0), DARK, Enum.Material.Metal)
		return 1.1
	elseif kind == "pump" then
		part(model, Vector3.new(2, 4.6, 1.4), cf * CFrame.new(0, 2.3, 0), Color3.fromRGB(230, 60, 50))
		part(model, Vector3.new(1.6, 1.2, 0.1), cf * CFrame.new(0, 3.4, -0.75), WHITE, Enum.Material.Neon)
		return 1.3
	elseif kind == "crate" then
		part(model, Vector3.new(3, 3, 3), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(140, 120, 70), Enum.Material.WoodPlanks)
		return 1.7
	elseif kind == "statue" then
		part(model, Vector3.new(4, 2, 4), cf * CFrame.new(0, 1, 0), Color3.fromRGB(150, 150, 155), Enum.Material.Marble)
		part(model, Vector3.new(2, 3, 1.2), cf * CFrame.new(0, 3.5, 0), Color3.fromRGB(170, 175, 185), Enum.Material.Marble)
		ball(model, 1.4, cf * CFrame.new(0, 5.7, 0), Color3.fromRGB(170, 175, 185), Enum.Material.Marble)
		part(model, Vector3.new(0.6, 2.4, 0.6), cf * CFrame.new(1.4, 5, 0) * CFrame.Angles(0, 0, math.rad(-30)), Color3.fromRGB(170, 175, 185), Enum.Material.Marble)
		return 2.2
	elseif kind == "specimen" then
		cylinder(model, 0.6, 4.4, cf * CFrame.new(0, 0.3, 0), DARK, Enum.Material.Metal)
		cylinder(model, 6, 4, cf * CFrame.new(0, 3.6, 0), Color3.fromRGB(140, 230, 220), Enum.Material.Glass, { Transparency = 0.5 })
		ball(model, 2, cf * CFrame.new(0, 3.4, 0), Color3.fromRGB(90, 200, 90), Enum.Material.Neon)
		cylinder(model, 0.6, 4.4, cf * CFrame.new(0, 6.9, 0), DARK, Enum.Material.Metal)
		return 2.2
	elseif kind == "lamp" then
		cylinder(model, 9, 0.5, cf * CFrame.new(0, 4.5, 0), DARK, Enum.Material.Metal)
		local head = part(model, Vector3.new(1.4, 0.6, 1.4), cf * CFrame.new(0, 9.2, 0), Color3.fromRGB(255, 240, 180), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 230, 170)
		light.Parent = head
		return 0.6
	elseif kind == "atm" then
		part(model, Vector3.new(2.6, 5, 2), cf * CFrame.new(0, 2.5, 0), Color3.fromRGB(60, 90, 140), Enum.Material.Metal)
		part(model, Vector3.new(1.8, 1.2, 0.1), cf * CFrame.new(0, 3.4, -1.05), Color3.fromRGB(120, 255, 180), Enum.Material.Neon)
		return 1.4
	elseif kind == "vending" then
		part(model, Vector3.new(3, 6, 2.4), cf * CFrame.new(0, 3, 0), Color3.fromRGB(220, 50, 60))
		part(model, Vector3.new(2.2, 3.4, 0.1), cf * CFrame.new(-0.2, 3.6, -1.25), Color3.fromRGB(200, 240, 255), Enum.Material.Neon)
		return 1.7
	elseif kind == "coffee" then
		part(model, Vector3.new(5, 3, 2.4), cf * CFrame.new(0, 1.5, 0), Color3.fromRGB(110, 75, 50), Enum.Material.Wood)
		part(model, Vector3.new(1.6, 2, 1.4), cf * CFrame.new(-1, 4, 0), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
		cylinder(model, 0.8, 0.8, cf * CFrame.new(1, 3.4, 0), WHITE)
		return 2.5
	elseif kind == "shelf" then
		part(model, Vector3.new(6, 5, 1.6), cf * CFrame.new(0, 2.5, 0), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		for row = 1, 3 do
			for k = -2, 2 do
				part(model, Vector3.new(0.8, 0.9, 0.8), cf * CFrame.new(k * 1.1, row * 1.4 - 0.2, -0.5), hsv(rng:NextNumber(), 0.6, 0.95))
			end
		end
		return 3
	elseif kind == "bench" then
		part(model, Vector3.new(5, 0.4, 1.6), cf * CFrame.new(0, 1.3, 0), Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
		part(model, Vector3.new(5, 1.2, 0.3), cf * CFrame.new(0, 2.1, 0.7), Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
		for _, sx in ipairs({ -1, 1 }) do
			part(model, Vector3.new(0.3, 1.1, 1.4), cf * CFrame.new(sx * 2.1, 0.55, 0), DARK, Enum.Material.Metal)
		end
		return 2.5
	end
	part(model, Vector3.new(2, 2, 2), cf * CFrame.new(0, 1, 0), Color3.fromRGB(200, 200, 200))
	return 1.2
end

function World.MakeProp(kind: string, cf: CFrame, building, color: Color3?)
	nextPropId += 1
	local model = Instance.new("Model")
	model.Name = kind
	local radius = buildPropVisual(kind, model, cf, color)

	local prop = {
		Id = nextPropId,
		Kind = kind,
		Model = model,
		CFrame = cf,
		Pos = cf.Position,
		R = radius,
		HP = PROP_HP[kind] or 0,
		MaxHP = PROP_HP[kind] or 0,
		Broken = false,
		Building = building,
		Color = color,
		RepairAt = 0,
	}
	model:SetAttribute("PropId", prop.Id)
	model:SetAttribute("Kind", kind)
	if PROP_INTERACT[kind] then
		model:SetAttribute("Interact", PROP_INTERACT[kind])
	end
	setGroup(model, "Walls")
	model.Parent = folders.Props
	World.Props[prop.Id] = prop
	if building then
		table.insert(building.Props, prop)
	end
	return prop
end

function World.PropFromPart(inst: Instance)
	local model = inst.Parent
	local id = model and model:GetAttribute("PropId")
	return id and World.Props[id] or nil
end

local function hideProp(prop, hidden: boolean)
	prop.Model:SetAttribute("Broken", hidden)
	if hidden then
		prop.Model.Parent = folders.BrokenProps
	else
		prop.Model.Parent = folders.Props
	end
end

-- 소품 부수기 (효과는 Combat 쪽에서 처리)
function World.BreakProp(prop, byPlayer: Player?, quiet: boolean?)
	if prop.Broken or prop.MaxHP <= 0 then
		return
	end
	prop.Broken = true
	prop.HP = 0
	prop.RepairAt = os.clock() + 45
	hideProp(prop, true)
	if not quiet then
		G.Combat.OnPropBroken(prop, byPlayer)
	end
end

function World.DamageProp(prop, dmg: number, byPlayer: Player?)
	if prop.Broken or prop.MaxHP <= 0 then
		return
	end
	prop.HP -= dmg
	if prop.HP <= 0 then
		World.BreakProp(prop, byPlayer)
	end
end

function World.PropsNear(pos: Vector3, radius: number)
	local list = {}
	for _, prop in pairs(World.Props) do
		if not prop.Broken then
			local d = (prop.Pos - pos) * Vector3.new(1, 0, 1)
			if d.Magnitude < radius + prop.R then
				table.insert(list, prop)
			end
		end
	end
	return list
end

function World.NearestProp(pos: Vector3, kind: string)
	local best, bd = nil, math.huge
	for _, prop in pairs(World.Props) do
		if prop.Kind == kind and not prop.Broken then
			local d = (prop.Pos - pos).Magnitude
			if d < bd then
				best, bd = prop, d
			end
		end
	end
	return best
end

---------------------------------------------------------------------
-- 건물
---------------------------------------------------------------------
local nextBuildingId = 0

local BUILDING_STYLE = {
	police = { Color3.fromRGB(150, 170, 200), Color3.fromRGB(40, 60, 110) },
	school = { Color3.fromRGB(230, 200, 140), Color3.fromRGB(150, 70, 50) },
	cafe = { Color3.fromRGB(240, 215, 175), Color3.fromRGB(120, 70, 50) },
	mart = { Color3.fromRGB(220, 225, 235), Color3.fromRGB(60, 140, 90) },
	hosp = { Color3.fromRGB(245, 248, 250), Color3.fromRGB(200, 60, 60) },
	bank = { Color3.fromRGB(215, 205, 180), Color3.fromRGB(90, 80, 60) },
	gas = { Color3.fromRGB(235, 235, 235), Color3.fromRGB(220, 60, 50) },
	lab = { Color3.fromRGB(215, 235, 230), Color3.fromRGB(70, 150, 140) },
	base = { Color3.fromRGB(150, 140, 95), Color3.fromRGB(80, 85, 55) },
}

local function buildShell(b)
	local model = b.Model
	model:ClearAllChildren()
	local w, h, d = b.Size.X, b.Size.Y, b.Size.Z
	local cf = b.CFrame
	local wallC, roofC = b.WallColor, b.RoofColor
	local mat = if b.Kind == "house" then Enum.Material.Brick else Enum.Material.Concrete

	local function wall(size, offset)
		local p = part(model, size, cf * CFrame.new(offset), wallC, mat)
		p:SetAttribute("BuildingId", b.Id)
		return p
	end

	local door = 7
	wall(Vector3.new(w, h, 1), Vector3.new(0, h / 2, -d / 2 + 0.5))
	wall(Vector3.new(1, h, d), Vector3.new(-w / 2 + 0.5, h / 2, 0))
	wall(Vector3.new(1, h, d), Vector3.new(w / 2 - 0.5, h / 2, 0))
	local seg = (w - door) / 2
	wall(Vector3.new(seg, h, 1), Vector3.new(-(door / 2 + seg / 2), h / 2, d / 2 - 0.5))
	wall(Vector3.new(seg, h, 1), Vector3.new(door / 2 + seg / 2, h / 2, d / 2 - 0.5))
	wall(Vector3.new(door, h - 8, 1), Vector3.new(0, 8 + (h - 8) / 2, d / 2 - 0.5))

	local roof = part(model, Vector3.new(w + 1.5, 1, d + 1.5), cf * CFrame.new(0, h + 0.5, 0), roofC, Enum.Material.Slate, { Name = "Roof" })
	roof:SetAttribute("BuildingId", b.Id)

	-- 창문
	local glass = Color3.fromRGB(150, 200, 240)
	local count = math.max(1, math.floor(w / 9))
	for k = 1, count do
		local x = -w / 2 + k * w / (count + 1)
		if math.abs(x) > door / 2 + 2 then
			part(model, Vector3.new(3, 3, 0.2), cf * CFrame.new(x, h * 0.55, d / 2 + 0.05), glass, Enum.Material.Glass, { CanCollide = false, Transparency = 0.2 })
		end
		part(model, Vector3.new(3, 3, 0.2), cf * CFrame.new(x, h * 0.55, -d / 2 - 0.05), glass, Enum.Material.Glass, { CanCollide = false, Transparency = 0.2 })
	end

	-- 실내 바닥
	part(model, Vector3.new(w - 2, 0.2, d - 2), cf * CFrame.new(0, 0.5, 0), b.FloorColor, Enum.Material.WoodPlanks, { CanCollide = false, Name = "Floor" })

	-- 간판
	if b.Kind ~= "house" then
		local sign = part(model, Vector3.new(math.min(w - 4, 16), 2.4, 0.4), cf * CFrame.new(0, h - 1.6, d / 2 + 0.3), Color3.fromRGB(30, 30, 40), Enum.Material.SmoothPlastic, { CanCollide = false })
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 30
		sg.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = GD.BuildingName[b.Kind] or b.Kind
		label.Parent = sg
		if b.Kind == "hosp" then
			part(model, Vector3.new(1, 4, 0.3), cf * CFrame.new(0, h + 3, 0), Color3.fromRGB(220, 40, 40), Enum.Material.Neon)
			part(model, Vector3.new(4, 1, 0.3), cf * CFrame.new(0, h + 3, 0), Color3.fromRGB(220, 40, 40), Enum.Material.Neon)
		end
	end

	setGroup(model, "Walls")
end

local function buildRubble(b)
	local model = b.Model
	model:ClearAllChildren()
	local cf = b.CFrame
	local colors = { b.WallColor, b.RoofColor, Color3.fromRGB(150, 140, 125), Color3.fromRGB(110, 100, 90) }
	for _ = 1, 14 do
		local s = Vector3.new(rng:NextNumber(2, 6), rng:NextNumber(0.8, 2.5), rng:NextNumber(2, 6))
		local offset = Vector3.new(rng:NextNumber(-b.Size.X / 2.5, b.Size.X / 2.5), s.Y / 2, rng:NextNumber(-b.Size.Z / 2.5, b.Size.Z / 2.5))
		part(model, s, cf * CFrame.new(offset) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)), colors[rng:NextInteger(1, #colors)], Enum.Material.Slate, { CanCollide = false })
	end
	setGroup(model, "Walls")
end

function World.MakeBuilding(kind: string, cf: CFrame, size: Vector3)
	nextBuildingId += 1
	local style = BUILDING_STYLE[kind]
	local b = {
		Id = nextBuildingId,
		Kind = kind,
		CFrame = cf,
		Size = size,
		HP = GD.BuildingHP[kind] or 400,
		MaxHP = GD.BuildingHP[kind] or 400,
		Destroyed = false,
		RebuildAt = 0,
		Props = {},
		WallColor = if style then style[1] else hsv(rng:NextNumber(), 0.25, 0.95),
		RoofColor = if style then style[2] else hsv(rng:NextNumber(), 0.55, 0.6),
		FloorColor = Color3.fromRGB(200, 170, 130),
	}
	local model = Instance.new("Model")
	model.Name = kind .. b.Id
	model:SetAttribute("BuildingId", b.Id)
	model:SetAttribute("Center", cf.Position)
	model:SetAttribute("Size", size)
	model.Parent = folders.Buildings
	b.Model = model
	buildShell(b)
	World.Buildings[b.Id] = b
	return b
end

function World.BuildingFromPart(inst: Instance)
	local id = inst:GetAttribute("BuildingId")
	return id and World.Buildings[id] or nil
end

-- pos가 건물 안(바닥 기준)인지
function World.BuildingAt(pos: Vector3)
	for _, b in pairs(World.Buildings) do
		if not b.Destroyed then
			local lp = b.CFrame:PointToObjectSpace(pos)
			if math.abs(lp.X) < b.Size.X / 2 and math.abs(lp.Z) < b.Size.Z / 2 then
				return b
			end
		end
	end
	return nil
end

function World.DamageBuilding(b, dmg: number, byPlayer: Player?)
	if not b or b.Destroyed then
		return
	end
	b.HP -= dmg
	if dmg > 8 then
		local pos = b.CFrame.Position + Vector3.new(rng:NextNumber(-b.Size.X / 2, b.Size.X / 2), rng:NextNumber(2, b.Size.Y), rng:NextNumber(-b.Size.Z / 2, b.Size.Z / 2))
		World.Debris(pos, 3, { b.WallColor, Color3.fromRGB(160, 150, 140) }, 1, 15)
	end
	if b.HP <= 0 then
		World.DestroyBuilding(b, byPlayer)
	end
end

function World.DestroyBuilding(b, byPlayer: Player?)
	if b.Destroyed then
		return
	end
	b.Destroyed = true
	b.HP = 0
	b.RebuildAt = os.clock() + 120
	local center = b.CFrame.Position
	World.Debris(center + Vector3.new(0, b.Size.Y / 2, 0), 30, { b.WallColor, b.RoofColor, Color3.fromRGB(170, 160, 140) }, 2.5, 40)
	G.Fx.Sound("crash", center)
	buildRubble(b)
	for _, prop in ipairs(b.Props) do
		World.BreakProp(prop, nil, true)
	end
	G.Combat.OnBuildingDestroyed(b, byPlayer)
end

function World.HitBuildingsInRadius(pos: Vector3, radius: number, dmg: number, byPlayer: Player?)
	for _, b in pairs(World.Buildings) do
		if not b.Destroyed then
			local lp = b.CFrame:PointToObjectSpace(pos)
			local cx = math.clamp(lp.X, -b.Size.X / 2, b.Size.X / 2)
			local cz = math.clamp(lp.Z, -b.Size.Z / 2, b.Size.Z / 2)
			local d = Vector2.new(lp.X - cx, lp.Z - cz).Magnitude
			if d < radius then
				World.DamageBuilding(b, dmg * 1.4 * (1 - d / radius * 0.5), byPlayer)
			end
		end
	end
end

---------------------------------------------------------------------
-- 문 (연구소 / 군사기지)
---------------------------------------------------------------------
function World.OpenGate(key: string, byPlayer: Player?)
	local gate = World.Gates[key]
	if not gate or gate.Open then
		return
	end
	gate.Open = true
	gate.Part.CanCollide = false
	TweenService:Create(gate.Part, TweenInfo.new(1.2), { CFrame = gate.Part.CFrame * CFrame.new(0, -9, 0) }):Play()
	G.Fx.Sound("gate", gate.Pos)
	G.Players.Broadcast("Toast", if key == "lab" then "🚪 연구소 문이 열렸다!" else "🚪 군사기지 문이 열렸다!")
	G.Players.EventAll({ k = "gate", g = key })
end

---------------------------------------------------------------------
-- 도시 생성
---------------------------------------------------------------------
local ZONE_COLOR = {
	home = Color3.fromRGB(124, 196, 86), park = Color3.fromRGB(95, 180, 68), market = Color3.fromRGB(234, 215, 168),
	police = Color3.fromRGB(180, 184, 194), lab = Color3.fromRGB(207, 228, 222), base = Color3.fromRGB(185, 171, 114),
	school = Color3.fromRGB(216, 192, 138), cafe = Color3.fromRGB(230, 207, 166), mart = Color3.fromRGB(196, 200, 208),
	hosp = Color3.fromRGB(216, 228, 234), bank = Color3.fromRGB(212, 205, 184), gas = Color3.fromRGB(154, 160, 168),
}

local function tree(pos: Vector3)
	local m = Instance.new("Model")
	m.Name = "Tree"
	cylinder(m, 6, 1.4, CFrame.new(pos + Vector3.new(0, 3.4, 0)), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
	ball(m, 6.5, CFrame.new(pos + Vector3.new(0, 8, 0)), Color3.fromRGB(70, 160, 70), Enum.Material.Grass)
	ball(m, 4.5, CFrame.new(pos + Vector3.new(1.2, 10.4, -0.8)), Color3.fromRGB(85, 175, 80), Enum.Material.Grass)
	setGroup(m, "Walls")
	m.Parent = folders.Decor
end

local function blockLayout(i: number, j: number, zone: string, center: Vector3)
	local cf = CFrame.new(center + Vector3.new(0, 0.4, 0)) -- 블록 바닥 위
	local function at(x, z, rot)
		return cf * CFrame.new(x, 0, z) * CFrame.Angles(0, rot or 0, 0)
	end

	if zone == "home" then
		local b = World.MakeBuilding("house", at(0, -2), Vector3.new(26, 12, 24))
		World.MakeProp("fridge", at(-9, -10.5, math.pi), b)
		World.MakeProp("tv", at(7, -11, math.pi), b)
		World.MakeProp("bed", at(-9, 2), b, hsv(rng:NextNumber(), 0.4, 0.9))
		World.MakeProp("sofa", at(7, -3, math.pi), b, hsv(rng:NextNumber(), 0.45, 0.8))
		World.MakeProp("bin", at(19, 19))
		tree(center + Vector3.new(-19, 0.4, 19))
		if rng:NextNumber() < 0.5 then
			tree(center + Vector3.new(19, 0.4, -19))
		end
	elseif zone == "park" then
		-- 분수
		local f = Instance.new("Model")
		f.Name = "Fountain"
		cylinder(f, 1.2, 14, at(0, 0) * CFrame.new(0, 0.6, 0), Color3.fromRGB(200, 200, 205), Enum.Material.Marble)
		cylinder(f, 0.3, 12.4, at(0, 0) * CFrame.new(0, 1.15, 0), Color3.fromRGB(90, 170, 240), Enum.Material.Glass, { Transparency = 0.25, CanCollide = false })
		cylinder(f, 4, 1.6, at(0, 0) * CFrame.new(0, 2.5, 0), Color3.fromRGB(200, 200, 205), Enum.Material.Marble)
		local top = cylinder(f, 0.5, 4, at(0, 0) * CFrame.new(0, 4.5, 0), Color3.fromRGB(200, 200, 205), Enum.Material.Marble)
		local att = Instance.new("Attachment")
		att.CFrame = CFrame.Angles(0, 0, math.rad(-90))
		att.Parent = top
		local water = Instance.new("ParticleEmitter")
		water.Color = ColorSequence.new(Color3.fromRGB(140, 200, 255), Color3.new(1, 1, 1))
		water.Size = NumberSequence.new(0.5, 0.15)
		water.Transparency = NumberSequence.new(0.2, 1)
		water.Speed = NumberRange.new(9, 12)
		water.SpreadAngle = Vector2.new(18, 18)
		water.Acceleration = Vector3.new(0, -25, 0)
		water.Lifetime = NumberRange.new(0.9, 1.1)
		water.Rate = 40
		water.EmissionDirection = Enum.NormalId.Top
		water.Parent = att
		for _, p in ipairs(f:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
		f.Parent = folders.Decor
		table.insert(World.Fountains, { Pos = center, R = 6.5 })

		World.MakeProp("statue", at(-15, -15))
		World.MakeProp("bench", at(0, 14, math.pi))
		World.MakeProp("bench", at(14, 0, math.pi / 2))
		World.MakeProp("lamp", at(-12, 12))
		World.MakeProp("lamp", at(12, -12))
		World.MakeProp("hydrant", at(20, 20))
		for _, p in ipairs({ Vector3.new(-18, 0, 0), Vector3.new(18, 0, -18), Vector3.new(-6, 0, -19), Vector3.new(16, 0, 16), Vector3.new(-18, 0, 16) }) do
			tree(center + p + Vector3.new(0, 0.4, 0))
		end
	elseif zone == "market" then
		for row = 0, 1 do
			for col = -1, 1 do
				World.MakeProp("stall", at(col * 13, -8 + row * 15, row == 0 and 0 or math.pi))
			end
		end
		World.MakeProp("bin", at(-20, 20))
		World.MakeProp("bin", at(20, -20))
		World.MakeProp("lamp", at(0, 20))
	elseif zone == "police" then
		local b = World.MakeBuilding("police", at(0, -4), Vector3.new(38, 14, 30))
		World.MakeProp("ppc", at(-10, -14, math.pi), b)
		World.MakeProp("pc", at(6, -14, math.pi), b)
		World.MakeProp("desk", at(-10, 0), b)
		World.MakeProp("vending", at(14, 4, -math.pi / 2), b)
		World.MakeProp("hydrant", at(21, 18))
	elseif zone == "school" then
		local b = World.MakeBuilding("school", at(0, -4), Vector3.new(40, 16, 30))
		for k = 0, 3 do
			World.MakeProp("desk", at(-12 + (k % 2) * 24, -10 + (k // 2) * 10, math.pi), b)
		end
		World.MakeProp("vending", at(16, 6, -math.pi / 2), b)
		tree(center + Vector3.new(-20, 0.4, 19))
	elseif zone == "cafe" then
		local b = World.MakeBuilding("cafe", at(0, -4), Vector3.new(28, 10, 22))
		World.MakeProp("coffee", at(0, -11, math.pi), b)
		World.MakeProp("desk", at(-7, 0), b)
		World.MakeProp("desk", at(7, 0), b)
		World.MakeProp("bench", at(-12, 18))
		World.MakeProp("lamp", at(18, 18))
	elseif zone == "mart" then
		local b = World.MakeBuilding("mart", at(0, -4), Vector3.new(34, 12, 28))
		for k = -1, 1 do
			World.MakeProp("shelf", at(k * 10, -6), b)
		end
		World.MakeProp("vending", at(-12, 6, math.pi / 2), b)
		World.MakeProp("fridge", at(12, 6, -math.pi / 2), b)
		World.MakeProp("bin", at(20, 20))
	elseif zone == "hosp" then
		local b = World.MakeBuilding("hosp", at(0, -4), Vector3.new(36, 16, 30))
		for k = -1, 1 do
			World.MakeProp("bed", at(k * 10, -10), b, Color3.fromRGB(230, 240, 250))
		end
		World.MakeProp("desk", at(0, 4), b)
	elseif zone == "bank" then
		local b = World.MakeBuilding("bank", at(0, -4), Vector3.new(30, 14, 26))
		World.MakeProp("atm", at(-8, -12, math.pi), b)
		World.MakeProp("atm", at(8, -12, math.pi), b)
		World.MakeProp("desk", at(0, -2), b)
	elseif zone == "gas" then
		local b = World.MakeBuilding("gas", at(-12, -14), Vector3.new(16, 9, 14))
		World.MakeProp("vending", at(-12, -18, math.pi), b)
		for _, x in ipairs({ -6, 4, 14 }) do
			World.MakeProp("pump", at(x, 10))
		end
		local canopy = Instance.new("Model")
		canopy.Name = "Canopy"
		part(canopy, Vector3.new(30, 0.8, 12), at(4, 10) * CFrame.new(0, 10, 0), Color3.fromRGB(230, 60, 50))
		for _, x in ipairs({ -10, 18 }) do
			part(canopy, Vector3.new(0.8, 10, 0.8), at(x, 10) * CFrame.new(0, 5, 0), Color3.fromRGB(230, 230, 230), Enum.Material.Metal)
		end
		setGroup(canopy, "Walls")
		canopy.Parent = folders.Decor
		World.MakeProp("barrel", at(20, -18))
	end
end

local function buildCompound(key: string, R, gateSide: string)
	local x0, z0 = R.x, R.y
	local p0 = World.ToWorld(x0, z0, 0)
	local w, d = R.w, R.h
	local center = p0 + Vector3.new(w / 2, 0, d / 2)
	local compound = Instance.new("Model")
	compound.Name = key .. "Compound"

	part(folders.Ground, Vector3.new(w, 0.4, d), CFrame.new(center + Vector3.new(0, 0.2, 0)), ZONE_COLOR[key], Enum.Material.Concrete)

	local wallC = if key == "lab" then Color3.fromRGB(190, 205, 205) else Color3.fromRGB(120, 115, 85)
	local H, T, GATE = 10, 1.5, 12
	local function wallSeg(size, pos)
		part(compound, size, CFrame.new(pos), wallC, Enum.Material.Concrete)
	end
	-- 4면 (gateSide 쪽에 구멍)
	local sides = {
		north = { Vector3.new(w, H, T), center + Vector3.new(0, H / 2, -d / 2) },
		south = { Vector3.new(w, H, T), center + Vector3.new(0, H / 2, d / 2) },
		west = { Vector3.new(T, H, d), center + Vector3.new(-w / 2, H / 2, 0) },
		east = { Vector3.new(T, H, d), center + Vector3.new(w / 2, H / 2, 0) },
	}
	for name, s in pairs(sides) do
		if name ~= gateSide then
			wallSeg(s[1], s[2])
		else
			local size, pos = s[1], s[2]
			local horizontal = size.X > size.Z
			local len = if horizontal then size.X else size.Z
			local seg = (len - GATE) / 2
			local offset = GATE / 2 + seg / 2
			if horizontal then
				wallSeg(Vector3.new(seg, H, T), pos + Vector3.new(-offset, 0, 0))
				wallSeg(Vector3.new(seg, H, T), pos + Vector3.new(offset, 0, 0))
			else
				wallSeg(Vector3.new(T, H, seg), pos + Vector3.new(0, 0, -offset))
				wallSeg(Vector3.new(T, H, seg), pos + Vector3.new(0, 0, offset))
			end
			local gatePart = part(compound, if horizontal then Vector3.new(GATE, H - 1, 1) else Vector3.new(1, H - 1, GATE), CFrame.new(pos - Vector3.new(0, 0.5, 0)), Color3.fromRGB(240, 200, 40), Enum.Material.DiamondPlate, { Name = "Gate" })
			World.Gates[key] = { Part = gatePart, Open = false, Pos = pos }
		end
	end
	setGroup(compound, "Walls")
	compound.Parent = folders.Compounds

	local cf = CFrame.new(center + Vector3.new(0, 0.4, 0))
	local function at(x, z, rot)
		return cf * CFrame.new(x, 0, z) * CFrame.Angles(0, rot or 0, 0)
	end
	if key == "lab" then
		local b = World.MakeBuilding("lab", at(0, -18), Vector3.new(56, 14, 36))
		for k = -1, 1 do
			World.MakeProp("specimen", at(k * 12, -26), b)
		end
		World.MakeProp("pc", at(-18, -10), b)
		World.MakeProp("pc", at(18, -10), b)
		for _, p in ipairs({ Vector2.new(-30, 20), Vector2.new(-24, 24), Vector2.new(28, 22), Vector2.new(34, 18) }) do
			World.MakeProp("barrel", at(p.X, p.Y))
		end
		World.MakeProp("lamp", at(-40, 40))
		World.MakeProp("lamp", at(40, 40))
	else
		local b = World.MakeBuilding("base", at(-14, 20), Vector3.new(50, 12, 28))
		World.MakeProp("bed", at(-30, 16), b, Color3.fromRGB(90, 100, 70))
		World.MakeProp("bed", at(-22, 16), b, Color3.fromRGB(90, 100, 70))
		World.MakeProp("pc", at(0, 28, math.pi), b)
		for k = 0, 4 do
			World.MakeProp("crate", at(26 + (k % 2) * 4, -30 + k * 5))
		end
		for k = 0, 2 do
			World.MakeProp("barrel", at(-36 + k * 3, -36))
		end
		World.MakeProp("lamp", at(-44, -44))
		World.MakeProp("lamp", at(44, 44))
	end
end

function World.Init(g)
	G = g

	for _, group in ipairs({ "Walls", "Ghost", "Bodies", "Effects" }) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(group)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Walls", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Bodies", false)
	PhysicsService:CollisionGroupSetCollidable("Ghost", "Ghost", false)
	PhysicsService:CollisionGroupSetCollidable("Effects", "Effects", false)
	PhysicsService:CollisionGroupSetCollidable("Effects", "Bodies", false)
	PhysicsService:CollisionGroupSetCollidable("Effects", "Ghost", false)

	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = workspace
	for _, name in ipairs({ "Ground", "Buildings", "Props", "Decor", "Compounds" }) do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = city
		folders[name] = f
	end
	local broken = Instance.new("Folder")
	broken.Name = "BrokenProps"
	broken.Parent = game:GetService("ServerStorage")
	folders.BrokenProps = broken

	for _, name in ipairs({ "Bodies", "Effects" }) do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
		folders[name] = f
	end
	World.Folders = folders

	local old = workspace:FindFirstChild("Baseplate")
	if old then
		old:Destroy()
	end

	-- 도로 바닥 (전체) + 바깥 잔디
	part(folders.Ground, Vector3.new(WS + 400, 2, WS + 400), CFrame.new(0, -1.05, 0), Color3.fromRGB(80, 140, 70), Enum.Material.Grass, { Name = "Grass" })
	part(folders.Ground, Vector3.new(WS, 2, WS), CFrame.new(0, -1, 0), Color3.fromRGB(70, 72, 80), Enum.Material.Asphalt, { Name = "Road" })

	-- 차선 (교차로 사이 점선)
	for k = 0, NB do
		local line = k * BS + RW / 2
		for seg = 0, NB - 1 do
			local mid = seg * BS + RW + (BS - RW) / 2
			part(folders.Ground, Vector3.new(0.4, 0.05, 30), CFrame.new(World.ToWorld(line, mid, 0.02)), Color3.fromRGB(240, 220, 120), Enum.Material.SmoothPlastic, { CanCollide = false })
			part(folders.Ground, Vector3.new(30, 0.05, 0.4), CFrame.new(World.ToWorld(mid, line, 0.02)), Color3.fromRGB(240, 220, 120), Enum.Material.SmoothPlastic, { CanCollide = false })
		end
	end

	-- 블록
	for j = 0, NB - 1 do
		for i = 0, NB - 1 do
			local zone = GD.ZoneMap[j + 1][i + 1]
			local center = World.ToWorld(i * BS + RW + BLOCK / 2, j * BS + RW + BLOCK / 2)
			table.insert(World.Blocks, { I = i, J = j, Zone = zone, Center = center })
			if zone ~= "lab" and zone ~= "base" then
				local mat = if zone == "home" or zone == "park" then Enum.Material.Grass else Enum.Material.Concrete
				part(folders.Ground, Vector3.new(BLOCK, 0.4, BLOCK), CFrame.new(center + Vector3.new(0, 0.2, 0)), ZONE_COLOR[zone], mat)
				blockLayout(i, j, zone, center)
			end
		end
	end

	buildCompound("lab", LAB, "south")
	buildCompound("base", BASE, "north")

	-- 재건 / 수리 루프
	task.spawn(function()
		while true do
			task.wait(2)
			local now = os.clock()
			for _, b in pairs(World.Buildings) do
				if b.Destroyed and now >= b.RebuildAt then
					b.Destroyed = false
					b.HP = b.MaxHP
					buildShell(b)
					for _, prop in ipairs(b.Props) do
						if prop.Broken then
							prop.Broken = false
							prop.HP = prop.MaxHP
							hideProp(prop, false)
						end
					end
				end
			end
			for _, prop in pairs(World.Props) do
				if prop.Broken and now >= prop.RepairAt and not (prop.Building and prop.Building.Destroyed) then
					prop.Broken = false
					prop.HP = prop.MaxHP
					hideProp(prop, false)
				end
			end
		end
	end)
end

---------------------------------------------------------------------
-- 스폰 위치
---------------------------------------------------------------------
function World.StartPos(): Vector3
	return World.Intersection(1, 1) + Vector3.new(0, 4, 0)
end

local function blocksOf(zones: { string })
	local list = {}
	local set = {}
	for _, z in ipairs(zones) do
		set[z] = true
	end
	for _, b in ipairs(World.Blocks) do
		if set[b.Zone] then
			table.insert(list, b)
		end
	end
	return list
end

-- zones 중 한 블록 안의 랜덤 위치 (건물 안 허용 여부)
function World.ZoneSpot(zones: { string }, allowIndoor: boolean?): Vector3?
	local list = blocksOf(zones)
	if #list == 0 then
		return nil
	end
	for _ = 1, 12 do
		local b = list[rng:NextInteger(1, #list)]
		local spread = if b.Zone == "lab" or b.Zone == "base" then BLOCK / 2 + 6 else BLOCK / 2 - 3
		local pos = b.Center + Vector3.new(rng:NextNumber(-spread, spread), 3, rng:NextNumber(-spread, spread))
		if allowIndoor or not World.BuildingAt(pos) then
			return pos
		end
	end
	return nil
end

-- 근처 도로 위의 점 (출동 차량/경찰용)
function World.RoadPointNear(pos: Vector3, dmin: number, dmax: number): Vector3?
	local x, z = World.ToCity(pos)
	for _ = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(dmin, dmax)
		local px, pz = x + math.cos(a) * d, z + math.sin(a) * d
		if rng:NextNumber() < 0.5 then
			px = math.floor((px - RW / 2) / BS + 0.5) * BS + RW / 2
		else
			pz = math.floor((pz - RW / 2) / BS + 0.5) * BS + RW / 2
		end
		px = math.clamp(px, RW / 2, WS - RW / 2)
		pz = math.clamp(pz, RW / 2, WS - RW / 2)
		local wp = World.ToWorld(px, pz, 3)
		if not World.InCompound(wp) then
			return wp
		end
	end
	return nil
end

-- 자동차 주행 경로
local DIRS = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
World.DIRS = DIRS

function World.ValidNext(ix: number, iy: number, dir: number): boolean
	local nx, ny = ix + DIRS[dir][1], iy + DIRS[dir][2]
	if nx < 0 or ny < 0 or nx > NB or ny > NB then
		return false
	end
	local a, b = World.Intersection(ix, iy), World.Intersection(nx, ny)
	if World.InCompound(b) or World.InCompound((a + b) / 2) then
		return false
	end
	return true
end

function World.CarSpot(): (Vector3?, number?, number?, number?)
	for _ = 1, 40 do
		local ix, iy = rng:NextInteger(0, NB), rng:NextInteger(0, NB)
		if not World.InCompound(World.Intersection(ix, iy)) then
			local dirs = {}
			for d = 1, 4 do
				if World.ValidNext(ix, iy, d) then
					table.insert(dirs, d)
				end
			end
			if #dirs > 0 then
				local d = dirs[rng:NextInteger(1, #dirs)]
				local t = rng:NextNumber(0.2, 0.8)
				local from = World.Intersection(ix, iy)
				local to = World.Intersection(ix + DIRS[d][1], iy + DIRS[d][2])
				local pos = from:Lerp(to, t) + World.LaneOffset(d) + Vector3.new(0, 3, 0)
				return pos, d, ix + DIRS[d][1], iy + DIRS[d][2]
			end
		end
	end
	return nil
end

-- 우측 차선 오프셋
function World.LaneOffset(dir: number): Vector3
	local dx, dz = DIRS[dir][1], DIRS[dir][2]
	return Vector3.new(-dz, 0, dx) * 3.5
end

return World
