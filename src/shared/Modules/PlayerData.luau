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

--| Template

return Scribe({
	Template = {
		Player = {
			XP = Count(), -- level is worked out from XP (Modules/Levels)
			Streak = Count(), -- current win streak
			LostStreak = Count(), -- streak lost in the last duel; what Save Streak restores (0 = nothing to save)
		},

		Currencies = {
			Won = Count(), -- coins
		},

		Inventory = {
			Title = Scribe.String(""), -- equipped title shown on the HUD ("" = default)
			Titles = Scribe.SetOf(Id(40)), -- titles unlocked
			-- songs guessed correctly at least once (the Index collection), by Song Id
			Index = Scribe.SetOf(Id(80)),
			Sets = Scribe.SetOf(Id(40)), -- stage sets owned (each also unlocks its stage + mic piece)
			EquippedSet = Scribe.String("Default", { MaxLength = 40 }), -- legacy: last set equipped as a whole
			Stages = Scribe.SetOf(Id(40)), -- stages owned (bought in Items, or a set's piece), by ShopCatalog id
			Mics = Scribe.SetOf(Id(40)), -- mic stands owned, same
			EquippedStage = Scribe.String("Default", { MaxLength = 40 }),
			EquippedMic = Scribe.String("Default", { MaxLength = 40 }),
			Packs = Scribe.SetOf(Id(80)), -- song packs completed (pack ids, see Modules/Library/Packs)
			Songs = Scribe.SetOf(Id(80)), -- songs bought in the shop, by Song Id (My Pack)
			-- pack mixed into duels ("" = off): "My", "Company:HYBE", "Group:BTS"…
			DuelPack = Scribe.String("", { MaxLength = 80 }),
		},

		Rewards = {
			DailyStreak = Count(), -- consecutive days claimed
			LastDailyClaim = Count(), -- os.time() of the last daily claim (0 = never)
			Claimed = Scribe.SetOf(Id(40)), -- one-off rewards already collected ("Group", codes…)
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
			},
			QuestClaimed = Scribe.SetOf(Id(20)), -- quest Ids claimed today, plus "Bonus"
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
		},

		GamePasses = Scribe.SetOf(Id(32)),

		Statistics = {
			PlayTime = Count(), -- seconds
			Duels = Count(), -- 1v1 duels finished (not solo)
			Wins = Count(),
			Losses = Count(),
			Draws = Count(),
			SoloGames = Count(),
			HighestStreak = Count(),
			StreaksSaved = Count(),
			CorrectAnswers = Count(),
			PerfectGames = Count(),
			CoinsEarned = Count(), -- lifetime coins from duels
		},
	},
	Products = if next(Products) then Products else nil,
	ProfileStoreIndex = "PlayerData", -- required: your DataStore name
	ProfileKeyPrefix = "PLAYER_",
	Mode = "Live",
})
