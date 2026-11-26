local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
local ShopService = require(ServerScriptService.Engine.ShopService)
return function(_, players, key)
	local packIds = {}
	if key == "all" then
		for _, k in CmdrKeys.PackKeys() do
			table.insert(packIds, CmdrKeys.Pack(k))
		end
	else
		packIds = { CmdrKeys.Pack(key) }
	end
	local songs, ids = {}, {}
	for _, id in packIds do
		for _, song in Packs.Get(id).Songs do
			table.insert(songs, song)
			table.insert(ids, song.Id)
		end
	end
	return CmdrUtil.Each(players, function(_, data)
		local added = CmdrUtil.AddAll(data.Inventory.Songs, ids)
		ShopService.CheckPacksComplete(data, songs)
		return `+{added} song(s), {#packIds} pack(s)`
	end)
end
