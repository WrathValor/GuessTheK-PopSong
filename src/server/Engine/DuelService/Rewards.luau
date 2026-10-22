--| Rewards
-- Turns a finished duel into XP, coins, wins, streaks and Index entries, and returns
-- what each player earned so the results screen can show it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server

local Rewards = {}

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
	IndexNew: number,
	Perfect: boolean,
	Outcome: "Win" | "Lose" | "Draw" | "Solo" | "Left",
}

function Rewards.Apply(result, players: { Player }): { [Player]: Earned }
	local out = {}
	for _, player in players do
		local ok, data = pcall(PlayerData.Get, player)
		if not ok or not data then
			continue
		end

		-- per-player round stats
		local correct, fastCorrect = 0, 0
		local songs = {}
		for _, round in result.Rounds do
			local pick = round.Picks[player]
			if pick and pick.Correct then
				correct += 1
				if pick.Tier <= DuelConstants.PERFECT_MAX_TIER then
					fastCorrect += 1
				end
				table.insert(songs, round.Song.Id)
			end
		end
		local perfect = correct == DuelConstants.ROUNDS and fastCorrect == DuelConstants.ROUNDS

		local earned: Earned = {
			XP = correct * DuelConstants.XP_CORRECT,
			Coins = 0,
			CoinsDetail = "",
			Streak = data.Player.Streak.Get(),
			StreakLost = 0,
			IndexNew = 0,
			Perfect = false,
			Outcome = "Solo",
		}

		if result.Solo then
			-- solo practice pays the rolled stake as XP
			earned.Outcome = "Solo"
			earned.XP = result.Stake
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
			earned.Streak += 1
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

		if perfect and not result.Solo and earned.Outcome ~= "Left" then
			earned.Perfect = true
			earned.XP += DuelConstants.PERFECT_XP
			earned.Coins += DuelConstants.PERFECT_COINS
			earned.CoinsDetail ..= " + perfect"
		end

		-- write it all in one replication flush
		PlayerData.Batch(player, function()
			if earned.XP > 0 then
				data.Player.XP.Increment(earned.XP)
			end
			if earned.Coins > 0 then
				data.Currencies.Won.Increment(earned.Coins)
			end
			if not result.Solo then
				data.Player.Streak.Set(earned.Streak)
				if earned.Outcome == "Win" then
					data.Statistics.Wins.Increment(1)
					if earned.Streak > data.Statistics.HighestStreak.Get() then
						data.Statistics.HighestStreak.Set(earned.Streak)
					end
				end
			end
			for _, id in songs do
				if not data.Inventory.Index.Has(id) then
					data.Inventory.Index.Add(id)
					earned.IndexNew += 1
				end
			end
		end)

		-- remembered for a Save Streak purchase (handled by the receipt processor)
		player:SetAttribute("LostStreak", if earned.StreakLost > 0 then earned.StreakLost else nil)

		out[player] = earned
	end
	return out
end

return Rewards
