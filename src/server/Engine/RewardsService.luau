--| RewardsService
-- Server side of the Rewards screen (Constants/RewardsCatalog). Every claim is checked here.
--
-- RewardsRemote requests: { Action = "ClaimDaily" }
--                         { Action = "ClaimQuest", Id = questId }
--                         { Action = "ClaimBonus" }
--                         { Action = "ClaimGroup" }
-- Reply to the player:     { Message = "Result", Ok = bool, Text = string, Action, Coins = number? }
--
-- RewardsService.Record(player, facts) is called by DuelService after each match to move the
-- daily quest counters (facts: Correct, Win, Lost, Solo, Perfect; new songs from RecordNewSongs).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local Analytics = require(script.Parent.Analytics)

local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")

local RewardsService = {}

local busy: { [Player]: boolean } = {}

local function reply(player: Player, action: string, ok: boolean, text: string, coins: number?)
	RewardsRemote:Fire(player, { Message = "Result", Ok = ok, Text = text, Action = action, Coins = coins })
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

local ACTIONS = {
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
