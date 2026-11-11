--| Levels.spec
-- The XP curve and level titles (Modules/Levels).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Levels = require(ReplicatedStorage.Modules.Levels)

describe("XPToNext", function()
	it("matches the curve in the header comment", function()
		expect(Levels.XPToNext(1)).toBe(100)
		expect(Levels.XPToNext(7)).toBe(1000)
		expect(Levels.XPToNext(20)).toBe(2950)
	end)

	it("caps at 6,000 from level 41", function()
		expect(Levels.XPToNext(40)).toBe(5950)
		expect(Levels.XPToNext(41)).toBe(6000)
		expect(Levels.XPToNext(100)).toBe(6000)
	end)
end)

describe("FromXP", function()
	it("starts at level 1", function()
		expect({ Levels.FromXP(0) }).toEqual({ 1, 0, 100 })
		expect({ Levels.FromXP(99) }).toEqual({ 1, 99, 100 })
	end)

	it("levels up exactly on the boundary", function()
		expect({ Levels.FromXP(100) }).toEqual({ 2, 0, 250 })
	end)

	it("treats bad totals safely", function()
		expect({ Levels.FromXP(-50) }).toEqual({ 1, 0, 100 })
		expect({ Levels.FromXP(150.9) }).toEqual({ 2, 50, 250 })
	end)

	it("reaches level 100 at 475,000 XP and stops there", function()
		expect({ Levels.FromXP(474999) }).toEqual({ 99, 5999, 6000 })
		expect({ Levels.FromXP(475000) }).toEqual({ 100, 0, 6000 })
		expect((Levels.FromXP(10 ^ 9))).toBe(Levels.MAX_LEVEL)
	end)
end)

describe("titles", function()
	it("are listed in level order", function()
		for i = 2, #Levels.TITLES do
			expect(Levels.TITLES[i].Level).toBeGreaterThan(Levels.TITLES[i - 1].Level)
		end
	end)

	it("unlock at their level", function()
		expect(Levels.TitlesUpTo(1)).toEqual({ "Fan" })
		expect(Levels.TitlesUpTo(9)).toEqual({ "Fan", "Trainee" })
		expect(Levels.TitlesUpTo(10)).toEqual({ "Fan", "Trainee", "Rookie" })
	end)

	it("name the next title, and none at the top", function()
		expect({ Levels.NextTitle(1) }).toEqual({ "Trainee", 5 })
		expect({ Levels.NextTitle(5) }).toEqual({ "Rookie", 10 })
		expect((Levels.NextTitle(100))).toBeNil()
	end)

	it("all have a chip colour or an animated tier (except Fan's default)", function()
		for _, t in Levels.TITLES do
			if t.Title ~= "Fan" then
				local styled = Levels.TITLE_COLOURS[t.Title] ~= nil or Levels.TITLE_TIERS[t.Title] ~= nil
				expect(styled).toBe(true)
			end
		end
	end)
end)
