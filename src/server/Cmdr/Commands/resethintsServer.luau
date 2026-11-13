local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.Settings.Hints.Clear()
		return "nudges + screen guides will show again (rejoin to reset this session's)"
	end)
end
