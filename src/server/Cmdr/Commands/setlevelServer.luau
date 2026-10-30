local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Levels = require(ReplicatedStorage.Modules.Levels)
return function(_, players, level)
	level = math.clamp(level, 1, Levels.MAX_LEVEL)
	local xp = 0
	for l = 1, level - 1 do
		xp += Levels.XPToNext(l)
	end
	return CmdrUtil.Each(players, function(_, data)
		data.Player.XP.Set(xp)
		return `level {level} ({xp} XP)`
	end)
end
