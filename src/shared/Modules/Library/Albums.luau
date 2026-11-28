--| Albums
-- K-POPPED! albums and their photocards, built from Songs.Albums (the Albums lists in the group
-- modules, src/server/Songs). Same API on the server and the client.
--
-- A card id is album:member:rarity ("bts-love-yourself:jungkook:luckydraw"). Each rarity of a
-- member is its own card: copies of one id level it (Normal, then Gold at GOLD_COPIES, Rainbow
-- at RAINBOW_COPIES) and copies of different rarities never combine. Cards are saved in
-- Inventory.Cards (card id → copies), so member keys and rarity keys never change once they're
-- live. An album id can change only through AlbumConstants.RENAMED_ALBUMS (Albums.Current).
--
-- Cards come in packs (AlbumConstants): a group pack rolls each card from that GROUP
-- (RollGroup: one of its albums, then a rarity, then a member); a gen pack or a free pack rolls
-- each from a random group of a generation (RollGen). The binder sorts what you pull into
-- album pages. FreePacks works out the free-pack clock (the same on both sides). Your bias (Inventory.Bias, "<Artist>|<member
-- key>", Engine/BiasService) makes that member's cards BIAS_PULL_WEIGHT times as likely in
-- their group's pulls and earn BIAS_EARN more.
-- Only albums with card art are pulled (Albums.Pullable / PullAlbums / PullArtists).
-- Collecting and duels are separate: an album's Songs list is optional and nothing needs it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local Songs = require(script.Parent.Songs)
local Upgrades = require(script.Parent.Upgrades)

local Albums = {}

-- Person: who's on the card (a group member's name, or the soloist). Version: a soloist era's
-- photocard number (Songs/init.luau "Versions"); nil for group members.
export type Member = { Key: string, Name: string, Art: string, Person: string, Version: number? }
export type Album = {
	Id: string,
	Name: string,
	Year: number?,
	Colour: string?,
	Artist: string,
	Company: string,
	Generation: string?, -- the group's ("2nd" … "5th")
	GroupType: string?, -- "Boy" | "Girl" | "Co-ed" | "Solo"
	PackArt: string?, -- the group's photo for its group pack sleeve ("" or nil = none)
	Event: string?, -- an event set's album (Constants/LiveEvents id): see "Event sets" below
	Cover: string?, -- this album's own cover: its binder page header ("" or nil = the group's PackArt)
	Members: { Member },
	Songs: { any }, -- library songs (Songs.GetById), in the order the album lists them
}
export type Rarity = { Key: string, Name: string, Odds: number, Earn: number, Sell: number?, Live: boolean, Announce: boolean?, Unsellable: boolean?, Serial: boolean? }

Albums.LEVELS = { "Normal", "Gold", "Rainbow" }
Albums.LEVEL_RANK = { Normal = 1, Gold = 2, Rainbow = 3 }

-- [[ Rarities ]]

local rarityByKey: { [string]: Rarity } = {}
local rarityRank: { [string]: number } = {}
for i, rarity in AlbumConstants.RARITIES do
	rarityByKey[rarity.Key] = rarity
	rarityRank[rarity.Key] = i
end


Albums.RARITIES = AlbumConstants.RARITIES -- worst to best, One of One included

function Albums.Rarity(key: string): Rarity?
	return rarityByKey[key]
end

-- 1 (Standard) … 7 (One of One); 0 for an unknown key
local LUCKY_FROM = "luckydraw" -- Luck (Upgrades) lifts this rarity and every one above it

function Albums.RarityRank(key: string): number
	return rarityRank[key] or 0
end

-- The odds a pull actually uses: { { Rarity, Odds } }, worst to best. A rarity that isn't live
-- or is closed for this album (`closed[key]`, a claimed One of One)
-- gives its share to FALLBACK_RARITY.
-- `minKey` (premium packs) leaves out every rarity below it and scales the rest up to 1.
-- `luck` (Upgrades.Luck, 1 = none) multiplies Lucky Draw and up; Standard gives up the difference.
-- It can also be Albums.Luck's { Upgrade, Potion }: a running Luck potion adds its +50% to the
-- upgrade's (1.25 + 0.5 = ×1.75 at most), for every lucky rarity but One of One (only the upgrade).
function Albums.Luck(upgrade: number, potion: boolean): any
	if not potion then
		return upgrade
	end
	return { Upgrade = upgrade, Potion = AlbumConstants.LUCK_POTION }
end

