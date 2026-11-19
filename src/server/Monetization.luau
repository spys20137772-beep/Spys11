-- 게임패스(수입 2배) / 개발자 상품(돈 구매) 처리
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local Monetization = {}

local Tycoon
local saveNow: (Player) -> ()

function Monetization.CheckGamepass(player: Player)
	if Config.GAMEPASS_2X_CASH == 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.GAMEPASS_2X_CASH)
	end)
	if ok and owns then
		Tycoon.SetHas2x(player, true)
	end
end

local function findProduct(productId: number)
	for _, product in ipairs(Config.CASH_PRODUCTS) do
		if product.Id ~= 0 and product.Id == productId then
			return product
		end
	end
	return nil
end

function Monetization.Init(tycoonModule, saveFunction: (Player) -> ())
	Tycoon = tycoonModule
	saveNow = saveFunction

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if purchased and gamePassId == Config.GAMEPASS_2X_CASH and Config.GAMEPASS_2X_CASH ~= 0 then
			Tycoon.SetHas2x(player, true)
			Tycoon.Notify(player, "🎉 수입 2배 게임패스 적용!", "success")
		end
	end)

	MarketplaceService.ProcessReceipt = function(info)
		local player = Players:GetPlayerByUserId(info.PlayerId)
		local state = player and Tycoon.GetState(player)
		if not player or not state or not state.Loaded then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 이미 지급한 영수증이면 다시 지급하지 않음
		if table.find(state.Receipts, info.PurchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local product = findProduct(info.ProductId)
		if not product then
			warn("[Tycoon] Config.CASH_PRODUCTS에 없는 상품 ID:", info.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		Tycoon.AddCash(player, product.Cash, false)
		table.insert(state.Receipts, info.PurchaseId)
		Tycoon.Notify(player, `💸 {Format.Cash(product.Cash)} 지급 완료! 감사합니다!`, "success")
		saveNow(player)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return Monetization
