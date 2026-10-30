--| Themes
-- What a solo practice game can be limited to, picked on the back of the queue card:
--   • "All"                     – the whole library
--   • "2000s" / "2010s" / "2020s" – by each song's Year
--   • "Gen2" … "Gen5"           – by the group's Generation
--   • "Pack"                    – only songs from the player's duel pack (needs ROUNDS songs)
-- Every clip and every wrong answer comes from the theme, so you can't rule an option out by
-- era. A theme only opens once it has MIN_SONGS playable songs (Draft songs never count);
-- until then the picker shows it as SEALED. The last pick is saved in Settings.SoloTheme.

local Songs = require(script.Parent.Songs)

local Themes = {}

Themes.DEFAULT = "All"
Themes.PACK = "Pack"
Themes.MIN_SONGS = 12 -- 7 rounds + enough that the same songs don't come up every game
Themes.TABS = { "All", "Era", "Gen", "Pack" }

-- Numeral = the big text on the photocard; Colour = the card's accent
local LIST = {
	{ Id = "All", Tab = "All", Name = "All songs", Numeral = "★", Colour = "FFE07A" },
	{ Id = "2000s", Tab = "Era", Name = "2000s", Numeral = "00", Colour = "FF9EC4", From = 0, To = 2009 },
	{ Id = "2010s", Tab = "Era", Name = "2010s", Numeral = "10", Colour = "9ED8F5", From = 2010, To = 2019 },
	{ Id = "2020s", Tab = "Era", Name = "2020s", Numeral = "20", Colour = "A7E9B8", From = 2020, To = 9999 },
	{ Id = "Gen2", Tab = "Gen", Name = "Gen 2", Numeral = "II", Colour = "FF9EC4", Generation = "2nd" },
	{ Id = "Gen3", Tab = "Gen", Name = "Gen 3", Numeral = "III", Colour = "9ED8F5", Generation = "3rd" },
	{ Id = "Gen4", Tab = "Gen", Name = "Gen 4", Numeral = "IV", Colour = "B9A6FF", Generation = "4th" },
	{ Id = "Gen5", Tab = "Gen", Name = "Gen 5", Numeral = "V", Colour = "A7E9B8", Generation = "5th" },
	{ Id = "Pack", Tab = "Pack", Name = "My duel pack", Numeral = "♪", Colour = "FFB38A" },
}
local BY_ID = {}
for _, theme in LIST do
	BY_ID[theme.Id] = theme
end
Themes.List = LIST

function Themes.Get(id: string?)
	return id and BY_ID[id] or nil
end

-- the themes on one tab of the picker, in order
function Themes.ForTab(tab: string)
	local out = {}
	for _, theme in LIST do
		if theme.Tab == tab then
			table.insert(out, theme)
		end
	end
	return out
end

-- Does this song fit the theme? ("Pack" is decided by the player's pack, not here.)
function Themes.Matches(id: string, song): boolean
	local theme = BY_ID[id]
	if not theme or theme.Id == "All" then
		return true
	end
	if theme.Generation then
		return song.Generation == theme.Generation
	end
	if theme.From then
		local year = song.Year or 0
		return year >= theme.From and year <= theme.To
	end
	return false
end

local cache = {}
-- every playable song in the theme (not "Pack")
function Themes.SongsFor(id: string): { any }
	if cache[id] then
		return cache[id]
	end
	local out = {}
	if BY_ID[id] and id ~= Themes.PACK then
		for _, song in Songs.GetAllSongs() do
			if Themes.Matches(id, song) then
				table.insert(out, song)
			end
		end
	end
	cache[id] = out
	return out
end

function Themes.Count(id: string): number
	return #Themes.SongsFor(id)
end

-- Can this theme be played yet? ("Pack" depends on the player's pack: see the callers.)
function Themes.IsOpen(id: string): boolean
	if id == "All" then
		return true
	end
	return BY_ID[id] ~= nil and id ~= Themes.PACK and Themes.Count(id) >= Themes.MIN_SONGS
end

-- A random song in the theme that isn't excluded, or nil if none are left.
function Themes.RandomSong(id: string, exclude: { [string]: boolean }?)
	local pool = {}
	for _, song in Themes.SongsFor(id) do
		if not (exclude and exclude[song.Id]) then
			table.insert(pool, song)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

-- "BTS, TWICE, BLACKPINK": the groups with the most songs in the theme, for the card
function Themes.TopGroups(id: string, count: number): string
	local per, order = {}, {}
	for _, song in Themes.SongsFor(id) do
		if not per[song.Artist] then
			per[song.Artist] = 0
			table.insert(order, song.Artist)
		end
		per[song.Artist] += 1
	end
	table.sort(order, function(a, b)
		if per[a] ~= per[b] then
			return per[a] > per[b]
		end
		return a < b
	end)
	local names = {}
	for i = 1, math.min(count, #order) do
		names[i] = order[i]
	end
	return table.concat(names, ", ")
end

-- "2012–2019": the years the theme's songs actually cover ("" when empty)
function Themes.Years(id: string): string
	local low, high = math.huge, -math.huge
	for _, song in Themes.SongsFor(id) do
		if song.Year then
			low = math.min(low, song.Year)
			high = math.max(high, song.Year)
		end
	end
	if low == math.huge then
		return ""
	end
	return if low == high then tostring(low) else `{low}–{high}`
end

return Themes