function Albums.RarityOdds(closed: { [string]: boolean }?, minKey: string?, luck: any?): { { Rarity: Rarity, Odds: number } }
	local base: { [string]: number } = {}
	local extra = 0
	local upgrade = if type(luck) == "table" then luck.Upgrade or 1 elseif type(luck) == "number" then luck else 1
	local potion = if type(luck) == "table" then luck.Potion or 0 else 0
	for _, rarity in AlbumConstants.RARITIES do
		local odds = rarity.Odds
		local mult = upgrade + (if rarity.Key == "oneofone" then 0 else potion)
		if mult ~= 1 and (rarityRank[rarity.Key] or 0) >= (rarityRank[LUCKY_FROM] or 99) then
			extra += odds * (mult - 1)
			odds *= mult
		end
		base[rarity.Key] = odds
	end
	local first = AlbumConstants.RARITIES[1].Key
	base[first] = math.max(0, base[first] - extra)
	local moved = 0
	for _, rarity in AlbumConstants.RARITIES do
		if not rarity.Live or (closed and closed[rarity.Key]) then
			moved += base[rarity.Key]
		end
	end
	local out = {}
	for _, rarity in AlbumConstants.RARITIES do
		if rarity.Live and not (closed and closed[rarity.Key]) then
			local odds = base[rarity.Key] + (if rarity.Key == AlbumConstants.FALLBACK_RARITY then moved else 0)
			table.insert(out, { Rarity = rarity, Odds = odds })
		end
	end
	local min = if minKey then rarityRank[minKey] or 0 else 0
	if min > 1 then
		local kept, total = {}, 0
		for _, entry in out do
			if rarityRank[entry.Rarity.Key] >= min then
				table.insert(kept, entry)
				total += entry.Odds
			end
		end
		if total > 0 then
			for _, entry in kept do
				entry.Odds /= total
			end
			return kept
		end
	end
	return out
end

-- [[ Library ]]

local all: { Album } = {}
local byId: { [string]: Album } = {}
local byArtist: { [string]: { Album } } = {}
local eventAlbums: { [string]: { Album } } = {}

-- accented letters idol names use, kept readable in keys ("ROSÉ" → "rose")
local ACCENTS = { ["É"] = "e", ["é"] = "e", ["È"] = "e", ["è"] = "e", ["Á"] = "a", ["á"] = "a", ["Í"] = "i", ["í"] = "i", ["Ó"] = "o", ["ó"] = "o", ["Ú"] = "u", ["ú"] = "u", ["Ü"] = "u", ["ü"] = "u", ["Ö"] = "o", ["ö"] = "o", ["Ä"] = "a", ["ä"] = "a" }

-- "Jung Kook" → "jungkook", "ROSÉ" → "rose"; the card id's member part
function Albums.MemberKey(name: string): string
	for from, to in ACCENTS do
		name = name:gsub(from, to)
	end
	return (string.lower(name):gsub("[^%w]", ""))
end

