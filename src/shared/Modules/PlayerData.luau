--| PlayerData
-- Everything saved per player. Server: PlayerData.Server (.Get / .WaitForData / .Batch).
-- Client: PlayerData.Client (read-only mirror, e.g. PlayerData.Client.Currencies.Won.Observe).
-- New fields are seeded with their defaults for existing players automatically.

--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports

local Scribe = require(ReplicatedStorage.Packages.scribe)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local DataMigrations = require(script.Parent.DataMigrations)

--| Helpers

local function Id(maxLength: number?)
	return Scribe.String("", { MaxLength = maxLength or 40 })
end

local function Count()
	return Scribe.Int(0, { Min = 0 })
end

--| Products (developer products, granted through Scribe's receipt handling)
-- Grants run inside a transaction and must not yield.

local Products = {}
if (DuelConstants.SAVE_STREAK_PRODUCT_ID or 0) > 0 then
	Products.SaveStreak = {
		Id = DuelConstants.SAVE_STREAK_PRODUCT_ID,
		Category = "Streak",
		Grant = function(data)
			-- give back the streak lost in the last duel (the loss itself still counts)
			local lost = data.Player.LostStreak.Get()
			if lost > data.Player.Streak.Get() then
				data.Player.Streak.Set(lost)
			end
			data.Player.LostStreak.Set(0)
			data.Statistics.StreaksSaved.Increment(1)
		end,
	}
end

-- coin bundles bought with Robux
for _, bundle in ShopCatalog.CoinBundles do
	if (bundle.ProductId or 0) > 0 then
		local amount = bundle.Amount
		Products[bundle.Id] = {
			Id = bundle.ProductId,
			Category = "Coins",
			Grant = function(data)
				data.Currencies.Won.Increment(amount)
			end,
		}
	end
end

-- roll tickets + card upgrades bought with Robux (ShopCatalog.RollBundles)
for _, bundle in ShopCatalog.RollBundles do
	if (bundle.ProductId or 0) > 0 then
		local amount, currency = bundle.Amount, bundle.Currency
		Products[bundle.Id] = {
			Id = bundle.ProductId,
			Category = currency,
			Grant = function(data)
				Currencies.Data(data, currency).Increment(amount)
			end,
		}
	end
end

-- the one-time Debut Pack (ShopCatalog.DebutPack)
do
	local pack = ShopCatalog.DebutPack
	if pack and (pack.ProductId or 0) > 0 then
		Products[pack.Id] = {
			Id = pack.ProductId,
			Category = "Bundle",
			Grant = function(data)
				if not data.Rewards.Claimed.Has(pack.Id) then
					data.Rewards.Claimed.Add(pack.Id)
				end
				data.Currencies.Won.Increment(pack.Coins)
				if pack.Stage and not data.Inventory.Stages.Has(pack.Stage) then
					data.Inventory.Stages.Add(pack.Stage)
				end
				if pack.Mic and not data.Inventory.Mics.Has(pack.Mic) then
					data.Inventory.Mics.Add(pack.Mic)
				end
			end,
		}
	end
end

-- bundles: tickets + upgrades + coins, and the Headliner's stage + mic (ShopCatalog.Bundles)
for _, bundle in ShopCatalog.Bundles do
	if (bundle.ProductId or 0) > 0 then
		Products[bundle.Id] = {
			Id = bundle.ProductId,
			Category = "Bundle",
			Grant = function(data)
				data.Rewards.Bundles[bundle.Id].Increment(1) -- (the shop stops at bundle.Limit)
				for _, kind in { "Tickets", "Upgrades" } do
					if (bundle[kind] or 0) > 0 then
						Currencies.Data(data, kind).Increment(bundle[kind])
					end
				end
				if (bundle.Coins or 0) > 0 then
					data.Currencies.Won.Increment(bundle.Coins)
				end
				if bundle.Stage and not data.Inventory.Stages.Has(bundle.Stage) then
					data.Inventory.Stages.Add(bundle.Stage)
				end
				if bundle.Mic and not data.Inventory.Mics.Has(bundle.Mic) then
					data.Inventory.Mics.Add(bundle.Mic)
				end
			end,
		}
	end
end

--| Template

return Scribe({
	Template = {
		Player = {
			XP = Count(), -- level is worked out from XP (Modules/Levels)
			Streak = Count(), -- current win streak
			LostStreak = Count(), -- streak lost in the last duel; what Save Streak restores (0 = nothing to save)
		},

		-- the current season (Engine/SeasonService; Constants/SeasonConstants). A new SEASON.Id
		-- starts the track over.
		Season = {
			Id = Scribe.String("", { MaxLength = 20 }),
			Stars = Count(),
			Claimed = Count(), -- milestones claimed (always the first n)
			Duels = Count(),
			Wins = Count(),
			Day = Count(), -- UTC day the daily counts below are for
			DuelsToday = Count(),
			QuestsToday = Count(),
			SoloToday = Count(),
			SP = Count(), -- Season Points: ranked duels move it (Engine/SeasonService.Rate)
			PeakSP = Count(), -- highest SP this season: season-end rewards go by this
			History = Scribe.MapOf("string", Count(), { MaxKeys = 100, MaxKeyLength = 20 }), -- season id → peak SP, kept when a season ends
		},

		Currencies = {
			Won = Count(), -- coins
		},

		Inventory = {
			Title = Scribe.String(""), -- equipped title shown on the HUD ("" = default)
			Titles = Scribe.SetOf(Id(40)), -- titles unlocked
			-- set titles' tier, by title: 2 = Gold, 3 = Rainbow (no entry = Normal). Only goes up
			-- (Engine/Collection, Modules/Library/Cards.SetLevel)
			TitleTiers = Scribe.MapOf("string", Count(), { MaxKeys = 200, MaxKeyLength = 40 }),
			Index = Scribe.SetOf(Id(80)), -- legacy: songs guessed correctly (the Index is owned songs now)
			Sets = Scribe.SetOf(Id(40)), -- stage sets owned (each also unlocks its stage + mic piece)
			EquippedSet = Scribe.String("Default", { MaxLength = 40 }), -- legacy: last set equipped as a whole
			Stages = Scribe.SetOf(Id(40)), -- stages owned (bought in Items, or a set's piece), by ShopCatalog id
			Mics = Scribe.SetOf(Id(40)), -- mic stands owned, same
			EquippedStage = Scribe.String("Default", { MaxLength = 40 }),
			EquippedMic = Scribe.String("Default", { MaxLength = 40 }),
			-- profile style (Constants/SeasonConstants): banners + photocards owned (bought in the
			-- shop as halves or sets, or earned) and the ones worn ("" = the default)
			Banners = Scribe.SetOf(Id(40)),
			Photocards = Scribe.SetOf(Id(40)),
			Banner = Scribe.String("", { MaxLength = 40 }),
			Photocard = Scribe.String("", { MaxLength = 40 }),
			-- Season Track rewards waiting to be used: a free roll from one group (RollService) and
			-- +1 copy on a card of your choice (Engine/SeasonService UseUpgrade)
			Tickets = Count(),
			Upgrades = Count(),
			Packs = Scribe.SetOf(Id(80)), -- song packs completed (pack ids, see Modules/Library/Packs)
			Songs = Scribe.SetOf(Id(80)), -- songs owned (bought in the shop or pulled from a roll), by Song Id
			-- copies pulled from the song roll, by Song Id (card level: Modules/Library/Cards).
			-- A bought song with no entry counts as 1 copy.
			Copies = Scribe.MapOf("string", Count(), { MaxKeys = 4000, MaxKeyLength = 80 }),
			DupesInRow = Count(), -- song roll: duplicates since the last new song (RollConstants.PITY)
			DuelPack = Scribe.String("", { MaxLength = 80 }), -- legacy: bias packs are gone (owned songs just count)
		},

		Rewards = {
			DailyStreak = Count(), -- consecutive days claimed
			LastDailyClaim = Count(), -- os.time() of the last daily claim (0 = never)
			Claimed = Scribe.SetOf(Id(40)), -- one-off rewards already collected ("Group", codes…)
			Bundles = Scribe.MapOf("string", Count(), { MaxKeys = 20, MaxKeyLength = 20 }), -- times each ShopCatalog.Bundles entry was bought
			-- daily quests (Constants/RewardsCatalog): counters for QuestDay only, reset each UTC day
			QuestDay = Count(),
			Quest = {
				Correct = Count(),
				Wins = Count(),
				WinRun = Count(), -- current run of wins today
				BestRun = Count(), -- longest run of wins today
				Duels = Count(),
				Solo = Count(),
				Perfect = Count(),
				NewSongs = Count(),
				DailySong = Count(), -- Daily Songs solved
			},
			QuestClaimed = Scribe.SetOf(Id(20)), -- quest Ids claimed today, plus "Bonus"
			-- today's one quest swap (RewardsCatalog.DailyQuests): the quest swapped out and in
			-- ("" = no swap yet today). Cleared with the day.
			QuestSwapFrom = Id(20),
			QuestSwapTo = Id(20),
			-- weekly quests (RewardsCatalog.WeeklyFor): counters for QuestWeek only, reset Mondays
			QuestWeek = Scribe.Int(0), -- (week numbers can be negative in theory; Count() can't)
			WeekQuest = {
				Correct = Count(),
				Wins = Count(),
				WinRun = Count(),
				BestRun = Count(),
				Duels = Count(),
				Solo = Count(),
				Perfect = Count(),
				NewSongs = Count(),
				DailySong = Count(), -- Daily Songs solved this week
			},
			WeekClaimed = Scribe.SetOf(Id(20)), -- weekly quest Ids claimed this week, plus "Bonus"
			LevelClaimed = Scribe.SetOf(Id(8)), -- level rewards claimed (RewardsCatalog.LEVEL_REWARDS), as "5", "10"…
		},

		-- the Daily Song (Engine/DailySongService): today's play, kept for Day only, and the streak.
		-- The answer itself is never saved here, only what was guessed.
		DailySong = {
			Day = Count(), -- UTC day (RewardsCatalog.Day) the play below is for (0 = never played)
			Guesses = Scribe.ArrayOf(Id(80), { MaxItems = 5 }), -- song Ids guessed in order, "" = a skip
			Solved = false,
			Done = false, -- solved, or out of tries
			Streak = Count(), -- days solved in a row (DailySongService shows 0 once a day is missed)
			Best = Count(), -- longest streak
			LastSolved = Count(), -- UTC day last solved (0 = never)
			Played = Count(), -- days finished, all time
			Wins = Count(), -- days solved, all time
		},

		Settings = {
			MusicVolume = Scribe.Number(1, { Min = 0, Max = 1 }),
			SfxVolume = Scribe.Number(1, { Min = 0, Max = 1 }),
			ClipVolume = Scribe.Number(1, { Min = 0, Max = 1 }), -- round snippets + the reveal song
			DuelInvites = true, -- false = other players can't send this player duel invites
			NewsSeen = Scribe.String("", { MaxLength = 40 }), -- Id of the newest News entry opened
			-- solo practice with a duel pack on: "Mix" (its songs that fit the theme mix in) or "Off"
			SoloPool = Scribe.String("Mix", { MaxLength = 8 }),
			-- the last solo theme picked on the queue card (Modules/Library/Themes ids)
			SoloTheme = Scribe.String("All", { MaxLength = 12 }),
			TutorialDone = false, -- finished or skipped the first-join tutorial
			FavoritePrompted = false, -- shown the one-time "favourite the game" prompt (Client/FavoritePrompt)
			Hints = Scribe.SetOf(Id(16)), -- one-time hints already seen: lobby nudges ("Money", "Rewards") + screen guides ("Guide…")
		},

		GamePasses = Scribe.SetOf(Id(32)),

		-- the Profile screen (InterfaceController/Controllers/ProfileController)
		Profile = {
			-- the 5 song cards pinned to the showcase, by Song Id ("" = empty slot; all empty =
			-- your best 5 are shown). Set through ProfileRemote (Engine/ProfileService).
			Showcase = { S1 = Id(80), S2 = Id(80), S3 = Id(80), S4 = Id(80), S5 = Id(80) },
			-- a Rainbow card played as your background music, by Song Id ("" = the game's own
			-- playlist). Set through ProfileRemote (Engine/ProfileService).
			BgMusic = Id(80),
		},

		Statistics = {
			PlayTime = Count(), -- seconds
			Duels = Count(), -- 1v1 duels finished (not solo)
			Wins = Count(),
			Losses = Count(),
			Draws = Count(),
			SoloGames = Count(),
			SoloBest = Count(), -- legacy: best solo score on the old 10/7/5/2/1 scale (out of 70)
			-- best solo practice score on the 6/5/4/2/1 + ENCORE scale (7 rounds, not the tutorial).
			-- A fresh stat so old bests out of 70 don't sit out of reach.
			SoloBest2 = Count(),
			HighestStreak = Count(),
			-- your all-time record against each rival, by their userId: "wins.losses.last5.time"
			-- (Engine/RivalRecord keeps the 100 most recent)
			Rivals = Scribe.MapOf("string", Scribe.String("", { MaxLength = 40 }), { MaxKeys = 110, MaxKeyLength = 20 }),
			StreaksSaved = Count(),
			CorrectAnswers = Count(),
			PerfectGames = Count(),
			CoinsEarned = Count(), -- lifetime coins from duels
			SuspectGames = Count(), -- duels flagged by Scoring.Suspect (DuelConstants.SUSPECT_*); nothing reads it but the stats command
		},
	},
	Products = if next(Products) then Products else nil,
	-- The map signs (client/Client/Leaderboards). Scribe writes, reads and replicates them;
	-- the client reads PlayerData.Client.GetLeaderboard(name) / OnLeaderboard.
	-- Limit 100: the signs show the top 10, the rest is there so each player's own place
	-- (the YOU row) is known inside the top 100.
	Leaderboards = {
		MostWins = { Stat = "Statistics.Wins", Replicate = true, Limit = 100 }, -- all time
		TopStreaks = { Stat = "Statistics.HighestStreak", Replicate = true, Limit = 100 },
		PerfectGames = { Stat = "Statistics.PerfectGames", Replicate = true, Limit = 100 },
		MostAnswers = { Stat = "Statistics.CorrectAnswers", Replicate = true, Limit = 100 }, -- all time
		TopFans = { Stat = "Player.XP", Replicate = true, Limit = 100 }, -- shown as a level (Modules/Levels)
	},
	-- one-off fixes to old saves, run once per profile on load (Modules/DataMigrations)
	Migrations = DataMigrations,
	ProfileStoreIndex = "PlayerDataV2", -- required: your DataStore name
	ProfileKeyPrefix = "PLAYER_",
	Mode = "Live",
})
