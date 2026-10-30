local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.Rewards.LastDailyClaim.Set(math.max(0, os.time() - 86400))
		return `daily ready (day {data.Rewards.DailyStreak.Get() + 1})`
	end)
end
