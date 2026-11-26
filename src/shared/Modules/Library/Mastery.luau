--| Mastery
-- How well you know each song (the Binder's Songs tab, design board "46 · Binder · Songs tab").
-- Duels and solo practice record every Song-mode round you play (Engine/DuelService/Duels):
-- one entry a song in Inventory.Mastery, "plays,rights,fast,best":
--   plays   rounds the song came up
--   rights  rounds you guessed it right
--   fast    right guesses on FAST_TIER or quicker (0.5 s)
--   best    the quickest tier you've guessed it on (1 = 0.1 s … 5 = 15 s; 0 = never right)
-- Stars, from those:
--   ★    guessed it right once
--   ★★   guessed it right at STAR2_TIER or quicker (2 s)
--   ★★★  guessed it right at FAST_TIER or quicker, FAST_COUNT times — the song is mastered
--
--   Mastery.Parse(value) → { Plays, Rights, Fast, Best }
--   Mastery.Record(value, correct, tier) → the new value
--   Mastery.Stars(value) → 0–3
--   Mastery.Percent(map, songIds) → 0–1: stars earned of the most those songs could have
--   Mastery.GroupSongs(artist) → that group's song ids
-- What the stars pay is the group's songs ladder (Modules/Library/Ladders): that replaced the
-- 25/50/75/100% milestones.

local Mastery = {}

Mastery.STAR2_TIER = 3 -- 2 s (DuelConstants.TIERS.Song[3])
Mastery.FAST_TIER = 2 -- 0.5 s
Mastery.FAST_COUNT = 3
Mastery.MAX_STARS = 3
export type Entry = { Plays: number, Rights: number, Fast: number, Best: number }

function Mastery.Parse(value: string?): Entry
	local plays, rights, fast, best = string.match(value or "", "^(%d+),(%d+),(%d+),(%d+)$")
	return {
		Plays = tonumber(plays) or 0,
		Rights = tonumber(rights) or 0,
		Fast = tonumber(fast) or 0,
		Best = tonumber(best) or 0,
	}
end

local function encode(e: Entry): string
	return `{e.Plays},{e.Rights},{e.Fast},{e.Best}`
end

-- one round of the song played: right or not, on which tier (1 = the shortest clip)
function Mastery.Record(value: string?, correct: boolean, tier: number): string
	local e = Mastery.Parse(value)
	e.Plays = math.min(e.Plays + 1, 99999)
	if correct then
		e.Rights = math.min(e.Rights + 1, 99999)
		if tier <= Mastery.FAST_TIER then
			e.Fast = math.min(e.Fast + 1, 99999)
		end
		if e.Best == 0 or tier < e.Best then
			e.Best = tier
		end
	end
	return encode(e)
end

function Mastery.Stars(value: string?): number
	local e = Mastery.Parse(value)
	if e.Fast >= Mastery.FAST_COUNT then
		return 3
	elseif e.Best > 0 and e.Best <= Mastery.STAR2_TIER then
		return 2
	elseif e.Rights > 0 then
		return 1
	end
	return 0
end

function Mastery.Mastered(value: string?): boolean
	return Mastery.Stars(value) >= Mastery.MAX_STARS
end

-- the share of stars earned across these songs (a group's "64% mastered")
function Mastery.Percent(map: { [string]: string }, songIds: { string }): number
	if #songIds == 0 then
		return 0
	end
	local stars = 0
	for _, id in songIds do
		stars += Mastery.Stars(map[id])
	end
	return stars / (#songIds * Mastery.MAX_STARS)
end

-- a group's song ids (every playable song by that artist)
local groupCache: { [string]: { string } } = {}
function Mastery.GroupSongs(artist: string): { string }
	local cached = groupCache[artist]
	if cached then
		return cached
	end
	local Songs = require(script.Parent.Songs)
	local ids = {}
	for _, song in Songs.GetAllSongs() do
		if song.Artist == artist then
			table.insert(ids, song.Id)
		end
	end
	groupCache[artist] = ids
	return ids
end

return Mastery
