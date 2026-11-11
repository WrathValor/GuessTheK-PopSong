--| DuelConstants.spec
-- Design rules the duel tuning has to keep. These fail when a number in
-- Constants/DuelConstants is changed in a way that breaks a rule its comments promise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)

local function weightedAverage(values, weights)
	local total, weight = 0, 0
	for i, v in values do
		total += v * weights[i]
		weight += weights[i]
	end
	return total / weight
end

describe("snippet tiers", function()
	it("has a point value for every tier of every mode", function()
		for _, mode in DuelConstants.MODES do
			expect(#DuelConstants.TIERS[mode]).toBe(#DuelConstants.TIER_POINTS)
		end
	end)

	it("unlocks longer clips tier by tier", function()
		for _, mode in DuelConstants.MODES do
			local tiers = DuelConstants.TIERS[mode]
			for i = 2, #tiers do
				expect(tiers[i]).toBeGreaterThan(tiers[i - 1])
			end
		end
	end)

	it("never pays more for unlocking more", function()
		local points = DuelConstants.TIER_POINTS
		for i = 2, #points do
			expect(points[i]).toBeLessThanOrEqual(points[i - 1])
		end
	end)

	it("makes a blind tap on tier 1 worth less than knowing the song at 8 s", function()
		-- 4 answers: a blind guess is right a quarter of the time
		expect(DuelConstants.TIER_POINTS[1] / 4).toBeLessThan(DuelConstants.TIER_POINTS[4])
	end)

	it("only charges wrong-answer penalties on tiers that exist", function()
		for tier, cost in DuelConstants.WRONG_PENALTY do
			expect(DuelConstants.TIER_POINTS[tier]).never.toBeNil()
			expect(cost).toBeGreaterThan(0)
		end
	end)

	it("keeps the perfect-game tier inside the ladder", function()
		expect(DuelConstants.PERFECT_MAX_TIER).toBeLessThanOrEqual(#DuelConstants.TIER_POINTS)
	end)
end)

describe("stakes", function()
	it("has a weight for every stake", function()
		expect(#DuelConstants.STAKE_WEIGHTS).toBe(#DuelConstants.STAKES)
		expect(#DuelConstants.SOLO_STAKES).toBe(#DuelConstants.STAKES)
	end)

	it("pays less XP in solo than a duel's stake, so duels stay the better way to level", function()
		local duel = weightedAverage(DuelConstants.STAKES, DuelConstants.STAKE_WEIGHTS)
		local solo = weightedAverage(DuelConstants.SOLO_STAKES, DuelConstants.STAKE_WEIGHTS)
		expect(solo).toBeLessThan(duel)
	end)

	it("pays the winner more than the loser's consolation", function()
		for _, stake in DuelConstants.STAKES do
			expect(stake).toBeGreaterThan(DuelConstants.LOSER_COINS)
		end
	end)
end)

describe("win streaks", function()
	it("lists the streak multipliers from the longest streak down", function()
		local rows = DuelConstants.STREAK_MULTIPLIERS
		for i = 2, #rows do
			expect(rows[i][1]).toBeLessThan(rows[i - 1][1])
			expect(rows[i][2]).toBeLessThanOrEqual(rows[i - 1][2])
		end
		for _, row in rows do
			expect(row[2]).toBeGreaterThan(1)
		end
	end)
end)

describe("owned songs", function()
	it("has a weight above 1 for every card level", function()
		for _, level in Cards.LEVELS do
			expect(DuelConstants.OWNED_WEIGHT[level]).toBeGreaterThan(1)
		end
	end)
end)

describe("tutorial", function()
	it("has enough songs for its rounds", function()
		expect(#DuelConstants.TUTORIAL_SONGS).toBeGreaterThanOrEqual(DuelConstants.TUTORIAL_ROUNDS)
	end)
end)
