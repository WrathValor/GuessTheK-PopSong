local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		local before = `had Debut: {data.Rewards.Claimed.Has("Debut")}, started: {data.Rewards.StarterAt.Get()}, seen: {data.Settings.Hints.Has("Starter")}, tutorial: {data.Settings.TutorialDone.Get()}`
		if data.Rewards.Claimed.Has("Debut") then
			data.Rewards.Claimed.Remove("Debut")
		end
		data.Rewards.StarterAt.Set(0)
		if data.Settings.Hints.Has("Starter") then
			data.Settings.Hints.Remove("Starter")
		end
		return `{before} → reset`
	end)
end
