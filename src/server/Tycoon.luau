-- 타이쿤 핵심 로직: 부지 배정, 구매 버튼, 드로퍼/광석, 돈, 환생
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Builders = require(script.Parent:WaitForChild("ItemBuilders"))

local Tycoon = {}

-- Main에서 설정: 환생 같은 중요한 변화 직후 바로 저장하기 위한 콜백
Tycoon.SaveCallback = nil :: ((Player) -> ())?

local ORE_SIZE = Vector3.new(1.2, 1.2, 1.2)
local CONVEYOR_Z = -10
local BUTTON_GREEN = Color3.fromRGB(46, 204, 113)
local BUTTON_RED = Color3.fromRGB(231, 76, 60)

local plots = {}
local states = {} -- [Player] = state
local itemById = {}
for _, def in ipairs(Config.Items) do
	assert(not itemById[def.Id], "Config.Items에 중복된 Id: " .. def.Id)
	itemById[def.Id] = def
end

local notifyRemote: RemoteEvent

---------------------------------------------------------------------
-- 유틸
---------------------------------------------------------------------
function Tycoon.Notify(player: Player, text: string, kind: string?)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, kind or "info")
	end
end

local function popIn(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local target = part.Transparency
			part.Transparency = 1
			TweenService:Create(part, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Transparency = target }):Play()
		end
	end
end

local function setConveyorSpeed(plot, speed: number)
	plot.ConveyorSpeed = speed
	-- 앵커된 파트에 속도를 주면 위에 놓인 물체가 밀려감 (컨베이어 원리)
	plot.Conveyor.AssemblyLinearVelocity = plot.CFrame:VectorToWorldSpace(Vector3.new(speed, 0, 0))
end

local function setSign(plot, text: string)
	for _, label in ipairs(plot.SignLabels) do
		label.Text = text
	end
end

---------------------------------------------------------------------
-- 버튼
---------------------------------------------------------------------
local function updateButtonColors(plot, cash: number)
	for _, button in ipairs(plot.ButtonsFolder:GetChildren()) do
		local price = button:GetAttribute("Price") or 0
		button.Color = if cash >= price then BUTTON_GREEN else BUTTON_RED
	end
end

local function createButton(plot, def, index: number)
	local row = (index - 1) // 9
	local col = (index - 1) % 9
	local cf = plot.CFrame * CFrame.new(-40 + col * 10, 1.5, 22 + row * 8)

	local button = Instance.new("Part")
	button.Name = def.Id
	button.Anchored = true
	button.Size = Vector3.new(5, 0.6, 5)
	button.CFrame = cf
	button.Material = Enum.Material.Neon
	button.TopSurface = Enum.SurfaceType.Smooth
	button:SetAttribute("Price", def.Price)
	button:SetAttribute("ItemId", def.Id)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 56)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.MaxDistance = 70
	gui.Adornee = button
	gui.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0.55)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.Text = def.Name
	nameLabel.Parent = gui

	local priceLabel = nameLabel:Clone()
	priceLabel.Position = UDim2.fromScale(0, 0.55)
	priceLabel.Size = UDim2.fromScale(1, 0.45)
	priceLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
	priceLabel.Text = if def.Price <= 0 then "무료" else Format.Cash(def.Price)
	priceLabel.Parent = gui

	button.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and player == plot.Owner then
			Tycoon.TryPurchase(player, def.Id)
		end
	end)

	button.Parent = plot.ButtonsFolder
	return button
end

local function refreshButtons(plot)
	plot.ButtonsFolder:ClearAllChildren()
	local owner = plot.Owner
	local state = owner and states[owner]
	if not state then
		return
	end

	for i, def in ipairs(Config.Items) do
		if not state.Purchased[def.Id] and (not def.Requires or state.Purchased[def.Requires]) then
			createButton(plot, def, i)
		end
	end
	updateButtonColors(plot, state.Cash)
end

