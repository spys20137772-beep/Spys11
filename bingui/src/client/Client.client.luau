-- 빙의 대소동 클라이언트: 화면(UI), 조작, 빙의 대상 표시, 지붕 숨기기, 돌진 이동
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local GD = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = Remotes:WaitForChild("Action") :: RemoteEvent
local Event = Remotes:WaitForChild("Event") :: RemoteEvent

local C = {
	Dark = Color3.fromHex("#2a1f33"),
	Cream = Color3.fromHex("#fffbea"),
	Paper = Color3.fromHex("#f4efe2"),
	Purple = Color3.fromHex("#b39cff"),
	PurpleDark = Color3.fromHex("#26124d"),
	Lilac = Color3.fromHex("#efeaff"),
	Yellow = Color3.fromHex("#ffd23a"),
	Blue = Color3.fromHex("#8fe8ff"),
	Red = Color3.fromHex("#ff7a7a"),
	Green = Color3.fromHex("#8fe08a"),
	White = Color3.new(1, 1, 1),
}

---------------------------------------------------------------------
-- UI 헬퍼
---------------------------------------------------------------------
local function make(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 10) })
end
local function stroke(color, t)
	return make("UIStroke", { Color = color or C.Dark, Thickness = t or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function pad(px)
	return make("UIPadding", { PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px), PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px) })
end
local function maxText(n)
	return make("UITextSizeConstraint", { MaxTextSize = n })
end

local function label(props, children)
	local base = { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = C.Dark, TextScaled = true, TextWrapped = true, Text = "" }
	for k, v in pairs(props) do
		base[k] = v
	end
	return make("TextLabel", base, children)
end

local function button(props, children)
	local base = { AutoButtonColor = true, BorderSizePixel = 0, Font = Enum.Font.GothamBlack, TextColor3 = C.Dark, TextScaled = true, Text = "" }
	for k, v in pairs(props) do
		base[k] = v
	end
	return make("TextButton", base, children)
end

local scales = {}
local function addScale(frame)
	table.insert(scales, make("UIScale", { Parent = frame }))
end
local function updateScales()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local s = math.clamp(cam.ViewportSize.Y / 720, 0.62, 1)
	for _, sc in ipairs(scales) do
		sc.Scale = s
	end
end

local gui = make("ScreenGui", { Name = "BinguiHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
local hud = make("Frame", { Name = "HUD", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })

---------------------------------------------------------------------
-- 상단 왼쪽: 진화 / 바이오 / 구역
---------------------------------------------------------------------
local topLeft = make("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(170, 120), BackgroundTransparency = 1, Parent = hud }, {
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
addScale(topLeft)
local evoButton = button({ Size = UDim2.fromOffset(120, 36), BackgroundColor3 = C.Purple, TextColor3 = C.PurpleDark, Text = "🧬 진화", LayoutOrder = 1, Parent = topLeft }, { stroke(), pad(6) })
local bioLabel = label({ Size = UDim2.fromOffset(170, 22), TextColor3 = C.White, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = topLeft })
local ownLabel = label({ Size = UDim2.fromOffset(170, 20), TextColor3 = C.White, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3, Font = Enum.Font.GothamMedium, Parent = topLeft })

---------------------------------------------------------------------
-- 상단 가운데: 경계 별 + 몸 상태
---------------------------------------------------------------------
local topCenter = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(260, 92), BackgroundTransparency = 1, Parent = hud })
addScale(topCenter)
local starLabel = label({ Size = UDim2.new(1, 0, 0, 28), TextColor3 = C.Yellow, TextStrokeTransparency = 0.2, Font = Enum.Font.GothamBlack, Text = "☆☆☆☆☆", Parent = topCenter })
local statusCard = make("Frame", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.Paper, Parent = topCenter }, { stroke(), corner(8) })
local bodyLabel = label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = statusCard })
local heartsLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(90, 22), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Red, Parent = statusCard })
local lifeBack = make("Frame", { Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 14), BackgroundColor3 = Color3.fromHex("#d8d0c0"), Parent = statusCard }, { corner(7) })
local lifeFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Purple, Parent = lifeBack }, { corner(7) })

