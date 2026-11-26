--| RewardsService
-- Server side of the Rewards screen (Constants/RewardsCatalog). Every claim is checked here.
--
-- RewardsRemote requests: { Action = "RedeemCode", Code = "LAUNCH" }   (the shop's code box;
--                           codes from RewardsCatalog.CODES and the GitHub file, Engine/RemoteCodes)
--                         { Action = "ClaimDaily" }
--                         { Action = "ClaimQuest", Id = questId, Scope = "Daily" | "Weekly" }
--                         { Action = "ClaimBonus", Scope = "Daily" | "Weekly" }
--                         { Action = "SwapQuest", Id = questId }   (one daily quest a day)
--                         { Action = "ClaimLevel", Level = n }     (a LEVEL_REWARDS level you've reached)
--                         { Action = "ClaimLevels" }               (every reached, unclaimed level)
--                         { Action = "ClaimGroup" }
-- Reply to the player:     { Message = "Result", Ok = bool, Text = string, Action, Coins = number? }
--   ClaimLevel adds { All, Rewards, Titles, Levels = { first, last } }; ClaimBonus adds
--   { Scope, Rewards, XP }. PurchasedController shows Claim All and the bonuses as a reveal.
--   The small claims (ClaimDaily, ClaimQuest, one ClaimLevel, ClaimGroup) add Toast =
--   { Source = "Quest · Win 3 duels", Items = { { Kind = "Coins", Amount } | { Kind = "Stage" |
--   "Title", Name } }, Streak = n? } for the Rewards screen's claim toast.
--                          RedeemCode also sends Code and Rewards (RewardsCatalog.CodeRewards) so
--                          the client can show the purchase reveal
--
-- RewardsService.Record(player, facts) is called by DuelService after each match to move the
-- daily + weekly quest counters (facts: Correct, Win, Lost, Solo, Perfect). The photocard
-- loops move theirs through RecordStats (AlbumService: packs, new cards, Lucky Draws, Gold,
-- albums; BinderService: collects, pins, sells). Rewards are currency tables ({ Coins, Tickets }: grant()).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local StreakReminders = require(script.Parent.StreakReminders)
local Levels = require(ReplicatedStorage.Modules.Levels)
local Analytics = require(script.Parent.Analytics)
local SeasonService = require(script.Parent.SeasonService)
local RemoteCodes = require(script.Parent.RemoteCodes)

local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")

local RewardsService = {}

local busy: { [Player]: boolean } = {}

local function reply(player: Player, action: string, ok: boolean, text: string, coins: number?, extra: { [string]: any }?)
	local packet = { Message = "Result", Ok = ok, Text = text, Action = action, Coins = coins }
	for k, v in extra or {} do
		packet[k] = v
	end
	RewardsRemote:Fire(player, packet)
end

-- pays a reward table ({ Coins, Tickets }); call inside PlayerData.Batch. (Card upgrades are
-- gone: an Upgrades left in a code or reward pays Currencies.UPGRADE_COINS each.)
local function grant(data, reward)
	for _, r in Catalog.RewardList(reward) do
		if r.Kind == "Upgrades" then
			Currencies.Data(data, "Coins").Increment(r.Amount * Currencies.UPGRADE_COINS)
		else
			Currencies.Data(data, r.Kind).Increment(r.Amount)
		end
	end
end

-- New UTC day: the quest counters and claims start over. Safe to call any time.
local function rollQuestDay(data, now: number)
	local today = Catalog.Day(now)
	if data.Rewards.QuestDay.Get() == today then
		return
	end
	data.Rewards.QuestDay.Set(today)
	for _, stat in Catalog.QUEST_STATS do
		data.Rewards.Quest[stat].Set(0)
	end
	data.Rewards.QuestClaimed.Clear()
	data.Rewards.QuestSwapFrom.Set("")
	data.Rewards.QuestSwapTo.Set("")
end

-- New week (Monday 00:00 UTC): the weekly counters and claims start over. Weekly quests that
-- were finished but never claimed are paid first (and the bonus, if every one was), so a
-- finished week is never lost (board 59b). (No analytics here: it can run inside any Batch.)
local function rollQuestWeek(data, now: number)
	local week = Catalog.Week(now)
	local old = data.Rewards.QuestWeek.Get()
	if old == week then
		return
	end
	if old ~= 0 then
		local list, counters, claimed = Catalog.WeeklyFor(old), data.Rewards.WeekQuest, data.Rewards.WeekClaimed
		local done = 0
		for _, q in list do
			if claimed.Has(q.Id) then
				done += 1
			elseif (counters[q.Stat].Get() or 0) >= q.Need then
				done += 1
				grant(data, q.Reward)
				data.Player.XP.Increment(Catalog.WEEKLY_QUEST_XP)
			end
		end
		if done >= #list and not claimed.Has("Bonus") then
			grant(data, Catalog.WEEKLY_BONUS)
			data.Player.XP.Increment(Catalog.WEEKLY_BONUS_XP)
		end
	end
	data.Rewards.QuestWeek.Set(week)
	for _, stat in Catalog.QUEST_STATS do
		data.Rewards.WeekQuest[stat].Set(0)
	end
	data.Rewards.WeekClaimed.Clear()
end

-- both rollovers; call inside PlayerData.Batch
local function roll(data, now: number)
	rollQuestDay(data, now)
	rollQuestWeek(data, now)
end

-- this player's quests for a scope: the list, its counters and its claimed set
local function scopeOf(data, scope: string, now: number)
	if scope == "Weekly" then
		return Catalog.WeeklyFor(Catalog.Week(now)), data.Rewards.WeekQuest, data.Rewards.WeekClaimed
	end
	local list = Catalog.DailyQuests(Catalog.Day(now), data.Rewards.QuestSwapFrom.Get(), data.Rewards.QuestSwapTo.Get())
	return list, data.Rewards.Quest, data.Rewards.QuestClaimed
end

local function claimedCount(list, claimed): number
	local n = 0
	for _, q in list do
		if claimed.Has(q.Id) then
			n += 1
		end
	end
	return n
end


-- the economy events for a reward just paid (after the Batch)
local function logReward(player: Player, data, reward, transaction: string, sku: string)
	for _, r in Catalog.RewardList(reward) do
		Analytics.Economy(player, "Source", r.Kind, r.Amount, Currencies.Data(data, r.Kind).Get(), transaction, sku)
	end
end

-- [[ Claims ]]

local function claimDaily(player: Player, data)
	local now = os.time()
	local canClaim, nextStreak, index = Catalog.DailyState(data.Rewards.DailyStreak.Get(), data.Rewards.LastDailyClaim.Get(), now)
	if not canClaim then
		return reply(player, "ClaimDaily", false, "Come back tomorrow")
	end
	local reward = Catalog.DAILY[index]
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
	StreakReminders.Schedule(player, data) -- today's claimed: tomorrow's reminder instead
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
	})
