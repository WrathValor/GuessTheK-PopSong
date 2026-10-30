--| CmdrKeys
-- Space-free keys for Cmdr arguments, so songs and packs can be typed without quotes:
-- "Dynamite - BTS" -> "BTSDynamite", "Group:LE SSERAFIM" -> "GroupLESSERAFIM". Used by the
-- Cmdr types (client + server, for autocomplete) and the commands (to turn a key back into
-- the real Id).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Themes = require(ReplicatedStorage.Modules.Library.Themes)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)

local CmdrKeys = {}

local function slug(s: string): string
	return (s:gsub("[^%w]", ""))
end
CmdrKeys.Slug = slug

-- song key -> song, pack key -> pack id
local songByKey, songKeys = {}, {}
for _, song in Songs.GetAllSongs() do
	local key = slug((song.Artist or "") .. song.Name)
	songByKey[key] = song
	table.insert(songKeys, key)
end
table.sort(songKeys)

local packByKey, packKeys = {}, {}
local function addPack(pack)
	local key = slug(pack.Id)
	packByKey[key] = pack.Id
	table.insert(packKeys, key)
end
for _, pack in Packs.Companies() do
	addPack(pack)
end
for _, pack in Packs.Groups() do
	addPack(pack)
end
table.sort(packKeys)

function CmdrKeys.SongKeys(): { string }
	return songKeys
end
function CmdrKeys.Song(key: string)
	return songByKey[key]
end
function CmdrKeys.PackKeys(): { string }
	return packKeys
end
function CmdrKeys.Pack(key: string): string?
	return packByKey[key]
end

local function ids(list): { string }
	local out = {}
	for _, item in list do
		table.insert(out, item.Id)
	end
	return out
end
function CmdrKeys.StageIds(): { string }
	return ids(ShopCatalog.Stages)
end
function CmdrKeys.MicIds(): { string }
	return ids(ShopCatalog.Mics)
end
function CmdrKeys.SetIds(): { string }
	return ids(ShopCatalog.Sets)
end
function CmdrKeys.PassIds(): { string }
	return ids(ShopCatalog.Passes)
end
function CmdrKeys.ThemeIds(): { string }
	return ids(Themes.List)
end

return CmdrKeys
