local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.Rewards.QuestDay.Set(RewardsCatalog.Day(os.time()))
		for _, stat in RewardsCatalog.QUEST_STATS do
			data.Rewards.Quest[stat].Set(0)
		end
		data.Rewards.QuestClaimed.Clear()
		return "quests reset"
	end)
end
