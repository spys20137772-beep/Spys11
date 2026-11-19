-- 클라이언트 UI: 돈 표시, 상점, 환생, 알림, +$ 팝업
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("TycoonRemotes")
local NotifyRemote = Remotes:WaitForChild("Notify") :: RemoteEvent
local RebirthRemote = Remotes:WaitForChild("Rebirth") :: RemoteFunction

local leaderstats = player:WaitForChild("leaderstats")
local cashValue = leaderstats:WaitForChild("Cash") :: NumberValue
local rebirthValue = leaderstats:WaitForChild("Rebirths") :: IntValue

local COLORS = {
	Panel = Color3.fromRGB(24, 26, 33),
	PanelLight = Color3.fromRGB(40, 44, 56),
	Text = Color3.new(1, 1, 1),
	Sub = Color3.fromRGB(170, 176, 190),
	Green = Color3.fromRGB(46, 204, 113),
	Red = Color3.fromRGB(231, 76, 60),
	Gold = Color3.fromRGB(255, 200, 60),
	Blue = Color3.fromRGB(52, 152, 219),
	Purple = Color3.fromRGB(155, 89, 182),
	Gray = Color3.fromRGB(90, 94, 105),
}

---------------------------------------------------------------------
-- UI 헬퍼
---------------------------------------------------------------------
local function make(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(radius: number?)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

local function stroke(color: Color3, thickness: number?)
	return make("UIStroke", { Color = color, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function padding(px: number)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	})
end

local function maxText(size: number)
	return make("UITextSizeConstraint", { MaxTextSize = size })
end

local function label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.Text,
		TextScaled = true,
		TextWrapped = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return make("TextLabel", defaults)
end

local function button(props, children)
	local defaults = {
		AutoButtonColor = true,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.Text,
		TextScaled = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return make("TextButton", defaults, children)
end

-- 작은 화면(모바일)에서 UI 크기 자동 축소
local scales = {}
local function addScale(frame: GuiObject)
	table.insert(scales, make("UIScale", { Parent = frame }))
end
local function updateScales()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local scale = math.clamp(camera.ViewportSize.Y / 700, 0.6, 1)
	for _, s in ipairs(scales) do
		s.Scale = scale
	end
end

---------------------------------------------------------------------
-- 화면 구성
---------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "TycoonHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- 돈 표시
local cashPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(280, 76),
	BackgroundColor3 = COLORS.Panel,
	BackgroundTransparency = 0.1,
	Parent = gui,
}, { corner(14), stroke(COLORS.Gold, 2) })
addScale(cashPanel)

local cashLabel = label({
	Position = UDim2.fromOffset(12, 6),
	Size = UDim2.new(1, -24, 0, 42),
	Font = Enum.Font.GothamBlack,
	TextColor3 = COLORS.Gold,
	Text = "$0",
	Parent = cashPanel,
})
local subLabel = label({
	Position = UDim2.fromOffset(12, 48),
	Size = UDim2.new(1, -24, 0, 20),
	Font = Enum.Font.GothamMedium,
	TextColor3 = COLORS.Sub,
	Text = "",
	Parent = cashPanel,
})

-- 왼쪽 메뉴 버튼
local side = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(140, 110),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
})
addScale(side)

local shopButton = button({
	Text = "🛒 상점",
	Size = UDim2.fromOffset(140, 50),
	BackgroundColor3 = COLORS.Blue,
	LayoutOrder = 1,
	Parent = side,
}, { corner(12), padding(10), maxText(22) })

local rebirthButton = button({
	Text = "♻ 환생",
	Size = UDim2.fromOffset(140, 50),
	BackgroundColor3 = COLORS.Purple,
	LayoutOrder = 2,
	Parent = side,
}, { corner(12), padding(10), maxText(22) })

-- 패널 공통
local panels = {}
local function makePanel(title: string, accent: Color3, height: number)
	local panel = make("Frame", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, height),
		BackgroundColor3 = COLORS.Panel,
		Parent = gui,
	}, { corner(16), stroke(accent, 3) })
	addScale(panel)

	label({
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -80, 0, 34),
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = accent,
		Text = title,
		Parent = panel,
	})

	local close = button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = COLORS.Red,
		Text = "X",
		Parent = panel,
	}, { corner(8), padding(6) })
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	local content = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 58),
		Size = UDim2.new(1, -32, 1, -74),
		Parent = panel,
	})

	table.insert(panels, panel)
	return panel, content
