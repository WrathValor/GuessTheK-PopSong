local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		for _, name in { "Stars", "Claimed", "Duels", "Wins", "DuelsToday", "QuestsToday", "SoloToday", "SP", "PeakSP" } do
			data.Season[name].Set(0)
		end
		return "season track + SP reset"
	end)
end
