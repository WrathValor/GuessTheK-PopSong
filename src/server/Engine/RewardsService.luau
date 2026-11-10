--| RewardsService
-- Server side of the Rewards screen (Constants/RewardsCatalog). Every claim is checked here.
--
-- RewardsRemote requests: { Action = "RedeemCode", Code = "LAUNCH" }   (the shop's code box)
--                         { Action = "ClaimDaily" }
--                         { Action = "ClaimQuest", Id = questId }
--                         { Action = "ClaimBonus" }
--                         { Action = "ClaimGroup" }
-- Reply to the player:     { Message = "Result", Ok = bool, Text = string, Action, Coins = number? }
--                          RedeemCode also sends Code and Rewards (RewardsCatalog.CodeRewards) so
--                          the client can show the purchase reveal
--
-- RewardsService.Record(player, facts) is called by DuelService after each match to move the
-- daily quest counters (facts: Correct, Win, Lost, Solo, Perfect; new songs from RecordNewSongs).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local Analytics = require(script.Parent.Analytics)
local SeasonService = require(script.Parent.SeasonService)

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
end

local function questsDone(data, day: number): number
	local n = 0
	for _, q in Catalog.QuestsFor(day) do
		if data.Rewards.QuestClaimed.Has(q.Id) then
			n += 1
		end
	end
	return n
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

local function claimQuest(player: Player, data, id)
	local now = os.time()
	PlayerData.Batch(player, function()
		rollQuestDay(data, now)
	end)
	local today = Catalog.Day(now)
	local quest
	for _, q in Catalog.QuestsFor(today) do
		if q.Id == id then
			quest = q
		end
	end
	if not quest then
		return reply(player, "ClaimQuest", false, "That quest isn't on today")
	end
	if data.Rewards.QuestClaimed.Has(quest.Id) then
		return reply(player, "ClaimQuest", false, "Already claimed")
	end
	if data.Rewards.Quest[quest.Stat].Get() < quest.Need then
		return reply(player, "ClaimQuest", false, "Not finished yet")
	end
	PlayerData.Batch(player, function()
		data.Rewards.QuestClaimed.Add(quest.Id)
		data.Currencies.Won.Increment(quest.Reward)
	end)
	Analytics.Event(player, "QuestClaimed", quest.Reward, quest.Id)
	Analytics.Economy(player, "Source", "Coins", quest.Reward, data.Currencies.Won.Get(), "Quest", "Quest") -- the quest is in QuestClaimed (SKUs are capped at 100)
	SeasonService.Award(player, "Quest") -- season Stars too
	reply(player, "ClaimQuest", true, `+{quest.Reward} coins`, quest.Reward)
end

local function claimBonus(player: Player, data)
	local now = os.time()
	PlayerData.Batch(player, function()
		rollQuestDay(data, now)
	end)
	if data.Rewards.QuestClaimed.Has("Bonus") then
		return reply(player, "ClaimBonus", false, "Already claimed")
	end
	if questsDone(data, Catalog.Day(now)) < Catalog.QUESTS_PER_DAY then
		return reply(player, "ClaimBonus", false, "Claim all 3 quests first")
	end
	PlayerData.Batch(player, function()
		data.Rewards.QuestClaimed.Add("Bonus")
		data.Currencies.Won.Increment(Catalog.BONUS)
	end)
	Analytics.Event(player, "QuestBonusClaimed", Catalog.BONUS)
	Analytics.Economy(player, "Source", "Coins", Catalog.BONUS, data.Currencies.Won.Get(), "QuestBonus", "QuestBonus")
	reply(player, "ClaimBonus", true, `Bonus: +{Catalog.BONUS} coins`, Catalog.BONUS)
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
	local entry = if #code > 0 and #code <= 30 then Catalog.CODES[code] else nil
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
		claimQuest(player, data, packet.Id)
	end,
	ClaimBonus = claimBonus,
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
		rollQuestDay(data, os.time())
		data.Rewards.Quest.NewSongs.Increment(count)
	end)
end

function RewardsService.Record(player: Player, facts)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local q = data.Rewards.Quest
	PlayerData.Batch(player, function()
		rollQuestDay(data, os.time())
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
	end)
end

-- [[ Lifecycle ]]

function RewardsService.Start()
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
				rollQuestDay(data, os.time())
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