---------------------------------------------------------------------
-- 상단 오른쪽: 미션
---------------------------------------------------------------------
local missionCard = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(250, 84), BackgroundColor3 = C.Cream, Parent = hud }, { stroke(), corner(8) })
addScale(missionCard)
local missionTitle = label({ Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromHex("#8a6ae8"), Font = Enum.Font.GothamBlack, Parent = missionCard })
local missionText = label({ Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, Parent = missionCard })
local missionTip = label({ Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromHex("#5a4a66"), Parent = missionCard })

---------------------------------------------------------------------
-- 오른쪽 아래: 버튼들 (모바일 점프 버튼 위쪽)
---------------------------------------------------------------------
local cluster = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -170), Size = UDim2.fromOffset(200, 170), BackgroundTransparency = 1, Parent = hud })
addScale(cluster)
local aButton = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(88, 88), BackgroundColor3 = C.Purple, TextColor3 = C.PurpleDark, Text = "A", Parent = cluster }, { stroke(nil, 4), corner(44), pad(10), maxText(16) })
local bButton = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -98, 1, 0), Size = UDim2.fromOffset(70, 70), BackgroundColor3 = C.Paper, Text = "B 빙의", Parent = cluster }, { stroke(nil, 4), corner(35), pad(8), maxText(14) })
local skillButton = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -98, 1, -78), Size = UDim2.fromOffset(70, 42), BackgroundColor3 = C.Blue, TextColor3 = Color3.fromHex("#0d2a3a"), Text = "스킬", Parent = cluster }, { stroke(nil, 3), corner(10), pad(5), maxText(12) })
local interactButton = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -98), Size = UDim2.fromOffset(120, 44), BackgroundColor3 = C.Yellow, TextColor3 = Color3.fromHex("#3a2a00"), Text = "", Visible = false, Parent = cluster }, { stroke(nil, 3), corner(10), pad(6), maxText(14) })

local keyHint = label({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 10, 1, -10),
	Size = UDim2.fromOffset(420, 20),
	TextColor3 = C.White,
	TextStrokeTransparency = 0.3,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamMedium,
	Text = "클릭/J: 능력   E/K: 빙의·순간이동   Q: 스킬   F: 상호작용",
	Visible = not UserInputService.TouchEnabled,
	Parent = hud,
})

---------------------------------------------------------------------
-- 배너 / 뉴스 / 떠오르는 글자
---------------------------------------------------------------------
local banner = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(420, 70), BackgroundTransparency = 1, Visible = false, Parent = gui })
addScale(banner)
local bannerTitle = label({ Size = UDim2.new(1, 0, 0, 42), Font = Enum.Font.GothamBlack, TextColor3 = C.Purple, TextStrokeColor3 = C.Dark, TextStrokeTransparency = 0, Parent = banner })
local bannerSub = label({ Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.White, TextStrokeTransparency = 0.2, Parent = banner })
local bannerToken = 0

