--| Boosts.spec
-- Boost potions (ShopCatalog.Boosts): the coin multiplier with the 2× Coins pass and a coin
-- potion (×2 each, ×3 together), and that every potion is set up to be sold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)

describe("coin multiplier", function()
	it("is 1 with neither", function()
		expect(ShopCatalog.CoinMultiplier(false, false)).toBe(1)
	end)

	it("doubles with the pass or a potion", function()
		expect(ShopCatalog.CoinMultiplier(true, false)).toBe(2)
		expect(ShopCatalog.CoinMultiplier(false, true)).toBe(2)
	end)

	it("is 3 (not 4) with both", function()
		expect(ShopCatalog.CoinMultiplier(true, true)).toBe(3)
	end)
end)

describe("potions", function()
	it("each have a kind, a length under the cap and a product", function()
		for _, boost in ShopCatalog.Boosts do
			expect(ShopCatalog.BOOST_KINDS[boost.Kind]).toBeDefined()
			expect(boost.Seconds > 0 and boost.Seconds <= ShopCatalog.BOOST_MAX_SECONDS).toBe(true)
			expect(boost.ProductId > 0).toBe(true)
		end
	end)
end)
