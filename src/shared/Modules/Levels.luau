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
-- TITLE_TIERS: level titles that come animated (a title tier, Modules/UI/TierShine: "Gold"
-- shines, "Rainbow" scrolls). DataService sets it in Inventory.TitleTiers with the title, so
-- name tags, the profile and the Inventory all animate it.
-- TITLE_COLOURS: the chip colour of each still level title (TitleChip, the Inventory, the
-- Rewards cards, the "YOU GOT!" reveal). Warmer as you level, two titles per colour so each
-- colour reads as a stage ("Level title colours" board). Fan keeps the default lilac.

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

Levels.TITLE_TIERS = table.freeze({
	Icon = "Gold", -- level 80: the gold shine
	Legend = "Rainbow", -- level 100
})

Levels.TITLE_COLOURS = table.freeze({
	Trainee = Color3.fromHex("A7E9B8"), -- mint
	Rookie = Color3.fromHex("A7E9B8"),
	Idol = Color3.fromHex("9ED8F5"), -- blue
	Maknae = Color3.fromHex("9ED8F5"),
	Visual = Color3.fromHex("FF9EC4"), -- pink
	Center = Color3.fromHex("FF9EC4"),
	Leader = Color3.fromHex("FFB38A"), -- peach
	Ace = Color3.fromHex("FFE07A"), -- yellow
	Icon = Color3.fromHex("FFE07A"), -- (shows its Gold tier)
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
