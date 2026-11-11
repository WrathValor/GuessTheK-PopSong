--| RewardsCatalog
-- Everything on the Rewards screen, shared by the server (RewardsService checks and pays)
-- and the client (draws it). Days are UTC days: Day(t) = floor(t / 86400), so the daily
-- login and the daily quests roll over at 00:00 UTC for everyone.
--
--   • Daily login – a 7-day ladder (DAILY coins). Claim once a day; claiming on the next day
--                   moves up a step, missing a day starts again at day 1, after day 7 it loops.
--   • Daily quests – 3 quests a day picked from QUEST_POOL (same 3 for everyone that day),
--                   each paying its Reward (coins capped at DAILY_COIN_CAP); finishing all 3
--                   unlocks BONUS. One quest a day can be swapped for another (SwapCandidates).
--   • Weekly quests – WEEKLY_PER_WEEK from WEEKLY_POOL, Monday 00:00 UTC to Monday; the hard
--                   ones (perfect game, long streaks) live here. Coins capped at
--                   WEEKLY_COIN_CAP; finishing them all unlocks WEEKLY_BONUS.
--   • Level rewards – LEVEL_REWARDS: some levels (2 … 100) pay out one reward once, claimed on
--                   the screen. Title levels (Modules/Levels.TITLES) pay their title and
--                   nothing else ({ Title = "Rookie" }); the title itself is granted on
--                   reaching the level, the claim just collects the card.
-- A reward is a table of currency amounts: { Coins = 75, Tickets = 1, Upgrades = 1 }
-- (Constants/Currencies ids); RewardList turns it into display order.
--   • Group reward – one time: join the Roblox group, get GROUP.Coins, the group stage and
--                   the GROUP.Title title.
--   • Codes – typed into the shop's code box; each pays its rewards once per account
--             (Rewards.Claimed "Code:<CODE>"). Codes past their Expires (os.time) stop working.

local RewardsCatalog = {}

RewardsCatalog.DAILY = table.freeze({ 50, 100, 150, 200, 250, 300, 350 })
RewardsCatalog.DAY_COLOURS = table.freeze({ "EDE4D4", "EDE4D4", "FFD2CE", "9ED8F5", "B9A6FF", "A7E9B8", "FFE07A" })

-- Stat = the counter in Rewards.Quest (daily) / Rewards.WeekQuest (weekly) it reads
-- (RewardsService.Record fills them). Hint = the line under the title.
RewardsCatalog.DAILY_COIN_CAP = 100
RewardsCatalog.WEEKLY_COIN_CAP = 200
RewardsCatalog.LEVEL_COIN_CAP = 500 -- most coins any one level reward pays

