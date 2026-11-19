-- 서버 진입점: 리모트 생성, 플레이어 접속/퇴장, 자동 저장
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Tycoon = require(script.Parent:WaitForChild("Tycoon"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local Monetization = require(script.Parent:WaitForChild("Monetization"))

-- 리모트
local remotes = Instance.new("Folder")
remotes.Name = "TycoonRemotes"

local notify = Instance.new("RemoteEvent")
notify.Name = "Notify"
notify.Parent = remotes

local rebirth = Instance.new("RemoteFunction")
rebirth.Name = "Rebirth"
rebirth.Parent = remotes

remotes.Parent = ReplicatedStorage

-- 저장
local pendingSaves = 0

local function saveState(state)
	if not state or not state.Loaded or not state.CanSave then
		return
	end
	pendingSaves += 1
	local ok, err = pcall(DataService.Save, state.Player.UserId, Tycoon.Serialize(state))
	if not ok then
		warn("[Tycoon] 저장 중 오류:", err)
	end
	pendingSaves -= 1
end

local function savePlayer(player: Player)
	saveState(Tycoon.GetState(player))
end

Tycoon.SaveCallback = savePlayer
Tycoon.Init(remotes)
Monetization.Init(Tycoon, savePlayer)

-- 환생 요청 (쿨다운으로 연타 방지)
local lastRebirth = {}
rebirth.OnServerInvoke = function(player)
	local now = os.clock()
	if lastRebirth[player] and now - lastRebirth[player] < 1 then
		return false, "잠시 후 다시 시도해 주세요."
	end
	lastRebirth[player] = now
	return Tycoon.Rebirth(player)
end

-- 접속 / 퇴장
local function onPlayerAdded(player: Player)
	Tycoon.SetupPlayer(player)
	local data, canSave = DataService.Load(player)
	if not player.Parent then
		return -- 로딩 중에 나감
	end
	Tycoon.LoadPlayer(player, data, canSave)
	Monetization.CheckGamepass(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRebirth[player] = nil
	local state = Tycoon.RemovePlayer(player)
	saveState(state)
end)

-- 자동 저장
task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for _, state in ipairs(Tycoon.GetAllStates()) do
			task.spawn(saveState, state)
		end
	end
end)

-- 서버 종료 시 전부 저장
game:BindToClose(function()
	for _, state in ipairs(Tycoon.GetAllStates()) do
		task.spawn(saveState, state)
	end
	local start = os.clock()
	task.wait(0.5)
	while pendingSaves > 0 and os.clock() - start < 25 do
		task.wait(0.2)
	end
end)