end

local function togglePanel(panel: Frame)
	local show = not panel.Visible
	for _, p in ipairs(panels) do
		p.Visible = false
	end
	panel.Visible = show
end

---------------------------------------------------------------------
-- 환생 패널
---------------------------------------------------------------------
local rebirthPanel, rebirthContent = makePanel("♻ 환생", COLORS.Purple, 330)

label({
	Size = UDim2.new(1, 0, 0, 44),
	Font = Enum.Font.GothamMedium,
	TextColor3 = COLORS.Sub,
	Text = "돈과 구매한 아이템이 모두 초기화돼요.\n대신 수입 배수가 영구적으로 올라가요!",
	Parent = rebirthContent,
})

local multLabel = label({
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(1, 0, 0, 30),
	TextColor3 = COLORS.Gold,
	Parent = rebirthContent,
})

local costLabel = label({
	Position = UDim2.fromOffset(0, 90),
	Size = UDim2.new(1, 0, 0, 24),
	Font = Enum.Font.GothamMedium,
	Parent = rebirthContent,
})

local barBack = make("Frame", {
	Position = UDim2.fromOffset(0, 124),
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundColor3 = COLORS.PanelLight,
	Parent = rebirthContent,
}, { corner(12) })
local barFill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = COLORS.Purple,
	Parent = barBack,
}, { corner(12) })
local barText = label({
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
	Text = "0%",
	Parent = barBack,
})
make("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = barText })

local confirmRebirth = button({
	Position = UDim2.fromOffset(0, 166),
	Size = UDim2.new(1, 0, 0, 54),
	BackgroundColor3 = COLORS.Purple,
	Text = "환생하기",
	Parent = rebirthContent,
}, { corner(12), padding(12), maxText(24) })

---------------------------------------------------------------------
-- 상점 패널
---------------------------------------------------------------------
local shopPanel, shopContent = makePanel("🛒 상점", COLORS.Blue, 340)

local shopList = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = shopContent,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local toast -- 아래에서 정의

local gamepassButton = button({
	Size = UDim2.new(1, -6, 0, 60),
	BackgroundColor3 = COLORS.Gold,
	TextColor3 = COLORS.Panel,
	Text = "",
	LayoutOrder = 1,
	Parent = shopList,
}, { corner(12), padding(10), maxText(22) })

gamepassButton.Activated:Connect(function()
	if Config.GAMEPASS_2X_CASH == 0 then
		toast("게임패스 ID가 아직 설정되지 않았어요 (Config.GAMEPASS_2X_CASH)", "error")
	elseif player:GetAttribute("Has2x") then
		toast("이미 가지고 있어요!", "info")
	else
		MarketplaceService:PromptGamePassPurchase(player, Config.GAMEPASS_2X_CASH)
	end
end)

for i, product in ipairs(Config.CASH_PRODUCTS) do
	local configured = product.Id ~= 0
	local b = button({
		Size = UDim2.new(1, -6, 0, 52),
		BackgroundColor3 = if configured then COLORS.Green else COLORS.Gray,
		Text = product.Label .. (if configured then "" else " (ID 설정 필요)"),
		LayoutOrder = 1 + i,
		Parent = shopList,
	}, { corner(12), padding(10), maxText(20) })

	b.Activated:Connect(function()
		if configured then
			MarketplaceService:PromptProductPurchase(player, product.Id)
		else
			toast("상품 ID가 아직 설정되지 않았어요 (Config.CASH_PRODUCTS)", "error")
		end
	end)
end

---------------------------------------------------------------------
-- 알림 (토스트)
---------------------------------------------------------------------
local toastHolder = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(420, 220),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}),
})
addScale(toastHolder)

