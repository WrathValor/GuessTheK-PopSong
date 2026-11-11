--| Rewards
-- Turns a finished duel into XP, coins, wins and streaks, and returns
-- what each player earned so the results screen can show it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Levels = require(ReplicatedStorage.Modules.Levels)
local DailyQuests = require(script.Parent.Parent.RewardsService) -- Engine/RewardsService
local SeasonService = require(script.Parent.Parent.SeasonService) -- Engine/SeasonService
local Analytics = require(script.Parent.Parent.Analytics) -- Engine/Analytics
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)

local Rewards = {}

-- [[ Same-rival guard ]]
-- duels between the same two players today (UTC), for DuelConstants.SAME_RIVAL_GAMES
local rivalGames: { [string]: number } = {}
local rivalDay = 0

-- counts this duel and returns how many the pair has now played today
local function countRivalGame(a: Player, b: Player): number
	local day = math.floor(os.time() / 86400)
	if day ~= rivalDay then
		rivalDay = day
		table.clear(rivalGames)
	end
	local x, y = a.UserId, b.UserId
	local key = if x < y then `{x}:{y}` else `{y}:{x}`
	rivalGames[key] = (rivalGames[key] or 0) + 1
	return rivalGames[key]
end

local function streakMultiplier(streak: number): number
	for _, row in DuelConstants.STREAK_MULTIPLIERS do
		if streak >= row[1] then
			return row[2]
		end
	end
	return 1
end