end

local function claimQuest(player: Player, data, id, scope: string)
	scope = if scope == "Weekly" then "Weekly" else "Daily"
	local now = os.time()
	PlayerData.Batch(player, function()
		roll(data, now)
	end)
	local list, counters, claimed = scopeOf(data, scope, now)
	local quest
	for _, q in list do
		if q.Id == id then
			quest = q
		end
	end
	if not quest then
		return reply(player, "ClaimQuest", false, if scope == "Weekly" then "That quest isn't on this week" else "That quest isn't on today")
	end
	if claimed.Has(quest.Id) then
		return reply(player, "ClaimQuest", false, "Already claimed")
	end
	if counters[quest.Stat].Get() < quest.Need then
		return reply(player, "ClaimQuest", false, "Not finished yet")
	end
	local xp = if scope == "Daily" then Catalog.DAILY_QUEST_XP else Catalog.WEEKLY_QUEST_XP
	PlayerData.Batch(player, function()
		claimed.Add(quest.Id)
		grant(data, quest.Reward)
		if xp > 0 then
			data.Player.XP.Increment(xp)
		end
	end)
	if xp > 0 then
		Analytics.Economy(player, "Source", "XP", xp, data.Player.XP.Get(), "Quest", scope .. "Quest")
	end
	Analytics.Event(player, "QuestClaimed", quest.Reward.Coins or 0, quest.Id)
	logReward(player, data, quest.Reward, "Quest", scope .. "Quest") -- the quest is in QuestClaimed (SKUs are capped at 100)
	SeasonService.Award(player, "Quest") -- season Stars too
	reply(player, "ClaimQuest", true, Catalog.RewardText(quest.Reward), quest.Reward.Coins, {
		Scope = scope,
		Toast = { Source = `Quest · {quest.Title}`, Items = Catalog.RewardList(quest.Reward, xp) },
	})
