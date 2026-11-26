local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(_, data)
		local upgrades = math.max(0, data.Inventory.Upgrades.Get() + amount)
		data.Inventory.Upgrades.Set(upgrades)
		return `{upgrades} card upgrades`
	end)
end
