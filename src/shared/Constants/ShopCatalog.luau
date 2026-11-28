--| ShopCatalog
-- Everything the shop sells, shared by the server (prices are checked there) and the client
-- (to draw the pages). Robux items need real IDs before they can be bought: until an ID is
-- set (> 0) its button shows "Soon" and does nothing.

local ShopCatalog = {}

-- Developer products belong to one game. The live game ("Guess The K-POP Song!", universe
-- 10774118391) owns the originals; products added since are made in both it and the
-- development place, and LIVE picks which ID a catalog entry uses.
ShopCatalog.LIVE_UNIVERSE = 10774118391
ShopCatalog.LIVE = game.GameId == ShopCatalog.LIVE_UNIVERSE
local function pick(live: number, dev: number): number
	return if ShopCatalog.LIVE then live else dev
end

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
	{ Id = "Photocard", Name = "Photocard Set", Rarity = "Epic", Price = 3000, Bg = "EFEAFF", Stage = "B9A6FF", Platform = "FFD2CE", Mic = "FF9EC4" },
	{ Id = "Hanbok", Name = "Hanbok Set", Rarity = "Epic", Price = 3000, Bg = "FFF0EE", Stage = "FFD2CE", Platform = "B9A6FF", Mic = "FF5A4E" },
	{ Id = "Hologram", Name = "Hologram Set", Rarity = "Epic", Price = 3000, Bg = "E4F4FF", Stage = "C9F2FF", Platform = "B9A6FF", Mic = "9ED8F5" },
	{ Id = "FanMeet", Name = "Fan-meet Booth", Rarity = "Legendary", Price = 6000, Bg = "FFF6D6", Stage = "FFE07A", Platform = "FF5A4E", Mic = "FF5A4E" },
	{ Id = "Encore", Name = "Encore Stage Set", Rarity = "Legendary", Price = 6000, Bg = "3B2F63", Stage = "FF5A4E", Platform = "FFE07A", Mic = "FFE07A",
		Blurb = "Legendary stage skin, gold spotlight platform + mic" },
	-- event sets (Event = a Constants/LiveEvents id): only from that event's shop, never in the rotation
	{ Id = "FirstSnow", Name = "First Snow Set", Rarity = "Legendary", Price = 0, Bg = "E6F6FF", Stage = "CFEFFF", Platform = "FFFFFF", Mic = "9ED8F5", Event = "winter26",
		Blurb = "Winter Special · icy stage, snow-white platform + mic" },
}

