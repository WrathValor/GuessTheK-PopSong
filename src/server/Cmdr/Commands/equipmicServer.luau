local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, id)
	if id == "all" then
		return "Pick one mic"
	end
	return CmdrUtil.Each(players, function(_, data)
		if not data.Inventory.Mics.Has(id) then
			data.Inventory.Mics.Add(id)
		end
		data.Inventory.EquippedMic.Set(id)
		return `wearing {id}`
	end)
end
