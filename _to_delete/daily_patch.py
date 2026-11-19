import sys
ROOT = sys.argv[1]
def sub(p, old, new, count=1):
    p = ROOT + "/" + p
    s = open(p, encoding='utf-8', newline='').read()
    nl = "\r\n" if "\r\n" in s else "\n"
    old, new = old.replace("\n", nl), new.replace("\n", nl)
    assert s.count(old) == count, (p, s.count(old), old[:60])
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))

R = 'src/shared/Constants/RewardsCatalog.luau'
sub(R, '''--   • Daily login – a 7-day ladder (DAILY coins). Claim once a day; claiming on the next day
--                   moves up a step, missing a day starts again at day 1, after day 7 it loops.''', '''--   • Daily login – two 7-day weeks of rewards (DAILY) that take turns: Week 1, Week 2, Week 1…
--                   Claim once a day; claiming on the next day moves up a step, missing a day
--                   starts again at Week 1, day 1. The screen (DailyLoginController) never
--                   names the weeks; the rewards just change.''')
sub(R, '''RewardsCatalog.DAILY = table.freeze({ 50, 100, 150, 200, 250, 300, 350 })
''', '''-- The daily login, Week 1 then Week 2 (the "Daily login 1–3" boards). Each day is a reward
-- table (Coins / Tickets / Upgrades) plus CoinsBoost / XPBoost = minutes of 2× potion time.
RewardsCatalog.DAILY_DAYS = 7 -- days in a week of the ladder
RewardsCatalog.DAILY = table.freeze({
	-- Week 1
	{ Coins = 100 },
	{ Tickets = 1 },
	{ Coins = 200 },
	{ Upgrades = 1 },
	{ XPBoost = 30 },
	{ Coins = 300, Tickets = 1 },
	{ Coins = 500, CoinsBoost = 30 },
	-- Week 2
	{ Coins = 150 },
	{ CoinsBoost = 30 },
	{ Tickets = 2 },
	{ Coins = 250 },
	{ Upgrades = 1 },
	{ Coins = 200, XPBoost = 30 },
	{ Coins = 750, CoinsBoost = 120 },
})
''')
sub(R, '''-- Returns: canClaim, nextStreak (what the streak becomes on claiming), dayIndex (1–7 of the
-- step that is claimable or was claimed today).
function RewardsCatalog.DailyState(streak: number, last: number, now: number): (boolean, number, number)
	local today = RewardsCatalog.Day(now)
	local lastDay = if last > 0 then RewardsCatalog.Day(last) else -1000
	if lastDay == today then
		return false, streak, ((math.max(streak, 1) - 1) % 7) + 1
	end
	local nextStreak = if lastDay == today - 1 then streak + 1 else 1
	return true, nextStreak, ((nextStreak - 1) % 7) + 1
end''', '''-- Returns: canClaim, nextStreak (what the streak becomes on claiming), dayIndex (1 … #DAILY,
-- the step that is claimable or was claimed today; DailyWeek splits it into week + day).
function RewardsCatalog.DailyState(streak: number, last: number, now: number): (boolean, number, number)
	local today = RewardsCatalog.Day(now)
	local lastDay = if last > 0 then RewardsCatalog.Day(last) else -1000
	local steps = #RewardsCatalog.DAILY
	if lastDay == today then
		return false, streak, ((math.max(streak, 1) - 1) % steps) + 1
	end
	local nextStreak = if lastDay == today - 1 then streak + 1 else 1
	return true, nextStreak, ((nextStreak - 1) % steps) + 1
end

-- a ladder index (1 … #DAILY) → the index of its week's day 1, and the day in the week (1–7)
function RewardsCatalog.DailyWeek(index: number): (number, number)
	local day = ((index - 1) % RewardsCatalog.DAILY_DAYS) + 1
	return index - day + 1, day
end

-- the potion time in a daily reward, Coins first: { { Kind = "Coins" | "XP", Minutes } }
function RewardsCatalog.DailyBoosts(reward): { { Kind: string, Minutes: number } }
	local out = {}
	for _, pair in { { "CoinsBoost", "Coins" }, { "XPBoost", "XP" } } do
		local n = reward and reward[pair[1]]
		if type(n) == "number" and n > 0 then
			table.insert(out, { Kind = pair[2], Minutes = n })
		end
	end
	return out
end''')

