--| Gifts.spec
-- Gift twins (ShopCatalog.GiftProducts): an item's gift product name and back, and that each
-- twin gifts something that exists in the shop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)

describe("gift twins", function()
	it("round-trip between the item and its twin", function()
		for base in ShopCatalog.GiftProducts do
			local twin = ShopCatalog.GiftProduct(base)
			expect(twin).toBe(base .. ShopCatalog.GIFT_SUFFIX)
			expect(ShopCatalog.GiftBase(twin)).toBe(base)
		end
	end)

	it("leave items without a twin alone", function()
		expect(ShopCatalog.GiftProduct("GiftVIP")).toBe("GiftVIP")
		expect(ShopCatalog.GiftBase("GiftVIP")).toBe("GiftVIP")
		expect(ShopCatalog.GiftBase("Coins250")).toBe("Coins250")
	end)

	it("each gift a named shop item with a different product", function()
		for base, id in ShopCatalog.GiftProducts do
			expect(ShopCatalog.GiftName(base)).toBeDefined()
			expect(ShopCatalog.GiftName(base .. ShopCatalog.GIFT_SUFFIX)).toBe(ShopCatalog.GiftName(base))
			expect(id > 0).toBe(true)
		end
	end)
end)
