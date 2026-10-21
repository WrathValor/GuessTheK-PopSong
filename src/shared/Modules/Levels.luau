--| Levels
-- Player.XP is stored as a lifetime total. Level and progress are derived from it here so
-- the curve can be retuned without migrating saved data.
--
-- XP needed to go from level n to n+1 = BASE + STEP * (n - 1)
--   Lv1 -> 2: 100,  Lv7 -> 8: 1,000,  Lv20 -> 21: 2,950

local BASE = 100
local STEP = 150
local MAX_LEVEL = 999

local Levels = {}

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
