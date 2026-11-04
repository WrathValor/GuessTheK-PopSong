--| Packs
-- Song packs, worked out from the song library. Players only ever own songs
-- (Inventory.Songs); a pack is just a way of grouping them, so packs overlap: a BTS song
-- counts towards the BTS pack and the HYBE pack, and is never paid for twice.
--   • "My"            – My Pack: every song the player has bought
--   • "Company:<name>" – every song from that company (only companies with MIN_COMPANY_SONGS+)
--   • "Group:<artist>" – every song by that group (only groups with MIN_GROUP_SONGS+)
-- Nothing is equipped: every owned song comes up more often in duels (DuelConstants.OWNED_WEIGHT),
-- and owning every song of a group pack gives its title.
-- Packs aren't sold: songs come from the song roll (Engine/RollService). A pack is the set the
-- Index, Inventory and titles count against. Owned songs are always yours.

local Songs = require(script.Parent.Songs)

local Packs = {}

Packs.MY = "My"
Packs.MIN_GROUP_SONGS = 3 -- smaller groups don't get a pack of their own (yet)
-- smaller companies don't get a pack (yet); their groups can still have group packs. A song in
-- neither kind of pack is still played in rounds, it just can't be bought.
Packs.MIN_COMPANY_SONGS = 10

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
	YENA = "Jigumi",
	ZEROBASEONE = "ZEROSE",
	CORTIS = "COER",
	Hearts2Hearts = "S2U",
	BESTie = "BESTiny",
	KiiiKiii = "TiiiKiii",
	-- A2O LITE: no fandom name yet (shows "A2O LITE Stan")
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

function Packs.DisplayName(id: string): string
	local pack = Packs.Get(id)
	if not pack then
		return "?"
	end
	return if pack.Kind == "My" then pack.Name else `{pack.Name} Pack`
end

return Packs
