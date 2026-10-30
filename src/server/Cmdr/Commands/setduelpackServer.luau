local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
return function(_, players, key)
	local id = if key == "off" then "" elseif key == "My" then "My" else (CmdrKeys.Pack(key) or "")
	return CmdrUtil.Each(players, function(_, data)
		data.Inventory.DuelPack.Set(id)
		return if id == "" then "duel pack off" else `duel pack {id}`
	end)
end
