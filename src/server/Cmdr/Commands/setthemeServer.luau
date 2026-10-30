local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, theme)
	return CmdrUtil.Each(players, function(_, data)
		data.Settings.SoloTheme.Set(theme)
		return `solo theme {theme}`
	end)
end