end

local function claimBonus(player: Player, data, scope: string)
	scope = if scope == "Weekly" then "Weekly" else "Daily"
	local now = os.time()
	PlayerData.Batch(player, function()
		roll(data, now)
	end)
	local list, _, claimed = scopeOf(data, scope, now)
	if claimed.Has("Bonus") then
		return reply(player, "ClaimBonus", false, "Already claimed")
	end
	if claimedCount(list, claimed) < #list then
		return reply(player, "ClaimBonus", false, `Claim all {#list} quests first`)
	end
	local reward = if scope == "Weekly" then Catalog.WEEKLY_BONUS else Catalog.BONUS
	local xp = if scope == "Daily" then Catalog.DAILY_BONUS_XP else Catalog.WEEKLY_BONUS_XP
	PlayerData.Batch(player, function()
		claimed.Add("Bonus")
		grant(data, reward)
		if xp > 0 then
			data.Player.XP.Increment(xp)
		end
	end)
	if xp > 0 then
		Analytics.Economy(player, "Source", "XP", xp, data.Player.XP.Get(), "QuestBonus", scope .. "Bonus")
	end
	Analytics.Event(player, "QuestBonusClaimed", reward.Coins or 0)
	logReward(player, data, reward, "QuestBonus", scope .. "Bonus")
	reply(player, "ClaimBonus", true, `Bonus: {Catalog.RewardText(reward)}`, reward.Coins, { Scope = scope, Rewards = reward, XP = xp })
end

