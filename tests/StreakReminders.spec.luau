--| StreakReminders.spec
-- The daily login's streak reminder (Engine/StreakReminders): when a player's next reminder is
-- due, which message it uses, and the request it sends. Nothing here touches MemoryStore.

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local StreakReminders = require(ServerScriptService.Engine.StreakReminders)
local Catalog = require(game:GetService("ReplicatedStorage").Constants.RewardsCatalog)

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

	it("doesn't come for a lost streak, or after today's reminder time", function()
		expect(StreakReminders.Next(1, MORNING - DAY, MORNING)).toBeNil() -- day 1 was yesterday's
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

	it("nudges a day-1 claim about day 2, the next UTC day", function()
		-- with the Day 2 message: 20 hours after the claim
		local r = StreakReminders.Next(1, MORNING, MORNING + 60, true)
		expect(r.Kind).toBe("DayTwo")
		expect(r.Day).toBe(TODAY + 1)
		expect(r.Due).toBe(MORNING + 20 * 3600)
		-- never before 01:00 UTC of that day (day 2 can't be claimed before the reset)
		local early = StreakReminders.Next(1, TODAY * DAY + 60, TODAY * DAY + 120, true)
		expect(early.Due).toBe((TODAY + 1) * DAY + 3600)
		local late = StreakReminders.Next(1, TODAY * DAY + 23 * 3600, TODAY * DAY + 23 * 3600, true)
		expect(late.Due).toBe((TODAY + 1) * DAY + 19 * 3600)
		-- without it: the streak message at 20:00 UTC, days = 1
		local fallback = StreakReminders.Next(1, MORNING, MORNING + 60, false)
		expect(fallback.Kind).toBe("Streak")
		expect(fallback.Days).toBe(1)
		expect(fallback.Due).toBe((TODAY + 1) * DAY + 20 * 3600)
	end)

	it("matches the Day 2 message's wording: day 2 is always Week 1's 1 roll ticket", function()
		-- the ladder step is the streak (RewardsCatalog.DailyState), so a day-1 claimer's next
		-- claim is step 2 whatever week came before. Change DAILY[2]? Change the message too.
		local _, nextStreak, index = Catalog.DailyState(1, MORNING - DAY, MORNING)
		expect(nextStreak).toBe(2)
		expect(index).toBe(2)
		expect(Catalog.DAILY[2].Tickets).toBe(1)
		expect(Catalog.DAILY[2].Coins).toBeNil()
	end)

	it("builds the request with the right parameter", function()
		local streak = StreakReminders.Payload({ Kind = "Streak", Days = 9, Coins = 0 })
		expect(streak.payload.type).toBe("MOMENT")
		expect(streak.payload.parameters.days.int64Value).toBe(9)
		local big = StreakReminders.Payload({ Kind = "BigDay", Days = 6, Coins = 500 })
		expect(big.payload.parameters.coins.int64Value).toBe(500)
		expect(big.payload.messageId).never.toBe(streak.payload.messageId)
		local dayTwo = StreakReminders.Payload({ Kind = "DayTwo", Days = 1, Coins = 0 })
		expect(dayTwo.payload.parameters).toBeNil()
		expect(dayTwo.payload.type).toBe("MOMENT")
	end)
end)