local function showBanner(title: string, sub: string)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerSub.Text = sub or ""
	banner.Visible = true
	task.delay(2.8, function()
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

local toastHolder = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(440, 160), BackgroundTransparency = 1, Parent = gui }, {
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
})
addScale(toastHolder)
local toastN = 0
local function toast(text: string)
	toastN += 1
	local t = label({ Size = UDim2.fromOffset(420, 32), BackgroundTransparency = 0, BackgroundColor3 = C.Paper, Text = text, LayoutOrder = toastN, Parent = toastHolder }, { stroke(nil, 2), pad(6), maxText(16) })
	local items = {}
	for _, c in ipairs(toastHolder:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(items, c)
		end
	end
	if #items > 3 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #items - 3 do
			items[i]:Destroy()
		end
	end
	task.delay(3.5, function()
		if t.Parent then
			t:Destroy()
		end
	end)
end

local function pop(pos: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = workspace
	local bb = make("BillboardGui", { Size = UDim2.fromOffset(220, 34), AlwaysOnTop = true, Adornee = anchor, Parent = anchor })
	local l = label({ Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = color, TextStrokeTransparency = 0, Font = Enum.Font.GothamBlack, Parent = bb })
	TweenService:Create(anchor, TweenInfo.new(1.2), { CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) }):Play()
	TweenService:Create(l, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.25, function()
		anchor:Destroy()
	end)
end

---------------------------------------------------------------------
-- 오버레이 카드 (타이틀 / 게임오버 / 진화)
---------------------------------------------------------------------
local function overlay(name: string, height: number)
	local ov = make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 14, 30), BackgroundTransparency = 0.22, Visible = false, ZIndex = 10, Parent = gui })
	local card = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, height), BackgroundColor3 = C.Cream, ZIndex = 11, Parent = ov }, { stroke(nil, 4), corner(6) })
	addScale(card)
	return ov, card
end

-- 타이틀
local titleOv, titleCard = overlay("Title", 560)
titleOv.Visible = true
label({ Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 30), Text = "👻", ZIndex = 12, Parent = titleCard })
label({ Position = UDim2.fromOffset(20, 44), Size = UDim2.new(1, -40, 0, 44), Text = "빙의 대소동", TextColor3 = Color3.fromHex("#9a7cff"), TextStrokeColor3 = C.Dark, TextStrokeTransparency = 0, Font = Enum.Font.GothamBlack, ZIndex = 12, Parent = titleCard })
label({ Position = UDim2.fromOffset(20, 90), Size = UDim2.new(1, -40, 0, 40), Font = Enum.Font.GothamMedium, Text = "몸을 잃어버린 귀여운 영혼 혼이!\n남의 몸에 빙의해서 도시를 난장판으로 만들어 보자.", ZIndex = 12, Parent = titleCard }, { maxText(16) })
local how = make("Frame", { Position = UDim2.fromOffset(20, 138), Size = UDim2.new(1, -40, 0, 340), BackgroundColor3 = C.Lilac, ZIndex = 12, Parent = titleCard }, { stroke(nil, 3), pad(10) })
label({
	Size = UDim2.fromScale(1, 1),
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 13,
	Text = table.concat({
		"👻 영혼 상태로는 금방 흩어져요. 벽을 통과해 날아가서 몸에 닿으면 빙의해요.",
		"💫 빙의한 몸은 오래 못 버텨요. B(E키)를 누르면 바라보는 쪽의 몸(흰 테두리)으로 순간이동!",
		"🚪 건물 안 물건 앞에서 노란 버튼(F키)으로 상호작용해요.",
		"🏚️ 건물도 부술 수 있어요. 차로 들이받고, 터뜨리고, 포격해요.",
		"⭐ 깽판을 칠수록 경계 단계가 올라가고 경찰, 퇴마사, 군대가 와요.",
		"🥸 아무도 안 볼 때 숙주를 바꾸면 변장돼서 경계가 내려가요.",
		"🌀 몸마다 고유 스킬(파란 버튼, Q키)이 있어요. 밤엔 퇴마사가 순찰해요.",
		"🎮 A(클릭/J) 몸의 능력, B(E/K) 순간이동 빙의",
	}, "\n"),
	Parent = how,
}, { maxText(15) })
local startButton = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(240, 52), BackgroundColor3 = C.Purple, TextColor3 = C.PurpleDark, Text = "불러오는 중…", ZIndex = 12, Parent = titleCard }, { stroke(nil, 4), pad(10) })