RewardsCatalog.QUEST_POOL = table.freeze({
	{ Id = "Correct10", Stat = "Correct", Need = 10, Reward = { Coins = 75 }, Title = "Get 10 answers right", Hint = "Solo games count too" },
	{ Id = "Correct25", Stat = "Correct", Need = 25, Reward = { Coins = 100 }, Title = "Get 25 answers right", Hint = "Solo games count too" },
	{ Id = "Wins2", Stat = "Wins", Need = 2, Reward = { Coins = 100 }, Title = "Win 2 duels", Hint = "1v1 or a Party Stage win" },
	{ Id = "Wins3", Stat = "Wins", Need = 3, Reward = { Coins = 100 }, Title = "Win 3 duels", Hint = "1v1 or a Party Stage win" },
	{ Id = "Run2", Stat = "BestRun", Need = 2, Reward = { Coins = 100 }, Title = "Win 2 duels in a row", Hint = "A loss starts the run again" },
	{ Id = "Duels3", Stat = "Duels", Need = 3, Reward = { Coins = 75 }, Title = "Play 3 duels", Hint = "Win or lose" },
	{ Id = "Duels6", Stat = "Duels", Need = 6, Reward = { Coins = 100 }, Title = "Play 6 duels", Hint = "Win or lose" },
	{ Id = "Solo2", Stat = "Solo", Need = 2, Reward = { Coins = 50 }, Title = "Finish 2 solo games", Hint = "Any theme" },
	{ Id = "NewSongs3", Stat = "NewSongs", Need = 3, Reward = { Tickets = 1 }, Title = "Roll 3 new songs", Hint = "Duplicates don't count" },
})
RewardsCatalog.WEEKLY_POOL = table.freeze({
	{ Id = "W_Perfect1", Stat = "Perfect", Need = 1, Reward = { Coins = 200, Upgrades = 1 }, Title = "Win a perfect game", Hint = "7–0, every answer within 2 s" },
	{ Id = "W_Run5", Stat = "BestRun", Need = 5, Reward = { Tickets = 2 }, Title = "Win 5 duels in a row", Hint = "Your best run this week" },
	{ Id = "W_Correct150", Stat = "Correct", Need = 150, Reward = { Coins = 200 }, Title = "Get 150 answers right", Hint = "Any mode" },
	{ Id = "W_NewSongs10", Stat = "NewSongs", Need = 10, Reward = { Tickets = 1, Upgrades = 1 }, Title = "Collect 10 new songs", Hint = "Rolls, tickets or the shop" },
	{ Id = "W_Wins15", Stat = "Wins", Need = 15, Reward = { Coins = 200 }, Title = "Win 15 duels", Hint = "1v1 or a Party Stage win" },
	{ Id = "W_Duels25", Stat = "Duels", Need = 25, Reward = { Coins = 150, Tickets = 1 }, Title = "Play 25 duels", Hint = "Win or lose" },
	{ Id = "W_Solo10", Stat = "Solo", Need = 10, Reward = { Coins = 150 }, Title = "Finish 10 solo games", Hint = "Any theme" },
})
RewardsCatalog.QUEST_STATS = table.freeze({ "Correct", "Wins", "WinRun", "BestRun", "Duels", "Solo", "Perfect", "NewSongs" })
RewardsCatalog.QUESTS_PER_DAY = 3
RewardsCatalog.WEEKLY_PER_WEEK = 4
RewardsCatalog.QUEST_COLOURS = table.freeze({ "9ED8F5", "FFB38A", "B9A6FF" })
RewardsCatalog.BONUS = table.freeze({ Coins = 100, Upgrades = 1 }) -- all daily quests claimed
-- XP paid on top of a daily quest's Reward / the daily BONUS (kept out of the reward tables,
-- which are currencies only; RewardsService adds it to Player.XP)
RewardsCatalog.DAILY_QUEST_XP = 25
RewardsCatalog.DAILY_BONUS_XP = 75
RewardsCatalog.WEEKLY_BONUS = table.freeze({ Coins = 400, Tickets = 2 }) -- all weekly quests claimed

-- Level rewards: each level here pays its one Reward once (claimed on the Rewards screen).
-- T(level) = a title level: its reward is the title from Modules/Levels.TITLES.
local Levels = require(script.Parent.Parent.Modules.Levels)
local function L(level: number, reward)
	return table.freeze({ Level = level, Reward = table.freeze(reward) })
end
local function T(level: number)
	for _, t in Levels.TITLES do
		if t.Level == level then
			return L(level, { Title = t.Title })
		end
	end
	error(`RewardsCatalog: no title at level {level}`)
end
RewardsCatalog.LEVEL_REWARDS = table.freeze({
	L(2, { Coins = 50 }), L(3, { Coins = 100 }), T(5), L(7, { Tickets = 1 }), T(10), L(12, { Coins = 150 }),
	T(15), L(18, { Upgrades = 1 }), T(20), L(22, { Coins = 200 }), L(25, { Tickets = 2 }), L(28, { Coins = 250 }),
	T(30), L(33, { Upgrades = 2 }), L(36, { Coins = 300 }), T(40), L(44, { Coins = 350 }), L(47, { Upgrades = 2 }),
	T(50), L(54, { Tickets = 3 }), L(58, { Coins = 400 }), L(62, { Upgrades = 3 }), T(65), L(70, { Tickets = 4 }),
	L(75, { Coins = 450 }), T(80), L(85, { Coins = 500 }), L(90, { Tickets = 5 }), L(95, { Upgrades = 4 }), T(100),
})

RewardsCatalog.GROUP = table.freeze({
	GroupId = 430052409,
	Coins = 500,
	Stage = "GroupStage", -- ShopCatalog stage, only from this reward
	Title = "Supporter", -- name-tag title, only from this reward
	ClaimedKey = "Group", -- in Rewards.Claimed
})

-- Shop codes, by code (upper case, no spaces, at most 30 characters). A code gives every
-- reward it lists, once per account, then shows the purchase reveal:
--   Coins / Tickets / Upgrades = how many (Constants/Currencies)
--   Stage / Mic = a ShopCatalog stage / mic id
--   Banner / Photocard = a SeasonConstants banner / photocard id
--   Title = a title (TitleTier 1 Normal / 2 Gold / 3 Rainbow, default 1)
--   Expires = when it stops working, in UTC (os.time with a date, or a unix time); no
--             Expires = it never does
-- e.g.
--   LAUNCH = { Coins = 500, Tickets = 2 },
--   HALLOWEEN = { Coins = 250, Upgrades = 1, Mic = "PumpkinMic", Expires = os.time({ year = 2026, month = 11, day = 1, hour = 0 }) },
RewardsCatalog.CODES = table.freeze({})

