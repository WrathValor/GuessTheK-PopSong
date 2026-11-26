--| PlayerData
-- Everything saved per player. Server: PlayerData.Server (.Get / .WaitForData / .Batch).
-- Client: PlayerData.Client (read-only mirror, e.g. PlayerData.Client.Currencies.Won.Observe).
-- New fields are seeded with their defaults for existing players automatically.

--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
				if currency == "Upgrades" then
					-- (card upgrades are gone: a purchase still in flight pays coins)
					data.Currencies.Won.Increment(amount * Currencies.UPGRADE_COINS)
				else
					Currencies.Data(data, currency).Increment(amount)
				end
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

-- the Debut Pack + its starter bonus (ShopCatalog.DebutPack.Bonus): the same pack, plus tickets
do
	local pack = ShopCatalog.DebutPack
	local bonus = pack and pack.Bonus
	if bonus and (bonus.ProductId or 0) > 0 then
		Products[pack.Id .. "Bonus"] = {
			Id = bonus.ProductId,
			Category = "Bundle",
			Grant = function(data)
				if not data.Rewards.Claimed.Has(pack.Id) then
					data.Rewards.Claimed.Add(pack.Id)
				end
				data.Currencies.Won.Increment(pack.Coins)
				Currencies.Data(data, "Tickets").Increment(bonus.Tickets)
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
				if (bundle.Tickets or 0) > 0 then
					Currencies.Data(data, "Tickets").Increment(bundle.Tickets)
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

-- boost potions (ShopCatalog.Boosts): time added to the kind's clock, capped at
-- BOOST_MAX_SECONDS (Engine/BoostService runs the clock down while you play)
for _, boost in ShopCatalog.Boosts do
	if (boost.ProductId or 0) > 0 then
		local kind, seconds = boost.Kind, boost.Seconds
		Products[boost.Id] = {
			Id = boost.ProductId,
			Category = "Boost",
			Grant = function(data)
				local clock = data.Boosts[kind]
				clock.Set(math.min(clock.Get() + seconds, ShopCatalog.BOOST_MAX_SECONDS))
				data.Statistics.BoostsDrunk.Increment(1)
			end,
		}
	end
end

-- pass gifts (ShopCatalog.PassGifts): the pass in-game for whoever they're gifted to
-- (Engine/GiftService opens these with PlayerData.PromptGift; Scribe delivers to the recipient)
for _, gift in ShopCatalog.PassGifts do
	if (gift.ProductId or 0) > 0 then
		local pass = gift.Pass
		Products[gift.Id] = {
			Id = gift.ProductId,
			Category = "PassGift",
			Grant = function(data)
				if not data.GamePasses.Has(pass) then
					data.GamePasses.Add(pass)
				end
			end,
		}
	end
end

-- gift twins (ShopCatalog.GiftProducts): the same Grant as the item, on its own product id,
-- so gifts and ordinary purchases of one item never wait on each other's receipts
for base, id in ShopCatalog.GiftProducts do
	local item = Products[base]
	if item and (id or 0) > 0 then
		Products[base .. ShopCatalog.GIFT_SUFFIX] = {
			Id = id,
			Category = item.Category,
			Grant = item.Grant,
		}
	end
end

--| Template

local PlayerData = Scribe({
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
			-- roll tickets: each opens a free pack (Engine/AlbumService). Upgrades: card upgrades,
			-- gone with the song Index (Currencies.UPGRADE_COINS); kept so old saves still read
			Tickets = Count(),
			Upgrades = Count(),
			Packs = Scribe.SetOf(Id(80)), -- song packs completed (pack ids, see Modules/Library/Packs)
			Songs = Scribe.SetOf(Id(80)), -- songs owned (bought in the shop or pulled from a roll), by Song Id
			-- copies pulled from the song roll, by Song Id (card level: Modules/Library/Cards).
			-- A bought song with no entry counts as 1 copy.
			Copies = Scribe.MapOf("string", Count(), { MaxKeys = 4000, MaxKeyLength = 80 }),
			-- how well you know each song, by Song Id: "plays,rights,fast,best" (Modules/Library/Mastery)
			Mastery = Scribe.MapOf("string", Scribe.String("", { MaxLength = 32 }), { MaxKeys = 4000, MaxKeyLength = 80 }),
			-- group badges (Modules/Library/Ladders): the highest rung paid, by ladder key ("C:aespa",
			-- "S:aespa"; "L:aespa" = 1 once Legend is paid). Kept for good, so a sold card never drops a rung
			Ladders = Scribe.MapOf("string", Count(), { MaxKeys = 400, MaxKeyLength = 64 }),
			DupesInRow = Count(), -- song roll: duplicates since the last new song (RollConstants.PITY)
			DuelPack = Scribe.String("", { MaxLength = 80 }), -- legacy: bias packs are gone (owned songs just count)
			-- K-POPPED! photocards (Modules/Library/Albums, Engine/AlbumService): copies owned, by
			-- card id ("album:member:rarity"). Capped at AlbumConstants.RAINBOW_COPIES.
			Cards = Scribe.MapOf("string", Count(), { MaxKeys = 4000, MaxKeyLength = 80 }),
			-- pinned cards: only these earn binder coins (Engine/BinderService). Card ids in slot
			-- order, "|" between them; AlbumConstants.PIN_SLOTS of PIN_SLOTS_MAX are unlocked.
			Pins = Scribe.String("", { MaxLength = 420 }),
			CardDupes = Count(), -- (unused: album pulls have no new-card pity any more)
			-- your bias, "<Artist>|<member key>" ("" = not picked yet), and when it was last set
			-- (os.time; Engine/BiasService allows one change a week)
			Bias = Scribe.String("", { MaxLength = 80 }),
			BiasAt = Count(),
			-- free photocard packs (Engine/AlbumService, Albums.FreePacks): how many are banked,
			-- when the current refill started (os.time; 0 = never set up: the first ones are
			-- AlbumConstants.FREE_PACK_START), and the UTC day the daily one was last given
			FreePacks = Count(),
			FreePackAt = Count(),
			FreePackDay = Count(),
			-- starred groups ("A|B", AlbumConstants.FAVOURITES_MAX): their group packs are always on
			-- sale. And premium packs opened since the last Signed Polaroid (PREMIUM_GUARANTEE).
			FavGroups = Scribe.String("", { MaxLength = 120 }),
			PremiumPity = Count(),
			-- serial numbers of numbered cards (AlbumConstants rarity Serial = true), by card id:
			-- "3,17", lowest first (Modules/Library/Albums.Serials, Engine/SerialService). Copies
			-- still waiting for a number (the global counter couldn't be reached) are counted in
			-- SerialsPending and get one later.
			Serials = Scribe.MapOf("string", Scribe.String("", { MaxLength = 80 }), { MaxKeys = 2000, MaxKeyLength = 80 }),
			-- when you rolled each card id first, by card id (os.time; Engine/AlbumService). Shown
			-- on the card ("Rolled 25 Nov 2026", a Signed Polaroid's date stamp).
			CardDates = Scribe.MapOf("string", Count(), { MaxKeys = 2500, MaxKeyLength = 80 }),
			SerialsPending = Scribe.MapOf("string", Count(), { MaxKeys = 200, MaxKeyLength = 80 }),
		},

		-- boost potions: seconds of play left on each clock (Engine/BoostService)
		Boosts = {
			Coins = Count(),
			XP = Count(),
		},

		Rewards = {
			DailyStreak = Count(), -- consecutive days claimed
			LastDailyClaim = Count(), -- os.time() of the last daily claim (0 = never)
			Claimed = Scribe.SetOf(Id(40)), -- one-off rewards already collected ("Group", codes…)
			StarterAt = Count(), -- os.time the starter offer began (0 = not yet; ShopCatalog.DebutPack.Bonus)
			Bundles = Scribe.MapOf("string", Count(), { MaxKeys = 20, MaxKeyLength = 20 }), -- times each ShopCatalog.Bundles entry was bought
			-- VIP Pass daily perks (Engine/VIPService): the UTC day (os.time() // 86400) each was last used
			VIPTicketDay = Count(), -- the free roll ticket
			VIPSaveDay = Count(), -- the free Save Streak
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
			-- the binder's earnings clock (Engine/BinderService): coins earned at the old rate when
			-- the binder last changed, in hundredths of a coin, and when the current rate started
			-- (os.time; 0 = no cards yet). Albums.Waiting turns them into coins waiting.
			BinderBank = Count(),
			BinderAt = Count(),
			-- what the one-off K-POPPED! conversion gave (Modules/KPoppedMigration), for the
			-- "Welcome to K-POPPED!" card, and whether that card has been seen
			WelcomeCoins = Count(),
			WelcomeTickets = Count(),
			WelcomeSeen = false,
		},

		-- Invite friends (Engine/ReferralService, Constants/ReferralConstants)
		Referral = {
			Seen = false, -- loaded before: only a player's very first load can come from an invite
			InvitedBy = Id(20), -- UserId of who invited this player, as text ("" = nobody); set once, never changes
			InviterName = Scribe.String("", { MaxLength = 40 }), -- their display name, for the welcome card
			Welcomed = false, -- the "You were invited!" card was collected
			Credited = false, -- this player's first game has been passed on to InvitedBy
			Paid = Scribe.SetOf(Id(20)), -- (inviter) friends' UserIds already paid INVITER_GIFT for: the milestone count
			Claimed = Scribe.SetOf(Id(4)), -- (inviter) milestones claimed, by Key ("1", "3", "5", "10")
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
			-- "Rivals can join my practice" (on by default): solo from the queue card keeps the
			-- stage open, so someone stepping on ends practice after the round and starts a duel
			-- (DuelService)
			SoloOpen = true,
			-- "Low effects": card tiles (binder, All cards, profile, HUD) keep still; a card
			-- opened full size still plays its effects (Modules/UI/CardDecor)
			LowEffects = false,
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
			-- K-POPPED!: the 5 photocards on your profile's showcase, card ids by slot, "|"
			-- between them ("" = an empty slot). Set through ProfileRemote (Engine/ProfileService).
			Cards = Scribe.String("", { MaxLength = 420 }),
		},

		Statistics = {
			PlayTime = Count(), -- seconds
			BoostsDrunk = Count(), -- boost potions bought
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
			-- ghost rival games (DuelService Rewards): finished, won, and today's wins for the daily
			-- taper (GhostWinsToday counts the UTC day in GhostDay, days since 1970)
			GhostGames = Count(),
			GhostWins = Count(),
			GhostWinsToday = Count(),
			GhostDay = Count(),
		},
	},
	Products = if next(Products) then Products else nil,
	-- gifting (Engine/GiftService): no gap between gifts (Roblox's own purchase prompt already
	-- paces them), and a gift that's opened but never paid for stops blocking another of the
	-- same item after 15 minutes instead of an hour
	GiftCooldown = 0,
	GiftIntentTTL = 15 * 60,
	-- lets the Scribe Studio plugin show live data, receipts and gifts while testing
	StudioHook = true,
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

-- Server.Get returns nil while a save is still loading (or has gone), like the callers all
-- expect ("if not data then return"), instead of Scribe's error. The error used to escape from
-- loops that check every player (referral credits, the potion clock), stopping them for the
-- whole server whenever one player's data was slow to load.
-- (a running server only: in edit mode Scribe.Server is a stub that errors when touched)
if RunService:IsServer() and RunService:IsRunning() then
	local server = PlayerData.Server
	if server and not table.isfrozen(server) then
		local get = server.Get
		server.Get = function(player: Player)
			local ok, data = pcall(get, player)
			return if ok then data else nil
		end
	end
end

return PlayerData
