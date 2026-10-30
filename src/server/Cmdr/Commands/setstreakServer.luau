local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, streak)
	streak = math.max(0, streak)
	return CmdrUtil.Each(players, function(_, data)
		data.Player.Streak.Set(streak)
		data.Player.LostStreak.Set(0)
		if streak > data.Statistics.HighestStreak.Get() then
			data.Statistics.HighestStreak.Set(streak)
		end
		return `streak {streak}`
	end)
end
