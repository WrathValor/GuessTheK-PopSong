--| AlbumConstants
-- K-POPPED! photocard tuning (Modules/Library/Albums, Engine/AlbumService, Engine/BinderService,
-- Engine/BiasService). Coins can be bought with Robux, so opening a pack is a paid random item:
-- the Packs page shows these odds before opening, and packs are off for players whose
-- PolicyService says paid random items are restricted (the "RollsAllowed" attribute).
-- Every number here is a starting point to tune from analytics after launch.
--
-- Packs (design board "22 · Packs"), after SHUFFLED:
--   Free pack   1 card from a gen you pick (or any gen). They refill on a clock and bank up to
--               FREE_PACK_CAP, plus one a day for logging in. Roll tickets open one too.
--   Gen pack    PACK_SIZE cards, each from any group in that gen. The MIXES are gen packs over
--               other pools: girl groups, boy groups, every group.
--   Group pack  PACK_SIZE cards from the group you pick; the only pack your bias is
--               BIAS_PULL_WEIGHT× as likely in. Group packs rotate: ROTATION_SIZE groups at a
--               time, new ones every ROTATION_SECONDS (Albums.Rotation, the same for everyone).
--               Your bias's group is always there too, and up to FAVOURITES_MAX groups you star.
--   Premium     PACK_SIZE cards from any group with a rarity floor: every card is CardMin or
--               better and the last is LastMin or better. Coins (or Robux once ProductId is set).
--               Go PREMIUM_GUARANTEE - 1 premium packs without a GUARANTEE_RARITY card and the
--               next one ends with one.
-- A pack's cards are shown worst to best, so the best one is always last.

