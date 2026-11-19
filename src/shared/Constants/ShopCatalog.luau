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
-- three bundles of each, left to right. Currency is a Constants/Currencies id. A bundle whose
-- ProductId is still 0 shows "Soon" and can't be bought; Hidden ones aren't shown but still
-- grant (like CoinBundles). Bought ones show the purchase reveal (PurchasedController).
ShopCatalog.RollBundles = {
	{ Id = "Tickets1", Currency = "Tickets", Amount = 1, ProductId = 3730112610 },
	{ Id = "Tickets5", Currency = "Tickets", Amount = 5, ProductId = 3730112632, Tag = "POPULAR" },
	{ Id = "Tickets12", Currency = "Tickets", Amount = 12, ProductId = 3730112656, Tag = "BEST VALUE" },
	{ Id = "Upgrades1", Currency = "Upgrades", Amount = 1, ProductId = 3730112680 },
	{ Id = "Upgrades5", Currency = "Upgrades", Amount = 5, ProductId = 3730112697, Tag = "POPULAR" },
	{ Id = "Upgrades12", Currency = "Upgrades", Amount = 12, ProductId = 3730112726, Tag = "BEST VALUE" },
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
	Bonus = { ProductId = 3732070614, Tickets = 3, Hours = 48 },
}

-- Bundles: Robux packs of roll tickets, card upgrades and coins ("Shop v3 · Bundles" board).
-- Big = the featured one: drawn like the Debut Pack, at the very top of the shop; the rest
-- are the shorter banners under the Debut Pack, in the "Bundles" section.
-- Stage / Mic = a set only that bundle gives (their Reward is the bundle's Id). Limit = how
-- many times one player can buy it (Rewards.Bundles counts them; the banner shows "n/Limit
-- left"). Hidden behind "Soon" while ProductId is 0. Gradient = the banner's two colours.
-- Hidden = off the shop (still grants, so a purchase already in flight pays out).
ShopCatalog.Bundles = {
	{ Id = "Headliner", Name = "Headliner", Sub = "Spotlight Stage + Mic, only here", ProductId = 3730244515, Big = true, Limit = 1,
		Tag = "FEATURED", TagColour = "FF5A4E", Gradient = { "D8F6F2", "FFE3DE" }, -- the Spotlight set's teal → coral
		Stage = "SpotlightStage", Mic = "SpotlightMic", Tickets = 15, Upgrades = 10, Coins = 6000 },
	{ Id = "WarmUp", Name = "Warm-up", Sub = "A few rolls to get going", ProductId = 3730244340, Limit = 2,
		Gradient = { "F1ECFF", "FFFFFF" }, Tickets = 3, Upgrades = 1, Coins = 500 },
	{ Id = "Practice", Name = "Practice", Sub = "Rolls + upgrades for your sets", ProductId = 3730244371, Limit = 2,
		Tag = "POPULAR", TagColour = "FFE07A", Gradient = { "FFE4EF", "FFF6F3" }, Tickets = 6, Upgrades = 3, Coins = 1500 },
	{ Id = "Comeback", Name = "Comeback", Sub = "Back in the game, fully stocked", ProductId = 3730244488, Limit = 2, Hidden = true,
		Gradient = { "E3F3FC", "F4FBFF" }, Tickets = 10, Upgrades = 6, Coins = 4000 },
}
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

-- What a bundle's banner shows, in order: its stage + mic, then tickets, upgrades, coins.
-- { Kind = "Stage" | "Mic" | "Tickets" | "Upgrades" | "Coins", Id?, Amount? }
function ShopCatalog.BundleContents(bundle): { any }
	local out = {}
	if bundle.Stage then
		table.insert(out, { Kind = "Stage", Id = bundle.Stage })
	end
	if bundle.Mic then
		table.insert(out, { Kind = "Mic", Id = bundle.Mic })
	end
	for _, kind in { "Tickets", "Upgrades", "Coins" } do
		if (bundle[kind] or 0) > 0 then
			table.insert(out, { Kind = kind, Amount = bundle[kind] })
		end
	end
	return out
end

ShopCatalog.Passes = {
	{ Id = "DoubleCoins", Name = "2× Coins", Sub = "Double coins from every match, forever", Line = "Double coins from\nevery match!", GamePassId = 2063766272, Bg = "9ED8F5", Icon = "2×" },
	-- (the daily perks are Engine/VIPService's; the looks are NameTags, VIPChat and the ★ VIP chips)
	{ Id = "VIP", Name = "VIP Pass", Title = "VIP!", Sub = "Gold name tag · daily free ticket + Save Streak", Line = "Gold name tag, daily\nrewards & more!", GamePassId = 2063596588, Bg = "FFE07A", Icon = "Crown",
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
ShopCatalog.Boosts = {
	{ Id = "CoinsSmall", Kind = "Coins", Seconds = 30 * 60, ProductId = pick(3733529669, 3733232797), Image = "rbxassetid://120664233001275" },
	{ Id = "CoinsBig", Kind = "Coins", Seconds = 2 * 60 * 60, ProductId = pick(3733529934, 3733232856), Image = "rbxassetid://90605715561632", Best = true },
	{ Id = "XPSmall", Kind = "XP", Seconds = 30 * 60, ProductId = pick(3733529678, 3733232866), Image = "rbxassetid://93064684252304" },
	{ Id = "XPBig", Kind = "XP", Seconds = 2 * 60 * 60, ProductId = pick(3733529688, 3733232874), Image = "rbxassetid://86807835649616", Best = true },
}
ShopCatalog.BOOST_KINDS = { Coins = { Name = "2× Coins", Colour = "FFD23F" }, XP = { Name = "2× XP", Colour = "B9A6FF" } }

function ShopCatalog.GetBoost(id: string)
	for _, boost in ShopCatalog.Boosts do
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
}

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
			return if b.Currency == "Tickets" then `{b.Amount} roll ticket{if b.Amount == 1 then "" else "s"}` else `{b.Amount} card upgrade{if b.Amount == 1 then "" else "s"}`
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
	for _, b in ShopCatalog.Boosts do
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
