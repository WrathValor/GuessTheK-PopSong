local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local DuelService = require(ServerScriptService.Engine.DuelService)
return function(_, players)
	for _, player in players do
		DuelService.Request(player, "Leave")
	end
	return `{#players} player(s) taken off`
end
