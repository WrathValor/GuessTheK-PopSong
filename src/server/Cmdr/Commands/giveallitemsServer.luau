local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		CmdrUtil.AddAll(data.Inventory.Sets, CmdrKeys.SetIds())
		local s = CmdrUtil.AddAll(data.Inventory.Stages, CmdrKeys.StageIds())
		local m = CmdrUtil.AddAll(data.Inventory.Mics, CmdrKeys.MicIds())
		return `+{s} stages, +{m} mics, all sets`
	end)
end
