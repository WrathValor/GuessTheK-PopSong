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
	SoloStarted = { Fields = { "Theme", "PackMix" } },
	StreakReached = { Fields = { "Streak" } }, -- value: new win streak
	StreakLost = { Fields = { "Streak" } }, -- value: the streak that was lost
	LevelUp = { Fields = { "Title" } }, -- value: new level
	SongsDiscovered = { Fields = { "Mode" } }, -- value: new Index entries from one game
	PackRound = { Fields = { "Pack", "Whose" } }, -- a round played a duel-pack song

	-- [[ Queue ]]
	QueueJoined = { Fields = { "Stage", "How" } },
	MatchFound = { Fields = { "Stage" } }, -- value: seconds waited
	QueueLeft = { Fields = { "Stage", "When" } }, -- value: seconds waited
	RematchRequested = { Fields = { "Mode" } },
	RematchStarted = { Fields = { "Mode" } },
	InviteSent = { Fields = { "Stage" } },
	InviteResult = { Fields = { "Result", "Stage" } }, -- Accepted / Declined / Expired / Cancelled / Failed

	-- [[ Shop / inventory / rewards ]]
	Equip = { Fields = { "Kind", "Item" } },
	DuelPackSet = { Fields = { "Pack" } },
	DailyClaimed = { Fields = { "Day" } }, -- value: coins
	QuestClaimed = { Fields = { "Quest" } }, -- value: coins
	QuestBonusClaimed = {},
	GroupRewardClaimed = {},
	SettingChanged = { Fields = { "Setting", "Value" } },

	-- [[ From the client ]]
	ScreenOpened = { Fields = { "Screen" }, Client = true, Allowed = {
		Screen = { "Shop", "Inventory", "Index", "Rewards", "News", "Settings", "Queue", "Results", "SaveStreak", "Tutorial" },
	} },
	ShopTabOpened = { Fields = { "Tab" }, Client = true, Allowed = {
		Tab = { "Featured", "Sets", "Items", "Packs", "UGC", "Coins" },
	} },
	SoloPickerOpened = { Client = true },
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

-- Coins + XP are the "currencies" in the Economy dashboard (TransactionType + Sku below).
AnalyticsEvents.Currencies = { Coins = "Coins", XP = "XP" }
AnalyticsEvents.Transactions = {
	-- sources
	DuelWin = "DuelWin",
	DuelLoss = "DuelLoss",
	DuelDraw = "DuelDraw",
	Perfect = "PerfectBonus",
	Solo = "Solo",
	Daily = "DailyReward",
	Quest = "Quest",
	QuestBonus = "QuestBonus",
	Group = "GroupReward",
	Robux = "RobuxBundle",
	-- sinks
	ShopSet = "ShopSet",
	ShopStage = "ShopStage",
	ShopMic = "ShopMic",
	ShopSong = "ShopSong",
	ShopPack = "ShopPack",
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
}

return AnalyticsEvents
