local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
return function(_, players, id)
	local ids = if id == "all" then CmdrKeys.MicIds() else { id }
	return CmdrUtil.Each(players, function(_, data)
		return `+{CmdrUtil.AddAll(data.Inventory.Mics, ids)} mic(s)`
	end)
end