local toastCount = 0
toast = function(text: string, kind: string?)
	toastCount += 1
	local accent = if kind == "success" then COLORS.Green elseif kind == "error" then COLORS.Red else COLORS.Blue

	local outline = stroke(accent, 2)
	local t = label({
		Size = UDim2.fromOffset(400, 40),
		BackgroundTransparency = 0.05,
		BackgroundColor3 = COLORS.Panel,
		Text = text,
		LayoutOrder = toastCount,
		Parent = toastHolder,
	})
	corner(10).Parent = t
	outline.Parent = t
	padding(8).Parent = t
	maxText(18).Parent = t

	-- 최대 4개까지만 표시
	local existing = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(existing, child)
		end
	end
	if #existing > 4 then
		table.sort(existing, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #existing - 4 do
			existing[i]:Destroy()
		end
	end

	task.delay(3, function()
		if not t.Parent then
			return
		end
		local info = TweenInfo.new(0.4)
		TweenService:Create(t, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(outline, info, { Transparency = 1 }):Play()
		task.wait(0.45)
		t:Destroy()
	end)
end

NotifyRemote.OnClientEvent:Connect(toast)

---------------------------------------------------------------------
-- 상태 갱신
---------------------------------------------------------------------
local function refresh()
	local cash = cashValue.Value
	local rebirths = rebirthValue.Value
	local mult = player:GetAttribute("Multiplier") or 1
	local has2x = player:GetAttribute("Has2x") == true

	cashLabel.Text = Format.Cash(cash)
	subLabel.Text = `수입 {Format.Multiplier(mult)}  ·  환생 {rebirths}회`

	local cost = Config.GetRebirthCost(rebirths)
	local nextMult = Config.GetMultiplier(rebirths + 1, has2x)
	local progress = math.clamp(cash / cost, 0, 1)
	multLabel.Text = `{Format.Multiplier(mult)}  →  {Format.Multiplier(nextMult)}`
	costLabel.Text = `필요 금액: {Format.Cash(cost)}`
	barFill.Size = UDim2.fromScale(progress, 1)
	barText.Text = `{math.floor(progress * 100)}%`
	confirmRebirth.BackgroundColor3 = if progress >= 1 then COLORS.Purple else COLORS.Gray

	if Config.GAMEPASS_2X_CASH == 0 then
		gamepassButton.Text = "⭐ 수입 2배 게임패스 (ID 설정 필요)"
	elseif has2x then
		gamepassButton.Text = "⭐ 수입 2배 게임패스 — 보유 중"
	else
		gamepassButton.Text = "⭐ 수입 2배 게임패스 구매"
	end
end

-- 돈이 늘어날 때 "+$" 팝업 (0.6초마다 묶어서 표시)
local pendingGain = 0
local lastCash = cashValue.Value

cashValue.Changed:Connect(function(value)
	if player:GetAttribute("Loaded") and value > lastCash then
		pendingGain += value - lastCash
	end
	lastCash = value
	refresh()
end)

task.spawn(function()
	while true do
		task.wait(0.6)
		if pendingGain > 0 then
			local amount = pendingGain
			pendingGain = 0

			local popup = label({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, math.random(-70, 70), 0, 92),
				Size = UDim2.fromOffset(140, 30),
				Font = Enum.Font.GothamBlack,
				TextColor3 = COLORS.Green,
				TextStrokeTransparency = 0.4,
				Text = "+" .. Format.Cash(amount),
				Parent = gui,
			})
			local info = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(popup, info, {
				Position = popup.Position + UDim2.fromOffset(0, 40),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
			task.delay(1.05, function()
				popup:Destroy()
			end)
		end
	end
end)

rebirthValue.Changed:Connect(refresh)
player:GetAttributeChangedSignal("Multiplier"):Connect(refresh)
player:GetAttributeChangedSignal("Has2x"):Connect(refresh)

shopButton.Activated:Connect(function()
	togglePanel(shopPanel)
end)
rebirthButton.Activated:Connect(function()
	togglePanel(rebirthPanel)
end)

local rebirthBusy = false
confirmRebirth.Activated:Connect(function()
	if rebirthBusy then
		return
	end
	rebirthBusy = true
	local ok, success, message = pcall(function()
		return RebirthRemote:InvokeServer()
	end)
	rebirthBusy = false

	if not ok then
		toast("요청에 실패했어요. 다시 시도해 주세요.", "error")
		return
	end
	toast(message, if success then "success" else "error")
	if success then
		rebirthPanel.Visible = false
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScales)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScales)
end
updateScales()
refresh()
