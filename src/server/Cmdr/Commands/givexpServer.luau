local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Levels = require(ReplicatedStorage.Modules.Levels)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(_, data)
		local xp = math.max(0, data.Player.XP.Get() + amount)
		data.Player.XP.Set(xp)
		return `{xp} XP (level {(Levels.FromXP(xp))})`
	end)
end
