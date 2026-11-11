--| Cards.spec
-- Card levels of owned songs (Modules/Library/Cards), from RollConstants' copy counts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local RollConstants = require(ReplicatedStorage.Constants.RollConstants)

local GOLD, RAINBOW = RollConstants.GOLD_COPIES, RollConstants.RAINBOW_COPIES

local function owns(ids: { [string]: boolean })
	return function(id: string)
		return ids[id] == true
	end
end

local SET = { { Id = "a" }, { Id = "b" }, { Id = "c" } }
local ALL = owns({ a = true, b = true, c = true })

describe("Level", function()
	it("follows the copy counts", function()
		expect(Cards.Level(0)).toBeNil()
		expect(Cards.Level(1)).toBe("Normal")
		expect(Cards.Level(GOLD - 1)).toBe("Normal")
		expect(Cards.Level(GOLD)).toBe("Gold")
		expect(Cards.Level(RAINBOW - 1)).toBe("Gold")
		expect(Cards.Level(RAINBOW)).toBe("Rainbow")
		expect(Cards.Level(RAINBOW + 10)).toBe("Rainbow")
	end)

	it("needs more copies for Rainbow than Gold", function()
		expect(RAINBOW).toBeGreaterThan(GOLD)
	end)
end)

describe("Copies", function()
	it("counts a shop-bought song (no Copies entry) as 1", function()
		expect(Cards.Copies(nil, true, "a")).toBe(1)
		expect(Cards.Copies({}, true, "a")).toBe(1)
	end)

	it("reads the Copies map", function()
		expect(Cards.Copies({ a = 4 }, true, "a")).toBe(4)
		expect(Cards.Copies({ a = 4 }, false, "a")).toBe(4)
		expect(Cards.Copies({}, false, "a")).toBe(0)
	end)
end)

describe("Next", function()
	it("names the next level up and its copies", function()
		expect({ Cards.Next(0) }).toEqual({ "Gold", GOLD })
		expect({ Cards.Next(GOLD) }).toEqual({ "Rainbow", RAINBOW })
		expect((Cards.Next(RAINBOW))).toBeNil()
	end)
end)

describe("SetLevel", function()
	it("is nil for an empty set or one with an unowned song", function()
		expect(Cards.SetLevel({}, {}, ALL)).toBeNil()
		expect(Cards.SetLevel(SET, {}, owns({ a = true, b = true }))).toBeNil()
	end)

	it("is the lowest card in the set", function()
		expect(Cards.SetLevel(SET, {}, ALL)).toBe("Normal")
		expect(Cards.SetLevel(SET, { a = GOLD, b = RAINBOW, c = GOLD }, ALL)).toBe("Gold")
		expect(Cards.SetLevel(SET, { a = RAINBOW, b = RAINBOW, c = RAINBOW }, ALL)).toBe("Rainbow")
	end)
end)

describe("CountAtLeast", function()
	it("counts owned songs at a level or higher", function()
		local copies = { a = 1, b = GOLD, c = RAINBOW }
		expect(Cards.CountAtLeast(SET, copies, ALL, "Normal")).toBe(3)
		expect(Cards.CountAtLeast(SET, copies, ALL, "Gold")).toBe(2)
		expect(Cards.CountAtLeast(SET, copies, ALL, "Rainbow")).toBe(1)
		expect(Cards.CountAtLeast(SET, copies, owns({ c = true }), "Normal")).toBe(1)
	end)
end)
