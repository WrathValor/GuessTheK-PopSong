--| PurchaseSounds
-- Plays the "Success" sound whenever a Robux purchase goes through, wherever it was prompted
-- from (Shop coins + passes, Save Streak, the UGC tab / reveal / results). Coin buys, claims
-- and the tutorial gift play it from their own controllers when the server says OK.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Modules.Sounds)

local LOCAL_PLAYER = Players.LocalPlayer

local PurchaseSounds = {}

function PurchaseSounds.Start()
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, purchased)
		if purchased and userId == LOCAL_PLAYER.UserId then
			Sounds.Play("Success")
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if purchased and player == LOCAL_PLAYER then
			Sounds.Play("Success")
		end
	end)
	MarketplaceService.PromptPurchaseFinished:Connect(function(player, _assetId, purchased)
		if purchased and player == LOCAL_PLAYER then
			Sounds.Play("Success")
		end
	end)
end

return PurchaseSounds