-- More codes, from a text file anyone with the repo can edit (Engine/RemoteCodes reads it every
-- minute; "" = off). Same rewards as above, one code a line, "#" starts a comment:
--   LAUNCH   coins=500 tickets=2
--   SPOOKY   coins=250 upgrades=1 mic=PumpkinMic   expires=2026-11-01
--   CHAMP    title="S0 Champion" tier=3 banner=S0Glow   expires=2026-12-24T18:00
-- Keys: coins, tickets, upgrades, stage, mic, banner, photocard, title, tier, expires (a UTC
-- date, date + time, or a unix time). Ids (stage, mic…) are written exactly as in the game;
-- a value with spaces goes in quotes. tier = the title's tier (1 Normal, 2 Gold, 3 Rainbow).
-- The file can be JSON instead (it starts with "{"): one object per code, same keys:
--   { "LAUNCH": { "coins": 500, "tickets": 2 },
--     "SPOOKY": { "coins": 250, "mic": "PumpkinMic", "expires": "2026-11-01" } }
RewardsCatalog.CODES_URL = "https://raw.githubusercontent.com/WrathValor/KPOPCodes/main/codes.txt"

local CODE_KEYS = {
	coins = "Coins", tickets = "Tickets", upgrades = "Upgrades",
	stage = "Stage", mic = "Mic", banner = "Banner", photocard = "Photocard",
	title = "Title", tier = "TitleTier", expires = "Expires",
}
local NUMBER_KEYS = { Coins = true, Tickets = true, Upgrades = true, TitleTier = true }

-- "2026-11-01", "2026-11-01T18:00" (UTC) or "1793577600" → os.time, or nil
local function parseTime(s: string): number?
	if s:match("^%d+$") then
		return tonumber(s)
	end
	local y, mo, d, rest = s:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)(.*)$")
	if not y then
		return nil
	end
	local h, mi = rest:match("^[T ](%d%d?):(%d%d)")
	local ok, t = pcall(DateTime.fromUniversalTime, tonumber(y), tonumber(mo), tonumber(d), tonumber(h) or 0, tonumber(mi) or 0, 0)
	return if ok then t.UnixTimestamp else nil
end

-- one code's key/value pairs (as written in the file) → its entry, or nil if it's unusable
local function readCode(code: string, pairs_: { { any } }, where: string, problems: { string })
	if #code > 30 then
		table.insert(problems, `{where}: {code} is longer than 30 characters`)
		return nil
	end
	local entry = {}
	for _, kv in pairs_ do
		local key, value = tostring(kv[1]), kv[2]
		local k = CODE_KEYS[string.lower(key)]
		if not k then
			table.insert(problems, `{where}: unknown key "{key}"`)
		elseif k == "Expires" then
			entry.Expires = if type(value) == "number" then value else parseTime(tostring(value))
			if not entry.Expires then
				-- (skipped: a bad date mustn't make a code last forever)
				table.insert(problems, `{where}: can't read the date "{tostring(value)}", skipping {code}`)
				return nil
			end
		elseif NUMBER_KEYS[k] then
			entry[k] = tonumber(value)
		else
			entry[k] = tostring(value)
		end
	end
	if #RewardsCatalog.CodeRewards(entry) == 0 then
		table.insert(problems, `{where}: {code} gives nothing`)
		return nil
	end
	return entry
end

-- The codes file → { [CODE] = entry }, plus a list of what it couldn't use (for warnings).
-- A JSON file that won't parse returns nil (so the last good list stays).
function RewardsCatalog.ParseCodes(text: string): ({ [string]: any }?, { string })
	local out, problems = {}, {}
	if text:match("^%s*{") then
		local ok, data = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), text)
		if not ok or type(data) ~= "table" then
			table.insert(problems, `the JSON doesn't parse: {tostring(data)}`)
			return nil, problems
		end
		for code, fields in data do
			if type(code) == "string" and type(fields) == "table" then
				local list = {}
				for k, v in fields do
					table.insert(list, { k, v })
				end
				local entry = readCode(string.upper(code), list, code, problems)
				if entry then
					out[string.upper(code)] = entry
				end
			end
		end
		return out, problems
	end
	local n = 0
	for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
		n += 1
		line = line:gsub("#.*$", "")
		local code, rest = line:match("^%s*(%S+)(.*)$")
		if code then
			code = string.upper(code)
			-- key=value pairs; a value with spaces goes in quotes: title="S0 Champion"
			local list = {}
			rest = rest:gsub('(%a+)%s*=%s*"([^"]*)"', function(key, value)
				table.insert(list, { key, value })
				return ""
			end)
			for key, value in rest:gmatch("(%a+)%s*=%s*(%S+)") do
				table.insert(list, { key, value })
			end
			local entry = readCode(code, list, `line {n}`, problems)
			if entry then
				out[code] = entry
			end
		end
	end
	return out, problems
