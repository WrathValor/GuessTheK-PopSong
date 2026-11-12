--| Scoring
-- The duel maths, with no players, data or remotes, so it can be tested on its own
-- (tests/Scoring.spec). Duels and Rewards call these; every number comes from
-- Constants/DuelConstants.
--   • a round's multiplier (the final ENCORE round counts FINAL_ROUND_MULTIPLIER times over)
--   • what each tier pays and costs, and one answer's points
--   • who wins a 1v1, and the Party Stage placement order
--   • the stake roll, the win-streak multiplier and a win's coins
--   • the perfect-game check, the same-rival guard and the suspect-game check

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)

local Scoring = {}

-- [[ Rounds ]]

-- the final round counts FINAL_ROUND_MULTIPLIER times over (never in the tutorial)
function Scoring.RoundMultiplier(round: number, roundCount: number, tutorial: boolean?): number
	return if not tutorial and round == roundCount then DuelConstants.FINAL_ROUND_MULTIPLIER else 1
end

-- what each tier pays this round (+) and what a wrong answer on it costs (as a positive number)
function Scoring.RoundPoints(mult: number, tutorial: boolean?): ({ number }, { number })
	local pays, costs = {}, {}
	for i, p in DuelConstants.TIER_POINTS do
		pays[i] = p * mult
		costs[i] = if tutorial then 0 else (DuelConstants.WRONG_PENALTY[i] or 0) * mult
	end
	return pays, costs
end

-- one player's points for a round: a right answer pays its tier (+ the first-correct bonus); a
-- wrong guess on a penalised tier costs points (can take a score below 0); no answer is 0
function Scoring.PickPoints(correct: boolean, picked: boolean, tier: number, first: boolean, mult: number, tutorial: boolean?): number
	local pays, costs = Scoring.RoundPoints(mult, tutorial)
	if correct then
		return (pays[tier] or 0) + (if first then DuelConstants.FIRST_CORRECT_BONUS * mult else 0)
	elseif picked and (costs[tier] or 0) > 0 then
		return -costs[tier]
	end
	return 0
end

-- [[ Results ]]

-- a 1v1's result: "A", "B" or "Draw". More points wins; a tie on points goes to the faster
-- total time to correct answers (only when they scored, so 0–0 is a draw).
function Scoring.Decide(scoreA: number, scoreB: number, timeA: number, timeB: number): "A" | "B" | "Draw"
	if scoreA ~= scoreB then
		return if scoreA > scoreB then "A" else "B"
	elseif timeA ~= timeB and scoreA > 0 then
		return if timeA < timeB then "A" else "B"
	end
	return "Draw"
end

export type Placing = { Left: boolean, Score: number, Time: number, UserId: number }

-- Party Stage order (a table.sort comparator): players still in before whoever left, then
-- points, then total seconds to correct answers (faster first), then UserId so it's stable
function Scoring.PlacedBefore(a: Placing, b: Placing): boolean
	if a.Left ~= b.Left then
		return not a.Left
	end
	if a.Score ~= b.Score then
		return a.Score > b.Score
	end
	if a.Time ~= b.Time then
		return a.Time < b.Time
	end
	return a.UserId < b.UserId
end

-- [[ Stakes and streaks ]]

-- a weighted pick from `stakes` (defaults to the duel table). `r` (0–1) is the random number,
-- passed in by tests; math.random() otherwise.
function Scoring.RollStake(stakes: { number }?, weights: { number }?, r: number?): number
	local list = stakes or DuelConstants.STAKES
	local w = weights or DuelConstants.STAKE_WEIGHTS
	local total = 0
	for _, weight in w do
		total += weight
	end
	local left = (r or math.random()) * total
	for i, weight in w do
		left -= weight
		if left <= 0 then
			return list[i]
		end
	end
	return list[1]
end

-- the stake multiplier for a win streak (STREAK_MULTIPLIERS, longest streak first)
function Scoring.StreakMultiplier(streak: number): number
	for _, row in DuelConstants.STREAK_MULTIPLIERS do
		if streak >= row[1] then
			return row[2]
		end
	end
	return 1
end

-- a win's coins for the streak it brings the player to, and the multiplier used
function Scoring.WinCoins(stake: number, streak: number): (number, number)
	local mult = Scoring.StreakMultiplier(streak)
	return math.floor(stake * mult + 0.5), mult
end

-- [[ Bonuses and guards ]]

-- a perfect game: every round right, and every right answer on PERFECT_MAX_TIER or better
function Scoring.IsPerfect(correct: number, fastCorrect: number): boolean
	return correct == DuelConstants.ROUNDS and fastCorrect == DuelConstants.ROUNDS
end

-- same-rival guard: the `count`th duel today between the same two players is past the limit
function Scoring.IsFarmed(count: number): boolean
	return count > DuelConstants.SAME_RIVAL_GAMES
end

function Scoring.RivalCoins(coins: number): number
	return math.floor(coins * DuelConstants.SAME_RIVAL_COIN_SCALE + 0.5)
end

-- a game's answers that look like a modified client (DuelConstants.SUSPECT_*): "Instant" or
-- "Slow" and how many rounds fit, or nil. picks = one player's { Correct, Tier, Time } per round.
function Scoring.Suspect(picks: { { Correct: boolean, Tier: number, Time: number? } }): (string?, number)
	local instant, slow = 0, 0
	for _, pick in picks do
		if pick.Correct and pick.Tier == 1 and pick.Time then
			if pick.Time < DuelConstants.SUSPECT_INSTANT then
				instant += 1
			elseif pick.Time >= DuelConstants.SUSPECT_SLOW then
				slow += 1
			end
		end
	end
	if instant >= DuelConstants.SUSPECT_ROUNDS then
		return "Instant", instant
	elseif slow >= DuelConstants.SUSPECT_ROUNDS then
		return "Slow", slow
	end
	return nil, 0
end

return table.freeze(Scoring)
