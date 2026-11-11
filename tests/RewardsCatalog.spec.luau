--| RewardsCatalog.spec
-- Daily login, daily / weekly quests, level rewards and shop codes (Constants/RewardsCatalog).
-- Days and weeks are UTC: a day rolls over at 00:00, a week on Monday 00:00.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local Levels = require(ReplicatedStorage.Modules.Levels)

local DAY = 86400

local function utc(year: number, month: number, day: number, hour: number?): number
	return DateTime.fromUniversalTime(year, month, day, hour or 0, 0, 0).UnixTimestamp
end

local function family(q): string
	return if q.Stat == "BestRun" then "Wins" else q.Stat
end

local function expectNoSharedFamily(list)
	local seen = {}
	for _, q in list do
		expect(seen[family(q)]).toBeNil()
		seen[family(q)] = true
	end
end

describe("days and weeks", function()
	it("rolls the day over at 00:00 UTC", function()
		expect(RewardsCatalog.Day(0)).toBe(0)
		expect(RewardsCatalog.Day(DAY - 1)).toBe(0)
		expect(RewardsCatalog.Day(DAY)).toBe(1)
		expect(RewardsCatalog.SecondsLeft(0)).toBe(DAY)
		expect(RewardsCatalog.SecondsLeft(DAY - 1)).toBe(1)
	end)

	it("starts weeks on Monday", function()
		local monday = utc(2026, 11, 9) -- a Monday
		expect(RewardsCatalog.Week(monday)).toBe(RewardsCatalog.Week(monday - 1) + 1)
		expect(RewardsCatalog.Week(monday + 7 * DAY - 1)).toBe(RewardsCatalog.Week(monday))
		expect(RewardsCatalog.WeekSecondsLeft(monday)).toBe(7 * DAY)
		expect(RewardsCatalog.WeekSecondsLeft(monday + 7 * DAY - 1)).toBe(1)
	end)
end)

describe("daily login", function()
	local now = utc(2026, 11, 11, 15)

	it("can be claimed on a first visit, as day 1", function()
		expect({ RewardsCatalog.DailyState(0, 0, now) }).toEqual({ true, 1, 1 })
	end)

	it("can't be claimed twice in a day", function()
		local canClaim = RewardsCatalog.DailyState(3, now - 3600, now)
		expect(canClaim).toBe(false)
	end)

	it("moves up a step when claimed the next day", function()
		expect({ RewardsCatalog.DailyState(3, now - DAY, now) }).toEqual({ true, 4, 4 })
	end)

	it("loops back to step 1 after day 7", function()
		expect({ RewardsCatalog.DailyState(7, now - DAY, now) }).toEqual({ true, 8, 1 })
	end)

	it("starts again at day 1 after a missed day", function()
		expect({ RewardsCatalog.DailyState(5, now - 2 * DAY, now) }).toEqual({ true, 1, 1 })
	end)

	it("pays more each step", function()
		for i = 2, #RewardsCatalog.DAILY do
			expect(RewardsCatalog.DAILY[i]).toBeGreaterThan(RewardsCatalog.DAILY[i - 1])
		end
	end)
end)