---------------------------------------------------------------------
-- 아이템 / 광석
---------------------------------------------------------------------
local function spawnOre(plot, def)
	local ore = Instance.new("Part")
	ore.Name = "Ore"
	ore.Size = ORE_SIZE
	ore.Color = def.OreColor or Color3.fromRGB(120, 120, 120)
	ore.Material = def.OreMaterial or Enum.Material.SmoothPlastic
	ore.CFrame = plot.CFrame * CFrame.new(def.X, 3.9, CONVEYOR_Z)
	ore.CollisionGroup = "Ores"
	ore:SetAttribute("Value", def.Value)
	ore.Parent = plot.OresFolder
	pcall(function()
		ore:SetNetworkOwner(nil) -- 서버가 물리 담당 (치트/끊김 방지)
	end)
	Debris:AddItem(ore, Config.ORE_LIFETIME)
end

local function buildItem(plot, def, animate: boolean)
	local builder = Builders[def.Type]
	if not builder then
		warn("[Tycoon] 알 수 없는 아이템 Type:", def.Type)
		return
	end

	local model = Instance.new("Model")
	model.Name = def.Id
	builder(model, plot.CFrame, def)
	model.Parent = plot.ItemsFolder

	if def.Type == "Dropper" then
		table.insert(plot.Droppers, { Def = def, NextDrop = os.clock() + def.Interval })
	elseif def.Type == "Upgrader" then
		local gate = model:FindFirstChild("Gate")
		local tag = "U_" .. def.Id
		gate.Touched:Connect(function(hit)
			if hit.Parent ~= plot.OresFolder or hit:GetAttribute(tag) then
				return
			end
			hit:SetAttribute(tag, true)
			hit:SetAttribute("Value", (hit:GetAttribute("Value") or 0) * def.Multiplier)
			hit.Color = def.Color
			hit.Material = Enum.Material.Neon
		end)
	elseif def.Type == "ConveyorBoost" then
		setConveyorSpeed(plot, math.max(plot.ConveyorSpeed, def.Speed))
	end

	if animate then
		popIn(model)
	end
end

local function resetPlotItems(plot)
	plot.Droppers = {}
	plot.ItemsFolder:ClearAllChildren()
	plot.OresFolder:ClearAllChildren()
	setConveyorSpeed(plot, Config.CONVEYOR_SPEED)
end

---------------------------------------------------------------------
-- 돈
---------------------------------------------------------------------
local function setCash(state, value: number)
	state.Cash = math.max(0, math.floor(value))
	state.CashValue.Value = state.Cash
	if state.Plot then
		updateButtonColors(state.Plot, state.Cash)
	end
end

local function syncStats(state)
	state.Multiplier = Config.GetMultiplier(state.Rebirths, state.Has2x)
	state.RebirthValue.Value = state.Rebirths
	state.Player:SetAttribute("Multiplier", state.Multiplier)
	state.Player:SetAttribute("Has2x", state.Has2x)
end

function Tycoon.AddCash(player: Player, amount: number, applyMultiplier: boolean?)
	local state = states[player]
	if not state or not state.Loaded then
		return
	end
	if applyMultiplier then
		amount *= state.Multiplier
	end
	setCash(state, state.Cash + amount)
end

function Tycoon.SetHas2x(player: Player, has2x: boolean)
	local state = states[player]
	if state then
		state.Has2x = has2x
		syncStats(state)
	end
end

---------------------------------------------------------------------
-- 부지 생성
---------------------------------------------------------------------
local function createPlot(index: number, cf: CFrame, root: Folder)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model.Parent = root

	local refs = Builders.Base(model, cf)

	local plot = {
		Index = index,
		CFrame = cf,
		Model = model,
		Owner = nil :: Player?,
		Conveyor = refs.Conveyor,
		SignLabels = refs.SignLabels,
		ConveyorSpeed = Config.CONVEYOR_SPEED,
		Droppers = {},
		OreCount = 0,
	}

	for _, name in ipairs({ "Items", "Buttons", "Ores" }) do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = model
		plot[name .. "Folder"] = folder
	end

	plot.OresFolder.ChildAdded:Connect(function()
		plot.OreCount += 1
	end)
	plot.OresFolder.ChildRemoved:Connect(function()
		plot.OreCount -= 1
	end)

	refs.Collector.Touched:Connect(function(hit)
		if hit.Parent ~= plot.OresFolder or hit:GetAttribute("Sold") then
			return
		end
		hit:SetAttribute("Sold", true)
		local value = hit:GetAttribute("Value") or 0
		hit:Destroy()
		if plot.Owner then
			Tycoon.AddCash(plot.Owner, value, true)
		end
	end)

	setConveyorSpeed(plot, Config.CONVEYOR_SPEED)
	return plot
