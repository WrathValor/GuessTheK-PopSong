local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CmdrUtil = require(ServerScriptService.Cmdr.CmdrUtil)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local CmdrKeys = require(ReplicatedStorage.Modules.CmdrKeys)
return function(_, players, key, copies)
	local songs = if key == "all" then Songs.GetAllSongs() else { CmdrKeys.Song(key) }
	local n = math.clamp(copies, 0, 20)
	return CmdrUtil.Each(players, function(_, data)
		for _, song in songs do
			if n == 0 then
				if data.Inventory.Songs.Has(song.Id) then
					data.Inventory.Songs.Remove(song.Id)
				end
			elseif not data.Inventory.Songs.Has(song.Id) then
				data.Inventory.Songs.Add(song.Id)
			end
			data.Inventory.Copies[song.Id].Set(n)
		end
		return `{#songs} song(s) set to {n} cop{if n == 1 then "y" else "ies"}`
	end)
end
