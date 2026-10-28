--| Levels
-- Player.XP is stored as a lifetime total. Level and progress are derived from it here so
-- the curve can be retuned without migrating saved data.
--
-- XP needed to go from level n to n+1 = BASE + STEP * (n - 1)
--   Lv1 -> 2: 100,  Lv7 -> 8: 1,000,  Lv20 -> 21: 2,950
-- Level 100 is the cap (742,500 XP in total).
--
-- Level titles: reaching a level in TITLES unlocks that title (DataService grants it into
-- Inventory.Titles; equip it in the Inventory). "Fan" is everyone's default.

local BASE = 100
local STEP = 150
local MAX_LEVEL = 100

local Levels = {}

Levels.MAX_LEVEL = MAX_LEVEL
Levels.TITLES = table.freeze({
	{ Level = 1, Title = "Fan" },
	{ Level = 5, Title = "Trainee" },
	{ Level = 10, Title = "Rookie" },
	{ Level = 15, Title = "Idol" },
	{ Level = 20, Title = "Maknae" },
	{ Level = 30, Title = "Visual" },
	{ Level = 40, Title = "Center" },
	{ Level = 50, Title = "Leader" },
	{ Level = 65, Title = "Ace" },
	{ Level = 80, Title = "Icon" },
	{ Level = 100, Title = "Legend" },
})

-- Every level title unlocked at `level` (lowest first).
function Levels.TitlesUpTo(level: number): { string }
	local out = {}
	for _, t in Levels.TITLES do
		if level >= t.Level then
			table.insert(out, t.Title)
		end
	end
	return out
end

-- The next title still to unlock above `level`, or nil at the top.
function Levels.NextTitle(level: number): (string?, number?)
	for _, t in Levels.TITLES do
		if t.Level > level then
			return t.Title, t.Level
		end
	end
	return nil, nil
end

function Levels.XPToNext(level: number): number
	return BASE + STEP * (level - 1)
end

-- Returns level, xp into the current level, xp needed for the next level.
function Levels.FromXP(totalXP: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, math.floor(totalXP))
	while level < MAX_LEVEL do
		local need = Levels.XPToNext(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return MAX_LEVEL, 0, Levels.XPToNext(MAX_LEVEL)
end

return table.freeze(Levels)
