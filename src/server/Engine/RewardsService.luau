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
--   { Scope, Rewards }. PurchasedController shows Claim All and the bonuses as a reveal.
--                          RedeemCode also sends Code and Rewards (RewardsCatalog.CodeRewards) so
--                          the client can show the purchase reveal
--
-- RewardsService.Record(player, facts) is called by DuelService after each match to move the
-- daily + weekly quest counters (facts: Correct, Win, Lost, Solo, Perfect; new songs from
-- RecordNewSongs). Rewards are currency tables ({ Coins, Tickets, Upgrades }: grant()).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
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

-- New week (Monday 00:00 UTC): the weekly counters and claims start over.
local function rollQuestWeek(data, now: number)
	local week = Catalog.Week(now)
	if data.Rewards.QuestWeek.Get() == week then
		return
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

-- pays a reward table ({ Coins, Tickets, Upgrades }); call inside PlayerData.Batch
local function grant(data, reward)
	for _, r in Catalog.RewardList(reward) do
		Currencies.Data(data, r.Kind).Increment(r.Amount)
	end
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
	local coins = Catalog.DAILY[index]
	PlayerData.Batch(player, function()
		data.Rewards.DailyStreak.Set(nextStreak)
		data.Rewards.LastDailyClaim.Set(now)
		data.Currencies.Won.Increment(coins)
	end)
	Analytics.Event(player, "DailyClaimed", coins, `Day{index}`)
	Analytics.Economy(player, "Source", "Coins", coins, data.Currencies.Won.Get(), "DailyReward", "DailyReward") -- the day is in DailyClaimed
	Analytics.Onboarding(player, "ClaimedDaily")
	reply(player, "ClaimDaily", true, `Day {index}: +{coins} coins`, coins)
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
	PlayerData.Batch(player, function()
		claimed.Add(quest.Id)
		grant(data, quest.Reward)
	end)
	Analytics.Event(player, "QuestClaimed", quest.Reward.Coins or 0, quest.Id)
	logReward(player, data, quest.Reward, "Quest", scope .. "Quest") -- the quest is in QuestClaimed (SKUs are capped at 100)
	SeasonService.Award(player, "Quest") -- season Stars too
	reply(player, "ClaimQuest", true, Catalog.RewardText(quest.Reward), quest.Reward.Coins, { Scope = scope })
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
	PlayerData.Batch(player, function()
		claimed.Add("Bonus")
		grant(data, reward)
	end)
	Analytics.Event(player, "QuestBonusClaimed", reward.Coins or 0)
	logReward(player, data, reward, "QuestBonus", scope .. "Bonus")
	reply(player, "ClaimBonus", true, `Bonus: {Catalog.RewardText(reward)}`, reward.Coins, { Scope = scope, Rewards = reward })
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
	-- All / Rewards / Titles / Levels: Claim All shows the "YOU GOT!" reveal (PurchasedController)
	reply(player, "ClaimLevel", true, what .. table.concat(parts, " · "), total.Coins, {
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
	reply(player, "ClaimGroup", true, `+{g.Coins} coins, Group Exclusive stage + {g.Title} title`, g.Coins)
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
-- New songs pulled from the song roll (Engine/RollService) count toward the "new songs" quest.
-- Call it outside any other Batch.
function RewardsService.RecordNewSongs(player: Player, count: number)
	local data = PlayerData.Get(player)
	if not data or count <= 0 then
		return
	end
	PlayerData.Batch(player, function()
		roll(data, os.time())
		data.Rewards.Quest.NewSongs.Increment(count)
		data.Rewards.WeekQuest.NewSongs.Increment(count)
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
