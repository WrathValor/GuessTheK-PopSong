--| RewardsCatalog
-- Everything on the Rewards screen, shared by the server (RewardsService checks and pays)
-- and the client (draws it). Days are UTC days: Day(t) = floor(t / 86400), so the daily
-- login and the daily quests roll over at 00:00 UTC for everyone.
--
--   • Daily login – a 7-day ladder (DAILY coins). Claim once a day; claiming on the next day
--                   moves up a step, missing a day starts again at day 1, after day 7 it loops.
--   • Daily quests – 3 quests a day picked from QUEST_POOL (same 3 for everyone that day),
--                   each paying its Reward; finishing all 3 unlocks BONUS.
--   • Group reward – one time: join the Roblox group, get GROUP.Coins, the group stage and
--                   the GROUP.Title title.

local RewardsCatalog = {}

RewardsCatalog.DAILY = table.freeze({ 50, 100, 150, 200, 250, 300, 350 })
RewardsCatalog.DAY_COLOURS = table.freeze({ "EDE4D4", "EDE4D4", "FFD2CE", "9ED8F5", "B9A6FF", "A7E9B8", "FFE07A" })

-- Stat = the daily counter in Rewards.Quest it reads (RewardsService.Record fills them).
RewardsCatalog.QUEST_POOL = table.freeze({
	{ Id = "Correct10", Stat = "Correct", Need = 10, Reward = 75, Title = "Get 10 answers right" },
	{ Id = "Correct25", Stat = "Correct", Need = 25, Reward = 125, Title = "Get 25 answers right" },
	{ Id = "Wins2", Stat = "Wins", Need = 2, Reward = 100, Title = "Win 2 duels" },
	{ Id = "Wins4", Stat = "Wins", Need = 4, Reward = 150, Title = "Win 4 duels" },
	{ Id = "Run2", Stat = "BestRun", Need = 2, Reward = 125, Title = "Win 2 duels in a row" },
	{ Id = "Run3", Stat = "BestRun", Need = 3, Reward = 150, Title = "Win 3 duels in a row" },
	{ Id = "Duels3", Stat = "Duels", Need = 3, Reward = 75, Title = "Play 3 duels" },
	{ Id = "Duels6", Stat = "Duels", Need = 6, Reward = 125, Title = "Play 6 duels" },
	{ Id = "Solo2", Stat = "Solo", Need = 2, Reward = 50, Title = "Finish 2 solo games" },
	{ Id = "Perfect1", Stat = "Perfect", Need = 1, Reward = 150, Title = "Win a perfect game" },
	{ Id = "NewSongs3", Stat = "NewSongs", Need = 3, Reward = 75, Title = "Add 3 new songs to your Index" },
})
RewardsCatalog.QUEST_STATS = table.freeze({ "Correct", "Wins", "WinRun", "BestRun", "Duels", "Solo", "Perfect", "NewSongs" })
RewardsCatalog.QUESTS_PER_DAY = 3
RewardsCatalog.QUEST_COLOURS = table.freeze({ "9ED8F5", "FFB38A", "B9A6FF" })
RewardsCatalog.BONUS = 150

RewardsCatalog.GROUP = table.freeze({
	GroupId = 430052409,
	Coins = 500,
	Stage = "GroupStage", -- ShopCatalog stage, only from this reward
	Title = "Supporter", -- name-tag title, only from this reward
	ClaimedKey = "Group", -- in Rewards.Claimed
})

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

-- The day's quests: QUESTS_PER_DAY from the pool, never two on the same stat.
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
		local family = if q.Stat == "BestRun" then "Wins" else q.Stat
		if not stats[family] then
			stats[family] = true
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

return RewardsCatalog