for _, raw in Songs.Albums or {} do
	if type(raw.Id) ~= "string" or raw.Id == "" or raw.Id:find(":") or byId[raw.Id] then
		warn(`[Albums] bad or duplicate album id {raw.Id} ({raw.Artist})`)
		continue
	end
	local album: Album = {
		Id = raw.Id,
		Name = raw.Name or raw.Id,
		Year = raw.Year,
		Colour = raw.Colour,
		Artist = raw.Artist,
		Company = raw.Company,
		Generation = raw.Generation,
		GroupType = raw.GroupType,
		PackArt = raw.PackArt,
		Cover = raw.Cover,
		Event = if type(raw.Event) == "string" and raw.Event ~= "" then raw.Event else nil,
		Members = {},
		Songs = {},
	}
	local seen = {}
	local versions = if type(raw.Versions) == "number" then math.max(1, math.floor(raw.Versions)) else 1
	for _, name in raw.Members or {} do
		-- a soloist's era has `Versions` photocards: "IU" (card key "iu", so the first card's id
		-- never changes), then "IU 2", "IU 3" … ("iu2", "iu3"). A version past the first only
		-- exists once it has art, so an era never shows empty slots or rolls an art-less card.
		local made = {}
		for v = 1, versions do
			local label = if v == 1 then name else `{name} {v}`
			-- (a member whose name was fixed after going live keeps the old key: Keys[label])
			local key = if type(raw.Keys) == "table" and type(raw.Keys[label]) == "string" then raw.Keys[label] else Albums.MemberKey(label)
			if key == "" or seen[key] then
				warn(`[Albums] {album.Id}: bad or duplicate member {label}`)
				continue
			end
			local art = type(raw.Art) == "table" and raw.Art[label] or ""
			if v > 1 and art == "" then
				continue
			end
			seen[key] = true
			local member = { Key = key, Name = name, Art = art, Person = name, Version = if versions > 1 then v else nil }
			table.insert(album.Members, member)
			table.insert(made, member)
		end
		if #made > 1 then
			for _, member in made do
				member.Name = `{name} · Ver. {member.Version}` -- (only once there's more than one to tell apart)
			end
		end
	end
	for _, songName in raw.Songs or {} do
		local song = Songs.GetById(`{songName} - {album.Artist}`)
		if song then
			table.insert(album.Songs, song) -- (songs not in the game are just left out)
		end
	end
	if #album.Members == 0 then
		warn(`[Albums] {album.Id} has no members`)
		continue
	end
	table.insert(all, album)
	byId[album.Id] = album
	if album.Event then
		-- (an event set's album isn't its group's: see "Event sets")
		eventAlbums[album.Event] = eventAlbums[album.Event] or {}
		table.insert(eventAlbums[album.Event], album)
	else
		byArtist[album.Artist] = byArtist[album.Artist] or {}
		table.insert(byArtist[album.Artist], album)
	end
end

local function byYear(a: Album, b: Album)
	if (a.Year or 0) ~= (b.Year or 0) then
		return (a.Year or 0) < (b.Year or 0)
	end
	return a.Id < b.Id
end
table.sort(all, function(a, b)
	if a.Artist ~= b.Artist then
		return a.Artist:lower() < b.Artist:lower()
	end
	return byYear(a, b)
end)
for _, list in byArtist do
	table.sort(list, byYear)
end
for _, list in eventAlbums do
	table.sort(list, function(a, b)
		return a.Artist:lower() < b.Artist:lower()
	end)
end

function Albums.All(): { Album }
	return all
end

function Albums.Get(id: string): Album?
	return byId[id]
end

-- a group's albums, oldest first
function Albums.ForArtist(artist: string): { Album }
	return byArtist[artist] or {}
end

-- groups that have albums, A–Z
function Albums.Artists(): { string }
	local out = {}
	for artist in byArtist do
		table.insert(out, artist)
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

-- [[ Pullable ]]
-- Only cards with art can come out of a pack: an album with no member art yet isn't rolled, and a
-- group with no such album has no group pack, isn't in a gen / free pack, today's rotation, the
-- favourites or the bias picker. (Its albums still exist, so cards already owned keep working.)

-- has at least one member's card art
function Albums.HasArt(album: Album): boolean
	for _, member in album.Members do
		if member.Art ~= nil and member.Art ~= "" then
			return true
		end
	end
	return false
end

-- a group's albums that can be pulled (HasArt), oldest first. An event set's key
-- (Albums.EventKey) gives that set's albums with art (the binder shows a set like a group).
function Albums.PullAlbums(artist: string): { Album }
	local out = {}
	local event = Albums.EventOf(artist)
	for _, album in (if event then eventAlbums[event] else byArtist[artist]) or {} do
		if Albums.HasArt(album) then
			table.insert(out, album)
		end
	end
	return out
end

-- [[ Event sets ]]
-- An album with Event = a Constants/LiveEvents id (the Christmas Stage '26 acts: a group module's
-- Albums entry, Songs/init.luau) belongs to that event's set, not its group: it's never in
-- Artists / ForArtist / PullArtists / Pullable, so no normal pack, the bias picker, group sets or
-- the binder's totals see it. Only the event's own pack rolls it (Engine/AlbumService, Kind =
-- "Event"), and the binder shows the set as one page under Events, keyed "event:<id>".

function Albums.EventKey(eventId: string): string
	return "event:" .. eventId
end

-- "event:winter26" → "winter26"; nil for a group's name
function Albums.EventOf(key: string?): string?
	return if type(key) == "string" then string.match(key, "^event:(.+)$") else nil
end

-- the albums of an event's set that have art, A–Z by act
function Albums.EventAlbums(eventId: string): { Album }
	return Albums.PullAlbums(Albums.EventKey(eventId))
end

-- the event ids that have a set (with art), A–Z
function Albums.EventSets(): { string }
	local out = {}
	for id in eventAlbums do
		if #Albums.EventAlbums(id) > 0 then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- an event pack's set card: an act's album, weighted by its members so every person is as
-- likely, then Albums.Roll (rarity from `minKey` up, Luck, your bias). Returns (album,
-- member key, rarity key), or nil when the set has no art yet.
function Albums.RollEvent(eventId: string, bias: string?, rng: Random, minKey: string?, luck: any?): (Album?, string?, string?)
	-- (only people with card art: a set can go live while its photos are still coming in)
	local albums = Albums.EventAlbums(eventId)
	local withArt: { [Album]: number } = {}
	local total = 0
	for _, album in albums do
		local n = 0
		for _, member in album.Members do
			if member.Art ~= "" then
				n += 1
			end
		end
		withArt[album] = n
		total += n
	end
	if total == 0 then
		return nil, nil, nil
	end
	local pick = rng:NextNumber() * total
	local chosen = albums[#albums]
	for _, album in albums do
		pick -= withArt[album]
		if withArt[album] > 0 and pick < 0 then
			chosen = album
			break
		end
	end
	local function hasArt(cardId: string): boolean
		local _, key = Albums.Parse(cardId)
		local member = key and Albums.Member(chosen, key)
		return member ~= nil and member.Art ~= ""
	end
	local member, rarity = Albums.Roll(chosen, bias, rng, nil, hasArt, minKey, luck)
	return chosen, member, rarity
end

-- whether any of a group's cards can be pulled
function Albums.Pullable(artist: string): boolean
	for _, album in byArtist[artist] or {} do
		if Albums.HasArt(album) then
			return true
		end
	end
	return false
end

-- groups that can be pulled, A–Z
function Albums.PullArtists(): { string }
	local out = {}
	for _, artist in Albums.Artists() do
		if Albums.Pullable(artist) then
			table.insert(out, artist)
		end
	end
	return out
end

function Albums.Member(album: Album, key: string): Member?
	for _, member in album.Members do
		if member.Key == key then
			return member
		end
	end
	return nil
end

-- [[ Card ids ]]

function Albums.CardId(albumId: string, memberKey: string, rarityKey: string): string
	return `{albumId}:{memberKey}:{rarityKey}`
end

-- "a:b:c" → "a", "b", "c" (nil if it isn't three parts)
function Albums.Parse(cardId: string): (string?, string?, string?)
	local a, m, r = string.match(cardId, "^([^:]+):([^:]+):([^:]+)$")
	return a, m, r
end

-- the card id under its album's current id (a saved card from before a rename, AlbumConstants.RENAMED_ALBUMS)
function Albums.Current(cardId: string): string
	local a, m, r = Albums.Parse(cardId)
	local renamed = a and AlbumConstants.RENAMED_ALBUMS[a]
	return if renamed and m and r then Albums.CardId(renamed, m, r) else cardId
end

-- the key a card's serial / One of One counter is saved under (Engine/SerialService): its first
-- album id, so renaming an album doesn't restart the numbers
local FIRST_ID: { [string]: string } = {}
for old, new in AlbumConstants.RENAMED_ALBUMS do
	FIRST_ID[new] = old
end
function Albums.StoreKey(cardId: string): string
	local a, m, r = Albums.Parse(cardId)
	local first = a and FIRST_ID[a]
	return if first and m and r then Albums.CardId(first, m, r) else cardId
end

export type Card = { Id: string, Album: Album, Member: Member, Rarity: Rarity }

-- a numbered copy's key in AlbumConstants.HISTORY_STORE: "<store key>#<serial>", kept under
-- the DataStore's 50 characters (a long one keeps its start and a short hash of the rest)
function Albums.HistoryKey(cardId: string, serial: number): string
	local key = `{Albums.StoreKey(cardId)}#{serial}`
	if #key <= 50 then
		return key
	end
	local h = 5381
	for i = 1, #key do
		h = (h * 33 + string.byte(key, i)) % 4294967296
	end
	local tail = `~{string.format("%x", h)}#{serial}`
	return string.sub(key, 1, 50 - #tail) .. tail
end

-- everything a card id points at, or nil if any part isn't in the game (any more)
function Albums.Card(cardId: string): Card?
	local a, m, r = Albums.Parse(cardId)
	local album = a and byId[a]
	local member = album and Albums.Member(album, m :: string)
	local rarity = r and rarityByKey[r]
	if not (album and member and rarity) then
		return nil
	end
	return { Id = cardId, Album = album, Member = member, Rarity = rarity }
end

-- [[ Levels ]]

function Albums.Level(copies: number): string?
	if copies >= AlbumConstants.RAINBOW_COPIES then
		return "Rainbow"
	elseif copies >= AlbumConstants.GOLD_COPIES then
		return "Gold"
	elseif copies >= 1 then
		return "Normal"
	end
	return nil
end

-- [[ Bias ]]

function Albums.BiasValue(artist: string, memberKey: string): string
	return `{artist}|{memberKey}`
end

-- "<Artist>|<member key>" → artist, key (nil, nil for no bias)
function Albums.BiasParts(bias: string?): (string?, string?)
	if type(bias) ~= "string" then
		return nil, nil
	end
	local artist, key = string.match(bias, "^(.+)|([^|]+)$")
	return artist, key
end

function Albums.IsBias(album: Album, memberKey: string, bias: string?): boolean
	local artist, key = Albums.BiasParts(bias)
	-- (a soloist's every card is your bias: the versions are all the same person)
	return artist == album.Artist and (key == memberKey or album.GroupType == "Solo")
end

-- [[ Pulls ]]

local function memberWeights(album: Album, bias: string?): ({ number }, number)
	local weights, total = {}, 0
	for i, member in album.Members do
		local w = if Albums.IsBias(album, member.Key, bias) then AlbumConstants.BIAS_PULL_WEIGHT else 1
		weights[i] = w
		total += w
	end
	return weights, total
end

-- The odds for the album page, as they apply to this player: { [member key] = { [rarity key] =
-- chance } }, adding up to 1 over the whole album. `closed` as in RarityOdds.
function Albums.Odds(album: Album, bias: string?, closed: { [string]: boolean }?, luck: any?): { [string]: { [string]: number } }
	local weights, total = memberWeights(album, bias)
	local rarities = Albums.RarityOdds(closed, nil, luck)
	local out = {}
	for i, member in album.Members do
		local row = {}
		for _, entry in rarities do
			row[entry.Rarity.Key] = entry.Odds * weights[i] / total
		end
		out[member.Key] = row
	end
	return out
end

-- One pull: (member key, rarity key). The rarity is rolled first, then the member (bias
-- weighted). `fresh(cardId)` (pity) limits the member to cards it says are new, when any are.
function Albums.Roll(album: Album, bias: string?, rng: Random, closed: { [string]: boolean }?, fresh: ((string) -> boolean)?, minKey: string?, luck: any?): (string, string)
	local rarities = Albums.RarityOdds(closed, minKey, luck)
	local roll = rng:NextNumber()
	local rarity = rarities[#rarities].Rarity
	for _, entry in rarities do
		roll -= entry.Odds
		if roll < 0 then
			rarity = entry.Rarity
			break
		end
	end
	local weights, total = memberWeights(album, bias)
	local candidates = album.Members
	if fresh then
		local list, w, t = {}, {}, 0
		for i, member in album.Members do
			if fresh(Albums.CardId(album.Id, member.Key, rarity.Key)) then
				table.insert(list, member)
				table.insert(w, weights[i])
				t += weights[i]
			end
		end
		if #list > 0 then
			candidates, weights, total = list, w, t
		end
	end
	local pick = rng:NextNumber() * total
	for i, member in candidates do
		pick -= weights[i]
		if pick < 0 then
			return member.Key, rarity.Key
		end
	end
	return candidates[#candidates].Key, rarity.Key
end

-- [[ Group pulls ]]
-- Every album of the group is equally likely, then the album's own odds (Albums.Odds).

-- The odds for a group's pull page: { [album id] = { [member key] = { [rarity key] = chance } } },
-- adding up to 1 over the whole group.
function Albums.GroupOdds(artist: string, bias: string?, closed: { [string]: boolean }?, luck: any?): { [string]: { [string]: { [string]: number } } }
	local albums = Albums.PullAlbums(artist)
	local out = {}
	for _, album in albums do
		local odds = Albums.Odds(album, bias, closed, luck)
		for _, row in odds do
			for key, p in row do
				row[key] = p / #albums
			end
		end
		out[album.Id] = odds
	end
	return out
end

-- One pull from a group: (album, member key, rarity key), or nil if the group has no albums
-- with art (PullAlbums).
function Albums.RollGroup(artist: string, bias: string?, rng: Random, closed: { [string]: boolean }?, fresh: ((string) -> boolean)?, minKey: string?, luck: any?): (Album?, string?, string?)
	local albums = Albums.PullAlbums(artist)
	if #albums == 0 then
		return nil, nil, nil
	end
	local album = albums[rng:NextInteger(1, #albums)]
	local member, rarity = Albums.Roll(album, bias, rng, closed, fresh, minKey, luck)
	return album, member, rarity
end

-- A pack's cards are shown worst to best, so its last card is the best of `size`: the chance
-- the last card is each rarity, { [rarity key] = chance } (the per-card odds for size 1).
-- Premium packs roll size - 1 cards from `cardMin` up and one from `lastMin` up.
function Albums.LastOdds(size: number, closed: { [string]: boolean }?, cardMin: string?, lastMin: string?, luck: any?): { [string]: number }
	local function cumulative(minKey: string?): { [string]: number }
		local out, total = {}, 0
		for _, entry in Albums.RarityOdds(closed, minKey, luck) do
			total += entry.Odds
			out[entry.Rarity.Key] = math.min(1, total)
		end
		return out
	end
	local cards, last = cumulative(cardMin), cumulative(lastMin or cardMin)
	local out = {}
	local belowCards, belowLast = 0, 0
	for _, entry in Albums.RarityOdds(closed, nil, luck) do
		local key = entry.Rarity.Key
		local c = cards[key] or belowCards
		local l = last[key] or belowLast
		out[key] = math.max(0, c ^ (size - 1) * l - belowCards ^ (size - 1) * belowLast)
		belowCards, belowLast = c, l
	end
	return out
end

-- [[ Generations, gen packs and free packs ]]

-- a group's generation ("2nd" … "5th"; "" when unknown)
function Albums.Generation(artist: string): string
	local albums = byArtist[artist]
	return albums and albums[1] and albums[1].Generation or ""
end

-- a group's type ("Boy" | "Girl" | "Co-ed" | "Solo"; "" when unknown)
function Albums.GroupType(artist: string): string
	local albums = byArtist[artist]
	return albums and albums[1] and albums[1].GroupType or ""
end

-- pullable groups in a pool, A–Z: a generation ("2nd" … "5th"), a mix ("Girl", "Boy", "All")
-- or nil (every group)
function Albums.ArtistsIn(pool: string?): { string }
	local out = {}
	for _, artist in Albums.PullArtists() do
		local ok = pool == nil or pool == "All"
		if pool == "Girl" or pool == "Boy" then
			ok = Albums.GroupType(artist) == pool
		elseif not ok then
			ok = Albums.Generation(artist) == pool
		end
		if ok then
			table.insert(out, artist)
		end
	end
	return out
end
Albums.ArtistsInGen = Albums.ArtistsIn

-- One card from a random group of a pool (ArtistsIn; nil = any group): every group is equally
-- likely, then RollGroup with no bias (your bias only counts in its own group's packs).
function Albums.RollGen(gen: string?, rng: Random, closed: { [string]: boolean }?, fresh: ((string) -> boolean)?, minKey: string?, luck: any?): (Album?, string?, string?)
	local artists = Albums.ArtistsIn(gen)
	if #artists == 0 then
		return nil, nil, nil
	end
	return Albums.RollGroup(artists[rng:NextInteger(1, #artists)], nil, rng, closed, fresh, minKey, luck)
end

-- starred groups, from Inventory.FavGroups ("A|B")
function Albums.Favourites(value: string?): { string }
	local out = {}
	for name in string.gmatch(value or "", "[^|]+") do
		if Albums.Pullable(name) then
			table.insert(out, name)
		end
	end
	return out
end

function Albums.Premium(key: string?)
	for _, pack in AlbumConstants.PREMIUM_PACKS do
		if pack.Key == key then
			return pack
		end
	end
	return nil
end

-- Today's group packs: ROTATION_SIZE groups, shuffled from every group with a seed that only
-- changes every ROTATION_SECONDS, so the server and every client agree. Returns (groups, when
-- this rotation ends). These are Today's picks: every group is on sale, these are TODAY_DISCOUNT off.
function Albums.Rotation(now: number): ({ string }, number)
	local period = AlbumConstants.ROTATION_SECONDS
	local slot = now // period
	local pool = Albums.PullArtists()
	local rng = Random.new(slot * 7919 + 17)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(AlbumConstants.ROTATION_SIZE, #pool) do
		out[i] = pool[i]
	end
	return out, (slot + 1) * period
end

-- whether a group is one of Today's picks (TODAY_DISCOUNT off its packs)
function Albums.IsTodaysPick(artist: string, now: number): boolean
	return table.find((Albums.Rotation(now)), artist) ~= nil
end

-- one group pack's price now: GROUP_PACK_COST, or TODAY_DISCOUNT off for Today's picks
function Albums.GroupPackCost(artist: string, now: number): number
	local cost = AlbumConstants.GROUP_PACK_COST
	if Albums.IsTodaysPick(artist, now) then
		cost = math.floor(cost * (1 - AlbumConstants.TODAY_DISCOUNT) + 0.5)
	end
	return cost
end

-- (old: whether a group pack was on sale before every group was. Kept for anything that asks)
-- whether a group pack is on sale now: in the rotation, your bias's group or a starred one
function Albums.InRotation(artist: string, bias: string?, now: number, favourites: string?): boolean
	if not Albums.Pullable(artist) then
		return false
	end
	if Albums.BiasParts(bias) == artist or table.find(Albums.Favourites(favourites), artist) then
		return true
	end
	return table.find((Albums.Rotation(now)), artist) ~= nil
end

-- The free-pack clock: (free packs now, when the current refill started, seconds until the
-- next one or nil while full). One refills every FREE_PACK_SECONDS up to FREE_PACK_CAP (both
-- moved by the Refill and Stash upgrades: lv = Upgrades.Levels); the clock doesn't run while
-- the bank is full, so `at` comes back as `now` then.
function Albums.FreePacks(packs: number, at: number, now: number, lv: Upgrades.Levels?): (number, number, number?)
	local cap, period = Upgrades.StashCap(lv), Upgrades.RefillSeconds(lv)
	if packs >= cap then
		return packs, now, nil
	end
	local gained = math.max(0, (now - at) // period)
	packs = math.min(cap, packs + gained)
	if packs >= cap then
		return packs, now, nil
	end
	at += gained * period
	return packs, at, at + period - now
end

-- [[ Binder ]]

-- coins one owned card id earns an hour (0 for a card that's no longer in the game)
function Albums.EarnPerHour(cardId: string, copies: number, bias: string?): number
	local card = Albums.Card(cardId)
	local level = Albums.Level(copies)
	if not card or not level then
		return 0
	end
	local rate = card.Rarity.Earn * AlbumConstants.LEVEL_EARN[level]
	if Albums.IsBias(card.Album, card.Member.Key, bias) then
		rate *= AlbumConstants.BIAS_EARN
	end
	return rate
end

-- [[ Flexing (design boards "69 · Leaderboard · Top Collectors", "69b · Showcase") ]]

-- the collection points of everything owned (AlbumConstants.POINTS, ×1 / ×1.5 / ×2 by stars)
function Albums.CollectionPoints(cards: { [string]: number }): number
	local total = 0
	for id, copies in cards do
		local card = (copies or 0) > 0 and Albums.Card(id)
		if card then
			local stars = Albums.LEVEL_RANK[Albums.Level(copies) or "Normal"] or 1
			total += (AlbumConstants.POINTS[card.Rarity.Key] or 0) * (1 + 0.5 * (stars - 1))
		end
	end
	return math.floor(total)
end

-- the card a player flexes: the rarest of their pins (then the most copies), else the rarest
-- card they own. Returns the card id and its copies, or nil with nothing owned.
function Albums.FlexCard(cards: { [string]: number }, pins: string?): (string?, number?)
	local function best(ids: { string }): (string?, number?)
		local top, topScore, topCopies = nil, -1, 0
		for _, id in ids do
			local copies = cards[id] or 0
			local card = copies > 0 and Albums.Card(id)
			if card then
				local score = Albums.RarityRank(card.Rarity.Key) * 10 + math.min(copies, AlbumConstants.RAINBOW_COPIES)
				if score > topScore then
					top, topScore, topCopies = id, score, copies
				end
			end
		end
		return top, if top then topCopies else nil
	end
	local id, copies = best(Albums.Pins(pins))
	if id then
		return id, copies
	end
	local all = {}
	for cardId in cards do
		table.insert(all, cardId)
	end
	return best(all)
end

-- a flex card as one string, "<cardId>*<copies>*<serial>" (serial 0 = none), and back
function Albums.FlexValue(cardId: string?, copies: number?, serial: number?): string
	return if cardId then `{cardId}*{copies or 1}*{serial or 0}` else ""
end
function Albums.ParseFlex(value: any): (string?, number, number?)
	if type(value) ~= "string" then
		return nil, 0, nil
	end
	local id, copies, serial = string.match(value, "^(.-)%*(%d+)%*(%d+)$")
	if not id or not Albums.Card(id) then
		return nil, 0, nil
	end
	local n = tonumber(serial) or 0
	return id, tonumber(copies) or 1, if n > 0 then n else nil
end

-- [[ Pins ]]
-- Only pinned cards earn (Inventory.Pins: card ids, "|" between them, in slot order).

-- "a|b|c" -> { "a", "b", "c" } (no blanks or repeats, at most PIN_SLOTS_MAX)
function Albums.Pins(value: string?): { string }
	local out = {}
	for id in string.gmatch(value or "", "[^|]+") do
		if not table.find(out, id) and #out < AlbumConstants.PIN_SLOTS_MAX then
			table.insert(out, id)
		end
	end
	return out
end

function Albums.PinValue(list: { string }): string
	return table.concat(list, "|")
end

-- how many pin slots a player has unlocked: PIN_SLOTS + the Slots upgrade (lv = Upgrades.Levels)
function Albums.PinSlots(lv: Upgrades.Levels?): number
	return Upgrades.PinSlots(lv)
end

-- The groups your duels lean towards: your bias's group ("Bias") and the groups of your pinned
-- cards ("Pinned"), artist → kind. Their songs come up more often (DuelConstants.OWNED_WEIGHT).
function Albums.FavouredGroups(cards: { [string]: number }, bias: string?, pins: string?, lv: Upgrades.Levels?): { [string]: string }
	local out = {}
	for i, id in Albums.Pins(pins) do
		if i > Albums.PinSlots(lv) then
			break
		end
		local info = (cards[id] or 0) > 0 and Albums.Card(id)
		if info then
			out[info.Album.Artist] = "Pinned"
		end
	end
	local group = Albums.BiasParts(bias)
	if group then
		out[group] = "Bias"
	end
	return out
end

-- the pinned-card multiplier: ×2 with the 2× Coins pass (ShopCatalog.Passes "DoubleCoins"),
-- the same pass that doubles duel coins, × the Payout upgrade (lv = Upgrades.Levels). Potions
-- stay duel-only. passes = data.GamePasses.
Albums.PIN_PASS = "DoubleCoins"
function Albums.Boost(passes, lv: Upgrades.Levels?): number
	local pass = if passes and passes.Has(Albums.PIN_PASS) == true then 2 else 1
	return pass * Upgrades.Payout(lv)
end

-- the binder's coins an hour: the pinned cards you still own (Inventory.Cards, Inventory.Pins),
-- × boost (Albums.Boost; 1 when left out), over the slots unlocked (lv = Upgrades.Levels)
function Albums.Rate(cards: { [string]: number }, bias: string?, pins: string?, boost: number?, lv: Upgrades.Levels?): number
	local total = 0
	for i, id in Albums.Pins(pins) do
		if i > Albums.PinSlots(lv) then
			break
		end
		total += Albums.EarnPerHour(id, cards[id] or 0, bias)
	end
	return total * (boost or 1)
end

-- the one-time bonus for owning every member of an album (Albums.Complete)
function Albums.SetBonus(album: Album): number
	return #album.Members * AlbumConstants.SET_BONUS_PER_MEMBER
end

-- its Rewards.Claimed key (kept under Claimed's 40 characters)
function Albums.SetKey(album: Album): string
	return string.sub(AlbumConstants.SET_KEY .. album.Id, 1, 40)
end

-- Coins waiting in the binder (Engine/BinderService): `bank` centi-coins already banked plus
-- what `rate` (coins an hour) earned since `since`, at `share` of it (1 online, OFFLINE_EARN for
-- time spent offline). Never more than BINDER_CAP_SECONDS (+ the Storage upgrade, lv =
-- Upgrades.Levels) of full-rate earnings.
-- Returns (whole coins, exact amount) – the exact one is for a ticking counter.
function Albums.Waiting(bank: number, since: number, rate: number, now: number, share: number?, lv: Upgrades.Levels?): (number, number)
	local cap = Upgrades.CapSeconds(lv)
	local elapsed = math.clamp(now - since, 0, cap)
	local exact = math.min(bank / 100 + rate * (share or 1) * elapsed / 3600, rate * cap / 3600)
	exact = math.max(exact, 0)
	return math.floor(exact), exact
end

-- coins for selling one copy; nil = can't be sold (One of One)
function Albums.SellPrice(cardId: string): number?
	local card = Albums.Card(cardId)
	if not card or card.Rarity.Unsellable then
		return nil
	end
	return card.Rarity.Sell
end

-- [[ Serial numbers ]]
-- Numbered rarities (Rarity.Serial) give every copy a serial, counted per card id across the
-- whole game (Engine/SerialService). A player's serials for one card id are saved as one
-- string, lowest first ("3,17"): Inventory.Serials. A One of One is always serial 1.

-- does this card id's rarity carry serial numbers?
function Albums.Numbered(cardId: string): boolean
	local card = Albums.Card(cardId)
	return card ~= nil and card.Rarity.Serial == true
end

-- "3,17" → { 3, 17 }, lowest first (bad entries are skipped)
function Albums.Serials(value: string?): { number }
	local out = {}
	for _, part in string.split(value or "", ",") do
		local n = tonumber(part)
		if n and n >= 1 and n == math.floor(n) then
			table.insert(out, n)
		end
	end
	table.sort(out)
	return out
end

-- adds a serial, keeping the list lowest first
function Albums.AddSerial(value: string?, serial: number): string
	local list = Albums.Serials(value)
	table.insert(list, serial)
	table.sort(list)
	return table.concat(list, ",")
end

-- takes the highest serial off (selling a copy keeps your best number): (new value, removed)
function Albums.DropSerial(value: string?): (string, number?)
	local list = Albums.Serials(value)
	local removed = table.remove(list)
	return table.concat(list, ","), removed
end

-- how a serial reads on a card: "#12", or "1 OF 1" for a One of One (nil = not numbered,
-- or no number yet)
function Albums.SerialText(cardId: string, serial: number?): string?
	local card = Albums.Card(cardId)
	if not card or not card.Rarity.Serial then
		return nil
	end
	if card.Rarity.Key == "oneofone" then
		return "1 OF 1"
	end
	return if serial then `#{serial}` else nil
end

-- The card a binder slot shows for one member: the best rarity owned, then the best level.
-- Returns (card id, copies), or nil when no card of that member in the album is owned.
function Albums.Best(cards: { [string]: number }, album: Album, memberKey: string): (string?, number?)
	local bestId, bestCopies, bestRank = nil, nil, -1
	for _, rarity in AlbumConstants.RARITIES do
		local id = Albums.CardId(album.Id, memberKey, rarity.Key)
		local copies = cards[id] or 0
		if copies > 0 then
			local rank = Albums.RarityRank(rarity.Key) * 10 + (Albums.LEVEL_RANK[Albums.Level(copies) or "Normal"] or 0)
			if rank > bestRank then
				bestId, bestCopies, bestRank = id, copies, rank
			end
		end
	end
	return bestId, bestCopies
end

-- every member owned at any rarity
function Albums.Complete(cards: { [string]: number }, album: Album): boolean
	for _, member in album.Members do
		if not Albums.Best(cards, album, member.Key) then
			return false
		end
	end
	return true
end

-- ALL-KILL: every member owned at Gold or better (GOLD_COPIES of one card, any rarity)
function Albums.AllKill(cards: { [string]: number }, album: Album): boolean
	for _, member in album.Members do
		local ok = false
		for _, rarity in AlbumConstants.RARITIES do
			if (cards[Albums.CardId(album.Id, member.Key, rarity.Key)] or 0) >= AlbumConstants.GOLD_COPIES then
				ok = true
				break
			end
		end
		if not ok then
			return false
		end
	end
	return #album.Members > 0
end

-- [[ Profile showcase ]]

-- "a||c" -> { "a", "", "c", "", "" }: exactly SHOWCASE_SLOTS entries, "" = empty
function Albums.Showcase(value: string?): { string }
	local out = {}
	local parts = string.split(value or "", "|")
	for i = 1, AlbumConstants.SHOWCASE_SLOTS do
		out[i] = parts[i] or ""
	end
	return out
end

function Albums.ShowcaseValue(list: { string }): string
	local out = {}
	for i = 1, AlbumConstants.SHOWCASE_SLOTS do
		out[i] = list[i] or ""
	end
	return table.concat(out, "|")
end

-- [[ Duels ]]

-- { [song id] = level rank } for every song in an album you own a card from: the rank of your
-- best-levelled card in that album (1 Normal, 2 Gold, 3 Rainbow). DuelConstants.OWNED_WEIGHT
-- turns it into how much more often the song comes up.
function Albums.SongLevels(cards: { [string]: number }): { [string]: number }
	local bestByAlbum = {}
	for id, copies in cards do
		local a = Albums.Parse(id)
		local level = Albums.Level(copies)
		if a and level and byId[a] then
			bestByAlbum[a] = math.max(bestByAlbum[a] or 0, Albums.LEVEL_RANK[level])
		end
	end
	local out = {}
	for albumId, rank in bestByAlbum do
		for _, song in byId[albumId].Songs do
			out[song.Id] = math.max(out[song.Id] or 0, rank)
		end
	end
	return out
end

return Albums
