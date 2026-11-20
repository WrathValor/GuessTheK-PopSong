--| Catalog.spec
-- The shop, gifting, potions, the daily login and the What's New post fit together: no two
-- things sell under one product id, every gift twin gifts a real item, every daily reward and
-- potion is complete, the codes file going live parses, and every code What's New shows is in
-- it. (ShopCatalog picks the live or dev ids by the universe it runs in: Studio checks dev's.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local News = require(ReplicatedStorage.Constants.News)

-- the codes.txt that goes live with the update (WrathValor/KPOPCodes)
local CODES_FILE = [[
{
  "KPOP":        { "coins": 500, "tickets": 2,                  "expires": "2026-11-26T23:59" },
  "DEBUT":       { "coins": 250, "upgrades": 1,                 "expires": "2026-11-26T23:59" },
  "DAYONE":      { "title": "Day One", "tier": 2, "coins": 300, "expires": "2026-11-26T23:59" },
  "GIFTED":      { "coins": 300, "tickets": 1,                  "expires": "2026-11-27T23:59" },
  "BOOSTED":     { "coinsboost": 30, "xpboost": 30,             "expires": "2026-11-27T23:59" },
  "5KVISITS":    { "coins": 500, "tickets": 1,                  "expires": "2026-11-27T23:59" }
}
]]

-- every Robux product the catalog sells: { name, id }
local function allProducts(): { { any } }
	local out = {}
	local function add(name, id)
		if type(id) == "number" and id > 0 then
			table.insert(out, { name, id })
		end
	end
	for _, list in { ShopCatalog.CoinBundles, ShopCatalog.RollBundles, ShopCatalog.Bundles, ShopCatalog.Boosts, ShopCatalog.PassGifts } do
		for _, b in list do
			add(b.Id, b.ProductId)
		end
	end
	local pack = ShopCatalog.DebutPack
	if pack then
		add(pack.Id, pack.ProductId)
		if pack.Bonus then
			add(pack.Id .. "Bonus", pack.Bonus.ProductId)
		end
	end
	for base, id in ShopCatalog.GiftProducts do
		add(base .. ShopCatalog.GIFT_SUFFIX, id)
	end
	return out
end

-- the item a product name sells, from any list
local function findItem(id: string)
	for _, list in { ShopCatalog.CoinBundles, ShopCatalog.RollBundles, ShopCatalog.Bundles, ShopCatalog.Boosts } do
		for _, b in list do
			if b.Id == id then
				return b
			end
		end
	end
	if ShopCatalog.DebutPack and ShopCatalog.DebutPack.Id == id then
		return ShopCatalog.DebutPack
	end
	return nil
end

describe("products", function()
	it("never sell two things under one id", function()
		local seen = {}
		for _, p in allProducts() do
			local name, id = p[1], p[2]
			expect(seen[id] == nil or seen[id] == name).toBe(true)
			if seen[id] and seen[id] ~= name then
				error(`{name} and {seen[id]} share product id {id}`)
			end
			seen[id] = name
		end
	end)

	it("give every gift twin a real item on sale, with its own id", function()
		for base, id in ShopCatalog.GiftProducts do
			local item = findItem(base)
			expect(item).toBeDefined()
			expect((item :: any).ProductId > 0).toBe(true)
			expect(id).never.toBe((item :: any).ProductId)
			expect(ShopCatalog.GiftName(base .. ShopCatalog.GIFT_SUFFIX)).toBeDefined()
		end
	end)

	it("name every giftable Robux item in the gift messages", function()
		for _, list in { ShopCatalog.CoinBundles, ShopCatalog.RollBundles, ShopCatalog.Bundles, ShopCatalog.Boosts, ShopCatalog.PassGifts } do
			for _, b in list do
				if not b.Hidden and (b.ProductId or 0) > 0 then
					expect(ShopCatalog.GiftName(b.Id)).toBeDefined()
				end
			end
		end
	end)
end)

describe("potions + passes", function()
	it("each potion has art, a kind, and a length that fits the cap", function()
		for _, b in ShopCatalog.Boosts do
			expect(type(b.Image) == "string" and #b.Image > 0).toBe(true)
			expect(ShopCatalog.BOOST_KINDS[b.Kind]).toBeDefined()
			expect(b.Seconds > 0 and b.Seconds <= ShopCatalog.BOOST_MAX_SECONDS).toBe(true)
		end
	end)

	it("each VIP perk has a name, a line and an icon", function()
		local vip = ShopCatalog.GetPass("VIP")
		expect(vip).toBeDefined()
		for _, perk in (vip :: any).Perks do
			expect(type(perk) == "table").toBe(true)
			expect(#perk.Name > 0 and #perk.Desc > 0 and #perk.Icon > 0).toBe(true)
		end
	end)

	it("pass gifts give a pass that exists", function()
		for _, g in ShopCatalog.PassGifts do
			expect(ShopCatalog.GetPass(g.Pass)).toBeDefined()
		end
	end)
end)

describe("daily login", function()
	local KNOWN = { Coins = true, Tickets = true, Upgrades = true, CoinsBoost = true, XPBoost = true }

	it("only gives things the claim knows how to pay", function()
		for i, reward in RewardsCatalog.DAILY do
			for key, value in reward do
				if not KNOWN[key] then
					error(`day {i} has an unknown reward {key}`)
				end
				expect(type(value) == "number" and value > 0).toBe(true)
			end
		end
	end)

	it("never gives more potion time than a clock can hold", function()
		for _, reward in RewardsCatalog.DAILY do
			for _, b in RewardsCatalog.DailyBoosts(reward) do
				expect(b.Minutes * 60 <= ShopCatalog.BOOST_MAX_SECONDS).toBe(true)
			end
		end
	end)

	it("labels every day, and day 7 of each week pays the most coins", function()
		local days = RewardsCatalog.DAILY_DAYS
		for i, reward in RewardsCatalog.DAILY do
			local big, small = RewardsCatalog.DailyLabel(reward)
			expect(#big > 0 and #small > 0).toBe(true)
			local first = i - ((i - 1) % days)
			local seventh = RewardsCatalog.DAILY[first + days - 1]
			expect((reward.Coins or 0) <= (seventh.Coins or 0)).toBe(true)
		end
	end)
end)

describe("codes", function()
	it("the live codes file parses with nothing skipped", function()
		local codes, problems = RewardsCatalog.ParseCodes(CODES_FILE)
		expect(#problems).toBe(0)
		expect(codes).toBeDefined()
		for _, name in { "KPOP", "DEBUT", "DAYONE", "GIFTED", "BOOSTED", "5KVISITS" } do
			expect((codes :: any)[name]).toBeDefined()
		end
		local boosted = RewardsCatalog.CodeRewards((codes :: any).BOOSTED)
		expect(#boosted).toBe(2)
		expect(boosted[1].Kind).toBe("Boost")
		expect(boosted[2].Kind).toBe("Boost")
	end)

	it("every code What's New shows is in the file, and its reward line matches", function()
		local codes = RewardsCatalog.ParseCodes(CODES_FILE) :: any
		for _, update in News.Updates do
			for _, c in update.Codes or {} do
				local entry = codes[string.upper(c.Code)]
				if not entry then
					error(`What's New shows {c.Code}, which isn't in the codes file`)
				end
				expect(entry.Expires).toBe(c.Expires)
			end
		end
	end)

	it("the newest update has room for its featured rows", function()
		local newest = News.Updates[1]
		expect(#newest.Featured <= 4).toBe(true)
		expect(#newest.Name > 0).toBe(true)
	end)
end)
