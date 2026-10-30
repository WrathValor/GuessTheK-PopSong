local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(_, data)
		local coins = math.max(0, data.Currencies.Won.Get() + amount)
		data.Currencies.Won.Set(coins)
		return `{coins} coins`
	end)
end
