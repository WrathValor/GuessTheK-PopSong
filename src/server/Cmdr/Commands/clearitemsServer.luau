local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players)
	return CmdrUtil.Each(players, function(_, data)
		data.Inventory.Sets.Clear()
		data.Inventory.Stages.Clear()
		data.Inventory.Mics.Clear()
		data.Inventory.EquippedSet.Set("Default")
		data.Inventory.EquippedStage.Set("Default")
		data.Inventory.EquippedMic.Set("Default")
		return "items cleared"
	end)
end