end

function Tycoon.Init(remotes: Folder)
	notifyRemote = remotes:WaitForChild("Notify") :: RemoteEvent

	pcall(function()
		PhysicsService:RegisterCollisionGroup("Ores")
	end)
	PhysicsService:CollisionGroupSetCollidable("Ores", "Ores", false) -- 광석끼리 안 부딪힘 (렉 감소)

	-- 베이스플레이트가 없으면 바닥 생성
	if not workspace:FindFirstChild("Baseplate") then
		local ground = Instance.new("Part")
		ground.Name = "Baseplate"
		ground.Anchored = true
		ground.Size = Vector3.new(1024, 2, 1024)
		ground.CFrame = CFrame.new(0, -1, 0)
		ground.Color = Color3.fromRGB(70, 115, 60)
		ground.Material = Enum.Material.Grass
		ground.Parent = workspace
	end

	local root = Instance.new("Folder")
	root.Name = "Tycoons"
	root.Parent = workspace

	-- 가운데 도로를 사이에 두고 두 줄로 마주보게 배치
	local perRow = math.ceil(Config.PLOT_COUNT / 2)
	local rowZ = Config.ROAD_HALF_WIDTH + 50
	for i = 1, Config.PLOT_COUNT do
		local row = if i <= perRow then 0 else 1
		local col = if row == 0 then i - 1 else i - 1 - perRow
		local x = (col - (perRow - 1) / 2) * Config.PLOT_SPACING
		local cf
		if row == 0 then
			cf = CFrame.new(x, 0, rowZ) * CFrame.Angles(0, math.pi, 0) -- 입구가 도로(-Z) 쪽
		else
			cf = CFrame.new(x, 0, -rowZ)
		end
		table.insert(plots, createPlot(i, cf, root))
	end

	-- 드로퍼 루프 (모든 부지 한 번에 처리)
	task.spawn(function()
		while true do
			local now = os.clock()
			for _, plot in ipairs(plots) do
				if plot.Owner then
					for _, dropper in ipairs(plot.Droppers) do
						if now >= dropper.NextDrop then
							dropper.NextDrop = now + dropper.Def.Interval
							if plot.OreCount < Config.MAX_ORES_PER_PLOT then
								spawnOre(plot, dropper.Def)
							end
						end
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

---------------------------------------------------------------------
-- 플레이어
---------------------------------------------------------------------
local function teleportToPlot(state)
	local character = state.Player.Character
	if not character or not state.Plot then
		return
	end
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if not root or not state.Plot then
			return
		end
		task.wait(0.1)
		character:PivotTo(state.Plot.CFrame * CFrame.new(0, 5, 40))
	end)
end

