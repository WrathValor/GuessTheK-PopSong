--| SeasonConstants.spec
-- Season tiers and divisions (TierOf) and the season calendar (Current / IsRated).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)

local TIERS = SeasonConstants.TIERS

describe("TierOf", function()
	it("starts at Trainee III", function()
		local info = SeasonConstants.TierOf(0)
		expect(info.Label).toBe("TRAINEE III")
		expect(info.Pips).toBe(1)
		expect(info.Floor).toBe(0)
		expect(info.Progress).toBe(0)
	end)

	it("treats nil and negative SP as 0", function()
		expect(SeasonConstants.TierOf(nil :: any).Label).toBe("TRAINEE III")
		expect(SeasonConstants.TierOf(-40).Label).toBe("TRAINEE III")
	end)

	it("enters each tier at its Min", function()
		for i, tier in TIERS do
			local info = SeasonConstants.TierOf(tier.Min)
			expect(info.Index).toBe(i)
			expect(info.Floor).toBe(tier.Min)
			if i > 1 then
				expect(SeasonConstants.TierOf(tier.Min - 1).Index).toBe(i - 1)
			end
		end
	end)

	it("has no divisions at Legend", function()
		local info = SeasonConstants.TierOf(TIERS[#TIERS].Min + 5000)
		expect(info.Division).toBe("")
		expect(info.Next).toBeNil()
		expect(info.Progress).toBe(1)
	end)

	-- walks every SP value below Legend: the division shown, its Floor and its Next must agree
	-- (a Rookie span is 133.3 SP, so rounding has to be the same everywhere)
	it("moves up a division exactly at Next, for every SP value", function()
		local legend = TIERS[#TIERS].Min
		for sp = 0, legend - 1 do
			local info = SeasonConstants.TierOf(sp)
			expect(sp).toBeGreaterThanOrEqual(info.Floor)
			expect(sp).toBeLessThan(info.Next)
			expect(info.Progress).toBeGreaterThanOrEqual(0)
			expect(info.Progress).toBeLessThan(1)
			if sp == info.Next - 1 then
				expect(SeasonConstants.TierOf(info.Next).Label).toBe(info.NextLabel)
			end
		end
	end)
end)

describe("calendar", function()
	it("has a live season at any time", function()
		expect(SeasonConstants.Current(0)).never.toBeNil()
		expect(SeasonConstants.Current(4102444800)).never.toBeNil() -- 2100
	end)

	it("lists seasons oldest first with unique ids", function()
		local seen = {}
		for i, season in SeasonConstants.SCHEDULE do
			expect(seen[season.Id]).toBeNil()
			seen[season.Id] = true
			if i > 1 then
				expect(season.Starts).toBeGreaterThan(SeasonConstants.SCHEDULE[i - 1].Starts)
			end
			expect(SeasonConstants.Find(season.Id)).toBe(season)
		end
	end)

	it("stops rating a season once its Ends has passed", function()
		for _, season in SeasonConstants.SCHEDULE do
			if season.Ends > 0 and SeasonConstants.Current(season.Ends) == season then
				expect(SeasonConstants.IsRated(season.Ends - 1)).toBe(true)
				expect(SeasonConstants.IsRated(season.Ends)).toBe(false)
			end
		end
	end)
end)
