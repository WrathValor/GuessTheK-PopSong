--| Upgrades
-- The Shop's coin upgrades (design board "50 · Shop rework · tabs + Upgrades"; the curves are
-- the Upgrades tab of assets/KPOPPED_Economy.xlsx). Small steps, lots of levels: level n costs
-- Base × Growth^(n-1) coins, rounded to 10. Levels are saved in Inventory.ShopUpgrades (key →
-- level) and bought through ShopRemote "Upgrade" (Engine/ShopService). Same API on both sides.
-- (Not Inventory.Upgrades: that's the old card-upgrade count.)
--   Upgrades.LIST                the six, in shop order: { Key, Name, Line, Max, Base, Growth, Colour }
--   Upgrades.Get(key)            one of them
--   Upgrades.Levels(data)        key → level (0 when not bought) from a player's data:
--                                PlayerData.Server data or PlayerData.Client
--   Upgrades.Cost(key, level)    coins for the level after `level`, nil once maxed
-- What each one does (lv = a Levels table, nil = none bought):
--   PinSlots(lv)       Slots    pinned cards that earn: PIN_SLOTS + 1 a level (3 → 5)
--   Payout(lv)         Payout   × on every pinned card: +2% a level (+50% at 25)
--   CapSeconds(lv)     Storage  how long the binder keeps earning: BINDER_CAP_SECONDS + 30 min a level (6 h → 12 h)
--   StashCap(lv)       Stash    free packs saved up: FREE_PACK_CAP + 1 a level (3 → 9)
--   RefillSeconds(lv)  Refill   a free pack refills every FREE_PACK_SECONDS − 5 min a level (2 h → 1 h 30)
--   Luck(lv)           Luck     Lucky Draw and up × (1 + 1% a level); Standard takes the difference

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)

export type Upgrade = { Key: string, Name: string, Line: string, Max: number, Base: number, Growth: number, Colour: string }
export type Levels = { [string]: number }

local Upgrades = {}

Upgrades.LIST = table.freeze({
	table.freeze({ Key = "Slots", Name = "Slots", Line = "More pinned cards earn more an hour", Max = 2, Base = 5000, Growth = 5, Colour = "FFE07A" }),
	table.freeze({ Key = "Payout", Name = "Payout", Line = "+2% on every pinned card, each level", Max = 25, Base = 500, Growth = 1.15, Colour = "A7E9B8" }),
	table.freeze({ Key = "Storage", Name = "Storage", Line = "+30 min of earning while you're away", Max = 12, Base = 300, Growth = 1.25, Colour = "9ED8F5" }),
	table.freeze({ Key = "Stash", Name = "Stash", Line = "+1 free pack saved up", Max = 6, Base = 2500, Growth = 1.3, Colour = "FF9EC4" }),
	table.freeze({ Key = "Refill", Name = "Refill", Line = "A free pack refills 5 min sooner", Max = 6, Base = 2000, Growth = 1.3, Colour = "B9A6FF" }),
	table.freeze({ Key = "Luck", Name = "Luck", Line = "Lucky Draw and up 1% more likely, each level", Max = 25, Base = 700, Growth = 1.15, Colour = "FFE07A" }),
})

local byKey: { [string]: Upgrade } = {}
for _, up in Upgrades.LIST do
	byKey[up.Key] = up
end

local PAYOUT_STEP = 0.02
local STORAGE_STEP = 30 * 60
local REFILL_STEP = 5 * 60
local LUCK_STEP = 0.01

function Upgrades.Get(key: string): Upgrade?
	return byKey[key]
end

function Upgrades.Levels(data): Levels
	local out = {}
	local map = data and data.Inventory and data.Inventory.ShopUpgrades
	local saved = map and map.Get() or {}
	for _, up in Upgrades.LIST do
		out[up.Key] = math.clamp(math.floor(tonumber(saved[up.Key]) or 0), 0, up.Max)
	end
	return out
end

function Upgrades.Cost(key: string, level: number): number?
	local up = byKey[key]
	if not up or level >= up.Max then
		return nil
	end
	local raw = up.Base * up.Growth ^ level
	return math.floor(raw / 10 + 0.5) * 10
end

local function lvl(lv: Levels?, key: string): number
	return lv and lv[key] or 0
end

function Upgrades.PinSlots(lv: Levels?): number
	return math.min(AlbumConstants.PIN_SLOTS + lvl(lv, "Slots"), AlbumConstants.PIN_SLOTS_MAX)
end

function Upgrades.Payout(lv: Levels?): number
	return 1 + PAYOUT_STEP * lvl(lv, "Payout")
end

function Upgrades.CapSeconds(lv: Levels?): number
	return AlbumConstants.BINDER_CAP_SECONDS + STORAGE_STEP * lvl(lv, "Storage")
end

function Upgrades.StashCap(lv: Levels?): number
	return AlbumConstants.FREE_PACK_CAP + lvl(lv, "Stash")
end

function Upgrades.RefillSeconds(lv: Levels?): number
	return AlbumConstants.FREE_PACK_SECONDS - REFILL_STEP * lvl(lv, "Refill")
end

function Upgrades.Luck(lv: Levels?): number
	return 1 + LUCK_STEP * lvl(lv, "Luck")
end

-- "Lv 7 / 25" style text for a level ("MAX" once maxed)
function Upgrades.LevelText(key: string, level: number): string
	local up = byKey[key]
	if not up then
		return ""
	end
	return if level >= up.Max then "MAX" else `Lv {level} / {up.Max}`
end

-- what this level gives ("4 slots", "+14%", "8 h 30", "9 packs", "Every 1 h 30 min", "+9%");
-- short = the bare number for the "→ next" side ("5", "9", "1 h 55")
local function hm(seconds: number): string
	local h, m = seconds // 3600, (seconds % 3600) // 60
	if m == 0 then
		return `{h} h`
	end
	return if h > 0 then `{h} h {m}` else `{m} min`
end
function Upgrades.Effect(key: string, level: number, short: boolean?): string
	local lv = { [key] = level }
	if key == "Slots" then
		return if short then tostring(Upgrades.PinSlots(lv)) else `{Upgrades.PinSlots(lv)} slots`
	elseif key == "Payout" then
		return `+{level * 2}%`
	elseif key == "Storage" then
		return hm(Upgrades.CapSeconds(lv))
	elseif key == "Stash" then
		return if short then tostring(Upgrades.StashCap(lv)) else `{Upgrades.StashCap(lv)} packs`
	elseif key == "Refill" then
		local t = hm(Upgrades.RefillSeconds(lv))
		if short then
			return t
		end
		return if string.find(t, " h %d") then `Every {t} min` else `Every {t}`
	elseif key == "Luck" then
		return `+{level}%`
	end
	return ""
end
Upgrades.HoursText = hm

return Upgrades
