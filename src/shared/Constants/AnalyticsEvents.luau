--| AnalyticsEvents
-- Every analytics event the game sends, in one place (Roblox AnalyticsService). Roblox's
-- limits shape this list:
--   • 100 custom event names per experience        → keep NAMES short and reuse them
--   • 3 custom fields per event (breakdowns)        → Fields = the three, in order
--   • ~8,000 field values in all, then "Other"      → no free text, no user ids in fields
--   • economy: 10 currencies, 20 transaction types, 100 item SKUs
--   • 10 funnels, 100 steps each
--   • 120 + 20 × players requests a minute per server (Engine/Analytics rate-limits)
-- Server code logs through Engine/Analytics; the client may only send the events marked
-- Client = true (through AnalyticsRemote), and only with values from Allowed when given.

local AnalyticsEvents = {}

AnalyticsEvents.Custom = {
	-- [[ Rounds + games ]]
	RoundResult = { Fields = { "Song", "Result", "Tier" } }, -- value: seconds to answer (0 = no answer)
	GameFinished = { Fields = { "Outcome", "Mode", "Packs" } }, -- value: correct answers (0-7)
	PerfectGame = { Fields = { "Mode" } },
	SoloStarted = { Fields = { "Theme", "OwnedMix" } },
	StreakReached = { Fields = { "Streak" } }, -- value: new win streak
	StreakLost = { Fields = { "Streak" } }, -- value: the streak that was lost
	LevelUp = { Fields = { "Title" } }, -- value: new level
	OwnedRound = { Fields = { "Whose" } }, -- a round played a song someone in the game owns

	-- [[ Queue ]]
	QueueJoined = { Fields = { "Stage", "How" } },
	MatchFound = { Fields = { "Stage" } }, -- value: seconds waited
	QueueLeft = { Fields = { "Stage", "When" } }, -- value: seconds waited
	RematchRequested = { Fields = { "Mode" } },
	RematchStarted = { Fields = { "Mode" } },
	InviteSent = { Fields = { "Stage" } },
	InviteResult = { Fields = { "Result", "Stage" } }, -- Accepted / Declined / Expired / Cancelled / Failed

	-- [[ Party Stages (Engine/PartyService) ]]
	PartyJoined = { Fields = { "Stage", "How" } }, -- How: Host / Walked / Invite / Request
	PartyStarted = { Fields = { "Kind", "Pool" } }, -- value: players; Kind FFA / Duel; Pool All / Custom
	PartyFinished = { Fields = { "Kind", "Place" } }, -- value: correct answers; Place 1st … / Left

	-- [[ Shop / inventory / rewards ]]
	SongRolled = { Fields = { "Result", "Level", "Count" } }, -- Result New / Duplicate; Count "x1" / "x10"
	Equip = { Fields = { "Kind", "Item" } },
	DailyClaimed = { Fields = { "Day" } }, -- value: coins
	QuestClaimed = { Fields = { "Quest" } }, -- value: coins
	SeasonClaim = { Fields = { "Kind" } }, -- value: milestone number
	CardUpgrade = { Fields = { "Song" } }, -- value: copies after
	TicketRoll = { Fields = { "Group", "Result" } }, -- Result New / Duplicate
	QuestBonusClaimed = {},
	GroupRewardClaimed = {},
	CodeRedeemed = { Fields = { "Code" } }, -- value: coins
	SettingChanged = { Fields = { "Setting", "Value" } },
	BadgeEarned = { Fields = { "Badge" } }, -- Constants/BadgeCatalog Key
	QuestSwapped = { Fields = { "From", "To" } }, -- the daily quest swap
	LevelRewardClaimed = { Fields = { "Level" } }, -- value: coins
	-- a coin purchase in the shop (Engine/ShopService). value: the buyer's level. Kind Set /
	-- Stage / Mic / Banner / Photocard / StyleSet; Rarity Common … Legendary, or Regular /
	-- Animated for banners + photocards
	ItemBought = { Fields = { "Kind", "Rarity", "Item" } },
	-- the first stage / mic / set of a rarity a player has ever bought (value: their level), so
	-- "how long until a first Legendary" is a chart
	FirstOfRarity = { Fields = { "Rarity", "Kind" } },
	-- a Robux purchase prompt closed (Engine/ShopService). Product = the catalog id
	-- (Coins1000, Debut, Tickets5…); Kind Coins / Tickets / Upgrades / Bundle / Pass / Streak
	RobuxPrompt = { Fields = { "Product", "Kind", "Result" } }, -- Result Bought / Cancelled

	-- [[ Economy guards (DuelService/Rewards) ]]
	RivalLimit = { Fields = { "Outcome" } }, -- coins halved by the same-rival guard; value: duels vs them today

	-- [[ From the client ]]
	ScreenOpened = { Fields = { "Screen" }, Client = true, Allowed = {
		Screen = { "Shop", "Roll", "UGC", "Inventory", "Index", "Rewards", "News", "Settings", "Queue", "Results", "SaveStreak", "Tutorial", "Party", "Profile", "PlayerCard" },
	} },
	ShopTabOpened = { Fields = { "Tab" }, Client = true, Allowed = {
		Tab = { "Featured", "Sets", "Items", "Songs", "UGC", "Coins" },
	} },
	SoloPickerOpened = { Client = true },
	-- the Save Streak popup answered (value: the streak on offer); shown = ScreenOpened SaveStreak
	SaveStreakOffer = { Fields = { "Result" }, Client = true, Allowed = {
		Result = { "Bought", "Cancelled", "NoThanks" },
	} },
	GroupJoinPrompt = { Fields = { "Result" }, Client = true, Allowed = {
		Result = { "Joined", "AlreadyMember", "Pending", "Cancelled", "Error" },
	} },
	ClipFailed = { Fields = { "Song", "Reason" }, Client = true, Allowed = {
		Reason = { "NotLoaded", "PastEnd" },
	} }, -- Song is checked against the library on the server
	ClipLoadTime = { Fields = { "Song" }, Client = true }, -- value: seconds until the clip was ready
	UGCPrompt = { Fields = { "Item", "Where" }, Client = true, Allowed = {
		Where = { "Shop", "Reveal", "Results" },
	} }, -- value: Robux price; Item is checked against the group's catalog on the server

	-- [[ Group UGC (Robux, Engine/UGCService) ]]
	UGCBought = { Fields = { "Item", "Kind" } }, -- value: Robux price
}

