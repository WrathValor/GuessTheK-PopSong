local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(_, data)
		local packs = math.max(0, data.Inventory.GenPacks.Get() + amount)
		data.Inventory.GenPacks.Set(packs)
		return `{packs} gen packs`
	end)
end
