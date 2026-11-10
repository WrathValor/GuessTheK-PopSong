local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.Rewards.LevelClaimed.Clear()
		return "level rewards unclaimed"
	end)
end
