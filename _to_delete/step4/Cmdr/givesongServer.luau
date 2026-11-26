local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
local ShopService = require(ServerScriptService.Engine.ShopService)
return function(_, players, key)
	local songs = if key == "all" then Songs.GetAllSongs() else { CmdrKeys.Song(key) }
	local ids = {}
	for _, song in songs do
		table.insert(ids, song.Id)
	end
	return CmdrUtil.Each(players, function(_, data)
		local added = CmdrUtil.AddAll(data.Inventory.Songs, ids)
		ShopService.CheckPacksComplete(data, songs)
		return `+{added} song(s)`
	end)
end
