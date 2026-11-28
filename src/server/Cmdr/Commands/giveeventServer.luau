local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
return function(_, players, currency, packs)
	return CmdrUtil.Each(players, function(_, data)
		local c = math.max(0, data.Events.Currency.Get() + currency)
		local p = math.max(0, data.Events.Packs.Get() + (packs or 0))
		data.Events.Currency.Set(c)
		data.Events.Packs.Set(p)
		return `{c} event currency, {p} event packs`
	end)
end