S = 'src/server/Engine/RewardsService.luau'
sub(S, '''	local coins = Catalog.DAILY[index]
	PlayerData.Batch(player, function()
		data.Rewards.DailyStreak.Set(nextStreak)
		data.Rewards.LastDailyClaim.Set(now)
		data.Currencies.Won.Increment(coins)
	end)
	Analytics.Event(player, "DailyClaimed", coins, `Day{index}`)
	Analytics.Economy(player, "Source", "Coins", coins, data.Currencies.Won.Get(), "DailyReward", "DailyReward") -- the day is in DailyClaimed
	reply(player, "ClaimDaily", true, `Day {index}: +{coins} coins`, coins, {
		Toast = { Source = `Daily login · Day {index}`, Items = { { Kind = "Coins", Amount = coins } }, Streak = nextStreak },
	})''', '''	local reward = Catalog.DAILY[index]
	local boosts = Catalog.DailyBoosts(reward)
	local _, day = Catalog.DailyWeek(index)
	PlayerData.Batch(player, function()
		data.Rewards.DailyStreak.Set(nextStreak)
		data.Rewards.LastDailyClaim.Set(now)
		grant(data, reward)
		-- potion time, like a bought potion (Engine/BoostService runs the clock)
		for _, b in boosts do
			local clock = data.Boosts[b.Kind]
			clock.Set(math.min(clock.Get() + b.Minutes * 60, ShopCatalog.BOOST_MAX_SECONDS))
		end
	end)
	local coins = reward.Coins or 0
	Analytics.Event(player, "DailyClaimed", coins, `Day{index}`) -- 1–14 (8–14 = the second week)
	logReward(player, data, reward, "DailyReward", "DailyReward")
	-- what it gave, for the reveal (DailyLoginController) and the Rewards screen's claim toast
	local items = {}
	for _, r in Catalog.RewardList(reward) do
		table.insert(items, { Kind = r.Kind, Amount = r.Amount })
	end
	for _, b in boosts do
		table.insert(items, { Kind = "Boost", Boost = b.Kind, Amount = b.Minutes })
	end
	local text = Catalog.RewardText(reward)
	for _, b in boosts do
		text ..= `{if text == "" then "" else " · "}{b.Minutes} min 2× {b.Kind} potion`
	end
	reply(player, "ClaimDaily", true, `Day {day}: {text}`, coins, {
		Toast = { Source = `Daily login · Day {day}`, Items = items, Streak = nextStreak },
		Day = day,
		Index = index,
		Streak = nextStreak,
	})''')

T = 'tests/RewardsCatalog.spec.luau'
sub(T, '''	it("loops back to step 1 after day 7", function()
		expect({ RewardsCatalog.DailyState(7, now - DAY, now) }).toEqual({ true, 8, 1 })
	end)''', '''	it("moves on to the second week after day 7, and back to the first after day 14", function()
		expect({ RewardsCatalog.DailyState(7, now - DAY, now) }).toEqual({ true, 8, 8 })
		expect({ RewardsCatalog.DailyWeek(8) }).toEqual({ 8, 1 })
		expect({ RewardsCatalog.DailyState(14, now - DAY, now) }).toEqual({ true, 15, 1 })
	end)''')
sub(T, '''	it("pays more each step", function()
		for i = 2, #RewardsCatalog.DAILY do
			expect(RewardsCatalog.DAILY[i]).toBeGreaterThan(RewardsCatalog.DAILY[i - 1])
		end
	end)''', '''	it("has whole weeks, each day paying something", function()
		expect(#RewardsCatalog.DAILY % RewardsCatalog.DAILY_DAYS).toBe(0)
		for _, reward in RewardsCatalog.DAILY do
			expect(#RewardsCatalog.RewardList(reward) + #RewardsCatalog.DailyBoosts(reward)).toBeGreaterThan(0)
		end
	end)

	it("reads potion time out of a day", function()
		local boosts = RewardsCatalog.DailyBoosts({ Coins = 500, CoinsBoost = 30, XPBoost = 15 })
		expect(boosts).toEqual({ { Kind = "Coins", Minutes = 30 }, { Kind = "XP", Minutes = 15 } })
	end)''')
print("ok")
