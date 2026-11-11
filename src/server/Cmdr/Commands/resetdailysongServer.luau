local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.DailySong.Guesses.Set({})
		data.DailySong.Solved.Set(false)
		data.DailySong.Done.Set(false)
		return "today's Daily Song is unplayed again"
	end)
end
