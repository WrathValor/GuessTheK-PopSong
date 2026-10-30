local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, streak)
	return CmdrUtil.Each(players, function(_, data)
		data.Player.LostStreak.Set(math.max(0, streak))
		return `lost streak {math.max(0, streak)}`
	end)
end