end

-- the order a code's rewards are given and shown in, and what kind each key is
RewardsCatalog.CODE_REWARDS = table.freeze({
	{ Key = "Coins", Kind = "Currency" },
	{ Key = "Tickets", Kind = "Currency" },
	{ Key = "Upgrades", Kind = "Currency" },
	{ Key = "Stage", Kind = "Item" },
	{ Key = "Mic", Kind = "Item" },
	{ Key = "Banner", Kind = "Style" },
	{ Key = "Photocard", Kind = "Style" },
	{ Key = "Title", Kind = "Title" },
})

-- a code's rewards as a list: { Key, Kind, Amount? (currencies), Id? (items, styles, titles) }
function RewardsCatalog.CodeRewards(entry): { any }
	local out = {}
	for _, spec in RewardsCatalog.CODE_REWARDS do
		local value = entry[spec.Key]
		if spec.Kind == "Currency" and type(value) == "number" and value > 0 then
			table.insert(out, { Key = spec.Key, Kind = spec.Kind, Amount = math.floor(value) })
		elseif spec.Kind ~= "Currency" and type(value) == "string" and value ~= "" then
			table.insert(out, { Key = spec.Key, Kind = spec.Kind, Id = value, Tier = if spec.Key == "Title" then entry.TitleTier else nil })
		end
	end
	return out
end

-- true once a code's Expires has passed
function RewardsCatalog.CodeExpired(entry, now: number?): boolean
	return type(entry.Expires) == "number" and (now or os.time()) >= entry.Expires
end

function RewardsCatalog.Day(t: number): number
	return math.floor(t / 86400)
end

-- Seconds until the next UTC day.
function RewardsCatalog.SecondsLeft(t: number): number
	return (RewardsCatalog.Day(t) + 1) * 86400 - t
end

local byId = {}
for _, q in RewardsCatalog.QUEST_POOL do
	byId[q.Id] = q
end
function RewardsCatalog.GetQuest(id: string)
	return byId[id]
end

-- The day's quests: QUESTS_PER_DAY from the pool, never two on the same stat (the same for
-- everyone; DailyQuests applies a player's swap).
function RewardsCatalog.QuestsFor(day: number): { any }
	local pool = table.clone(RewardsCatalog.QUEST_POOL)
	local rng = Random.new(day * 31337 + 7)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out, stats = {}, {}
	for _, q in pool do
		if #out >= RewardsCatalog.QUESTS_PER_DAY then
			break
		end
		-- "in a row" and "win" quests count the same wins, so keep them apart too
		local fam = if q.Stat == "BestRun" then "Wins" else q.Stat
		if not stats[fam] then
			stats[fam] = true
			table.insert(out, q)
		end
	end
	return out
end

-- Where the daily login stands. `streak` = Rewards.DailyStreak, `last` = Rewards.LastDailyClaim.
-- Returns: canClaim, nextStreak (what the streak becomes on claiming), dayIndex (1–7 of the
-- step that is claimable or was claimed today).
function RewardsCatalog.DailyState(streak: number, last: number, now: number): (boolean, number, number)
	local today = RewardsCatalog.Day(now)
	local lastDay = if last > 0 then RewardsCatalog.Day(last) else -1000
	if lastDay == today then
		return false, streak, ((math.max(streak, 1) - 1) % 7) + 1
	end
	local nextStreak = if lastDay == today - 1 then streak + 1 else 1
	return true, nextStreak, ((nextStreak - 1) % 7) + 1
end

-- [[ Weeks ]]
-- Weeks run Monday 00:00 UTC to Monday. Day 0 (1 Jan 1970) was a Thursday, so day 4 is the
-- first Monday.
function RewardsCatalog.Week(t: number): number
	return math.floor((RewardsCatalog.Day(t) - 4) / 7)
end

function RewardsCatalog.WeekSecondsLeft(t: number): number
	return ((RewardsCatalog.Week(t) + 1) * 7 + 4) * 86400 - t
