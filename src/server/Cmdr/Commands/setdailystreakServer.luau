local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, days)
	days = math.clamp(days, 0, 7)
	return CmdrUtil.Each(players, function(_, data)
		data.Rewards.DailyStreak.Set(days)
		return `day streak {days}`
	end)
end