ShopCatalog.SET_ROTATION_SECONDS = 6 * 60 * 60 -- a new lineup every 6 hours (sets, items, banners)
-- VIP Pass "early restocks": VIPs see (and can buy) the next lineup this long before everyone
-- else. The current one stays buyable for them until it leaves (ShopService checks both).
ShopCatalog.VIP_EARLY_SECONDS = 30 * 60
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
	{ Id = "SunsetRooftop", Name = "Sunset Rooftop", Rarity = "Epic", Price = 2000, Bg = "FFF0E6", Stage = "FFB38A", Platform = "FF5A4E" },
	{ Id = "Starlight", Name = "Starlight", Rarity = "Epic", Price = 2000, Bg = "2B2346", Stage = "B9A6FF", Platform = "FFE07A" },
	{ Id = "AwardNight", Name = "Award Night", Rarity = "Epic", Price = 2000, Bg = "2B2346", Stage = "FF5A4E", Platform = "F5C542" },
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
	{ Id = "Crystal", Name = "Crystal Mic", Rarity = "Epic", Price = 1400, Bg = "EFEAFF", Mic = "B9A6FF" },
	{ Id = "Gold", Name = "Golden Mic", Rarity = "Epic", Price = 1400, Bg = "2B2346", Mic = "FFE07A" },
	{ Id = "Butterfly", Name = "Butterfly Mic", Rarity = "Epic", Price = 1400, Bg = "EFEAFF", Mic = "B9A6FF" },
}
-- reward-only stages (no Price, so never in the shop)
table.insert(ShopCatalog.Stages, { Id = "GroupStage", Name = "Group Exclusive", Rarity = "Rare", Bg = "E8FFF0", Stage = "A7E9B8", Platform = "FFFFFF", Reward = "Group" })
-- the VIP Pass's gold platform: given while the pass is owned (Engine/DataService)
table.insert(ShopCatalog.Stages, { Id = "VIPGold", Name = "VIP Gold", Rarity = "Legendary", Bg = "FFF6D6", Stage = "F5C542", Platform = "FFE07A", Reward = "VIP" })
ShopCatalog.VIP_STAGE = "VIPGold"
-- Debut Pack only (ShopCatalog.DebutPack): never in the shop rotation
table.insert(ShopCatalog.Stages, { Id = "DebutStage", Name = "Debut Stage", Rarity = "Epic", Bg = "FFE4EF", Stage = "B9A6FF", Platform = "FF9EC4", Reward = "Debut" })
table.insert(ShopCatalog.Mics, { Id = "DebutMic", Name = "Debut Mic", Rarity = "Epic", Bg = "FFE4EF", Mic = "FF9EC4", Reward = "Debut" })
-- Invite friends milestones only (Constants/ReferralConstants): never in the shop
-- (a friendship bracelet: pastel beads, BFF blocks on a bead arch, two hearts)
table.insert(ShopCatalog.Stages, { Id = "FriendshipStage", Name = "Friendship Stage", Rarity = "Epic", Bg = "E8FFF0", Stage = "A7E9B8", Platform = "FF9EC4", Reward = "Referral" })
table.insert(ShopCatalog.Mics, { Id = "FriendshipMic", Name = "Friendship Mic", Rarity = "Epic", Bg = "E6F6FF", Mic = "9ED8F5", Reward = "Referral" })
ShopCatalog.DEFAULT_STAGE = { Id = "Default", Name = "Classic", Rarity = "Common", Bg = "F3EBDD", Stage = "FFFFFF", Platform = "FFFFFF" }
ShopCatalog.DEFAULT_MIC = { Id = "Default", Name = "Classic Mic", Rarity = "Common", Bg = "F3EBDD", Mic = "FFFFFF" }
ShopCatalog.ITEMS_PER_ROTATION = 4 -- stages, and the same number of mics, every rotation

-- add every set's pieces to the lists (not for sale on their own: Price = nil, Set = setId)
for _, set in ShopCatalog.Sets do
	local stage, mic = ShopCatalog.SetPieces(set)
	table.insert(ShopCatalog.Stages, stage)
	table.insert(ShopCatalog.Mics, mic)
end

-- [[ Song sets: colours for the pack cards in the Inventory. Songs come from the song roll
-- (Constants/RollConstants), not the shop. ]]
ShopCatalog.PACK_COLOURS = { "B9A6FF", "A7E9B8", "FFD2CE", "9ED8F5", "FFE07A" }

