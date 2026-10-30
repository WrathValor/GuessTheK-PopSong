local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
return function(_, players, id)
	local sets = if id == "all" then ShopCatalog.Sets else { ShopCatalog.GetSet(id) }
	return CmdrUtil.Each(players, function(_, data)
		for _, set in sets do
			local stage, mic = ShopCatalog.SetPieces(set)
			CmdrUtil.AddAll(data.Inventory.Sets, { set.Id })
			CmdrUtil.AddAll(data.Inventory.Stages, { stage.Id })
			CmdrUtil.AddAll(data.Inventory.Mics, { mic.Id })
		end
		return `{#sets} set(s)`
	end)
end
