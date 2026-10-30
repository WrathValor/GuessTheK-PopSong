local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, title)
	return CmdrUtil.Each(players, function(_, data)
		CmdrUtil.AddAll(data.Inventory.Titles, { title })
		data.Inventory.Title.Set(title)
		return `title "{title}"`
	end)
end
