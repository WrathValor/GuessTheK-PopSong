local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local LikeGoalConstants = require(ReplicatedStorage.Constants.LikeGoalConstants)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		local n = 0
		for _, g in LikeGoalConstants.GOALS do
			local key = `LikeGoal:{g.Id}`
			if data.Rewards.Claimed.Has(key) then
				data.Rewards.Claimed.Remove(key)
				n += 1
			end
		end
		return `{n} like goal rewards forgotten (rejoin to be paid again)`
	end)
end
