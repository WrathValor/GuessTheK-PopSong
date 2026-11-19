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
sub(R, '''-- the potion time in a daily reward, Coins first: { { Kind = "Coins" | "XP", Minutes } }''', '''-- "30 min" / "2 h" (potion time on the daily cards)
function RewardsCatalog.MinutesText(minutes: number): string
	return if minutes >= 60 and minutes % 60 == 0 then `{minutes // 60} h` else `{minutes} min`
end

-- a daily reward's two card lines: the big one ("500 + 30 min") and the small one under it
-- ("coins + 2× Coins potion"); one item spells its name out ("roll ticket", "2× XP potion")
function RewardsCatalog.DailyLabel(reward): (string, string)
	local parts = {} -- { big, name (alone), short (in a pair) }
	local names = { Coins = { "coins", "coins" }, Tickets = { "roll ticket", "roll tickets" }, Upgrades = { "card upgrade", "card upgrades" } }
	local short = { Coins = "coins", Tickets = "ticket", Upgrades = "upgrade" }
	for _, r in RewardsCatalog.RewardList(reward) do
		local n = names[r.Kind]
		table.insert(parts, { tostring(r.Amount), n[if r.Amount == 1 then 1 else 2], short[r.Kind] .. (if r.Amount > 1 and r.Kind ~= "Coins" then "s" else "") })
	end
	for _, b in RewardsCatalog.DailyBoosts(reward) do
		local potion = `2× {b.Kind} potion`
		table.insert(parts, { RewardsCatalog.MinutesText(b.Minutes), potion, potion })
	end
	if #parts == 1 then
		return parts[1][1], parts[1][2]
	end
	local big, small = {}, {}
	for _, p in parts do
		table.insert(big, p[1])
		table.insert(small, p[3])
	end
	return table.concat(big, " + "), table.concat(small, " + ")
end

-- the potion time in a daily reward, Coins first: { { Kind = "Coins" | "XP", Minutes } }''')

T = 'tests/RewardsCatalog.spec.luau'
sub(T, '''	it("reads potion time out of a day", function()''', '''	it("labels the day cards", function()
		expect({ RewardsCatalog.DailyLabel({ Coins = 100 }) }).toEqual({ "100", "coins" })
		expect({ RewardsCatalog.DailyLabel({ Tickets = 1 }) }).toEqual({ "1", "roll ticket" })
		expect({ RewardsCatalog.DailyLabel({ XPBoost = 30 }) }).toEqual({ "30 min", "2× XP potion" })
		expect({ RewardsCatalog.DailyLabel({ Coins = 300, Tickets = 1 }) }).toEqual({ "300 + 1", "coins + ticket" })
		expect({ RewardsCatalog.DailyLabel({ Coins = 750, CoinsBoost = 120 }) }).toEqual({ "750 + 2 h", "coins + 2× Coins potion" })
	end)

	it("reads potion time out of a day", function()''')
print("ok")
