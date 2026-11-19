-- 부지와 아이템을 파트로 직접 생성하는 모듈 (모델 파일 없이 동작).
-- 모든 좌표는 부지 기준 로컬 좌표. 부지는 100x100, 입구는 로컬 +Z 쪽.
--
--  z=+50  입구 / 간판
--  z=+40  스폰 패드
--  z=+22~30 구매 버튼
--  z=-10  컨베이어 (x: -42 -> 34, +X 방향으로 흐름) -> x=36.5 판매기
--  z=-19  드로퍼 본체
local Builders = {}

local DARK = Color3.fromRGB(45, 45, 52)
local METAL = Color3.fromRGB(120, 125, 135)
local WHITE = Color3.new(1, 1, 1)

local CONVEYOR_Z = -10

local function newPart(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			(p :: any)[k] = v
		end
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- 세로로 선 원기둥
local function cylinder(parent, cf: CFrame, height: number, diameter: number, color, material, props)
	local p = newPart(parent, cf * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(height, diameter, diameter), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent, cf: CFrame, diameter: number, color, material)
	return newPart(parent, cf, Vector3.new(diameter, diameter, diameter), color, material, { Shape = Enum.PartType.Ball })
end

local function billboard(adornee: BasePart, text: string, color: Color3, offsetY: number, width: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width or 140, 34)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 90
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	return label
end

---------------------------------------------------------------------
-- 기본 부지 (바닥, 컨베이어, 판매기, 스폰, 간판)
---------------------------------------------------------------------
function Builders.Base(model: Model, base: CFrame)
	local function L(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local refs = {}

	refs.Floor = newPart(model, L(0, 0.5, 0), Vector3.new(100, 1, 100), Color3.fromRGB(86, 140, 72), Enum.Material.Grass, { Name = "Floor" })

	-- 테두리
	newPart(model, L(0, 0.8, 50.5), Vector3.new(102, 0.6, 1), DARK, Enum.Material.Concrete)
	newPart(model, L(0, 0.8, -50.5), Vector3.new(102, 0.6, 1), DARK, Enum.Material.Concrete)
	newPart(model, L(50.5, 0.8, 0), Vector3.new(1, 0.6, 100), DARK, Enum.Material.Concrete)
	newPart(model, L(-50.5, 0.8, 0), Vector3.new(1, 0.6, 100), DARK, Enum.Material.Concrete)

	-- 컨베이어
	refs.Conveyor = newPart(model, L(-4, 2, CONVEYOR_Z), Vector3.new(76, 1, 6), Color3.fromRGB(40, 40, 45), Enum.Material.DiamondPlate, { Name = "Conveyor" })
	newPart(model, L(-4, 1.25, CONVEYOR_Z), Vector3.new(74, 0.5, 4), DARK, Enum.Material.Metal)
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, L(-4, 3.25, CONVEYOR_Z + side * 3.3), Vector3.new(76, 1.5, 0.6), METAL, Enum.Material.Metal)
	end
	newPart(model, L(-42.3, 3.25, CONVEYOR_Z), Vector3.new(0.6, 1.5, 7.2), METAL, Enum.Material.Metal)

	-- 판매기 (광석이 닿으면 돈으로 바뀜)
	refs.Collector = newPart(model, L(36.5, 4, CONVEYOR_Z), Vector3.new(5, 6, 8), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, { Name = "Collector" })
	newPart(model, L(36.5, 7.5, CONVEYOR_Z), Vector3.new(6, 1, 9), DARK, Enum.Material.Metal)
	billboard(refs.Collector, "💰 판매기", Color3.fromRGB(255, 200, 60), 6)

	-- 스폰 패드
	refs.SpawnPad = newPart(model, L(0, 1.3, 40), Vector3.new(8, 0.4, 8), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic, { Name = "SpawnPad" })

	-- 입구 간판
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, L(side * 8.6, 8, 49.5), Vector3.new(1.2, 15, 1.2), DARK, Enum.Material.Wood)
	end
	local board = newPart(model, L(0, 13.5, 49.5), Vector3.new(18, 4, 0.8), Color3.fromRGB(35, 38, 48), Enum.Material.SmoothPlastic, { Name = "Sign" })
	refs.SignLabels = {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.Parent = board

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = WHITE
		label.Text = "빈 자리"
		label.Parent = sg

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 20)
		pad.PaddingRight = UDim.new(0, 20)
		pad.PaddingTop = UDim.new(0, 12)
		pad.PaddingBottom = UDim.new(0, 12)
		pad.Parent = label

		table.insert(refs.SignLabels, label)
	end

	return refs
end

---------------------------------------------------------------------
-- 아이템들
---------------------------------------------------------------------
function Builders.Dropper(model: Model, base: CFrame, def)
	local x = def.X
	local function L(y, z)
		return base * CFrame.new(x, y, z)
	end

	newPart(model, L(4.5, -19), Vector3.new(5, 7, 5), def.Color, Enum.Material.Metal)
	newPart(model, L(6.5, -19), Vector3.new(5.2, 0.6, 5.2), def.Color, Enum.Material.Neon)
	newPart(model, L(8.3, -19), Vector3.new(4, 0.6, 4), DARK, Enum.Material.Metal)
	newPart(model, L(7.25, -14), Vector3.new(2, 1.5, 8), DARK, Enum.Material.Metal)
	newPart(model, L(5.7, CONVEYOR_Z), Vector3.new(2.4, 1.6, 2.4), DARK, Enum.Material.Metal, { Name = "Spout" })
	newPart(model, L(4.85, CONVEYOR_Z), Vector3.new(1.6, 0.1, 1.6), def.Color, Enum.Material.Neon, { CanCollide = false })
end

