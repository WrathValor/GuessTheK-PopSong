--| Packs
-- Song packs, worked out from the song library. Players only ever own songs
-- (Inventory.Songs); a pack is just a way of grouping them, so packs overlap: a BTS song
-- counts towards the BTS pack and the HYBE pack, and is never paid for twice.
--   • "My"            – My Pack: every song the player has bought
--   • "Company:<name>" – every song from that company (only companies with MIN_COMPANY_SONGS+)
--   • "Group:<artist>" – every song by that group (only groups with MIN_GROUP_SONGS+)
-- Any pack the player owns at least one song of can be their duel pack (Inventory.DuelPack).
-- The shop sells packs in a rotation: up to PACKS_PER_ROTATION company packs and as many group
-- packs, changing every ROTATION_SECONDS (same on every server). Owned songs are always yours.

local Songs = require(script.Parent.Songs)

local Packs = {}

Packs.MY = "My"
Packs.MIN_GROUP_SONGS = 3 -- smaller groups don't get a pack of their own (yet)
-- smaller companies don't get a pack (yet); their groups can still have group packs. A song in
-- neither kind of pack is still played in rounds, it just can't be bought.
Packs.MIN_COMPANY_SONGS = 10
Packs.ROTATION_SECONDS = 4 * 60 * 60 -- the packs in the shop change every 4 hours
Packs.PACKS_PER_ROTATION = 5 -- per kind (companies, groups); fewer packs than this = all of them

-- completing a group pack gives the fandom's name as a title; groups not listed get "<Group> Stan"
Packs.FANDOMS = {
	BTS = "ARMY",
	BLACKPINK = "BLINK",
	TWICE = "ONCE",
	aespa = "MY",
	NewJeans = "Bunnies",
	["Red Velvet"] = "ReVeluv",
	["LE SSERAFIM"] = "FEARNOT",
	BIGBANG = "VIP",
	iKON = "iKONIC",
	["Super Junior"] = "E.L.F.",
	["Stray Kids"] = "STAY",
	SEVENTEEN = "CARAT",
	ITZY = "MIDZY",
	IVE = "DIVE",
	TXT = "MOA",
	ENHYPEN = "ENGENE",
	["(G)I-DLE"] = "Neverland",
	EXO = "EXO-L",
	NCT = "NCTzen",
	IU = "UAENA",
	["i-dle"] = "Neverland", -- the group module's name (CUBE/i-dle)
	["Girls' Generation"] = "SONE",
	["2NE1"] = "Blackjack",
	ATEEZ = "ATINY",
	BABYMONSTER = "MONSTIEZ",
	BEAST = "B2UTY",
	BTOB = "Melody",
	ILLIT = "GLLIT",
	["KISS OF LIFE"] = "KISSY",
	LOONA = "Orbit",
	MAMAMOO = "MooMoo",
	MOMOLAND = "Merry-Go-Round",
	["MONSTA X"] = "MONBEBE",
	NEXZ = "NEX2Y",
	NMIXX = "NSWER",
	SHINee = "Shawol",
	STAYC = "SWITH",
	TREASURE = "Teume",
	TVXQ = "Cassiopeia",
	["Wonder Girls"] = "Wonderful",
	YENA = "Smiley",
	ZEROBASEONE = "ZEROSE",
	CORTIS = "COER",
	Hearts2Hearts = "S2U",
	BESTie = "BESTiny",
	-- A20 Lite: no fandom name yet (shows "A20 Lite Stan")
}

export type Pack = {
	Id: string,
	Kind: "My" | "Company" | "Group",
	Name: string, -- shown on cards ("HYBE", "BTS", "My Pack")
	Title: string?, -- title for owning every song (none for My Pack)
	Songs: { any }, -- every song in it (My Pack: filled per player, see SongsFor)
}

local companies: { Pack } = {}
local groups: { Pack } = {}
local byId: { [string]: Pack } = {}