-- 게임오버
local overOv, overCard = overlay("Over", 250)
local overTitle = label({ Position = UDim2.fromOffset(20, 20), Size = UDim2.new(1, -40, 0, 36), Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromHex("#9a7cff"), TextStrokeColor3 = C.Dark, TextStrokeTransparency = 0, ZIndex = 12, Parent = overCard })
local overScore = label({ Position = UDim2.fromOffset(20, 64), Size = UDim2.new(1, -40, 0, 48), Font = Enum.Font.GothamBold, ZIndex = 12, Parent = overCard }, { maxText(18) })
label({ Position = UDim2.fromOffset(20, 116), Size = UDim2.new(1, -40, 0, 20), Font = Enum.Font.GothamMedium, TextTransparency = 0.3, Text = "진화와 미션 진행은 그대로 남아 있어요.", ZIndex = 12, Parent = overCard }, { maxText(13) })
local againButton = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(220, 52), BackgroundColor3 = C.Purple, TextColor3 = C.PurpleDark, Text = "다시 둥실!", ZIndex = 12, Parent = overCard }, { stroke(nil, 4), pad(10) })

-- 진화
local evoOv, evoCard = overlay("Evo", 560)
label({ Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 32), Text = "🧬 진화", Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromHex("#9a7cff"), TextStrokeColor3 = C.Dark, TextStrokeTransparency = 0, ZIndex = 12, Parent = evoCard })
local evoBio = label({ Position = UDim2.fromOffset(20, 48), Size = UDim2.new(1, -40, 0, 22), ZIndex = 12, Parent = evoCard })
local evoList = make("ScrollingFrame", { Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 1, -150), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 12, Parent = evoCard }, {
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local evoClose = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(200, 48), BackgroundColor3 = C.Purple, TextColor3 = C.PurpleDark, Text = "돌아가기", ZIndex = 12, Parent = evoCard }, { stroke(nil, 4), pad(10) })

local evoRows = {}
for i, u in ipairs(GD.Upgrades) do
	local row = make("Frame", { Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = C.Lilac, LayoutOrder = i, ZIndex = 12, Parent = evoList }, { stroke(nil, 3) })
	label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(36, 48), Text = u.Icon, ZIndex = 13, Parent = row })
	local name = label({ Position = UDim2.fromOffset(50, 4), Size = UDim2.new(1, -150, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, ZIndex = 13, Parent = row })
	label({ Position = UDim2.fromOffset(50, 28), Size = UDim2.new(1, -150, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium, TextTransparency = 0.2, Text = u.Desc, ZIndex = 13, Parent = row }, { maxText(13) })
	local buy = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(84, 40), BackgroundColor3 = C.Purple, TextColor3 = C.PurpleDark, ZIndex = 13, Parent = row }, { stroke(nil, 3), pad(5), maxText(14) })
	buy.Activated:Connect(function()
		Action:FireServer("upgrade", u.Id)
	end)
	evoRows[u.Id] = { Name = name, Buy = buy, Def = u }
end

local function upgrades()
	local raw = player:GetAttribute("Upg")
	local ok, t = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return if ok and type(t) == "table" then t else {}
end

local function refreshEvo()
	local bio = player:GetAttribute("Bio") or 0
	evoBio.Text = `보유 🧬 {bio}`
	local upg = upgrades()
	for id, r in pairs(evoRows) do
		local lv = upg[id] or 0
		r.Name.Text = `{r.Def.Name}  Lv.{lv}/{r.Def.Max}`
		if lv >= r.Def.Max then
			r.Buy.Text = "MAX"
			r.Buy.BackgroundColor3 = Color3.fromHex("#cfd2c4")
		else
			local cost = GD.UpgradeCost(lv)
			r.Buy.Text = `🧬 {cost}`
			r.Buy.BackgroundColor3 = if bio >= cost then C.Purple else Color3.fromHex("#cfd2c4")
		end
	end
end

evoButton.Activated:Connect(function()
	refreshEvo()
	evoOv.Visible = true
end)
evoClose.Activated:Connect(function()
	evoOv.Visible = false
end)