export type Earned = {
	XP: number,
	Coins: number,
	CoinsDetail: string,
	Streak: number,
	StreakLost: number, -- streak the player just lost (0 if none), for the Save Streak offer
	Perfect: boolean,
	Outcome: "Win" | "Lose" | "Draw" | "Solo" | "Left",
	Tutorial: boolean?, -- the tutorial's welcome gift was paid this time
	LevelUp: number?, -- the new level, when this match levelled the player up
	NewTitle: string?, -- level title unlocked by that level up (Modules/Levels.TITLES)
	Place: number?, -- Party Stages: where they finished (1 = first)
	PrevBest: number?, -- solo: best score before this run (the results screen's "NEW BEST!" sticker)
	NewBest: boolean?, -- solo: this run beat PrevBest
	XPBefore: number?, -- total XP before this match (the results screen's level bar)
	-- the results screen's Season bar: SP moved by a rated duel (Engine/SeasonService.Rate) and
	-- the Stars it earned. Before / After / Delta are nil when the game wasn't rated.
	Season: { Before: number?, After: number?, Delta: number?, Gap: number?, TierUp: boolean?, TierDown: boolean?, Stars: number }?,
}

-- Analytics for one player's finished game (after the data is written)
local TX = AnalyticsEvents.Transactions
local OUTCOME_TX = { Win = TX.DuelWin, Lose = TX.DuelLoss, Left = TX.DuelLoss, Draw = TX.DuelDraw, Solo = TX.Solo }

function Rewards._log(player: Player, data, result, earned: Earned, correct: number)
	local mode = if result.Solo then "Solo" else result.Mode
	local tx = OUTCOME_TX[earned.Outcome] or TX.Solo
	Analytics.Event(player, "GameFinished", correct, earned.Outcome, mode, if result.Packs then "On" else "Off")
	Analytics.Onboarding(player, "FinishedGame")
	local session = result.Sessions and result.Sessions[player]
	if session then
		Analytics.Funnel(player, if result.Solo then "Solo" else "Duel", session, "Results")
	end
	if earned.Coins > 0 then
		local sku = if earned.Perfect then TX.Perfect else tx
		Analytics.Economy(player, "Source", "Coins", earned.Coins, data.Currencies.Won.Get(), tx, sku)
	end
	if earned.XP > 0 then
		Analytics.Economy(player, "Source", "XP", earned.XP, data.Player.XP.Get(), tx, mode)
	end
	if earned.Perfect then
		Analytics.Event(player, "PerfectGame", 1, mode)
	end
	if earned.Outcome == "Win" and earned.Streak >= 2 then
		Analytics.Event(player, "StreakReached", earned.Streak, if earned.Streak >= 10 then "10+" else tostring(earned.Streak))
	end
	if earned.StreakLost >= 2 then
		Analytics.Event(player, "StreakLost", earned.StreakLost, if earned.StreakLost >= 10 then "10+" else tostring(earned.StreakLost))
	end
	if earned.LevelUp then
		Analytics.Event(player, "LevelUp", earned.LevelUp, earned.NewTitle or "None")
	end
end

function Rewards.Apply(result, players: { Player }): { [Player]: Earned }
	local out = {}
	-- Season Points: 1v1 duels only (solo, the tutorial and party matches aren't rated). Worked
	-- out first, from both players' SP before the duel.
	local rated = if result.Solo or result.Tutorial then {} else SeasonService.Rate(result, players)
	-- same-rival guard: past SAME_RIVAL_GAMES duels today against this rival, coins halve and
	-- wins stop growing the streak
	local farmed, rivalCount = false, 0
	if not result.Solo and not result.Tutorial and #players == 2 then
		rivalCount = countRivalGame(players[1], players[2])
		farmed = rivalCount > DuelConstants.SAME_RIVAL_GAMES
	end
	for _, player in players do
		local ok, data = pcall(PlayerData.Get, player)
		if not ok or not data then
			continue
		end

		-- per-player round stats
		local correct, fastCorrect, ownedHits, answered = 0, 0, 0, 0
		for _, round in result.Rounds do
			local pick = round.Picks[player]
			if pick and pick.Picked ~= nil then
				answered += 1
			end
			if pick and pick.Correct then
				correct += 1
				if round.Owners and round.Owners[player] then
					ownedHits += 1
				end
				if pick.Tier <= DuelConstants.PERFECT_MAX_TIER then
					fastCorrect += 1
				end
			end
		end
		local perfect = correct == DuelConstants.ROUNDS and fastCorrect == DuelConstants.ROUNDS

		local earned: Earned = {
			XP = correct * DuelConstants.XP_CORRECT,
			Coins = 0,
			CoinsDetail = "",
			Streak = data.Player.Streak.Get(),
			StreakLost = 0,
			Perfect = false,
			Outcome = "Solo",
		}

		if result.Solo then
			-- solo practice pays the rolled stake as XP, a seventh of it per right answer (so
			-- clicking through at random isn't worth more than a duel)
			earned.Outcome = "Solo"
			earned.XP = math.floor(result.Stake * correct / DuelConstants.ROUNDS + 0.5)
			-- personal best (full 7-round runs only, so the tutorial can't set one)
			if not result.Tutorial then
				local score = result.Scores[player] or 0
				earned.PrevBest = data.Statistics.SoloBest2.Get()
				earned.NewBest = score > (earned.PrevBest :: number)
			end
			-- the first-join tutorial: a one-time welcome gift
			if result.Tutorial and not data.Rewards.Claimed.Has("Tutorial") then
				earned.Coins = DuelConstants.TUTORIAL_COINS
				earned.CoinsDetail = "Welcome gift"
				earned.Tutorial = true
			end
		elseif result.Leaver == player then
			earned.Outcome = "Left"
			earned.XP = 0
			earned.StreakLost = earned.Streak
			earned.Streak = 0
		elseif result.Draw then
			earned.Outcome = "Draw"
			earned.XP += DuelConstants.XP_LOSE
			earned.Coins = DuelConstants.LOSER_COINS
			earned.CoinsDetail = "Draw"
		elseif result.Winner == player then
			earned.Outcome = "Win"
			if not farmed then
				earned.Streak += 1
			end
			local mult = streakMultiplier(earned.Streak)
			earned.XP += DuelConstants.XP_WIN
			earned.Coins = math.floor(result.Stake * mult + 0.5)
			earned.CoinsDetail = if mult > 1 then `{result.Stake} × {mult}` else `{result.Stake} stake`
		else
			earned.Outcome = "Lose"
			earned.XP += DuelConstants.XP_LOSE
			earned.Coins = DuelConstants.LOSER_COINS
			earned.CoinsDetail = "Loser's share"
			earned.StreakLost = earned.Streak
			earned.Streak = 0
		end

		-- owned-song bonus: guessed a song you own
		if ownedHits > 0 and not result.Solo and earned.Outcome ~= "Left" then
			earned.XP += ownedHits * DuelConstants.OWNED_XP
		end

		if perfect and not result.Solo and earned.Outcome ~= "Left" then
			earned.Perfect = true
			earned.XP += DuelConstants.PERFECT_XP
			earned.Coins += DuelConstants.PERFECT_COINS
			earned.CoinsDetail ..= " + perfect"
		end

		-- same-rival guard (see `farmed` above)
		if farmed and earned.Coins > 0 then
			earned.Coins = math.floor(earned.Coins * DuelConstants.SAME_RIVAL_COIN_SCALE + 0.5)
			earned.CoinsDetail ..= " · same rival ×½"
			Analytics.Event(player, "RivalLimit", rivalCount, earned.Outcome)
		end

		-- AFK guard: no answer in any round = no coins (the base XP still counts)
		if not result.Solo and answered == 0 and earned.Coins > 0 then
			earned.Coins = 0
			earned.CoinsDetail = "No answers, no coins"
		end

		-- 2× Coins pass doubles everything coin-related from a match
		if earned.Coins > 0 and not earned.Tutorial and data.GamePasses.Has("DoubleCoins") then
			earned.Coins *= 2
			earned.CoinsDetail = if earned.CoinsDetail ~= "" then `{earned.CoinsDetail} · 2× pass` else "2× pass"
		end

		-- level up? (the results screen shows it next to the XP)
		earned.XPBefore = data.Player.XP.Get()
		local before = Levels.FromXP(data.Player.XP.Get())
		local after = Levels.FromXP(data.Player.XP.Get() + earned.XP)
		if after > before then
			earned.LevelUp = after
			for _, t in Levels.TITLES do
				if t.Level > before and t.Level <= after then
					earned.NewTitle = t.Title
				end
			end
		end

		-- write it all in one replication flush
		PlayerData.Batch(player, function()
			if earned.XP > 0 then
				data.Player.XP.Increment(earned.XP)
			end
			if earned.Tutorial then
				data.Rewards.Claimed.Add("Tutorial")
				data.Settings.TutorialDone.Set(true)
			end
			if earned.Coins > 0 then
				data.Currencies.Won.Increment(earned.Coins)
				data.Statistics.CoinsEarned.Increment(earned.Coins)
			end
			if correct > 0 then
				data.Statistics.CorrectAnswers.Increment(correct)
			end
			if earned.Perfect then
				data.Statistics.PerfectGames.Increment(1)
			end
			if result.Solo then
				data.Statistics.SoloGames.Increment(1)
				if earned.NewBest then
					data.Statistics.SoloBest2.Set(math.max(0, result.Scores[player] or 0))
				end
			else
				data.Statistics.Duels.Increment(1)
				data.Player.Streak.Set(earned.Streak)
				-- what a Save Streak purchase would give back (cleared by a win or a draw)
				data.Player.LostStreak.Set(earned.StreakLost)
				if earned.Outcome == "Win" then
					data.Statistics.Wins.Increment(1)
					if earned.Streak > data.Statistics.HighestStreak.Get() then
						data.Statistics.HighestStreak.Set(earned.Streak)
					end
				elseif earned.Outcome == "Draw" then
					data.Statistics.Draws.Increment(1)
				else -- "Lose" or "Left"
					data.Statistics.Losses.Increment(1)
				end
			end
		end)

		out[player] = earned
		Rewards._log(player, data, result, earned, correct)

		-- season Stars (Engine/SeasonService): a duel played (+ won), or a solo game; with the SP
		-- the duel moved, for the results screen's Season bar
		local stars = 0
		if result.Solo then
			stars = SeasonService.Award(player, "Solo")
		elseif earned.Outcome ~= "Left" then
			stars = SeasonService.Award(player, "Duel", earned.Outcome == "Win")
		end
		local sp = rated[player]
		earned.Season = {
			Before = sp and sp.Before,
			After = sp and sp.After,
			Delta = sp and sp.Delta,
			Gap = sp and sp.Gap,
			TierUp = sp and sp.TierUp,
			TierDown = sp and sp.TierDown,
			Stars = stars,
		}

		-- daily quest counters (Rewards screen)
		task.spawn(DailyQuests.Record, player, {
			Correct = correct,
			Win = earned.Outcome == "Win",
			Lost = earned.Outcome == "Lose" or earned.Outcome == "Left",
			Solo = result.Solo,
			Perfect = earned.Perfect == true,
		})
	end
	return out
end

-- [[ Party Stages ]]

-- A party match (Engine/PartyService): coins are the rolled pot (result.Stake, already times
-- info.Multiplier for FFA size / custom pool) paid by placement (PAYOUT). XP is the usual per-correct XP plus
-- a win / loss bonus. Nothing for anyone who left, and nothing at all when info.Eligible is
-- false (a custom pool under MIN_POOL_REWARDS songs). Party matches never touch win streaks.
-- info = { Multiplier, Eligible, Kind }
function Rewards.ApplyParty(result, info): { [Player]: Earned }
	local PartyConstants = require(ReplicatedStorage.Constants.PartyConstants)
	local out = {}
	local payout = if info.Kind == "Duel" then PartyConstants.DUEL_PAYOUT else PartyConstants.PAYOUT
	for place, player in result.Placement or {} do
		local ok, data = pcall(PlayerData.Get, player)
		if not ok or not data or not player.Parent then
			continue
		end
		local correct, answered = 0, 0
		for _, round in result.Rounds do
			local pick = round.Picks[player]
			if pick and pick.Picked ~= nil then
				answered += 1
			end
			if pick and pick.Correct then
				correct += 1
			end
		end
		local left = result.Left and result.Left[player] == true
		local earned: Earned = {
			XP = 0,
			Coins = 0,
			CoinsDetail = "",
			Streak = data.Player.Streak.Get(),
			StreakLost = 0,
			Perfect = false,
			Outcome = if left then "Left" elseif place == 1 then "Win" else "Lose",
		}
		earned.Place = place
		if not left and info.Eligible then
			local share = payout[place] or payout[#payout]
			local pot = result.Stake or 0
			earned.Coins = math.floor(pot * share + 0.5)
			earned.CoinsDetail = `{math.floor(share * 100 + 0.5)}% of {pot} pot`
			earned.XP = correct * DuelConstants.XP_CORRECT + (if place == 1 then DuelConstants.XP_WIN else DuelConstants.XP_LOSE)
			-- AFK guard: no answer in any round = no share of the pot (the XP still counts)
			if answered == 0 then
				earned.Coins = 0
				earned.CoinsDetail = "No answers, no coins"
			end
			if earned.Coins > 0 and data.GamePasses.Has("DoubleCoins") then
				earned.Coins *= 2
				earned.CoinsDetail ..= " · 2× pass"
			end
		elseif not left then
			earned.CoinsDetail = `Custom pools need {PartyConstants.MIN_POOL_REWARDS}+ songs to pay out`
		end

		local before = Levels.FromXP(data.Player.XP.Get())
		local after = Levels.FromXP(data.Player.XP.Get() + earned.XP)
		if after > before then
			earned.LevelUp = after
			for _, t in Levels.TITLES do
				if t.Level > before and t.Level <= after then
					earned.NewTitle = t.Title
				end
			end
		end

		PlayerData.Batch(player, function()
			if earned.XP > 0 then
				data.Player.XP.Increment(earned.XP)
			end
			if earned.Coins > 0 then
				data.Currencies.Won.Increment(earned.Coins)
				data.Statistics.CoinsEarned.Increment(earned.Coins)
			end
			if correct > 0 then
				data.Statistics.CorrectAnswers.Increment(correct)
			end
		end)
		out[player] = earned

		local placeName = if left then "Left" else ({ "1st", "2nd", "3rd", "4th", "5th", "6th" })[place] or "6th"
		Analytics.Event(player, "PartyFinished", correct, info.Kind, placeName)
		if earned.Coins > 0 then
			Analytics.Economy(player, "Source", "Coins", earned.Coins, data.Currencies.Won.Get(), TX.Party, info.Kind)
		end
		if earned.XP > 0 then
			Analytics.Economy(player, "Source", "XP", earned.XP, data.Player.XP.Get(), TX.Party, info.Kind)
		end
		if earned.LevelUp then
			Analytics.Event(player, "LevelUp", earned.LevelUp, earned.NewTitle or "None")
		end
		if not left then
			task.spawn(DailyQuests.Record, player, {
				Correct = correct,
				Win = place == 1,
				Lost = false,
				Solo = false,
				Perfect = false,
			})
		end
	end
	return out
end

return Rewards