return table.freeze({
	PACK_SIZE = 5,
	GEN_PACK_COST = 400,
	GROUP_PACK_COST = 1000, -- 2.5× a gen pack: picking exactly who you get costs more
	PACK_COUNTS = table.freeze({ 1, 5, 10 }), -- ×1 / ×5 / ×10 packs at a time (no discount)
	GENERATIONS = table.freeze({ "2nd", "3rd", "4th", "5th" }),
	MIXES = table.freeze({ -- gen packs over other pools (Albums.ArtistsIn), GEN_PACK_COST each
		table.freeze({ Key = "Girl", Name = "Girl groups" }),
		table.freeze({ Key = "Boy", Name = "Boy groups" }),
		table.freeze({ Key = "All", Name = "Full Shuffle" }),
	}),
	FAVOURITES_MAX = 2, -- starred groups (Inventory.FavGroups), always on sale like your bias's
	-- premium packs (design board "26 · Packs v3", K-pop names for SHUFFLED's Gold / Prism /
	-- Obsidian). CardMin / LastMin are rarity keys. ProductId 0 = no Robux button yet.
	PREMIUM_PACKS = table.freeze({
		table.freeze({ Key = "photobook", Name = "Photobook Pack", Short = "PHOTOBOOK", Cost = 2500, CardMin = "standard", LastMin = "store", Colour = "FFE07A", ProductId = 0, Robux = 24 }),
		table.freeze({ Key = "limited", Name = "Limited Edition", Short = "LIMITED", Cost = 10000, CardMin = "selca", LastMin = "luckydraw", Colour = "DCD3FF", ProductId = 0, Robux = 80 }),
		table.freeze({ Key = "fansign", Name = "Fansign Event", Short = "FANSIGN", Cost = 250000, CardMin = "store", LastMin = "fansign", Colour = "FBF7F0", ProductId = 0 }),
	}),
	PREMIUM_GUARANTEE = 100,
	GUARANTEE_RARITY = "polaroid",
	ROTATION_SIZE = 6, -- group packs on sale at a time (plus your bias's group)
	ROTATION_SECONDS = 24 * 3600, -- they change at midnight UTC
	FREE_PACK_SECONDS = 2 * 3600, -- one free pack refills this often (the Refill upgrade: −5 min a level)
	FREE_PACK_CAP = 3, -- free packs bank up to this many: 6 h of refills (the clock stops while full; the Stash upgrade: +1 a level, to 9). Was 6; the daily pack can go one over
	FREE_PACK_START = 3, -- a new player's first free packs
	FREE_OPEN_MAX = 10, -- "Open all" opens up to this many free packs at once
	FIRST_ALBUM_KEY = "FirstAlbum", -- Rewards.Claimed key: the free group pack after the bias pick is used

	-- Rarities, worst to best. Key is saved in card ids (album:member:rarity), so never rename one.
	--   Odds   chance per pull (they add up to 1 across the live rarities)
	--   Earn   binder coins an hour at Normal level, before bias
	--   Sell   coins for selling one copy (and for each copy pulled past Rainbow)
	--   Announce = true: PullChat tells the server
	--   Serial = true: every copy pulled gets a serial number, counted per card id across every
	--            server (Engine/SerialService): "#1" is the first one anyone ever pulled
	-- One of One: one copy of each card id in the whole game (Engine/SerialService claims it).
	-- When a member's One of One is already owned, the pull lands on FALLBACK_RARITY instead.
	RARITIES = table.freeze({
		table.freeze({ Key = "standard", Name = "Standard", Odds = 0.55, Earn = 6, Sell = 10, Live = true }),
		table.freeze({ Key = "selca", Name = "Selca", Odds = 0.25, Earn = 12, Sell = 20, Live = true }),
		table.freeze({ Key = "store", Name = "Store Benefit", Odds = 0.12, Earn = 18, Sell = 40, Live = true }),
		table.freeze({ Key = "luckydraw", Name = "Lucky Draw", Odds = 0.0545, Earn = 35, Sell = 100, Live = true, Announce = true }),
		table.freeze({ Key = "fansign", Name = "Fansign Benefit", Odds = 0.02, Earn = 70, Sell = 250, Live = true, Announce = true, Serial = true }),
		table.freeze({ Key = "polaroid", Name = "Signed Polaroid", Odds = 0.005, Earn = 175, Sell = 800, Live = true, Announce = true, Serial = true }),
		table.freeze({ Key = "oneofone", Name = "One of One", Odds = 0.0005, Earn = 475, Live = true, Announce = true, Unsellable = true, Serial = true }),
	}),
	-- where a rarity that isn't live (or a claimed One of One) lands instead
	FALLBACK_RARITY = "polaroid",
	-- Engine/SerialService's DataStores (shared by every server) and the One of One broadcast
	SERIAL_STORE = "CardSerials_v1", -- card id → serials handed out so far
	ONE_OF_ONE_STORE = "OneOfOne_v1", -- card id → { UserId, Name, At } of its owner
	-- a numbered copy's history: "<card id>#<serial>" → { Rolled = owner, Owners = { owner, … } },
	-- owner = { UserId, Name, At }, oldest first (Engine/SerialService.Record / Transfer / History)
	HISTORY_STORE = "CardHistory_v1",
	HISTORY_OWNERS_MAX = 20, -- owners kept per copy (the roller is always kept)
	ONE_OF_ONE_TOPIC = "OneOfOne", -- MessagingService: tell every server when one is pulled
	-- (and Signed Polaroids: these rarities are announced in every server, not just this one)
	GLOBAL_RARITIES = table.freeze({ polaroid = true, oneofone = true }),
	-- album ids that were renamed, old → new. Saved cards move to the new id on join
	-- (Engine/SerialService), and serial / One of One counters stay under the old id so the
	-- numbers carry on (Albums.StoreKey). Never reuse an old id for another album.
	RENAMED_ALBUMS = table.freeze({
		["enhypen-border"] = "enhypen-romance-untold",
		["lesserafim-antifragile"] = "lesserafim-pureflow",
		["seventeen-al1"] = "seventeen-fml",
		["itzy-crazy-in-love"] = "itzy-gold",
		["aespa-armageddon"] = "aespa-lemonade",
		["twice-twicetagram"] = "twice-with-youth",
		["snsd-oh"] = "snsd-forever-1",
		["shinee-lucifer"] = "shinee-atmos",
		["redvelvet-perfect-velvet"] = "redvelvet-cosmic",
		["exo-the-war"] = "exo-exact",
		["nmixx-fe3o4-break"] = "nmixx-blue-valentine",
		["straykids-noeasy"] = "straykids-this-and-that",
		["got7-flight-log-arrival"] = "got7-dye",
		["ive-ive-ive"] = "ive-looks-can-kill",
		["kiiikiii-uncut-gem"] = "kiiikiii-delulu-pack",
		["blackpink-in-your-area"] = "blackpink-born-pink",
		["ikon-return"] = "ikon-take-off",
	}),

	-- card levels, by copies of one card id (same rule as songs: Modules/Library/Cards)
	GOLD_COPIES = 3,
	RAINBOW_COPIES = 5, -- copies stop here: each one past it is sold automatically
	LEVEL_EARN = table.freeze({ Normal = 1, Gold = 2, Rainbow = 4 }),

	-- bias (Engine/BiasService): a group, then one member
	BIAS_PULL_WEIGHT = 2, -- your bias's cards are this many times as likely in their group's packs
	BIAS_EARN = 1.5, -- and earn this much more in the binder
	BIAS_CHANGE_SECONDS = 7 * 24 * 3600, -- you can change it once a week

	-- the binder (Engine/BinderService): your PINNED cards earn coins an hour (rarity Earn × level
	-- × bias), while you're away too (at OFFLINE_EARN of the rate), up to BINDER_CAP_SECONDS of it.
	-- Economy model: assets/KPOPPED_Economy.xlsx (rates and sell values set Nov 2026). Everyone has PIN_SLOTS
	-- slots; the Slots upgrade unlocks the other PIN_SLOTS_MAX - PIN_SLOTS (Modules/Library/Upgrades).
	BINDER_CAP_SECONDS = 6 * 3600, -- the base: the Storage upgrade adds 30 min a level, up to 12 h (Modules/Library/Upgrades)
	OFFLINE_EARN = 0.5, -- pins earn at this share of their rate while you're offline
	ONLINE_BANK_SECONDS = 60, -- online players' earnings are banked at full rate this often
	PIN_SLOTS = 3,
	PIN_SLOTS_MAX = 5,
	-- owning every member of an album (any rarity) pays once: this many coins a member
	SET_BONUS_PER_MEMBER = 200,
	SET_KEY = "Set:",
	-- the profile showcase: this many photocards everyone sees (Profile.Cards)
	SHOWCASE_SLOTS = 5, -- Rewards.Claimed key prefix for a paid set bonus ("Set:<album id>")
})
