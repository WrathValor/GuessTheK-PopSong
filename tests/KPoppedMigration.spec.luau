--| KPoppedMigration.spec
-- The one-off K-POPPED! conversion (Modules/KPoppedMigration), on fake raw saves shaped the
-- way Scribe stores them (SetOf = sorted array, MapOf = plain table).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local M = require(ReplicatedStorage.Modules.KPoppedMigration)
local Currencies = require(ReplicatedStorage.Constants.Currencies)

local function save(songs, copies)
	return {
		Currencies = { Won = 100 },
		Inventory = { Songs = songs or {}, Copies = copies or {}, Tickets = 1, Upgrades = 0, Packs = { "Group:BTS" }, Titles = { "ARMY" } },
		Rewards = { Claimed = {}, WelcomeCoins = 0, WelcomeTickets = 0, WelcomeSeen = true },
		Profile = { Showcase = { S1 = "Dynamite - BTS", S2 = "", S3 = "", S4 = "", S5 = "" }, BgMusic = "Dynamite - BTS" },
	}
end

describe("Value", function()
	it("pays per song and per extra copy", function()
		local coins, tickets = M.Value({ "a", "b" }, { a = 2 })
		expect(coins).toBe(2 * M.COINS_PER_SONG + M.COINS_PER_COPY)
		expect(tickets).toBe(0)
	end)

	it("gives tickets for Gold and Rainbow songs", function()
		local _, tickets = M.Value({ "a", "b", "c" }, { a = M.GOLD_COPIES, b = M.RAINBOW_COPIES + 3 })
		expect(tickets).toBe(M.TICKETS_GOLD + M.TICKETS_RAINBOW)
	end)

	it("counts a song that's only in Copies", function()
		local coins = M.Value({}, { a = 1 })
		expect(coins).toBe(M.COINS_PER_SONG)
	end)

	it("is nothing for an empty save", function()
		local coins, tickets = M.Value({}, {})
		expect(coins).toBe(0)
		expect(tickets).toBe(0)
	end)
end)

describe("Step", function()
	it("converts, clears the song bits and keeps the rest", function()
		local data = save({ "Dynamite - BTS" }, { ["Dynamite - BTS"] = M.RAINBOW_COPIES })
		M.Step(data)
		local coins = M.COINS_PER_SONG + M.COINS_PER_COPY * (M.RAINBOW_COPIES - 1)
		expect(data.Currencies.Won).toBe(100 + coins)
		expect(data.Inventory.Tickets).toBe(1 + M.TICKETS_RAINBOW)
		expect(data.Rewards.WelcomeCoins).toBe(coins)
		expect(data.Rewards.WelcomeTickets).toBe(M.TICKETS_RAINBOW)
		expect(data.Rewards.WelcomeSeen).toBe(false)
		expect(data.Profile.Showcase.S1).toBe("")
		expect(data.Profile.BgMusic).toBe("")
		expect(#data.Inventory.Packs).toBe(0)
		expect(data.Inventory.Titles[1]).toBe("ARMY")
		expect(data.Inventory.Songs[1]).toBe("Dynamite - BTS") -- kept for support
		expect(table.find(data.Rewards.Claimed, M.KEY)).never.toBeNil()
	end)

	it("turns card upgrades into coins", function()
		local data = save({}, {})
		data.Inventory.Upgrades = 3
		M.Step(data)
		expect(data.Currencies.Won).toBe(100 + 3 * Currencies.UPGRADE_COINS)
		expect(data.Rewards.WelcomeCoins).toBe(3 * Currencies.UPGRADE_COINS)
		expect(data.Inventory.Upgrades).toBe(0)
	end)

	it("never runs twice", function()
		local data = save({ "a" }, {})
		M.Step(data)
		local won = data.Currencies.Won
		M.Step(data)
		expect(data.Currencies.Won).toBe(won)
	end)
end)
