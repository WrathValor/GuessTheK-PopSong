local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
return function(_, players, kind, minutes)
	if kind ~= "Coins" and kind ~= "XP" then
		return "kind must be Coins or XP"
	end
	return CmdrUtil.Each(players, function(_, data)
		local clock = data.Boosts[kind]
		local left = if minutes <= 0 then 0 else math.min(clock.Get() + minutes * 60, ShopCatalog.BOOST_MAX_SECONDS)
		clock.Set(left)
		return `{kind} boost: {left // 60} min`
	end)
end
