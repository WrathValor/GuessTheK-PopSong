local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, id)
	return CmdrUtil.Each(players, function(_, data)
		if data.GamePasses.Has(id) then
			data.GamePasses.Remove(id)
		end
		return `no {id}`
	end)
end