startButton.Activated:Connect(function()
	if player:GetAttribute("Loaded") then
		titleOv.Visible = false
		Action:FireServer("start")
	end
end)
againButton.Activated:Connect(function()
	overOv.Visible = false
	Action:FireServer("start")
end)

local function onLoaded()
	if player:GetAttribute("Loaded") then
		startButton.Text = "둥실둥실 시작!"
	end
end
player:GetAttributeChangedSignal("Loaded"):Connect(onLoaded)
onLoaded()

---------------------------------------------------------------------
-- HUD 갱신
---------------------------------------------------------------------
local function refreshHud()
	local playing = player:GetAttribute("Playing") == true
	hud.Visible = playing
	if not playing then
		return
	end
	local stars = player:GetAttribute("Stars") or 0
	starLabel.Text = string.rep("★", stars) .. string.rep("☆", 5 - stars)
	bioLabel.Text = `🧬 {player:GetAttribute("Bio") or 0}`
	ownLabel.Text = `👑 {player:GetAttribute("Owned") or 0}/81` .. (if player:GetAttribute("Night") then "   🌙 밤" else "")

	local bodyType = player:GetAttribute("BodyType") or "ghost"
	local isGhost = bodyType == "ghost"
	local life = player:GetAttribute("Life") or 1
	bodyLabel.Text = if isGhost then "👻 영혼 (흩어지는 중!)" else `💫 {player:GetAttribute("BodyName") or ""}`
	lifeFill.Size = UDim2.fromScale(life, 1)
	lifeFill.BackgroundColor3 = if life < 0.3 then C.Red elseif isGhost then C.Blue else C.Purple
	local hp, hpMax = player:GetAttribute("GhostHP") or 3, player:GetAttribute("GhostMax") or 3
	heartsLabel.Text = string.rep("♥", math.max(0, hp)) .. string.rep("♡", math.max(0, hpMax - hp))

	aButton.Text = "A\n" .. (if isGhost then (if (upgrades().polter or 0) > 0 then "폴터가이스트" else "도약") else (player:GetAttribute("AbilityName") or ""))
	bButton.Text = if isGhost then "B\n빙의" else "B\n순간이동"
	local skill = player:GetAttribute("SkillName") or ""
	skillButton.Visible = not isGhost and skill ~= ""

	local mi = player:GetAttribute("Mission") or 1
	local m = GD.Missions[mi]
	if m then
		local prog = if m.N then ` ({player:GetAttribute("MProg") or 0}/{m.N})` else ""
		missionTitle.Text = `📜 미션 {mi}/{#GD.Missions}`
		missionText.Text = m.Text .. prog
		missionTip.Text = m.Tip
	else
		missionTitle.Text = "📜 미션"
		missionText.Text = "모든 미션 완료! 🎉"
		missionTip.Text = "자유롭게 깽판을 쳐요!"
	end
	if evoOv.Visible then
		refreshEvo()
	end
end

for _, attr in ipairs({ "Playing", "Stars", "Bio", "Owned", "Night", "BodyType", "BodyName", "Life", "GhostHP", "GhostMax", "AbilityName", "SkillName", "Mission", "MProg", "Upg" }) do
	player:GetAttributeChangedSignal(attr):Connect(refreshHud)
end
refreshHud()

---------------------------------------------------------------------
-- 카메라: 몸이 바뀌면 따라가기
---------------------------------------------------------------------
player.CameraMaxZoomDistance = 80
local function onCharacter()
	local char = player.Character
	if not char then
		return
	end
	local hum = char:WaitForChild("Humanoid", 5)
	if hum and workspace.CurrentCamera then
		workspace.CurrentCamera.CameraSubject = hum
	end
end
player:GetPropertyChangedSignal("Character"):Connect(onCharacter)

local zoomedOnce = false
player:GetAttributeChangedSignal("Playing"):Connect(function()
	if player:GetAttribute("Playing") and not zoomedOnce then
		zoomedOnce = true
		player.CameraMinZoomDistance = 30
		task.delay(0.5, function()
			player.CameraMinZoomDistance = 0.5
		end)
	end
end)

