-- DataStore 저장/불러오기 (재시도 포함)
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DataService = {}

local MAX_RECEIPTS = 50

local store: DataStore? = nil
local ok, err = pcall(function()
	store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
end)
if not ok then
	warn("[Tycoon] DataStore 사용 불가 (Studio라면 '게임 설정 > 보안 > API 서비스 접근 허용'을 켜세요):", err)
end

local function key(userId: number): string
	return "Player_" .. userId
end

local function defaultData()
	return {
		Cash = Config.START_CASH,
		Rebirths = 0,
		Purchased = {}, -- [itemId] = true
		Receipts = {}, -- 처리한 결제 영수증 ID (중복 지급 방지)
	}
end

-- 반환: data, canSave
-- 불러오기에 실패하면 canSave = false (기존 데이터를 빈 데이터로 덮어쓰지 않기 위해)
function DataService.Load(player: Player)
	local data = defaultData()
	if not store then
		return data, false
	end

	for attempt = 1, 3 do
		local success, result = pcall(function()
			return store:GetAsync(key(player.UserId))
		end)

		if success then
			if type(result) == "table" then
				data.Cash = tonumber(result.Cash) or data.Cash
				data.Rebirths = tonumber(result.Rebirths) or 0
				if type(result.Purchased) == "table" then
					for _, id in ipairs(result.Purchased) do
						data.Purchased[id] = true
					end
				end
				if type(result.Receipts) == "table" then
					data.Receipts = result.Receipts
				end
			end
			return data, true
		end

		warn(`[Tycoon] {player.Name} 데이터 불러오기 실패 ({attempt}/3):`, result)
		task.wait(attempt * 1.5)
	end

	return data, false
end

function DataService.Save(userId: number, serialized): boolean
	if not store then
		return false
	end

	-- 영수증 기록은 최근 것만 유지
	local receipts = serialized.Receipts
	if receipts and #receipts > MAX_RECEIPTS then
		local trimmed = table.move(receipts, #receipts - MAX_RECEIPTS + 1, #receipts, 1, {})
		serialized.Receipts = trimmed
	end

	for attempt = 1, 3 do
		local success, result = pcall(function()
			store:SetAsync(key(userId), serialized, { userId })
		end)
		if success then
			return true
		end
		warn(`[Tycoon] {userId} 저장 실패 ({attempt}/3):`, result)
		task.wait(attempt)
	end
	return false
end

return DataService