function Builders.Upgrader(model: Model, base: CFrame, def)
	local x = def.X
	local function L(y, z)
		return base * CFrame.new(x, y, z)
	end

	for _, side in ipairs({ -1, 1 }) do
		newPart(model, L(4.5, CONVEYOR_Z + side * 4.2), Vector3.new(1, 7, 1), DARK, Enum.Material.Metal)
	end
	local beam = newPart(model, L(8.5, CONVEYOR_Z), Vector3.new(1.4, 1, 9.4), def.Color, Enum.Material.Neon)
	newPart(model, L(4.8, CONVEYOR_Z), Vector3.new(0.6, 4.4, 6), def.Color, Enum.Material.Neon, {
		Name = "Gate",
		CanCollide = false,
		Transparency = 0.45,
	})
	billboard(beam, "x" .. tostring(def.Multiplier), def.Color, 2.5, 80)
end

function Builders.ConveyorBoost(model: Model, base: CFrame, def)
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, base * CFrame.new(-4, 4.05, CONVEYOR_Z + side * 3.3), Vector3.new(76, 0.15, 0.4), def.Color, Enum.Material.Neon, { CanCollide = false })
	end
end

function Builders.Walls(model: Model, base: CFrame, def)
	local function L(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local c, m = def.Color, Enum.Material.Brick
	newPart(model, L(0, 7, -49.5), Vector3.new(100, 12, 1), c, m)
	newPart(model, L(-49.5, 7, 0), Vector3.new(1, 12, 100), c, m)
	newPart(model, L(49.5, 7, 0), Vector3.new(1, 12, 100), c, m)
	newPart(model, L(-29, 7, 49.5), Vector3.new(42, 12, 1), c, m)
	newPart(model, L(29, 7, 49.5), Vector3.new(42, 12, 1), c, m)
	-- 벽 위 장식 띠
	newPart(model, L(0, 13.25, -49.5), Vector3.new(101, 0.5, 1.6), DARK, Enum.Material.Concrete)
	newPart(model, L(-49.5, 13.25, 0), Vector3.new(1.6, 0.5, 101), DARK, Enum.Material.Concrete)
	newPart(model, L(49.5, 13.25, 0), Vector3.new(1.6, 0.5, 101), DARK, Enum.Material.Concrete)
end

function Builders.Lamps(model: Model, base: CFrame, def)
	for _, pos in ipairs({ Vector2.new(-45, -45), Vector2.new(45, -45), Vector2.new(-45, 45), Vector2.new(45, 45), Vector2.new(-45, 0), Vector2.new(45, 0) }) do
		cylinder(model, base * CFrame.new(pos.X, 6, pos.Y), 10, 0.8, DARK, Enum.Material.Metal)
		local head = newPart(model, base * CFrame.new(pos.X, 11.5, pos.Y), Vector3.new(2, 1, 2), def.Color, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = def.Color
		light.Range = 28
		light.Brightness = 1.5
		light.Parent = head
	end
end

function Builders.Floor(model: Model, base: CFrame, def)
	newPart(model, base * CFrame.new(0, 1.1, 0), Vector3.new(98, 0.2, 98), def.Color, Enum.Material.Marble, { CanCollide = false })
	-- 통로 카펫 (입구 -> 버튼 구역)
	newPart(model, base * CFrame.new(0, 1.25, 44), Vector3.new(10, 0.1, 12), Color3.fromRGB(180, 40, 50), Enum.Material.Fabric, { CanCollide = false })
end

function Builders.Trees(model: Model, base: CFrame, def)
	for _, pos in ipairs({ Vector2.new(-42, 8), Vector2.new(42, 8), Vector2.new(-42, -32), Vector2.new(42, -32), Vector2.new(-42, 40), Vector2.new(42, 40) }) do
		cylinder(model, base * CFrame.new(pos.X, 5, pos.Y), 8, 2, Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
		ball(model, base * CFrame.new(pos.X, 11, pos.Y), 8, def.Color, Enum.Material.Grass)
		ball(model, base * CFrame.new(pos.X + 1.5, 14, pos.Y - 1), 5, def.Color, Enum.Material.Grass)
	end
end

function Builders.Fountain(model: Model, base: CFrame, def)
	local center = base * CFrame.new(-28, 0, 8)
	cylinder(model, center * CFrame.new(0, 1.75, 0), 1.5, 16, Color3.fromRGB(200, 200, 205), Enum.Material.Marble)
	cylinder(model, center * CFrame.new(0, 2.3, 0), 0.4, 14, def.Color, Enum.Material.Glass, { Transparency = 0.3, CanCollide = false })
	cylinder(model, center * CFrame.new(0, 4.5, 0), 5, 2, Color3.fromRGB(200, 200, 205), Enum.Material.Marble)
	local top = cylinder(model, center * CFrame.new(0, 7.2, 0), 0.6, 6, Color3.fromRGB(200, 200, 205), Enum.Material.Marble)

	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.Angles(0, 0, math.rad(-90)) -- 원기둥 회전 보정 (위쪽으로 분사)
	attachment.Parent = top

	local water = Instance.new("ParticleEmitter")
	water.Color = ColorSequence.new(def.Color, Color3.new(1, 1, 1))
	water.LightEmission = 0.4
	water.Size = NumberSequence.new(0.6, 0.2)
	water.Transparency = NumberSequence.new(0.2, 1)
	water.Speed = NumberRange.new(10, 13)
	water.SpreadAngle = Vector2.new(15, 15)
	water.Acceleration = Vector3.new(0, -25, 0)
	water.Lifetime = NumberRange.new(1, 1.2)
	water.Rate = 60
	water.EmissionDirection = Enum.NormalId.Top
	water.Parent = attachment
end

return Builders
