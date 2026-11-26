local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		local before = `step: "{data.Settings.Onboard.Get()}", tutorial: {data.Settings.TutorialDone.Get()}, rewards: {data.Rewards.Claimed.Has("Onboard")}, gift: {data.Rewards.Claimed.Has("OnboardGift")}`
		data.Settings.Onboard.Set("")
		data.Settings.TutorialDone.Set(false)
		for _, key in { "Onboard", "OnboardGift" } do
			if data.Rewards.Claimed.Has(key) then
				data.Rewards.Claimed.Remove(key)
			end
		end
		return `{before} → reset`
	end)
end
