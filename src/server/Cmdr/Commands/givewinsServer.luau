local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local SeasonService = require(ServerScriptService.Engine.SeasonService)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(player, data)
		local wins = math.max(0, data.Season.Wins.Get() + amount)
		SeasonService.SetWins(player, wins)
		return `{wins} season wins`
	end)
end
