--| ShopCatalog
-- Everything the shop sells, shared by the server (prices are checked there) and the client
-- (to draw the pages). Robux items need real IDs before they can be bought: until an ID is
-- set (> 0) its button shows "Soon" and does nothing.

local ShopCatalog = {}

ShopCatalog.RARITY_COLOURS = {
	Common = "EDE4D4",
	Uncommon = "A7E9B8",
	Rare = "9ED8F5",
	Epic = "B9A6FF",
	Legendary = "FFE07A",
}

-- [[ Stage sets: stage skin + spot platform + mic ]]
-- Colours drive the card art (and later the stage itself): Bg card background, Stage the
-- stage skin, Platform the pad, Mic the mic head. Buying a set unlocks its stage + mic as
-- pieces (see Stages/Mics below).
ShopCatalog.Sets = {
	{ Id = "Candy", Name = "Candy Set", Rarity = "Uncommon", Price = 675, Bg = "FFE4EF", Stage = "FF9EC4", Platform = "FFFFFF", Mic = "FFFFFF" },
	{ Id = "Rooftop", Name = "Rooftop Set", Rarity = "Uncommon", Price = 675, Bg = "E4F4FF", Stage = "9ED8F5", Platform = "FFFFFF", Mic = "9ED8F5" },
	{ Id = "Lightstick", Name = "Lightstick Set", Rarity = "Rare", Price = 1350, Bg = "E4F4FF", Stage = "9ED8F5", Platform = "FFE07A", Mic = "FFE07A" },
	{ Id = "Neon", Name = "Neon Set", Rarity = "Rare", Price = 1350, Bg = "E8FBEE", Stage = "A7E9B8", Platform = "9ED8F5", Mic = "A7E9B8" },
	{ Id = "CherryBlossom", Name = "Cherry Blossom Set", Rarity = "Rare", Price = 1350, Bg = "FFE4EF", Stage = "FFC9DD", Platform = "FFFFFF", Mic = "FF9EC4" },
	{ Id = "Photocard", Name = "Photocard Set", Rarity = "Epic", Price = 2400, Bg = "EFEAFF", Stage = "B9A6FF", Platform = "FFD2CE", Mic = "FF9EC4" },
	{ Id = "Hanbok", Name = "Hanbok Set", Rarity = "Epic", Price = 2400, Bg = "FFF0EE", Stage = "FFD2CE", Platform = "B9A6FF", Mic = "FF5A4E" },
	{ Id = "Hologram", Name = "Hologram Set", Rarity = "Epic", Price = 2400, Bg = "E4F4FF", Stage = "C9F2FF", Platform = "B9A6FF", Mic = "9ED8F5" },
	{ Id = "FanMeet", Name = "Fan-meet Booth", Rarity = "Legendary", Price = 4500, Bg = "FFF6D6", Stage = "FFE07A", Platform = "FF5A4E", Mic = "FF5A4E" },
	{ Id = "Encore", Name = "Encore Stage Set", Rarity = "Legendary", Price = 4500, Bg = "3B2F63", Stage = "FF5A4E", Platform = "FFE07A", Mic = "FFE07A",
		Blurb = "Legendary stage skin, gold spotlight platform + mic" },
}

ShopCatalog.SET_ROTATION_SECONDS = 2 * 60 * 60 -- a new set of 4 every 2 hours
ShopCatalog.SETS_PER_ROTATION = 4
ShopCatalog.FEATURED_SECONDS = 7 * 24 * 60 * 60 -- the featured set changes weekly
ShopCatalog.FEATURED_POOL = { "Encore", "FanMeet" } -- legendary sets that take turns being featured

-- the stage + mic each set unlocks ("<SetId>Stage", "<SetId>Mic")
local function pieceName(set): string
	return (set.Name:gsub(" Stage Set$", ""):gsub(" Set$", ""))
end
function ShopCatalog.SetPieces(set): (any, any)
	local name = pieceName(set)
	return { Id = set.Id .. "Stage", Name = `{name} Stage`, Rarity = set.Rarity, Set = set.Id, Bg = set.Bg, Stage = set.Stage, Platform = set.Platform },
		{ Id = set.Id .. "Mic", Name = `{name} Mic`, Rarity = set.Rarity, Set = set.Id, Bg = set.Bg, Mic = set.Mic }
end