describe("daily quests", function()
	local today = RewardsCatalog.Day(utc(2026, 11, 11))

	it("gives everyone the same quests on the same day", function()
		expect(RewardsCatalog.QuestsFor(today)).toEqual(RewardsCatalog.QuestsFor(today))
	end)

	it("picks QUESTS_PER_DAY quests, never two of the same kind, every day for a year", function()
		for day = today, today + 365 do
			local list = RewardsCatalog.QuestsFor(day)
			expect(#list).toBe(RewardsCatalog.QUESTS_PER_DAY)
			expectNoSharedFamily(list)
		end
	end)

	it("applies a player's swap", function()
		local list = RewardsCatalog.QuestsFor(today)
		local candidates = RewardsCatalog.SwapCandidates(list, list[1].Id)
		expect(#candidates).toBeGreaterThan(0)
		local swapped = RewardsCatalog.DailyQuests(today, list[1].Id, candidates[1].Id)
		expect(swapped[1].Id).toBe(candidates[1].Id)
		expectNoSharedFamily(swapped)
	end)

	it("ignores a swap to a quest that doesn't exist", function()
		local list = RewardsCatalog.QuestsFor(today)
		expect(RewardsCatalog.DailyQuests(today, list[1].Id, "NotAQuest")).toEqual(list)
	end)

	it("never offers a quest already on the list as a swap", function()
		local list = RewardsCatalog.QuestsFor(today)
		for _, candidate in RewardsCatalog.SwapCandidates(list, list[2].Id) do
			for _, q in list do
				expect(candidate.Id).never.toBe(q.Id)
			end
		end
	end)
end)

describe("weekly quests", function()
	it("picks WEEKLY_PER_WEEK quests, never two of the same kind, for two years", function()
		local week = RewardsCatalog.Week(utc(2026, 11, 11))
		for w = week, week + 104 do
			local list = RewardsCatalog.WeeklyFor(w)
			expect(#list).toBe(RewardsCatalog.WEEKLY_PER_WEEK)
			expectNoSharedFamily(list)
		end
	end)
end)

describe("level rewards", function()
	it("stay under the level coin cap", function()
		for _, r in RewardsCatalog.LEVEL_REWARDS do
			expect(r.Reward.Coins or 0).toBeLessThanOrEqual(RewardsCatalog.LEVEL_COIN_CAP)
		end
	end)

	it("have a card for every title level after Fan", function()
		for _, t in Levels.TITLES do
			if t.Level > 1 then
				local reward = RewardsCatalog.LevelReward(t.Level)
				expect(reward).never.toBeNil()
				expect(reward.Reward.Title).toBe(t.Title)
			end
		end
	end)

	it("only sit on reachable levels", function()
		for _, r in RewardsCatalog.LEVEL_REWARDS do
			expect(r.Level).toBeGreaterThanOrEqual(2)
			expect(r.Level).toBeLessThanOrEqual(Levels.MAX_LEVEL)
		end
	end)
end)

describe("reward text", function()
	it("lists currencies in order, singular and plural", function()
		expect(RewardsCatalog.RewardText({ Tickets = 2, Coins = 1 })).toBe("+1 coin · +2 tickets")
		expect(RewardsCatalog.RewardText({ Upgrades = 1 })).toBe("+1 upgrade")
	end)

	it("puts XP last", function()
		local list = RewardsCatalog.RewardList({ Coins = 75 }, 25)
		expect(list).toEqual({ { Kind = "Coins", Amount = 75 }, { Kind = "XP", Amount = 25 } })
	end)
end)

describe("shop codes", function()
	it("reads the text format, upper-casing codes and skipping comments", function()
		local codes, problems = RewardsCatalog.ParseCodes(table.concat({
			"# launch codes",
			"launch   coins=500 tickets=2",
			'CHAMP    title="S0 Champion" tier=3   expires=2026-12-24T18:00',
		}, "\n"))
		expect(#problems).toBe(0)
		expect(codes.LAUNCH.Coins).toBe(500)
		expect(codes.LAUNCH.Tickets).toBe(2)
		expect(codes.LAUNCH.Expires).toBeNil()
		expect(codes.CHAMP.Title).toBe("S0 Champion")
		expect(codes.CHAMP.TitleTier).toBe(3)
		expect(codes.CHAMP.Expires).toBe(utc(2026, 12, 24, 18))
	end)

	it("skips codes it can't use, and says why", function()
		local codes, problems = RewardsCatalog.ParseCodes(table.concat({
			"NOTHING",
			"TYPO coinz=50",
			"BADDATE coins=50 expires=someday",
			`{string.rep("A", 31)} coins=50`,
		}, "\n"))
		expect(next(codes)).toBeNil()
		expect(#problems).toBeGreaterThanOrEqual(4)
	end)

	it("never lets a bad date make a code last forever", function()
		local codes = RewardsCatalog.ParseCodes("SPOOKY coins=250 expires=31-10-2026")
		expect(codes.SPOOKY).toBeNil()
	end)

	it("reads the JSON format", function()
		local codes = RewardsCatalog.ParseCodes('{ "spooky": { "coins": 250, "expires": "2026-11-01" } }')
		expect(codes.SPOOKY.Coins).toBe(250)
		expect(codes.SPOOKY.Expires).toBe(utc(2026, 11, 1))
	end)

	it("keeps the last good list when the JSON doesn't parse", function()
		local codes, problems = RewardsCatalog.ParseCodes("{ oops")
		expect(codes).toBeNil()
		expect(#problems).toBe(1)
	end)

	it("expires a code at its Expires time", function()
		local entry = { Coins = 10, Expires = 1000 }
		expect(RewardsCatalog.CodeExpired(entry, 999)).toBe(false)
		expect(RewardsCatalog.CodeExpired(entry, 1000)).toBe(true)
		expect(RewardsCatalog.CodeExpired({ Coins = 10 }, 10 ^ 10)).toBe(false)
	end)
end)
