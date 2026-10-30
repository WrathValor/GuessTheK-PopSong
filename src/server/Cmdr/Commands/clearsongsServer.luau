local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.Inventory.Songs.Clear()
		data.Inventory.Packs.Clear()
		data.Inventory.DuelPack.Set("")
		return "songs cleared"
	end)
end
