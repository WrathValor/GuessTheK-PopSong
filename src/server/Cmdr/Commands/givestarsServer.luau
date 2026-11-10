local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(_, data)
		local stars = math.max(0, data.Season.Stars.Get() + amount)
		data.Season.Stars.Set(stars)
		return `{stars} Stars ({math.floor(stars / SeasonConstants.STARS_PER_MILESTONE)} milestones unlocked)`
	end)
end
