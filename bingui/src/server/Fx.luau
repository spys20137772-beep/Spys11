-- 시각 효과: 폭발, 총알 궤적, 말풍선, 떠오르는 글자
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Fx = {}
local G

function Fx.Init(g)
	G = g
end

local function effectsFolder()
	return G.World.Folders.Effects
end

-- 사운드는 에셋 ID가 필요해서 기본은 비워둠. 원하면 여기서 Sound를 재생하면 됨.
function Fx.Sound(_name: string, _pos: Vector3?) end

function Fx.Explosion(pos: Vector3, radius: number)
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = radius
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = workspace
	G.World.Debris(pos, 8, { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 120, 40), Color3.fromRGB(80, 75, 80) }, 1.2, 35)
end

function Fx.Tracer(from: Vector3, to: Vector3, color: Color3, width: number?)
	local dist = (to - from).Magnitude
	if dist < 0.1 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(width or 0.2, width or 0.2, dist)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = effectsFolder()
	TweenService:Create(p, TweenInfo.new(0.12), { Transparency = 1 }):Play()
	Debris:AddItem(p, 0.15)
end

-- 날아가는 투사체 (보이는 것만). 도착하면 callback 실행
function Fx.Lob(from: Vector3, to: Vector3, color: Color3, size: number, duration: number, callback: () -> ())
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * size
	p.Material = Enum.Material.Neon
	p.Color = color
	p.CFrame = CFrame.new(from)
	p.Parent = effectsFolder()
	local start = os.clock()
	local arc = math.min(8, (to - from).Magnitude * 0.2)
	task.spawn(function()
		while true do
			local t = math.min(1, (os.clock() - start) / duration)
			local pos = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * arc, 0)
			p.CFrame = CFrame.new(pos)
			if t >= 1 then
				break
			end
			task.wait()
		end
		p:Destroy()
		callback()
	end)
end

function Fx.SoulTrail(from: Vector3, to: Vector3)
	local n = math.clamp(math.floor((to - from).Magnitude / 3), 4, 20)
	for i = 0, n do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Color = if i % 2 == 0 then Color3.fromRGB(207, 234, 255) else Color3.fromRGB(179, 156, 255)
		p.Size = Vector3.one * 0.8
		p.CFrame = CFrame.new(from:Lerp(to, i / n) + Vector3.new(0, 2, 0))
		p.Parent = effectsFolder()
		TweenService:Create(p, TweenInfo.new(0.3 + i / n * 0.35), { Transparency = 1, Size = Vector3.one * 0.1 }):Play()
		Debris:AddItem(p, 0.7)
	end
end

-- 몸 위 말풍선
function Fx.Say(ent, text: string)
	local head = ent.Model and ent.Model:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild("Say")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Say"
		gui.Size = UDim2.fromOffset(160, 34)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 80
		gui.Parent = head
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.new(1, 1, 1)
		label.TextColor3 = Color3.fromRGB(42, 31, 51)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.PaddingTop = UDim.new(0, 3)
		pad.PaddingBottom = UDim.new(0, 3)
		pad.Parent = label
	end
	local label = gui:FindFirstChild("Text")
	label.Text = text
	gui.Enabled = true
	ent.SayUntil = os.clock() + 1.6
	local token = ent.SayUntil
	task.delay(1.6, function()
		if ent.SayUntil == token and gui.Parent then
			gui.Enabled = false
		end
	end)
end

-- 체력바 (맞았을 때만 표시)
function Fx.UpdateHealthBar(ent)
	local head = ent.Model and ent.Model:FindFirstChild("Head")
	if not head or ent.MaxHP <= 0 then
		return
	end
	local gui = head:FindFirstChild("HP")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "HP"
		gui.Size = UDim2.fromOffset(60, 7)
		gui.StudsOffset = Vector3.new(0, 1.6, 0)
		gui.MaxDistance = 60
		gui.Parent = head
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = Color3.fromRGB(40, 30, 50)
		back.BorderSizePixel = 0
		back.Parent = gui
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
		fill.BorderSizePixel = 0
		fill.Parent = back
	end
	local fill = gui:FindFirstChildWhichIsA("Frame"):FindFirstChild("Fill")
	fill.Size = UDim2.fromScale(math.clamp(ent.HP / ent.MaxHP, 0, 1), 1)
	gui.Enabled = ent.HP < ent.MaxHP and not ent.Possessor
end

return Fx
