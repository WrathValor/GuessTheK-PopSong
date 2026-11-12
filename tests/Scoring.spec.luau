--| Scoring.spec
-- The duel maths (Engine/DuelService/Scoring): round points, the ENCORE multiplier, who wins,
-- Party placement, stakes, streaks and the guards. Expected values are worked out from
-- DuelConstants, so retuning a number doesn't break these; changing a rule does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Scoring = require(ServerScriptService.Engine.DuelService.Scoring)

local POINTS = DuelConstants.TIER_POINTS
local BONUS = DuelConstants.FIRST_CORRECT_BONUS
local ENCORE = DuelConstants.FINAL_ROUND_MULTIPLIER
local ROUNDS = DuelConstants.ROUNDS

describe("round multiplier", function()
	it("is 1 for every round but the last", function()
		for round = 1, ROUNDS - 1 do
			expect(Scoring.RoundMultiplier(round, ROUNDS)).toBe(1)
		end
	end)

	it("doubles (FINAL_ROUND_MULTIPLIER) the ENCORE round", function()
		expect(Scoring.RoundMultiplier(ROUNDS, ROUNDS)).toBe(ENCORE)
	end)

	it("never applies in the tutorial", function()
		expect(Scoring.RoundMultiplier(DuelConstants.TUTORIAL_ROUNDS, DuelConstants.TUTORIAL_ROUNDS, true)).toBe(1)
	end)
end)