do
	local byCompany, byArtist = {}, {}
	for _, song in Songs.All do
		local company = song.Company or "Other"
		byCompany[company] = byCompany[company] or {}
		table.insert(byCompany[company], song)
		if song.Artist then
			byArtist[song.Artist] = byArtist[song.Artist] or {}
			table.insert(byArtist[song.Artist], song)
		end
	end
	local function byName(a, b)
		return a.Name < b.Name
	end
	for company, list in byCompany do
		if company == "Other" or #list < Packs.MIN_COMPANY_SONGS then
			continue -- small labels: group packs only
		end
		table.sort(list, byName)
		local pack = { Id = `Company:{company}`, Kind = "Company", Name = company, Title = `{company} Expert`, Songs = list }
		table.insert(companies, pack)
		byId[pack.Id] = pack
	end
	for artist, list in byArtist do
		if #list >= Packs.MIN_GROUP_SONGS then
			table.sort(list, byName)
			local pack = { Id = `Group:{artist}`, Kind = "Group", Name = artist, Title = Packs.FANDOMS[artist] or `{artist} Stan`, Songs = list }
			table.insert(groups, pack)
			byId[pack.Id] = pack
		end
	end
	table.sort(companies, byName)
	table.sort(groups, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
end

byId[Packs.MY] = { Id = Packs.MY, Kind = "My", Name = "My Pack", Songs = {} }

function Packs.Companies(): { Pack }
	return companies
end

function Packs.Groups(): { Pack }
	return groups
end

-- Accepts a pack id, or a bare company name (older saves stored those).
function Packs.Get(id: string): Pack?
	return byId[id] or byId[`Company:{id}`]
end

-- Packs (company + group) a song belongs to.
function Packs.ForSong(song): { Pack }
	local out = {}
	local company = byId[`Company:{song.Company or "Other"}`]
	if company then
		table.insert(out, company)
	end
	local group = song.Artist and byId[`Group:{song.Artist}`]
	if group then
		table.insert(out, group)
	end
	return out
end

-- The songs of `id` the player owns. `has(songId)` answers "does this player own it?".
-- My Pack is every owned song.
function Packs.SongsFor(id: string, has: (string) -> boolean): { any }
	local out = {}
	if id == Packs.MY then
		for _, song in Songs.All do
			if has(song.Id) then
				table.insert(out, song)
			end
		end
		return out
	end
	local pack = Packs.Get(id)
	for _, song in pack and pack.Songs or {} do
		if has(song.Id) then
			table.insert(out, song)
		end
	end
	return out
end

-- [[ Shop rotation ]]

-- Which rotation window `time` falls in, and when it ends.
function Packs.RotationWindow(time: number?): (number, number)
	local t = time or os.time()
	local window = math.floor(t / Packs.ROTATION_SECONDS)
	return window, (window + 1) * Packs.ROTATION_SECONDS
end

-- The company or group packs for sale right now (kind = "Company" | "Group"), sorted by name.
function Packs.Rotation(kind: string, time: number?): { Pack }
	local all = if kind == "Group" then groups else companies
	if #all <= Packs.PACKS_PER_ROTATION then
		return all
	end
	local window = Packs.RotationWindow(time)
	local pool = table.clone(all)
	local rng = Random.new(window * 7907 + (if kind == "Group" then 11 else 13))
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, Packs.PACKS_PER_ROTATION do
		out[i] = pool[i]
	end
	table.sort(out, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return out
end

function Packs.IsForSale(id: string, time: number?): boolean
	local pack = Packs.Get(id)
	if not pack or pack.Kind == "My" then
		return false
	end
	for _, p in Packs.Rotation(pack.Kind, time) do
		if p.Id == pack.Id then
			return true
		end
	end
	return false
end

-- A song can be bought on its own while any pack it belongs to is in the shop.
function Packs.SongForSale(song, time: number?): boolean
	for _, pack in Packs.ForSong(song) do
		if Packs.IsForSale(pack.Id, time) then
			return true
		end
	end
	return false
end

-- Bias packs: the chip joined onto the player's title ("Fan | ♥ CARAT"). Group packs show
-- the fandom (FANDOMS, else the group name), company packs the company; My Pack has none.
-- The colour is picked from BADGE_COLOURS by name, so a group always gets the same one.
Packs.BADGE_COLOURS = { "FF9EC4", "9ED8F5", "A7E9B8", "FFE07A", "FFB38A", "B9A6FF", "FFD2CE", "C8EFD6" }

function Packs.Badge(id: string): (string?, string?)
	local pack = Packs.Get(id)
	if not pack or pack.Kind == "My" then
		return nil, nil
	end
	local text = if pack.Kind == "Group" then (Packs.FANDOMS[pack.Name] or pack.Name) else pack.Name
	local hash = 0
	for i = 1, #pack.Name do
		hash = (hash * 31 + string.byte(pack.Name, i)) % 1000003
	end
	return `♥ {text}`, Packs.BADGE_COLOURS[hash % #Packs.BADGE_COLOURS + 1]
end

-- The songs a bias round draws its 3 wrong answers from: the whole group / company, so all
-- 4 answers are by the same artist. nil (whole library) for My Pack or a pack under 4 songs.
function Packs.AnswerPool(id: string): { any }?
	local pack = Packs.Get(id)
	if not pack or pack.Kind == "My" or #pack.Songs < 4 then
		return nil
	end
	return pack.Songs
end

function Packs.DisplayName(id: string): string
	local pack = Packs.Get(id)
	if not pack then
		return "?"
	end
	return if pack.Kind == "My" then pack.Name else `{pack.Name} Pack`
end

return Packs
