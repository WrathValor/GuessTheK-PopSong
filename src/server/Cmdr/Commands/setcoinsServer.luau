local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(_, data)
		data.Currencies.Won.Set(math.max(0, amount))
		return `{math.max(0, amount)} coins`
	end)
end
