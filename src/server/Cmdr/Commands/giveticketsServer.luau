local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(_, data)
		local tickets = math.max(0, data.Inventory.Tickets.Get() + amount)
		data.Inventory.Tickets.Set(tickets)
		return `{tickets} roll tickets`
	end)
end
