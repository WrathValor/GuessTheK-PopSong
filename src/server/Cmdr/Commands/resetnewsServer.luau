local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.Settings.NewsSeen.Set("")
		return "news unread"
	end)
end
