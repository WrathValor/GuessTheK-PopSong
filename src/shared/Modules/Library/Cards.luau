--| Cards
-- Card levels of owned songs. Every copy of a song pulled from the song roll counts
-- (Inventory.Copies); a song bought in the shop counts as 1 copy. Normal at 1, Gold at
-- RollConstants.GOLD_COPIES, Rainbow at RAINBOW_COPIES. The level makes the song come up more
-- often in duels (DuelConstants.OWNED_WEIGHT) and shows on its Index card.
-- A whole set (a group or company pack) has a level too: the lowest card in it. That is its
-- title's tier (Engine/Collection): own them all → Normal, all Gold → Gold, all Rainbow →
-- Rainbow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RollConstants = require(ReplicatedStorage.Constants.RollConstants)

local Cards = {}

Cards.LEVELS = { "Normal", "Gold", "Rainbow" }
Cards.RANK = { Normal = 1, Gold = 2, Rainbow = 3 }

-- copies → "Normal" | "Gold" | "Rainbow" (nil = not owned)
function Cards.Level(copies: number): string?
	if copies >= RollConstants.RAINBOW_COPIES then
		return "Rainbow"
	elseif copies >= RollConstants.GOLD_COPIES then
		return "Gold"
	elseif copies >= 1 then
		return "Normal"
	end
	return nil
end

-- How many copies of `id` the player has: the Copies map (Inventory.Copies.Get()), and 1 for
-- a song they own with no entry there (bought in the shop).
function Cards.Copies(copiesMap: { [string]: number }?, owned: boolean, id: string): number
	local n = if type(copiesMap) == "table" then tonumber(copiesMap[id]) or 0 else 0
	return math.max(n, if owned then 1 else 0)
end

-- A set's level: its lowest card ("Normal" / "Gold" / "Rainbow"), or nil while any song in it
-- isn't owned. `owns(songId)` says whether the player owns a song.
function Cards.SetLevel(songs: { any }, copiesMap: { [string]: number }?, owns: (string) -> boolean): string?
	if #songs == 0 then
		return nil
	end
	local low = 3
	for _, song in songs do
		if not owns(song.Id) then
			return nil
		end
		local rank = Cards.RANK[Cards.Level(Cards.Copies(copiesMap, true, song.Id)) or "Normal"]
		low = math.min(low, rank)
	end
	return Cards.LEVELS[low]
end

-- How many songs of a set are at `level` or higher.
function Cards.CountAtLeast(songs: { any }, copiesMap: { [string]: number }?, owns: (string) -> boolean, level: string): number
	local need, n = Cards.RANK[level], 0
	for _, song in songs do
		if owns(song.Id) then
			local rank = Cards.RANK[Cards.Level(Cards.Copies(copiesMap, true, song.Id)) or "Normal"]
			n += if rank >= need then 1 else 0
		end
	end
	return n
end

-- The next level up and the copies it needs (nil once Rainbow).
function Cards.Next(copies: number): (string?, number?)
	if copies < RollConstants.GOLD_COPIES then
		return "Gold", RollConstants.GOLD_COPIES
	elseif copies < RollConstants.RAINBOW_COPIES then
		return "Rainbow", RollConstants.RAINBOW_COPIES
	end
	return nil, nil
end

return Cards