describe("answer points", function()
	it("pays each tier's points for a right answer", function()
		for tier, points in POINTS do
			expect(Scoring.PickPoints(true, true, tier, false, 1)).toBe(points)
		end
	end)

	it("adds the first-correct bonus", function()
		expect(Scoring.PickPoints(true, true, 1, true, 1)).toBe(POINTS[1] + BONUS)
	end)

	it("multiplies points and the bonus on the ENCORE round", function()
		expect(Scoring.PickPoints(true, true, 2, true, ENCORE)).toBe((POINTS[2] + BONUS) * ENCORE)
	end)

	it("scores 0 for no answer", function()
		expect(Scoring.PickPoints(false, false, 1, false, ENCORE)).toBe(0)
	end)

	it("only costs points for a wrong answer on a penalised tier", function()
		for tier = 1, #POINTS do
			local cost = (DuelConstants.WRONG_PENALTY[tier] or 0)
			expect(Scoring.PickPoints(false, true, tier, false, 1)).toBe(if cost > 0 then -cost else 0)
			-- never in the tutorial
			expect(Scoring.PickPoints(false, true, tier, false, 1, true)).toBe(0)
		end
	end)

	it("hands RoundPoints a pay and a cost for every tier", function()
		local pays, costs = Scoring.RoundPoints(ENCORE)
		expect(#pays).toBe(#POINTS)
		expect(#costs).toBe(#POINTS)
		expect(pays[1]).toBe(POINTS[1] * ENCORE)
	end)
end)

describe("who wins a 1v1", function()
	it("gives it to more points", function()
		expect(Scoring.Decide(10, 7, 99, 1)).toBe("A")
		expect(Scoring.Decide(3, 12, 1, 99)).toBe("B")
	end)

	it("breaks a tie on points with the faster correct answers", function()
		expect(Scoring.Decide(8, 8, 12.5, 14)).toBe("A")
		expect(Scoring.Decide(8, 8, 20, 9)).toBe("B")
	end)

	it("calls an exact tie a draw", function()
		expect(Scoring.Decide(8, 8, 10, 10)).toBe("Draw")
	end)

	it("calls 0–0 a draw, whatever the times", function()
		expect(Scoring.Decide(0, 0, 0, 5)).toBe("Draw")
	end)
end)

describe("Party placement", function()
	local function place(list)
		table.sort(list, Scoring.PlacedBefore)
		local ids = {}
		for i, p in list do
			ids[i] = p.UserId
		end
		return ids
	end

	it("ranks by points, then speed, then UserId, with leavers last", function()
		expect(place({
			{ UserId = 1, Left = true, Score = 99, Time = 0 },
			{ UserId = 2, Left = false, Score = 10, Time = 30 },
			{ UserId = 3, Left = false, Score = 14, Time = 50 },
			{ UserId = 4, Left = false, Score = 10, Time = 20 },
			{ UserId = 6, Left = false, Score = 5, Time = 10 },
			{ UserId = 5, Left = false, Score = 5, Time = 10 },
		})).toEqual({ 3, 4, 2, 5, 6, 1 })
	end)
end)

describe("stake roll", function()
	it("picks by weight from the low end up", function()
		expect(Scoring.RollStake(nil, nil, 0)).toBe(DuelConstants.STAKES[1])
		expect(Scoring.RollStake(nil, nil, 0.999999)).toBe(DuelConstants.STAKES[#DuelConstants.STAKES])
	end)

	it("gives each stake a share of rolls equal to its weight", function()
		local weights = DuelConstants.STAKE_WEIGHTS
		local total = 0
		for _, w in weights do
			total += w
		end
		-- walk r across 0–1 in even steps and count where each lands
		local counts, steps = {}, 10000
		for i = 0, steps - 1 do
			local stake = Scoring.RollStake(nil, nil, (i + 0.5) / steps)
			counts[stake] = (counts[stake] or 0) + 1
		end
		for i, stake in DuelConstants.STAKES do
			expect(counts[stake] / steps).toBeCloseTo(weights[i] / total, 2)
		end
	end)

	it("always returns one of the stakes", function()
		local valid = {}
		for _, s in DuelConstants.STAKES do
			valid[s] = true
		end
		for _ = 1, 500 do
			expect(valid[Scoring.RollStake()]).toBe(true)
		end
	end)
end)

describe("win streaks", function()
	it("pays no bonus below the first streak row", function()
		local first = DuelConstants.STREAK_MULTIPLIERS[#DuelConstants.STREAK_MULTIPLIERS][1]
		for streak = 0, first - 1 do
			expect(Scoring.StreakMultiplier(streak)).toBe(1)
		end
	end)

	it("uses each row from its streak upward", function()
		for _, row in DuelConstants.STREAK_MULTIPLIERS do
			expect(Scoring.StreakMultiplier(row[1])).toBe(row[2])
		end
		expect(Scoring.StreakMultiplier(1000)).toBe(DuelConstants.STREAK_MULTIPLIERS[1][2])
	end)

	it("never lowers the bonus as a streak grows", function()
		for streak = 1, 30 do
			expect(Scoring.StreakMultiplier(streak)).toBeGreaterThanOrEqual(Scoring.StreakMultiplier(streak - 1))
		end
	end)

	it("rounds a win's coins to whole coins", function()
		local row = DuelConstants.STREAK_MULTIPLIERS[#DuelConstants.STREAK_MULTIPLIERS]
		local coins, mult = Scoring.WinCoins(55, row[1])
		expect(mult).toBe(row[2])
		expect(coins).toBe(math.floor(55 * row[2] + 0.5))
		expect(coins % 1).toBe(0)
		expect({ Scoring.WinCoins(40, 0) }).toEqual({ 40, 1 })
	end)
end)

describe("perfect game", function()
	it("needs every round right and fast", function()
		expect(Scoring.IsPerfect(ROUNDS, ROUNDS)).toBe(true)
		expect(Scoring.IsPerfect(ROUNDS, ROUNDS - 1)).toBe(false)
		expect(Scoring.IsPerfect(ROUNDS - 1, ROUNDS - 1)).toBe(false)
	end)
end)

describe("suspect game", function()
	local N = DuelConstants.SUSPECT_ROUNDS
	local function game(n: number, time: number, tier: number?, correct: boolean?)
		local picks = {}
		for i = 1, ROUNDS do
			picks[i] = if i <= n
				then { Correct = correct ~= false, Tier = tier or 1, Time = time }
				else { Correct = false, Tier = 3, Time = 4 }
		end
		return picks
	end
	local fast = DuelConstants.SUSPECT_INSTANT / 2
	local slow = DuelConstants.SUSPECT_SLOW + 1
	local human = (DuelConstants.SUSPECT_INSTANT + DuelConstants.SUSPECT_SLOW) / 2

	it("flags SUSPECT_ROUNDS instant right answers on tier 1", function()
		expect({ Scoring.Suspect(game(N, fast)) }).toEqual({ "Instant", N })
		expect((Scoring.Suspect(game(N - 1, fast)))).toBe(nil)
	end)

	it("flags SUSPECT_ROUNDS slow right answers on tier 1", function()
		expect({ Scoring.Suspect(game(N, slow)) }).toEqual({ "Slow", N })
	end)

	it("leaves ordinary play alone", function()
		expect((Scoring.Suspect(game(ROUNDS, human)))).toBe(nil) -- a strong player at human speed
		expect((Scoring.Suspect(game(ROUNDS, slow, 2)))).toBe(nil) -- unlocked a longer tier
		expect((Scoring.Suspect(game(ROUNDS, fast, 1, false)))).toBe(nil) -- fast but wrong
		expect((Scoring.Suspect({}))).toBe(nil)
	end)
end)

describe("same-rival guard", function()
	it("starts after SAME_RIVAL_GAMES duels with the same rival in a day", function()
		expect(Scoring.IsFarmed(DuelConstants.SAME_RIVAL_GAMES)).toBe(false)
		expect(Scoring.IsFarmed(DuelConstants.SAME_RIVAL_GAMES + 1)).toBe(true)
	end)

	it("scales coins to whole coins", function()
		expect(Scoring.RivalCoins(100)).toBe(math.floor(100 * DuelConstants.SAME_RIVAL_COIN_SCALE + 0.5))
		expect(Scoring.RivalCoins(45) % 1).toBe(0)
	end)
end)
