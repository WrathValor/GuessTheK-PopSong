local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
return function(_, players, scope: string?)
	scope = string.lower(scope or "daily")
	if scope ~= "daily" and scope ~= "weekly" and scope ~= "all" then
		return "scope must be daily, weekly or all"
	end
	return CmdrUtil.Each(players, function(_, data)
		local now = os.time()
		if scope ~= "weekly" then
			data.Rewards.QuestDay.Set(RewardsCatalog.Day(now))
			for _, stat in RewardsCatalog.QUEST_STATS do
				data.Rewards.Quest[stat].Set(0)
			end
			data.Rewards.QuestClaimed.Clear()
			data.Rewards.QuestSwapFrom.Set("")
			data.Rewards.QuestSwapTo.Set("")
		end
		if scope ~= "daily" then
			data.Rewards.QuestWeek.Set(RewardsCatalog.Week(now))
			for _, stat in RewardsCatalog.QUEST_STATS do
				data.Rewards.WeekQuest[stat].Set(0)
			end
			data.Rewards.WeekClaimed.Clear()
		end
		return `{scope} quests reset`
	end)
end