-- Coins + XP are the "currencies" in the Economy dashboard (TransactionType + Sku below), with
-- Tickets + Upgrades from rewards and Robux bundles. Roblox keeps only 100 SKUs per experience,
-- so SKUs are kinds, not items: shop sinks use the rarity ("Legendary", "Animated"), Robux
-- sources the product kind ("CoinBundle"), the season track "Track". Per-item detail is in the
-- ItemBought / RobuxPrompt events instead.
AnalyticsEvents.Currencies = { Coins = "Coins", XP = "XP", Tickets = "Tickets", Upgrades = "Upgrades" }
AnalyticsEvents.Transactions = {
	-- sources
	DuelWin = "DuelWin",
	DuelLoss = "DuelLoss",
	DuelDraw = "DuelDraw",
	Perfect = "PerfectBonus",
	Solo = "Solo",
	Party = "PartyMatch",
	Daily = "DailyReward",
	Quest = "Quest",
	QuestBonus = "QuestBonus",
	Group = "GroupReward",
	Robux = "RobuxBundle",
	-- sinks
	ShopSet = "ShopSet",
	ShopStage = "ShopStage",
	ShopMic = "ShopMic",
	SeasonTrack = "SeasonTrack", -- (a source: milestone coins)
	ShopStyleSet = "ShopStyleSet", -- banner + photocard together
	ShopStyleBanner = "ShopStyleBanner",
	ShopStylePhotocard = "ShopStylePhotocard",
	ShopSong = "ShopSong",
	ShopPack = "ShopPack",
	Roll = "SongRoll",
	RollRefund = "RollRefund", -- source: coins back for duplicates
}

-- Funnels (10 max). Onboarding uses Roblox's own onboarding funnel.
AnalyticsEvents.Onboarding = {
	"Joined",
	"SteppedOnStage",
	"AnsweredRound",
	"FinishedGame",
	"OpenedShop",
	"BoughtSomething",
	"ClaimedDaily",
}
AnalyticsEvents.Funnels = {
	Duel = { "Queued", "Matched", "Round1", "Round4", "Round7", "Results", "Rematch" },
	Solo = { "PickerOpened", "Started", "Round1", "Round7", "Results", "PlayedAgain" },
	-- one per shop visit: opened the shop → a Robux prompt came up → bought (Engine/ShopService)
	Robux = { "ShopOpened", "Prompted", "Bought" },
}

return AnalyticsEvents