-- 접속 직후 (데이터 로딩 전) 리더보드 생성
function Tycoon.SetupPlayer(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = 0
	rebirths.Parent = leaderstats

	leaderstats.Parent = player

	states[player] = {
		Player = player,
		Loaded = false,
		CanSave = false,
		Cash = 0,
		Rebirths = 0,
		Multiplier = 1,
		Has2x = false,
		Purchased = {},
		Receipts = {},
		CashValue = cash,
		RebirthValue = rebirths,
		Plot = nil,
		Connections = {},
		LastPoorNotice = 0,
	}
end

function Tycoon.LoadPlayer(player: Player, data, canSave: boolean)
	local state = states[player]
	if not state then
		return
	end

	state.Rebirths = data.Rebirths
	state.Purchased = data.Purchased
	state.Receipts = data.Receipts
	state.CanSave = canSave
	syncStats(state)
	setCash(state, data.Cash)
	state.Loaded = true

	-- 빈 부지 배정
	for _, plot in ipairs(plots) do
		if not plot.Owner then
			plot.Owner = player
			state.Plot = plot
			break
		end
	end

	local plot = state.Plot
	if plot then
		setSign(plot, player.DisplayName .. "의 타이쿤")
		for _, def in ipairs(Config.Items) do
			if state.Purchased[def.Id] then
				buildItem(plot, def, false)
			end
		end
		refreshButtons(plot)
		player:SetAttribute("PlotIndex", plot.Index)

		table.insert(state.Connections, player.CharacterAdded:Connect(function()
			teleportToPlot(state)
		end))
		teleportToPlot(state)
	else
		Tycoon.Notify(player, "모든 부지가 찼어요! 다른 서버로 들어가 주세요.", "error")
	end

	player:SetAttribute("Loaded", true)

	if not canSave then
		Tycoon.Notify(player, "⚠ 데이터를 불러오지 못해 이번 진행은 저장되지 않아요.", "error")
	end
end

-- 나갈 때: 부지 비우고 저장할 state 반환
function Tycoon.RemovePlayer(player: Player)
	local state = states[player]
	states[player] = nil
	if not state then
		return nil
	end

	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end

	local plot = state.Plot
	if plot then
		plot.Owner = nil
		resetPlotItems(plot)
		plot.ButtonsFolder:ClearAllChildren()
		setSign(plot, "빈 자리")
		state.Plot = nil
	end

	return state
end

function Tycoon.GetState(player: Player)
	return states[player]
end

function Tycoon.GetAllStates()
	local list = {}
	for _, state in pairs(states) do
		table.insert(list, state)
	end
	return list
end

function Tycoon.Serialize(state)
	local purchased = {}
	for id in pairs(state.Purchased) do
		if itemById[id] then
			table.insert(purchased, id)
		end
	end
	return {
		Version = 1,
		Cash = state.Cash,
		Rebirths = state.Rebirths,
		Purchased = purchased,
		Receipts = state.Receipts,
	}
end

---------------------------------------------------------------------
-- 구매 / 환생
---------------------------------------------------------------------
function Tycoon.TryPurchase(player: Player, itemId: string)
	local state = states[player]
	local def = itemById[itemId]
	if not state or not state.Loaded or not state.Plot or not def then
		return
	end
	if state.Purchased[itemId] then
		return
	end
	if def.Requires and not state.Purchased[def.Requires] then
		return
	end

	if state.Cash < def.Price then
		local now = os.clock()
		if now - state.LastPoorNotice > 2 then
			state.LastPoorNotice = now
			Tycoon.Notify(player, `돈이 부족해요! ({Format.Cash(def.Price - state.Cash)} 더 필요)`, "error")
		end
		return
	end

	state.Purchased[itemId] = true
	setCash(state, state.Cash - def.Price)
	buildItem(state.Plot, def, true)
	refreshButtons(state.Plot)
	Tycoon.Notify(player, `✅ {def.Name} 구매 완료!`, "success")
end

function Tycoon.Rebirth(player: Player): (boolean, string)
	local state = states[player]
	if not state or not state.Loaded then
		return false, "아직 데이터를 불러오는 중이에요."
	end

	local cost = Config.GetRebirthCost(state.Rebirths)
	if state.Cash < cost then
		return false, `환생하려면 {Format.Cash(cost)}이 필요해요.`
	end

	state.Rebirths += 1
	state.Purchased = {}
	syncStats(state)
	setCash(state, Config.START_CASH)

	if state.Plot then
		resetPlotItems(state.Plot)
		refreshButtons(state.Plot)
		teleportToPlot(state)
	end

	if Tycoon.SaveCallback then
		task.spawn(Tycoon.SaveCallback, player)
	end

	return true, `♻ 환생 완료! 이제 수입 {Format.Multiplier(state.Multiplier)}!`
end

return Tycoon
