local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local SeasonService = require(ServerScriptService.Engine.SeasonService)
return function(_, players, amount)
	return CmdrUtil.Each(players, function(player, data)
		local sp = math.max(0, data.Season.SP.Get() + amount)
		SeasonService.SetSP(player, sp)
		return `{sp} SP ({SeasonConstants.TierOf(sp).Label})`
	end)
end
