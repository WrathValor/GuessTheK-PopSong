local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
return function(_, players, key)
	local songs = if key == "all" then Songs.GetAllSongs() else { CmdrKeys.Song(key) }
	local ids = {}
	for _, song in songs do
		table.insert(ids, song.Id)
	end
	return CmdrUtil.Each(players, function(_, data)
		return `+{CmdrUtil.AddAll(data.Inventory.Index, ids)} discovered`
	end)
end