-- [[ Stages + mic stands: sold one by one in the Items tab ]]
-- Every set also adds its own stage + mic (Set = setId); those pieces are never sold alone,
-- but once owned they mix and match with anything. "Default" is the free Classic piece.
-- Stage: Bg card background, Stage the stage skin, Platform the pad. Mic: Mic the mic head.
ShopCatalog.Stages = {
	{ Id = "PastelCloud", Name = "Pastel Cloud", Rarity = "Common", Price = 300, Bg = "F3F7FF", Stage = "9ED8F5", Platform = "FFFFFF" },
	{ Id = "Cream", Name = "Cream Soda", Rarity = "Common", Price = 300, Bg = "FFF6D6", Stage = "FFFFFF", Platform = "FFE07A" },
	{ Id = "PracticeRoom", Name = "Practice Room", Rarity = "Common", Price = 300, Bg = "F3EBDD", Stage = "DDB287", Platform = "B9A6FF" },
	{ Id = "Picnic", Name = "Picnic Blanket", Rarity = "Common", Price = 300, Bg = "E8FBEE", Stage = "FF9EC4", Platform = "C7E8B5" },
	{ Id = "MintArcade", Name = "Mint Arcade", Rarity = "Uncommon", Price = 500, Bg = "E8FFF0", Stage = "A7E9B8", Platform = "FFE07A" },
	{ Id = "Bubblegum", Name = "Bubblegum", Rarity = "Uncommon", Price = 500, Bg = "FFE4EF", Stage = "FF9EC4", Platform = "B9A6FF" },
	{ Id = "KaraokeBox", Name = "Karaoke Box", Rarity = "Uncommon", Price = 500, Bg = "EFEAFF", Stage = "2B2346", Platform = "FF9EC4" },
	{ Id = "BananaMilk", Name = "Banana Milk", Rarity = "Uncommon", Price = 500, Bg = "FFF6D6", Stage = "FFE07A", Platform = "FFFFFF" },
	{ Id = "MidnightVelvet", Name = "Midnight Velvet", Rarity = "Rare", Price = 900, Bg = "EFEAFF", Stage = "2B2346", Platform = "B9A6FF" },
	{ Id = "HanRiver", Name = "Han River", Rarity = "Rare", Price = 900, Bg = "E4F4FF", Stage = "9ED8F5", Platform = "A7E9B8" },
	{ Id = "SubwayLine", Name = "Subway Line", Rarity = "Rare", Price = 900, Bg = "F3F7FF", Stage = "C9C3DE", Platform = "3CB371" },
	{ Id = "Aquarium", Name = "Aquarium", Rarity = "Rare", Price = 900, Bg = "E4F4FF", Stage = "9ED8F5", Platform = "F6E3B4" },
	{ Id = "SunsetRooftop", Name = "Sunset Rooftop", Rarity = "Epic", Price = 1600, Bg = "FFF0E6", Stage = "FFB38A", Platform = "FF5A4E" },
	{ Id = "Starlight", Name = "Starlight", Rarity = "Epic", Price = 1600, Bg = "2B2346", Stage = "B9A6FF", Platform = "FFE07A" },
	{ Id = "AwardNight", Name = "Award Night", Rarity = "Epic", Price = 1600, Bg = "2B2346", Stage = "FF5A4E", Platform = "F5C542" },
}
ShopCatalog.Mics = {
	{ Id = "StudioClassic", Name = "Studio Classic", Rarity = "Common", Price = 150, Bg = "F3EBDD", Mic = "C9C3DE" },
	{ Id = "Bubble", Name = "Bubble Mic", Rarity = "Common", Price = 150, Bg = "E4F4FF", Mic = "9ED8F5" },
	{ Id = "Bunny", Name = "Bunny Mic", Rarity = "Common", Price = 150, Bg = "FFE4EF", Mic = "FFFFFF" },
	{ Id = "Strawberry", Name = "Strawberry Mic", Rarity = "Common", Price = 150, Bg = "FFE4EF", Mic = "FF5A4E" },
	{ Id = "Heart", Name = "Heart Mic", Rarity = "Uncommon", Price = 350, Bg = "FFE4EF", Mic = "FF9EC4" },
	{ Id = "Minty", Name = "Minty Mic", Rarity = "Uncommon", Price = 350, Bg = "E8FFF0", Mic = "A7E9B8" },
	{ Id = "Cloud", Name = "Cloud Mic", Rarity = "Uncommon", Price = 350, Bg = "E4F4FF", Mic = "9ED8F5" },
	{ Id = "Cassette", Name = "Cassette Mic", Rarity = "Uncommon", Price = 350, Bg = "FFF0E6", Mic = "FFB38A" },
	-- (Id isn't "LightstickMic": that's the Lightstick set's own mic)
	{ Id = "Glowstick", Name = "Glowstick Mic", Rarity = "Rare", Price = 650, Bg = "FFF6D6", Mic = "FFE07A" },
	{ Id = "Retro", Name = "Retro Mic", Rarity = "Rare", Price = 650, Bg = "FFF0E6", Mic = "FFB38A" },
	{ Id = "Disco", Name = "Disco Mic", Rarity = "Rare", Price = 650, Bg = "EFEAFF", Mic = "E8E2F2" },
	{ Id = "Planet", Name = "Planet Mic", Rarity = "Rare", Price = 650, Bg = "2B2346", Mic = "FFB38A" },
	{ Id = "Crystal", Name = "Crystal Mic", Rarity = "Epic", Price = 1100, Bg = "EFEAFF", Mic = "B9A6FF" },
	{ Id = "Gold", Name = "Golden Mic", Rarity = "Epic", Price = 1100, Bg = "2B2346", Mic = "FFE07A" },
	{ Id = "Butterfly", Name = "Butterfly Mic", Rarity = "Epic", Price = 1100, Bg = "EFEAFF", Mic = "B9A6FF" },
}
-- reward-only stages (no Price, so never in the shop)
table.insert(ShopCatalog.Stages, { Id = "GroupStage", Name = "Group Exclusive", Rarity = "Rare", Bg = "E8FFF0", Stage = "A7E9B8", Platform = "FFFFFF", Reward = "Group" })
ShopCatalog.DEFAULT_STAGE = { Id = "Default", Name = "Classic", Rarity = "Common", Bg = "F3EBDD", Stage = "FFFFFF", Platform = "FFFFFF" }
ShopCatalog.DEFAULT_MIC = { Id = "Default", Name = "Classic Mic", Rarity = "Common", Bg = "F3EBDD", Mic = "FFFFFF" }
ShopCatalog.ITEMS_PER_ROTATION = 4 -- stages, and the same number of mics, every rotation

-- add every set's pieces to the lists (not for sale on their own: Price = nil, Set = setId)
for _, set in ShopCatalog.Sets do
	local stage, mic = ShopCatalog.SetPieces(set)
	table.insert(ShopCatalog.Stages, stage)
	table.insert(ShopCatalog.Mics, mic)
end

-- [[ Song packs: one per company and one per group (Modules/Library/Packs); songs are bought
-- one by one or all missing at once ]]
ShopCatalog.SONG_PRICE = 150
ShopCatalog.PACK_DISCOUNT = 0.25 -- "buy all missing" costs 25% less
ShopCatalog.PACK_COLOURS = { "B9A6FF", "A7E9B8", "FFD2CE", "9ED8F5", "FFE07A" }

-- Price of buying `missing` songs of a pack at once.
function ShopCatalog.PackPrice(missing: number): number
	return math.floor(missing * ShopCatalog.SONG_PRICE * (1 - ShopCatalog.PACK_DISCOUNT) / 10 + 0.5) * 10
end

-- [[ Robux: coin bundles (developer products) and passes (game passes) ]]
ShopCatalog.CoinBundles = {
	{ Id = "Coins500", Amount = 500, Robux = 25, ProductId = 0, Sub = "A little top-up", Bg = "FFF6D6", Coins = 1 },
	{ Id = "Coins2500", Amount = 2500, Robux = 99, ProductId = 0, Sub = "Most popular", Bg = "FFE4EF", Coins = 3, Best = true },
	{ Id = "Coins12000", Amount = 12000, Robux = 399, ProductId = 0, Sub = "Mega bag", Bg = "E8FBEE", Coins = 6 },
}

ShopCatalog.Passes = {
	{ Id = "DoubleCoins", Name = "2× Coins", Sub = "Double coins from every match, forever", Robux = 149, GamePassId = 0, Bg = "9ED8F5", Icon = "2×" },
	{ Id = "VIP", Name = "VIP Pass", Sub = "VIP name tag · gold platform · early restocks", Robux = 199, GamePassId = 0, Bg = "FFE07A", Icon = "Crown",
		Perks = { "VIP name tag", "Gold platform", "Early restocks" } },
}

-- [[ Helpers ]]

function ShopCatalog.GetSet(id: string)
	for _, set in ShopCatalog.Sets do
		if set.Id == id then
			return set
		end
	end
	return nil
end

-- kind = "Stage" | "Mic"
function ShopCatalog.GetItem(kind: string, id: string)
	if id == "Default" then
		return if kind == "Stage" then ShopCatalog.DEFAULT_STAGE elseif kind == "Mic" then ShopCatalog.DEFAULT_MIC else nil
	end
	local list = if kind == "Stage" then ShopCatalog.Stages elseif kind == "Mic" then ShopCatalog.Mics else nil
	for _, item in list or {} do
		if item.Id == id then
			return item
		end
	end
	return nil
end

function ShopCatalog.GetPass(id: string)
	for _, pass in ShopCatalog.Passes do
		if pass.Id == id then
			return pass
		end
	end
	return nil
end

-- Which rotation window `time` falls in, and when it ends.
function ShopCatalog.RotationWindow(time: number?): (number, number)
	local t = time or os.time()
	local window = math.floor(t / ShopCatalog.SET_ROTATION_SECONDS)
	return window, (window + 1) * ShopCatalog.SET_ROTATION_SECONDS
end

-- The featured set this week, and when it changes.
function ShopCatalog.Featured(time: number?)
	local t = time or os.time()
	local week = math.floor(t / ShopCatalog.FEATURED_SECONDS)
	local id = ShopCatalog.FEATURED_POOL[(week % #ShopCatalog.FEATURED_POOL) + 1]
	return ShopCatalog.GetSet(id), (week + 1) * ShopCatalog.FEATURED_SECONDS
end

-- The 4 sets in the shop right now (same on every server: seeded by the window number).
-- The featured set is never part of the rotation.
function ShopCatalog.Rotation(time: number?): { any }
	local window = ShopCatalog.RotationWindow(time)
	local featured = ShopCatalog.Featured(time)
	local pool = {}
	for _, set in ShopCatalog.Sets do
		if not featured or set.Id ~= featured.Id then
			table.insert(pool, set)
		end
	end
	local rng = Random.new(window * 7919 + 17)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(ShopCatalog.SETS_PER_ROTATION, #pool) do
		out[i] = pool[i]
	end
	-- cheapest first, like the design
	table.sort(out, function(a, b)
		return a.Price < b.Price
	end)
	return out
end

-- The stages or mics in the Items tab right now (4 of each, seeded like the sets; set pieces
-- are never in it). Cheapest first.
function ShopCatalog.ItemRotation(kind: string, time: number?): { any }
	local window = ShopCatalog.RotationWindow(time)
	local pool = {}
	for _, item in (if kind == "Stage" then ShopCatalog.Stages else ShopCatalog.Mics) do
		if item.Price and not item.Set then
			table.insert(pool, item)
		end
	end
	local rng = Random.new(window * 104729 + (if kind == "Stage" then 3 else 5))
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(ShopCatalog.ITEMS_PER_ROTATION, #pool) do
		out[i] = pool[i]
	end
	table.sort(out, function(a, b)
		return a.Price < b.Price
	end)
	return out
end

function ShopCatalog.ItemForSale(kind: string, id: string, time: number?): boolean
	for _, item in ShopCatalog.ItemRotation(kind, time) do
		if item.Id == id then
			return true
		end
	end
	return false
end

-- Can this set be bought right now? (in the rotation or featured)
function ShopCatalog.IsForSale(id: string, time: number?): boolean
	local featured = ShopCatalog.Featured(time)
	if featured and featured.Id == id then
		return true
	end
	for _, set in ShopCatalog.Rotation(time) do
		if set.Id == id then
			return true
		end
	end
	return false
end

-- "1,350"
function ShopCatalog.Format(n: number): string
	local s = tostring(math.floor(n))
	local out, k = s, 0
	repeat
		out, k = out:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return out
end

-- "1h 42m" / "6d" / "18h"
function ShopCatalog.Countdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	if d > 0 then
		return `{d}d`
	elseif h > 0 then
		return `{h}h {m}m`
	end
	return `{m}m`
end

return ShopCatalog