-- one daily quest a day can be swapped for another that isn't on the list (not one that's
-- finished or claimed: that would just be a free reroll of a reward)
local function swapQuest(player: Player, data, id)
	local now = os.time()
	PlayerData.Batch(player, function()
		roll(data, now)
	end)
	if data.Rewards.QuestSwapFrom.Get() ~= "" then
		return reply(player, "SwapQuest", false, "You've used today's swap")
	end
	local list, counters, claimed = scopeOf(data, "Daily", now)
	local quest
	for _, q in list do
		if q.Id == id then
			quest = q
		end
	end
	if not quest then
		return reply(player, "SwapQuest", false, "That quest isn't on today")
	end
	if claimed.Has(quest.Id) or counters[quest.Stat].Get() >= quest.Need then
		return reply(player, "SwapQuest", false, "That one's done: claim it instead")
	end
	local options = Catalog.SwapCandidates(list, quest.Id)
	if #options == 0 then
		return reply(player, "SwapQuest", false, "Nothing to swap it for today")
	end
	local new = options[math.random(1, #options)]
	PlayerData.Batch(player, function()
		data.Rewards.QuestSwapFrom.Set(quest.Id)
		data.Rewards.QuestSwapTo.Set(new.Id)
	end)
	Analytics.Event(player, "QuestSwapped", 1, quest.Id, new.Id)
	reply(player, "SwapQuest", true, `New quest: {new.Title}`)
end

-- level rewards: any LEVEL_REWARDS level the player has reached, once each
local function levelOf(data): number
	return (Levels.FromXP(data.Player.XP.Get()))
end

local function claimLevels(player: Player, data, only: number?)
	local level = levelOf(data)
	local due = {}
	for _, r in Catalog.LEVEL_REWARDS do
		if r.Level <= level and not data.Rewards.LevelClaimed.Has(tostring(r.Level)) and (only == nil or r.Level == only) then
			table.insert(due, r)
		end
	end
	if #due == 0 then
		if only and Catalog.LevelReward(only) and only > level then
			return reply(player, "ClaimLevel", false, `Reach level {only} first`)
		end
		return reply(player, "ClaimLevel", false, if only then "Already claimed" else "Nothing to claim yet")
	end
	local total = { Coins = 0, Tickets = 0, Upgrades = 0 }
	local titles = {}
	local titleNames = {}
	PlayerData.Batch(player, function()
		for _, r in due do
			data.Rewards.LevelClaimed.Add(tostring(r.Level))
			grant(data, r.Reward)
			for kind, n in r.Reward do
				if type(n) == "number" then
					total[kind] += n
				end
			end
			-- title levels: the title is granted on reaching the level; make sure it's there
			local title = r.Reward.Title
			if title then
				table.insert(titles, `{title} title`)
				table.insert(titleNames, title)
				if not data.Inventory.Titles.Has(title) then
					data.Inventory.Titles.Add(title)
				end
			end
		end
	end)
	for _, r in due do
		Analytics.Event(player, "LevelRewardClaimed", r.Reward.Coins or 0, tostring(r.Level))
	end
	logReward(player, data, total, "LevelReward", "LevelReward")
	local what = if #due == 1 then `Level {due[1].Level}: ` else `{#due} rewards: `
	local parts = { Catalog.RewardText(total) }
	if parts[1] == "" then
		table.remove(parts, 1)
	end
	table.move(titles, 1, #titles, #parts + 1, parts)
	-- All / Rewards / Titles / Levels: Claim All shows the "YOU GOT!" reveal (PurchasedController);
	-- one level gets the claim toast
	local items = Catalog.RewardList(total)
	for _, name in titleNames do
		table.insert(items, { Kind = "Title", Name = name })
	end
	reply(player, "ClaimLevel", true, what .. table.concat(parts, " · "), total.Coins, {
		Toast = if only then { Source = `Level {due[1].Level} reward`, Items = items } else nil,
		All = only == nil,
		Rewards = total,
		Titles = titleNames,
		Levels = { due[1].Level, due[#due].Level },
	})
end

local function claimGroup(player: Player, data)
	local g = Catalog.GROUP
	if data.Rewards.Claimed.Has(g.ClaimedKey) then
		return reply(player, "ClaimGroup", false, "Already claimed")
	end
	-- GetGroupsAsync isn't cached like IsInGroup, so someone who just joined counts straight away
	local ok, inGroup = pcall(function()
		for _, info in GroupService:GetGroupsAsync(player.UserId) do
			if info.Id == g.GroupId then
				return true
			end
		end
		return false
	end)
	if not ok then
		return reply(player, "ClaimGroup", false, "Couldn't check the group, try again")
	end
	if not inGroup then
		return reply(player, "ClaimGroup", false, "Join the group first")
	end
	PlayerData.Batch(player, function()
		data.Rewards.Claimed.Add(g.ClaimedKey)
		data.Currencies.Won.Increment(g.Coins)
		if not data.Inventory.Stages.Has(g.Stage) then
			data.Inventory.Stages.Add(g.Stage)
		end
		if not data.Inventory.Titles.Has(g.Title) then
			data.Inventory.Titles.Add(g.Title)
		end
	end)
	Analytics.Event(player, "GroupRewardClaimed", g.Coins)
	Analytics.Economy(player, "Source", "Coins", g.Coins, data.Currencies.Won.Get(), "GroupReward", "GroupReward")
	reply(player, "ClaimGroup", true, `+{g.Coins} coins, Group Exclusive stage + {g.Title} title`, g.Coins, {
		Toast = {
			Source = "Group reward",
			Items = { { Kind = "Coins", Amount = g.Coins }, { Kind = "Stage", Name = "Group Exclusive" }, { Kind = "Title", Name = g.Title } },
		},
	})
end

-- the Inventory set each code item / style key goes into
local CODE_SETS = { Stage = "Stages", Mic = "Mics", Banner = "Banners", Photocard = "Photocards" }

-- one line for the toast / analytics: "+500 coins · 2 roll tickets · Pumpkin Mic"
local function codeSummary(rewards: { any }): string
	local parts = {}
	for _, r in rewards do
		if r.Kind == "Currency" then
			local c = Currencies.Get(r.Key)
			local name = if c then (if r.Amount == 1 then c.Name else c.Plural or c.Name) else r.Key
			table.insert(parts, `+{r.Amount} {string.lower(name)}`)
		elseif r.Kind == "Boost" then
			local k = ShopCatalog.BOOST_KINDS[r.Boost]
			table.insert(parts, `{r.Amount} min {k and k.Name or r.Boost} potion`)
		else
			table.insert(parts, r.Id)
		end
	end
	return table.concat(parts, " · ")
end

-- a code from the shop's code box (Catalog.CODES): every reward it lists, once per account
local function redeemCode(player: Player, data, packet)
	local code = if type(packet.Code) == "string" then string.upper((packet.Code:gsub("%s", ""))) else ""
	-- the GitHub codes file first (Engine/RemoteCodes), then the ones written in RewardsCatalog
	local entry = if #code > 0 and #code <= 30 then RemoteCodes.Get(code) or Catalog.CODES[code] else nil
	if not entry then
		return reply(player, "RedeemCode", false, "That code doesn't work")
	end
	if Catalog.CodeExpired(entry) then
		return reply(player, "RedeemCode", false, "That code has expired")
	end
	local key = `Code:{code}`
	if data.Rewards.Claimed.Has(key) then
		return reply(player, "RedeemCode", false, "You've already used that code")
	end
	local rewards = Catalog.CodeRewards(entry)
	if #rewards == 0 then
		warn(`[RewardsService] code {code} has no rewards`)
		return reply(player, "RedeemCode", false, "That code doesn't work")
	end
	PlayerData.Batch(player, function()
		data.Rewards.Claimed.Add(key)
		for _, r in rewards do
			if r.Kind == "Currency" then
				Currencies.Data(data, r.Key).Increment(r.Amount)
			elseif r.Kind == "Boost" then
				-- potion time, like a bought potion (Engine/BoostService runs the clock)
				local clock = data.Boosts[r.Boost]
				clock.Set(math.min(clock.Get() + r.Amount * 60, ShopCatalog.BOOST_MAX_SECONDS))
			elseif r.Kind == "Title" then
				if not data.Inventory.Titles.Has(r.Id) then
					data.Inventory.Titles.Add(r.Id)
				end
				local tier = math.clamp(math.floor(tonumber(r.Tier) or 1), 1, 3)
				if (data.Inventory.TitleTiers[r.Id].Get() or 0) < tier then
					data.Inventory.TitleTiers[r.Id].Set(tier)
				end
			else
				local set = data.Inventory[CODE_SETS[r.Key]]
				if not set.Has(r.Id) then
					set.Add(r.Id)
				end
			end
		end
	end)
	local coins = entry.Coins or 0
	Analytics.Event(player, "CodeRedeemed", coins, code)
	for _, r in rewards do
		if r.Kind == "Currency" then
			Analytics.Economy(player, "Source", r.Key, r.Amount, Currencies.Data(data, r.Key).Get(), "Code", "Code")
		end
	end
	reply(player, "RedeemCode", true, `Code redeemed: {codeSummary(rewards)}`, coins, { Code = code, Rewards = rewards })
end

local ACTIONS = {
	RedeemCode = redeemCode,
	ClaimDaily = claimDaily,
	ClaimQuest = function(player, data, packet)
		claimQuest(player, data, packet.Id, packet.Scope)
	end,
	ClaimBonus = function(player, data, packet)
		claimBonus(player, data, packet.Scope)
	end,
	SwapQuest = function(player, data, packet)
		swapQuest(player, data, packet.Id)
	end,
	ClaimLevel = function(player, data, packet)
		local n = tonumber(packet.Level)
		if n then
			claimLevels(player, data, math.floor(n))
		end
	end,
	ClaimLevels = function(player, data)
		claimLevels(player, data, nil)
	end,
	ClaimGroup = claimGroup,
}

-- [[ Quest progress ]]

-- facts = { Correct = n, Win = bool, Lost = bool, Solo = bool, Perfect = bool }
-- Call it outside any other Batch; it batches its own writes.
-- New photocards (Engine/AlbumService) count toward the "new photocards" quests. (The counter
-- is still called NewSongs: it counted new songs from the song roll before photocards.)
-- Call it outside any other Batch.
function RewardsService.RecordNewCards(player: Player, count: number)
	RewardsService.RecordStats(player, { NewSongs = count })
end

-- Moves quest counters by stat name (RewardsCatalog.QUEST_STATS), daily and weekly together:
-- { Packs = 5, Lucky = 1 } from AlbumService, { Collects = 1, BinderCoins = 420 } from
-- BinderService. Zeros and unknown stats are skipped. Call it outside any other Batch.
function RewardsService.RecordStats(player: Player, stats: { [string]: number })
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local any = false
	for stat, n in stats do
		if n > 0 and table.find(Catalog.QUEST_STATS, stat) then
			any = true
		end
	end
	if not any then
		return
	end
	PlayerData.Batch(player, function()
		roll(data, os.time())
		for stat, n in stats do
			if n > 0 and table.find(Catalog.QUEST_STATS, stat) then
				data.Rewards.Quest[stat].Increment(n)
				data.Rewards.WeekQuest[stat].Increment(n)
			end
		end
	end)
end

-- A solved Daily Song (Engine/DailySongService) counts toward the "Daily Song" quests.
-- Call it outside any other Batch.
function RewardsService.RecordDailySong(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	PlayerData.Batch(player, function()
		roll(data, os.time())
		data.Rewards.Quest.DailySong.Increment(1)
		data.Rewards.WeekQuest.DailySong.Increment(1)
	end)
end

-- one match's facts into one set of counters (daily or weekly)
local function bump(q, facts)
	if (facts.Correct or 0) > 0 then
		q.Correct.Increment(facts.Correct)
	end
	if facts.Solo then
		q.Solo.Increment(1)
		return
	end
	q.Duels.Increment(1)
	if facts.Win then
		q.Wins.Increment(1)
		q.WinRun.Increment(1)
		if q.WinRun.Get() > q.BestRun.Get() then
			q.BestRun.Set(q.WinRun.Get())
		end
	elseif facts.Lost then
		q.WinRun.Set(0)
	end
	if facts.Perfect then
		q.Perfect.Increment(1)
	end
end

function RewardsService.Record(player: Player, facts)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	PlayerData.Batch(player, function()
		roll(data, os.time())
		bump(data.Rewards.Quest, facts)
		bump(data.Rewards.WeekQuest, facts)
	end)
end

-- [[ Lifecycle ]]

function RewardsService.Start()
	RemoteCodes.Start()
	RewardsRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or busy[player] then
			return
		end
		local action = ACTIONS[packet.Action]
		local data = PlayerData.Get(player)
		if not action or not data then
			return
		end
		busy[player] = true
		local ok, err = pcall(action, player, data, packet)
		busy[player] = nil
		if not ok then
			warn("[RewardsService]", packet.Action, err)
			reply(player, packet.Action, false, "Something went wrong")
		end
	end)

	-- roll the quest day on join so the client never shows yesterday's progress
	local function onJoin(player: Player)
		local data = PlayerData.WaitForData(player)
		if data then
			PlayerData.Batch(player, function()
				roll(data, os.time())
			end)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

return RewardsService