---------------------------------------------------------------------
-- 입력
---------------------------------------------------------------------
local abilityHeld = false
local lastAbility = 0

local function fireAbility()
	local t = os.clock()
	if t - lastAbility < 0.09 then
		return
	end
	lastAbility = t
	Action:FireServer("ability")
end

local currentProp = nil
local function doInteract()
	if currentProp then
		Action:FireServer("interact", currentProp:GetAttribute("PropId"))
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not player:GetAttribute("Playing") then
		return
	end
	local k = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.J then
		abilityHeld = true
		fireAbility()
	elseif k == Enum.KeyCode.E or k == Enum.KeyCode.K then
		Action:FireServer("possess")
	elseif k == Enum.KeyCode.Q then
		Action:FireServer("skill")
	elseif k == Enum.KeyCode.F or k == Enum.KeyCode.G or k == Enum.KeyCode.H then
		doInteract()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.J then
		abilityHeld = false
	end
end)

aButton.MouseButton1Down:Connect(function()
	abilityHeld = true
	fireAbility()
end)
aButton.MouseButton1Up:Connect(function()
	abilityHeld = false
end)
aButton.MouseLeave:Connect(function()
	abilityHeld = false
end)
bButton.Activated:Connect(function()
	Action:FireServer("possess")
end)
skillButton.Activated:Connect(function()
	Action:FireServer("skill")
end)
interactButton.Activated:Connect(doInteract)

---------------------------------------------------------------------
-- 서버 이벤트
---------------------------------------------------------------------
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include
task.spawn(function()
	local city = workspace:WaitForChild("City")
	wallParams.FilterDescendantsInstances = { city:WaitForChild("Buildings"), city:WaitForChild("Compounds"), city:WaitForChild("Props") }
end)

local function dash(speed: number, duration: number, passWalls: boolean)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local elapsed = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration or not root.Parent or player.Character ~= char then
			conn:Disconnect()
			return
		end
		local step = look * speed * dt
		if not passWalls then
			local hit = workspace:Raycast(root.Position, look * (step.Magnitude + root.Size.Z / 2 + 0.5), wallParams)
			if hit then
				conn:Disconnect()
				return
			end
		end
		root.CFrame += step
	end)
end

Event.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Banner" then
		showBanner(a, b)
	elseif kind == "Toast" then
		toast(a)
	elseif kind == "Pop" then
		pop(a, b, c)
	elseif kind == "Dash" then
		dash(a, b, c)
	elseif kind == "GameOver" then
		abilityHeld = false
		overTitle.Text = if a.Why == "dry" then "영혼이 흩어졌다…" else "영혼이 퇴치당했다…"
		overScore.Text = `이번 깽판 점수 {a.Chaos}\n최고 기록 {a.Best} · 🧬 {a.Bio}`
		task.delay(0.6, function()
			overOv.Visible = true
		end)
	end
end)

---------------------------------------------------------------------
-- 빙의 대상 표시 / 상호작용 / 지붕 / 미션 표시
---------------------------------------------------------------------
local highlight = make("Highlight", { FillTransparency = 1, OutlineColor = C.White, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false, Parent = workspace })

local hintPart = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one * 0.2, Parent = workspace })
local hintGui = make("BillboardGui", { Size = UDim2.fromOffset(40, 40), StudsOffset = Vector3.new(0, 7, 0), AlwaysOnTop = true, Adornee = hintPart, Enabled = false, Parent = hintPart })
label({ Size = UDim2.fromScale(1, 1), Text = "📍", Parent = hintGui })