-- [[ Robux: coin bundles (developer products) and passes (game passes) ]]
-- No prices here: the shop reads each one live from Roblox (Modules/Prices), so regional /
-- managed pricing and price changes in Creator Hub show up by themselves.
-- Shown in this order (the shop's coin banner has 5 slots, pile art 1–5 left to right).
-- Tag puts a sticker on the bundle. Hidden bundles aren't shown but still grant, so a product
-- that's retired keeps paying out any purchase still being processed.
-- Pile = the stacked-coin picture (shop banner + the purchase reveal)
ShopCatalog.CoinBundles = {
	{ Id = "Coins250", Amount = 250, ProductId = 3729530222, Pile = "rbxassetid://121219836580813" },
	{ Id = "Coins500", Amount = 500, ProductId = 3726064237, Pile = "rbxassetid://80732573906769" },
	{ Id = "Coins1000", Amount = 1000, ProductId = 3729530471, Tag = "POPULAR", Pile = "rbxassetid://81363910226647" },
	{ Id = "Coins2500", Amount = 2500, ProductId = 3726065843, Pile = "rbxassetid://75882247530961" },
	{ Id = "Coins5000", Amount = 5000, ProductId = 3729530903, Tag = "BEST VALUE", Pile = "rbxassetid://95124619717890" },
	{ Id = "Coins12000", Amount = 12000, ProductId = 3726066331, Hidden = true, Pile = "rbxassetid://95124619717890" }, -- the old Mega bag
}

-- Roll tickets + card upgrades (developer products): the shop's "Rolls + upgrades" section,
-- three bundles of each, left to right. Card upgrades went with the song Index (25 Nov 2026):
-- their bundles are Hidden, and one still being processed pays Currencies.UPGRADE_COINS each
-- (Modules/PlayerData). Currency is a Constants/Currencies id. A bundle whose
-- ProductId is still 0 shows "Soon" and can't be bought; Hidden ones aren't shown but still
-- grant (like CoinBundles). Bought ones show the purchase reveal (PurchasedController).
ShopCatalog.RollBundles = {
	-- gen packs (each opens a whole 5-card gen pack; Currencies.GenPacks). They were pack tickets
	-- (1 card each) until 26 Nov 2026; the product Ids stay. Dev copies at the cut prices
	-- (15 / 59 / 129, 25 Nov 2026) to test before the live ones (19 / 79 / 169) change in Creator Hub
	{ Id = "Tickets1", Currency = "GenPacks", Amount = 1, ProductId = pick(3730112610, 3736256022) },
	{ Id = "Tickets5", Currency = "GenPacks", Amount = 5, ProductId = pick(3730112632, 3736256078), Tag = "POPULAR" },
	{ Id = "Tickets12", Currency = "GenPacks", Amount = 12, ProductId = pick(3730112656, 3736256092) },
	-- the bigger stacks (28 Nov 2026; dev 249 / 449: live ids 0 show "Soon" until they're made)
	{ Id = "Tickets25", Currency = "GenPacks", Amount = 25, ProductId = pick(0, 3737145825) },
	{ Id = "Tickets50", Currency = "GenPacks", Amount = 50, ProductId = pick(0, 3737145831), Tag = "BEST VALUE" },
	-- card upgrades went with the song Index (25 Nov 2026): off the shop, a purchase still in
	-- flight pays Currencies.UPGRADE_COINS each
	{ Id = "Upgrades1", Currency = "Upgrades", Amount = 1, ProductId = 3730112680, Hidden = true },
	{ Id = "Upgrades5", Currency = "Upgrades", Amount = 5, ProductId = 3730112697, Tag = "POPULAR", Hidden = true },
	{ Id = "Upgrades12", Currency = "Upgrades", Amount = 12, ProductId = 3730112726, Tag = "BEST VALUE", Hidden = true },
}

-- the shown RollBundles of one currency, in order
function ShopCatalog.RollBundlesFor(currency: string): { any }
	local out = {}
	for _, bundle in ShopCatalog.RollBundles do
		if bundle.Currency == currency and not bundle.Hidden then
			table.insert(out, bundle)
		end
	end
	return out
end

-- The Debut Pack: a one-time starter bundle (developer product), shown near the top of the
-- shop; once bought (Rewards.Claimed "Debut") it stays with a greyed "Bought" button.
-- Hidden while ProductId is 0. Items are the cards on its banner (Label big, Sub under it,
-- Only = an "ONLY HERE" tag). Its stage + mic (the Debut set) exist only in this pack.
ShopCatalog.DebutPack = {
	Id = "Debut",
	ProductId = 3729531904,
	Coins = 2500,
	Stage = "DebutStage",
	Mic = "DebutMic",
	Items = {
		{ Label = "2,500", Sub = "Coins", Colour = "FFE07A", Image = "rbxassetid://75882247530961" }, -- the 2,500 coin pile
		{ Label = "Debut Stage", Sub = "Stage set", Colour = "9ED8F5", Kind = "Stage", Id = "DebutStage", Only = true },
		{ Label = "Debut Mic", Sub = "Mic", Colour = "9ED8F5", Kind = "Mic", Id = "DebutMic", Only = true },
	},
	-- the starter offer (Money 2, StarterOfferController): for Hours after a new player's first
	-- duel the pack comes with Tickets extra, sold as its own product at the same price. After
	-- that the bonus is gone for good and the shop's pack is the plain one. ProductId 0 = the
	-- offer is off (in Studio it still shows, selling the plain pack, so it can be tested).
	Bonus = { ProductId = 3732070614, GenPacks = 3, Hours = 48 },
}

-- Bundles: Robux packs of gen packs (pack tickets until 26 Nov 2026) and coins ("Shop v3 · Bundles" board). (They had card
-- upgrades too until 25 Nov 2026: each became Currencies.UPGRADE_COINS coins.)
-- Big = the featured one: drawn like the Debut Pack, at the very top of the shop; the rest
-- are the shorter banners under the Debut Pack, in the "Bundles" section.
-- Stage / Mic = a set only that bundle gives (their Reward is the bundle's Id). Limit = how
-- many times one player can buy it (Rewards.Bundles counts them; the banner shows "n/Limit
-- left"). Hidden behind "Soon" while ProductId is 0. Gradient = the banner's two colours.
-- Hidden = off the shop (still grants, so a purchase already in flight pays out).
-- Photocard bundles (28 Nov 2026, design board "78 · Shop · Photocard bundles"): World Tour (the
-- featured one), Fan Meeting and Lucky Draw Event took the Headliner's, Warm-up's and Practice's
-- places. Besides GenPacks / Coins they give Premium = { [pack key] = n } (unopened premium packs,
-- Inventory.PremiumOwned: "Open yours" on the Packs page), LuckMinutes (added to the Luck potion
-- clock, up to BOOST_MAX_SECONDS) and PinSlots (Slots upgrade levels; past the max, PinSlot's
-- RefundCoins each). The old three stay off the shop once the new ones have product ids here.
local NEW_BUNDLES = {
	{ Id = "WorldTour", Name = "World Tour", Sub = "Limited Editions, 4 hours of Luck and a pin slot", ProductId = pick(0, 3737145843), Big = true, Limit = 1,
		Tag = "FEATURED", TagColour = "FF5A4E", Gradient = { "DCD3FF", "D9F7E2" },
		GenPacks = 15, Premium = { limited = 3 }, LuckMinutes = 240, PinSlots = 1, Coins = 7500 },
	{ Id = "FanMeeting", Name = "Fan Meeting", Sub = "A first taste of the good packs", ProductId = pick(0, 3737145858), Limit = 2,
		Gradient = { "FFE4EF", "FFF6F3" }, GenPacks = 3, Premium = { photobook = 1 }, LuckMinutes = 30 },
	{ Id = "LuckyDrawEvent", Name = "Lucky Draw Event", Sub = "Premium packs with Luck running", ProductId = pick(0, 3737145849), Limit = 2,
		Tag = "POPULAR", TagColour = "FFE07A", Gradient = { "FFF3B8", "FFFBEA" },
		GenPacks = 6, Premium = { photobook = 2, limited = 1 }, LuckMinutes = 120, Coins = 2000 },
}
local newBundlesReady = true
for _, b in NEW_BUNDLES do
	if b.ProductId <= 0 then
		newBundlesReady = false
	end
end
ShopCatalog.Bundles = {
	{ Id = "Headliner", Name = "Headliner", Sub = "Spotlight Stage + Mic, only here", ProductId = 3730244515, Big = true, Limit = 1, Hidden = newBundlesReady,
		Tag = "FEATURED", TagColour = "FF5A4E", Gradient = { "D8F6F2", "FFE3DE" }, -- the Spotlight set's teal → coral
		Stage = "SpotlightStage", Mic = "SpotlightMic", GenPacks = 15, Coins = 7500 },
	{ Id = "WarmUp", Name = "Warm-up", Sub = "A few packs to get going", ProductId = 3730244340, Limit = 2, Hidden = newBundlesReady,
		Gradient = { "F1ECFF", "FFFFFF" }, GenPacks = 3, Coins = 650 },
	{ Id = "Practice", Name = "Practice", Sub = "Packs + coins for your binder", ProductId = 3730244371, Limit = 2, Hidden = newBundlesReady,
		Tag = "POPULAR", TagColour = "FFE07A", Gradient = { "FFE4EF", "FFF6F3" }, GenPacks = 6, Coins = 1950 },
	{ Id = "Comeback", Name = "Comeback", Sub = "Back in the game, fully stocked", ProductId = 3730244488, Limit = 2, Hidden = true,
		Gradient = { "E3F3FC", "F4FBFF" }, GenPacks = 10, Coins = 4900 },
}
for _, b in NEW_BUNDLES do
	b.Hidden = not newBundlesReady -- (the live game keeps the old three until these have ids)
	table.insert(ShopCatalog.Bundles, b)
end
-- the Headliner's set: only in that bundle, never in the shop rotation
-- (a concert runway: teal LED strips, a coral centre line, a tile video wall, fan lightsticks)
table.insert(ShopCatalog.Stages, { Id = "SpotlightStage", Name = "Spotlight Stage", Rarity = "Legendary", Bg = "E3FBF8", Stage = "2EC4B6", Platform = "FF6F59", Reward = "Headliner" })
table.insert(ShopCatalog.Mics, { Id = "SpotlightMic", Name = "Spotlight Mic", Rarity = "Legendary", Bg = "E3FBF8", Mic = "2EC4B6", Reward = "Headliner" })

function ShopCatalog.GetBundle(id: string)
	for _, b in ShopCatalog.Bundles do
		if b.Id == id then
			return b
		end
	end
	return nil
end

-- What a bundle's banner shows, in order: its stage + mic, gen packs, tickets, premium packs
-- (Photobook before Limited Edition), Luck time, pin slots, coins.
-- { Kind = "Stage" | "Mic" | "GenPacks" | "Tickets" | "Premium" | "Luck" | "PinSlot" | "Coins",
--   Id? (item / pack key), Amount? (Luck: minutes) }
local PREMIUM_ORDER = { "photobook", "limited", "fansign" }

-- how a bundle's Premium / Luck / PinSlot entry is drawn (banners, the "YOU GOT!" cards):
-- { Label = "×2", Sub = "Photobook", Image, Colour (art tile) }
local PREMIUM_LOOK = {
	photobook = { Sub = "Photobook", Image = "rbxassetid://76102402433080", Colour = "FFE07A" },
	limited = { Sub = "Limited Ed.", Image = "rbxassetid://120509227699976", Colour = "DCD3FF" },
	fansign = { Sub = "Fansign", Image = "rbxassetid://76102402433080", Colour = "FFD2E5" },
}
function ShopCatalog.ContentLook(entry): { Label: string, Sub: string, Image: string, Colour: string }?
	if entry.Kind == "Premium" then
		local look = PREMIUM_LOOK[entry.Id] or PREMIUM_LOOK.photobook
		return { Label = `×{entry.Amount}`, Sub = look.Sub, Image = look.Image, Colour = look.Colour }
	elseif entry.Kind == "Luck" then
		local m = entry.Amount
		return { Label = if m >= 60 and m % 60 == 0 then `{m // 60} h` else `{m} min`, Sub = "+50% Luck", Image = "rbxassetid://136253068957955", Colour = "D9F7E2" }
	elseif entry.Kind == "PinSlot" then
		return { Label = `+{entry.Amount}`, Sub = if entry.Amount == 1 then "Pin slot" else "Pin slots", Image = "rbxassetid://108689827818959", Colour = "FFF6D6" }
	end
	return nil
end
function ShopCatalog.BundleContents(bundle): { any }
	local out = {}
	if bundle.Stage then
		table.insert(out, { Kind = "Stage", Id = bundle.Stage })
	end
	if bundle.Mic then
		table.insert(out, { Kind = "Mic", Id = bundle.Mic })
	end
	for _, kind in { "GenPacks", "Tickets" } do
		if (bundle[kind] or 0) > 0 then
			table.insert(out, { Kind = kind, Amount = bundle[kind] })
		end
	end
	for _, key in PREMIUM_ORDER do
		local n = bundle.Premium and bundle.Premium[key] or 0
		if n > 0 then
			table.insert(out, { Kind = "Premium", Id = key, Amount = n })
		end
	end
	if (bundle.LuckMinutes or 0) > 0 then
		table.insert(out, { Kind = "Luck", Amount = bundle.LuckMinutes })
	end
	if (bundle.PinSlots or 0) > 0 then
		table.insert(out, { Kind = "PinSlot", Amount = bundle.PinSlots })
	end
	if (bundle.Coins or 0) > 0 then
		table.insert(out, { Kind = "Coins", Amount = bundle.Coins })
	end
	return out
end

ShopCatalog.Passes = {
	{ Id = "DoubleCoins", Name = "2× Coins", Sub = "Double coins from matches and pinned cards, forever", Line = "Double coins from\nmatches + pins!", GamePassId = 2063766272, Bg = "9ED8F5", Icon = "2×", Art = "rbxassetid://113425820963640" }, -- assets/ui/DoubleCoins.png
	-- (the daily perks are Engine/VIPService's; the looks are NameTags, VIPChat and the ★ VIP chips)
	{ Id = "VIP", Name = "VIP Pass", Title = "VIP!", Sub = "Gold name tag · daily free ticket + Save Streak", Line = "Gold name tag, daily\nrewards & more!", GamePassId = 2063596588, Bg = "FFE07A", Icon = "Crown", Art = "rbxassetid://127211190617908", -- assets/ui/VIPPass.png
		-- the shop's VIP perks popup (ShopController, "Money 12b"), top to bottom
		Perks = {
			{ Name = "Gold name tag", Desc = "Shiny gold plate + crown above your head", Icon = "rbxassetid://93316822259435" },
			{ Name = "Early restocks", Desc = `See and buy the next shop lineup {ShopCatalog.VIP_EARLY_SECONDS // 60} min early`, Icon = "rbxassetid://70878487229406" },
			{ Name = "Daily roll ticket", Desc = "A free roll ticket every day you play", Icon = "rbxassetid://106180506046153" },
			{ Name = "Daily Save Streak", Desc = "Save a lost streak for free, once a day", Icon = "rbxassetid://74346417839400" },
			{ Name = "VIP Gold style", Desc = "Exclusive gold banner + photocard", Icon = "rbxassetid://119995213928145" },
			{ Name = "Gold platform", Desc = "Stand on a gold platform in your duels", Icon = "rbxassetid://86375644031928" },
		} },
}

-- [[ Pin slot: the Slots upgrade's next level for Robux ]]
-- (the Upgrades tab's Slots card shows it beside the coin price; PlayerData grants it. Bought
-- once already maxed: RefundCoins instead. Live id 0 until the live product is made.)
ShopCatalog.PinSlot = { Id = "PinSlot", ProductId = pick(0, 3737139565), RefundCoins = 25000 }

-- [[ Boost potions: 2× coins or 2× XP for a while ]]
-- Robux products ("Boosts 1" board). The clock only runs while you're in the game
-- (Engine/BoostService) and drinking more adds time up to BOOST_MAX_SECONDS. A coin potion
-- on top of the 2× Coins pass adds one more ×: 3× (the shop and HUD say so).
ShopCatalog.BOOST_MAX_SECONDS = 8 * 60 * 60

-- The coin multiplier for a match: ×2 pass, ×2 potion, ×3 both
function ShopCatalog.CoinMultiplier(pass: boolean, potion: boolean): number
	if pass and potion then
		return 3
	elseif pass or potion then
		return 2
	end
	return 1
end
-- The shop's potions: 2× Coins and Luck (+50% Lucky Draw and up in packs, AlbumConstants.LUCK_POTION,
-- added to the Luck upgrade; not One of One). Luck took the 2× XP potions' place (28 Nov 2026).
local COINS_SMALL = { Id = "CoinsSmall", Kind = "Coins", Seconds = 30 * 60, ProductId = pick(3733529669, 3733232797), Image = "rbxassetid://120664233001275" }
local COINS_BIG = { Id = "CoinsBig", Kind = "Coins", Seconds = 2 * 60 * 60, ProductId = pick(3733529934, 3733232856), Image = "rbxassetid://90605715561632", Best = true }
local LUCK = {
	{ Id = "LuckSmall", Kind = "Luck", Seconds = 30 * 60, ProductId = pick(0, 3737141318), Image = "rbxassetid://136253068957955" },
	{ Id = "LuckBig", Kind = "Luck", Seconds = 2 * 60 * 60, ProductId = pick(0, 3737141327), Image = "rbxassetid://85347957795481", Best = true },
}
-- the XP potions: off the shelf, but still granted (a purchase in flight, a gift, a live game that
-- has no Luck products yet: it keeps selling these until LUCK has its live ids)
local XP = {
	{ Id = "XPSmall", Kind = "XP", Seconds = 30 * 60, ProductId = pick(3733529678, 3733232866), Image = "rbxassetid://93064684252304" },
	{ Id = "XPBig", Kind = "XP", Seconds = 2 * 60 * 60, ProductId = pick(3733529688, 3733232874), Image = "rbxassetid://86807835649616", Best = true },
}
local luckReady = LUCK[1].ProductId > 0 and LUCK[2].ProductId > 0
ShopCatalog.Boosts = { COINS_SMALL, COINS_BIG, if luckReady then LUCK[1] else XP[1], if luckReady then LUCK[2] else XP[2] }
-- every potion product that can still be granted (the shelf, plus the ones it no longer shows)
ShopCatalog.AllBoosts = { COINS_SMALL, COINS_BIG, LUCK[1], LUCK[2], XP[1], XP[2] }
ShopCatalog.BOOST_KINDS = {
	Coins = { Name = "2× Coins", Colour = "FFD23F" },
	XP = { Name = "2× XP", Colour = "B9A6FF" },
	Luck = { Name = "+50% Luck", Colour = "A7E9B8" },
}

function ShopCatalog.GetBoost(id: string)
	for _, boost in ShopCatalog.AllBoosts do
		if boost.Id == id then
			return boost
		end
	end
	return nil
end

-- [[ Gifting ]] (Engine/GiftService, "Gifting 1–4" boards)
-- Passes can't be bought for someone else, so each has a gift product that grants it in-game
-- (data.GamePasses, the same set the real pass fills). Everything else Robux is gifted with
-- its own product through Scribe's PromptGift; coin items are paid with the giver's coins.
ShopCatalog.PassGifts = {
	{ Id = "GiftVIP", Pass = "VIP", ProductId = pick(3733529693, 3733272670) },
	{ Id = "GiftDoubleCoins", Pass = "DoubleCoins", ProductId = pick(3733529702, 3733272681) },
}

-- gift twins: a second product for every giftable Robux item, so a gift never shares a product
-- id with someone buying the same thing for themselves (Scribe can't tell those receipts apart).
-- PlayerData registers each as "<Id>Gift" with the item's own Grant. The dev place has its
-- own copies at 1 Robux for testing.
ShopCatalog.GIFT_SUFFIX = "Gift"
ShopCatalog.GiftProducts = {
	Coins250 = pick(3733530057, 3733546700),
	Coins500 = pick(3733530068, 3733546728),
	Coins1000 = pick(3733530076, 3733546754),
	Coins2500 = pick(3733530091, 3733546784),
	Coins5000 = pick(3733530097, 3733546807),
	Tickets1 = pick(3733530105, 3733546825),
	Tickets5 = pick(3733530117, 3733546842),
	Tickets12 = pick(3733530131, 3733546863),
	Upgrades1 = pick(3733530145, 3733546884),
	Upgrades5 = pick(3733530159, 3733546906),
	Upgrades12 = pick(3733530175, 3733546929),
	Headliner = pick(3733530193, 3733546951),
	WarmUp = pick(3733530211, 3733546969),
	Practice = pick(3733530226, 3733546990),
	Debut = pick(3733530242, 3733547011),
	CoinsSmall = pick(3733530256, 3733547041),
	CoinsBig = pick(3733530269, 3733547053),
	XPSmall = pick(3733530284, 3733547062),
	XPBig = pick(3733530300, 3733547076),
	LuckSmall = pick(0, 3737141335),
	LuckBig = pick(0, 3737141343),
}
for id, product in table.clone(ShopCatalog.GiftProducts) do
	if product == 0 then
		ShopCatalog.GiftProducts[id] = nil -- (no gift twin made in this game yet)
	end
end

-- the product name to gift an item with: its twin when there is one
function ShopCatalog.GiftProduct(id: string): string
	return if ShopCatalog.GiftProducts[id] then id .. ShopCatalog.GIFT_SUFFIX else id
end

-- a twin's name back to the item it gifts ("Coins250Gift" → "Coins250")
function ShopCatalog.GiftBase(product: string): string
	local suffix = ShopCatalog.GIFT_SUFFIX
	if string.sub(product, -#suffix) == suffix then
		local base = string.sub(product, 1, -#suffix - 1)
		if ShopCatalog.GiftProducts[base] then
			return base
		end
	end
	return product
end

-- what a giftable Robux product is called in the gift messages ("sent you the VIP Pass")
function ShopCatalog.GiftName(product: string): string?
	product = ShopCatalog.GiftBase(product)
	for _, g in ShopCatalog.PassGifts do
		if g.Id == product then
			local pass = ShopCatalog.GetPass(g.Pass)
			return pass and pass.Name
		end
	end
	for _, b in ShopCatalog.CoinBundles do
		if b.Id == product then
			return `{ShopCatalog.Format(b.Amount)} coins`
		end
	end
	for _, b in ShopCatalog.RollBundles do
		if b.Id == product then
			return if b.Currency == "GenPacks" then `{b.Amount} gen pack{if b.Amount == 1 then "" else "s"}`
				elseif b.Currency == "Tickets" then `{b.Amount} pack ticket{if b.Amount == 1 then "" else "s"}`
				else `{b.Amount} card upgrade{if b.Amount == 1 then "" else "s"}`
		end
	end
	for _, b in ShopCatalog.Bundles do
		if b.Id == product then
			return `{b.Name} bundle`
		end
	end
	if ShopCatalog.DebutPack and ShopCatalog.DebutPack.Id == product then
		return "Debut Pack"
	end
	for _, b in ShopCatalog.AllBoosts do
		if b.Id == product then
			local kind = ShopCatalog.BOOST_KINDS[b.Kind]
			local length = if b.Seconds >= 3600 then `{b.Seconds // 3600} h` else `{b.Seconds // 60} min`
			return `{kind and kind.Name or b.Kind} potion ({length})`
		end
	end
	return nil
end

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

-- The time the shop's rotations are worked out for: now, or VIP_EARLY_SECONDS ahead for a VIP
-- (so their restocks come early). Leave `time` off the rotation calls for everyone else.
function ShopCatalog.ShopTime(vip: boolean?): number
	return os.time() + (if vip then ShopCatalog.VIP_EARLY_SECONDS else 0)
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
		if (not featured or set.Id ~= featured.Id) and not set.Event then
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

-- [[ Banners + photocards (Constants/SeasonConstants: every BANNERS entry with Shop = true) ]]
-- Sold as a set (banner + its photocard, cheaper together) or either half on its own. They
-- rotate on the stage sets' clock, STYLE_PER_ROTATION at a time. Animated ones cost more.
local SeasonConstants = require(script.Parent.SeasonConstants)

ShopCatalog.STYLE_PER_ROTATION = 4
ShopCatalog.STYLE_PRICES = table.freeze({
	Regular = table.freeze({ Banner = 800, Photocard = 600, Set = 1200 }),
	Animated = table.freeze({ Banner = 1800, Photocard = 1400, Set = 2800 }),
})

-- the shop's banner spec for `id` (nil if it isn't sold)
function ShopCatalog.GetStyle(id: string?)
	local spec = id and SeasonConstants.Banner(id)
	if spec and spec.Id == id and spec.Shop and SeasonConstants.Photocard(id) then
		return spec
	end
	return nil
end

-- kind = "Banner" | "Photocard" | "Set"
function ShopCatalog.StylePrice(id: string, kind: string): number?
	local spec = ShopCatalog.GetStyle(id)
	if not spec then
		return nil
	end
	return ShopCatalog.STYLE_PRICES[if spec.Animated then "Animated" else "Regular"][kind]
end

-- the banners + photocards in the shop right now, in BANNERS order (same on every server)
function ShopCatalog.StyleRotation(time: number?): { any }
	local window = ShopCatalog.RotationWindow(time)
	local pool = {}
	for _, spec in SeasonConstants.BANNERS do
		if ShopCatalog.GetStyle(spec.Id) then
			table.insert(pool, spec)
		end
	end
	local rng = Random.new(window * 104729 + 31)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(ShopCatalog.STYLE_PER_ROTATION, #pool) do
		out[i] = pool[i]
	end
	return out
end

function ShopCatalog.StyleForSale(id: string, time: number?): boolean
	for _, spec in ShopCatalog.StyleRotation(time) do
		if spec.Id == id then
			return true
		end
	end
	return false
end

return ShopCatalog
