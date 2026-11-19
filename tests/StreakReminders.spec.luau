--| StreakReminders.spec
-- The daily login's streak reminder (Engine/StreakReminders): when a player's next reminder is
-- due, which message it uses, and the request it sends. Nothing here touches MemoryStore.

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local StreakReminders = require(ServerScriptService.Engine.StreakReminders)

local DAY = 86400
local TODAY = 20410 -- a UTC day number
local MORNING = TODAY * DAY + 9 * 3600

describe("streak reminder", function()
	it("comes tomorrow at 20:00 UTC once today's is claimed", function()
		local r = StreakReminders.Next(4, MORNING, MORNING + 60)
		expect(r.Day).toBe(TODAY + 1)
		expect(r.Due).toBe((TODAY + 1) * DAY + 20 * 3600)
		expect(r.Kind).toBe("Streak")
		expect(r.Days).toBe(4)
	end)

	it("comes today when yesterday was claimed but today isn't yet", function()
		local r = StreakReminders.Next(3, MORNING - DAY, MORNING)
		expect(r.Day).toBe(TODAY)
		expect(r.Due).toBe(TODAY * DAY + 20 * 3600)
	end)

	it("doesn't come for a short or lost streak, or after today's reminder time", function()
		expect(StreakReminders.Next(1, MORNING, MORNING)).toBeNil()
		expect(StreakReminders.Next(5, MORNING - 3 * DAY, MORNING)).toBeNil()
		expect(StreakReminders.Next(5, MORNING - DAY, TODAY * DAY + 21 * 3600)).toBeNil()
	end)

	it("uses the Big Day message when the next claim is a day 7", function()
		local r = StreakReminders.Next(6, MORNING, MORNING) -- claimed day 6 today
		expect(r.Kind).toBe("BigDay")
		expect(r.Coins).toBe(500)
		local week2 = StreakReminders.Next(13, MORNING, MORNING)
		expect(week2.Kind).toBe("BigDay")
		expect(week2.Coins).toBe(750)
	end)

	it("builds the request with the right parameter", function()
		local streak = StreakReminders.Payload({ Kind = "Streak", Days = 9, Coins = 0 })
		expect(streak.payload.type).toBe("MOMENT")
		expect(streak.payload.parameters.days.int64Value).toBe(9)
		local big = StreakReminders.Payload({ Kind = "BigDay", Days = 6, Coins = 500 })
		expect(big.payload.parameters.coins.int64Value).toBe(500)
		expect(big.payload.messageId).never.toBe(streak.payload.messageId)
	end)
end)