local function findTarget(root: BasePart)
	local bodies = workspace:FindFirstChild("Bodies")
	if not bodies then
		return nil
	end
	local upg = upgrades()
	local range = GD.SoulRange(upg.jump or 0)
	local pos = root.Position
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local best, bs = nil, math.huge
	for _, m in ipairs(bodies:GetChildren()) do
		if m ~= player.Character and m:GetAttribute("Type") and m:GetAttribute("Type") ~= "ghost" and not m:GetAttribute("Dead") and m:GetAttribute("Possessable") ~= false and not Players:GetPlayerFromCharacter(m) then
			local r = m:FindFirstChild("HumanoidRootPart")
			if r then
				local to = (r.Position - pos) * Vector3.new(1, 0, 1)
				local d = to.Magnitude
				if d > 0.1 and d <= range then
					local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
					if not (ang > 0.9 and d > 9.6) then
						local score = d + ang * 17
						if score < bs then
							best, bs = m, score
						end
					end
				end
			end
		end
	end
	return best
end

local function findProp(root: BasePart)
	local props = workspace:FindFirstChild("City") and workspace.City:FindFirstChild("Props")
	if not props then
		return nil
	end
	local best, bd = nil, 8
	for _, m in ipairs(props:GetChildren()) do
		if m:GetAttribute("Interact") then
			local p = m:GetPivot().Position
			local d = ((p - root.Position) * Vector3.new(1, 0, 1)).Magnitude
			if d < bd then
				best, bd = m, d
			end
		end
	end
	return best
end

local roofT = 0
local function updateRoofs(root: BasePart?)
	local city = workspace:FindFirstChild("City")
	local buildings = city and city:FindFirstChild("Buildings")
	if not buildings then
		return
	end
	for _, b in ipairs(buildings:GetChildren()) do
		local roof = b:FindFirstChild("Roof")
		if roof then
			local inside = false
			if root then
				local center, size = b:GetAttribute("Center"), b:GetAttribute("Size")
				if center and size then
					local d = root.Position - center
					inside = math.abs(d.X) < size.X / 2 + 1 and math.abs(d.Z) < size.Z / 2 + 1
				end
			end
			roof.LocalTransparencyModifier = if inside then 0.92 else 0
		end
	end
end

local skillT = 0
local scanT = 0
RunService.RenderStepped:Connect(function()
	local playing = player:GetAttribute("Playing") == true
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")

	if abilityHeld and playing then
		fireAbility()
	end

	local t = os.clock()
	if t - scanT > 0.1 then
		scanT = t
		-- 빙의 대상
		local target = if playing and root then findTarget(root) else nil
		highlight.Adornee = target
		highlight.Enabled = target ~= nil

		-- 상호작용
		local isHost = (player:GetAttribute("BodyType") or "ghost") ~= "ghost"
		currentProp = if playing and root and isHost then findProp(root) else nil
		interactButton.Visible = currentProp ~= nil
		if currentProp then
			interactButton.Text = currentProp:GetAttribute("Interact") .. (if UserInputService.TouchEnabled then "" else " [F]")
		end
	end

	-- 스킬 쿨다운
	if t - skillT > 0.1 then
		skillT = t
		local readyAt = player:GetAttribute("SkillReadyAt") or 0
		local left = readyAt - workspace:GetServerTimeNow()
		local name = player:GetAttribute("SkillName") or "스킬"
		if left > 0 then
			skillButton.Text = `{name}\n{math.ceil(left)}초`
			skillButton.BackgroundColor3 = Color3.fromRGB(120, 140, 150)
		else
			skillButton.Text = name .. (if UserInputService.TouchEnabled then "" else " [Q]")
			skillButton.BackgroundColor3 = C.Blue
		end
	end

	-- 지붕 숨기기 (0.15초마다)
	if t - roofT > 0.15 then
		roofT = t
		updateRoofs(if playing then root else nil)
	end

	-- 미션 위치
	local hint = player:GetAttribute("Hint")
	if playing and typeof(hint) == "Vector3" then
		hintPart.CFrame = CFrame.new(hint)
		hintGui.Enabled = true
	else
		hintGui.Enabled = false
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScales)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScales)
end
updateScales()