end

-- [[ Picking quests ]]

local function family(q): string
	-- "in a row" and "win" quests count the same wins, so keep them apart
	return if q.Stat == "BestRun" then "Wins" else q.Stat
end

-- `count` quests from `pool`, shuffled by `seed`, never two from the same family
local function pick(pool, count: number, seed: number): { any }
	local list = table.clone(pool)
	local rng = Random.new(seed)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	local out, used = {}, {}
	for _, q in list do
		if #out >= count then
			break
		end
		if not used[family(q)] then
			used[family(q)] = true
			table.insert(out, q)
		end
	end
	return out
end

local weeklyById = {}
for _, q in RewardsCatalog.WEEKLY_POOL do
	weeklyById[q.Id] = q
end
function RewardsCatalog.GetWeeklyQuest(id: string)
	return weeklyById[id]
end

-- The week's quests (same for everyone that week).
function RewardsCatalog.WeeklyFor(week: number): { any }
	return pick(RewardsCatalog.WEEKLY_POOL, RewardsCatalog.WEEKLY_PER_WEEK, week * 7919 + 3)
end

-- Today's quests for one player: the day's 3, with their swap applied (Rewards.QuestSwapFrom
-- → QuestSwapTo, "" = none).
function RewardsCatalog.DailyQuests(day: number, swapFrom: string?, swapTo: string?): { any }
	local list = RewardsCatalog.QuestsFor(day)
	local to = swapTo and swapTo ~= "" and byId[swapTo]
	if swapFrom and swapFrom ~= "" and to then
		for i, q in list do
			if q.Id == swapFrom then
				list[i] = to
			end
		end
	end
	return list
end

-- What `fromId` could be swapped for: pool quests not on today's list, not in a family the
-- other quests already cover.
function RewardsCatalog.SwapCandidates(list: { any }, fromId: string): { any }
	local onList, families = {}, {}
	for _, q in list do
		onList[q.Id] = true
		if q.Id ~= fromId then
			families[family(q)] = true
		end
	end
	local out = {}
	for _, q in RewardsCatalog.QUEST_POOL do
		if not onList[q.Id] and not families[family(q)] then
			table.insert(out, q)
		end
	end
	return out
end

-- [[ Rewards ]]

local REWARD_ORDER = { "Coins", "Tickets", "Upgrades" }

-- { { Kind = "Coins", Amount = 75 }, … } in display order
-- xp = XP paid with it (DAILY_QUEST_XP / DAILY_BONUS_XP), listed last as { Kind = "XP" }
function RewardsCatalog.RewardList(reward, xp: number?): { { Kind: string, Amount: number } }
	local out = {}
	for _, kind in REWARD_ORDER do
		local n = reward and reward[kind]
		if type(n) == "number" and n > 0 then
			table.insert(out, { Kind = kind, Amount = n })
		end
	end
	if xp and xp > 0 then
		table.insert(out, { Kind = "XP", Amount = xp })
	end
	return out
end

-- "+75 coins · +1 ticket" (toasts)
function RewardsCatalog.RewardText(reward): string
	local names = { Coins = { "coin", "coins" }, Tickets = { "ticket", "tickets" }, Upgrades = { "upgrade", "upgrades" } }
	local parts = {}
	for _, r in RewardsCatalog.RewardList(reward) do
		table.insert(parts, `+{r.Amount} {names[r.Kind][if r.Amount == 1 then 1 else 2]}`)
	end
	return table.concat(parts, " · ")
end

local byLevel = {}
for _, r in RewardsCatalog.LEVEL_REWARDS do
	byLevel[r.Level] = r
end
function RewardsCatalog.LevelReward(level: number)
	return byLevel[level]
end

-- keep the coin caps honest
for _, q in RewardsCatalog.QUEST_POOL do
	assert((q.Reward.Coins or 0) <= RewardsCatalog.DAILY_COIN_CAP, `RewardsCatalog: {q.Id} pays over the daily cap`)
end
for _, q in RewardsCatalog.WEEKLY_POOL do
	assert((q.Reward.Coins or 0) <= RewardsCatalog.WEEKLY_COIN_CAP, `RewardsCatalog: {q.Id} pays over the weekly cap`)
end
for _, r in RewardsCatalog.LEVEL_REWARDS do
	assert((r.Reward.Coins or 0) <= RewardsCatalog.LEVEL_COIN_CAP, `RewardsCatalog: level {r.Level} pays over the level cap`)
end

return RewardsCatalog
