local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
return function(_, players)
	local group = RewardsCatalog.GROUP
	return CmdrUtil.Each(players, function(_, data)
		if data.Rewards.Claimed.Has(group.ClaimedKey) then
			data.Rewards.Claimed.Remove(group.ClaimedKey)
		end
		if data.Inventory.Titles.Has(group.Title) then
			data.Inventory.Titles.Remove(group.Title)
		end
		return "group reward ready"
	end)
end
