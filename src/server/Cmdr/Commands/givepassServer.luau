local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, id)
	return CmdrUtil.Each(players, function(_, data)
		CmdrUtil.AddAll(data.GamePasses, { id })
		return id
	end)
end
