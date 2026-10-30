local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, id)
	if id == "all" then
		return "Pick one stage"
	end
	return CmdrUtil.Each(players, function(_, data)
		if not data.Inventory.Stages.Has(id) then
			data.Inventory.Stages.Add(id)
		end
		data.Inventory.EquippedStage.Set(id)
		return `wearing {id}`
	end)
end
