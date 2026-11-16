--| LikeGoalService
-- The like goal (Constants/LikeGoalConstants). Reads the game's like count from our Cloudflare
-- Worker (LikeGoalConstants.URL) every REFRESH seconds and puts it on ReplicatedStorage
-- (attribute ATTRIBUTE) for the sign, with how many goals are hit (REACHED). If a read fails, the
-- last count stays.
-- When a goal is hit, every player on the server gets its reward straight away (and the other
-- servers do on their next read); a player who joins later gets every goal hit so far. Each goal
-- pays once per account (Rewards.Claimed "LikeGoal:<Id>"). The most goals ever hit is kept in a
-- DataStore (STORE), so a goal stays hit if likes drop back under it.
-- RewardsRemote, server → client: { Message = "LikeGoal", Goals = { likes… }, Likes = the last,
--   Rewards = { { Key, Kind, Amount?, Id? } } } – everything paid at once (a player catching up
--   on several goals gets them in one go, currencies added up); PurchasedController shows it as
--   a "LIKE GOAL HIT!" / "LIKE GOALS HIT!" reveal once the tutorial is done
-- Needs Game Settings → Security → Allow HTTP Requests.
--   LikeGoalService.Start()
--   LikeGoalService.Set(30)   -- (testing, the setlikes command: this server only, not saved)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local LikeGoalConstants = require(ReplicatedStorage.Constants.LikeGoalConstants)
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local Analytics = require(script.Parent.Analytics)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)

local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")
local GOALS = LikeGoalConstants.GOALS

local LikeGoalService = {}

local likes = -1 -- not read yet
local reached = 0 -- goals hit (the most of: this count, the DataStore's)
local started = false
local paying: { [Player]: boolean } = {}

local function key(goal): string
	return `LikeGoal:{goal.Id}`
end

-- the Inventory set each item / style goes into
local ITEM_SETS = { Stage = "Stages", Mic = "Mics", Banner = "Banners", Photocard = "Photocards" }

-- a goal's reward as a list (RewardsCatalog.CodeRewards, plus a full Set):
-- { Key, Kind = "Currency" | "Item" | "Style" | "Title" | "Set", Amount?, Id?, Tier? }
local function rewardList(goal): { any }
	local list = Catalog.CodeRewards(goal.Reward)
	local setId = goal.Reward.Set
	if type(setId) == "string" and ShopCatalog.GetSet(setId) then
		table.insert(list, 1, { Key = "Set", Kind = "Set", Id = setId })
	end
	return list
end

-- pays one reward; call inside PlayerData.Batch
local function give(data, r)
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
	elseif r.Kind == "Set" then
		-- a set unlocks its own stage + mic too (as buying it does)
		local set = ShopCatalog.GetSet(r.Id)
		local stage, mic = ShopCatalog.SetPieces(set)
		if not data.Inventory.Sets.Has(r.Id) then
			data.Inventory.Sets.Add(r.Id)
		end
		if stage and not data.Inventory.Stages.Has(stage.Id) then
			data.Inventory.Stages.Add(stage.Id)
		end
		if mic and not data.Inventory.Mics.Has(mic.Id) then
			data.Inventory.Mics.Add(mic.Id)
		end
	else
		local set = data.Inventory[ITEM_SETS[r.Key]]
		if set and not set.Has(r.Id) then
			set.Add(r.Id)
		end
	end
end

-- every goal hit so far that this player hasn't had yet, paid and revealed
local function payout(player: Player)
	if reached == 0 or paying[player] then
		return
	end
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	paying[player] = true
	local due = {}
	for i = 1, reached do
		if not data.Rewards.Claimed.Has(key(GOALS[i])) then
			table.insert(due, GOALS[i])
		end
	end
	if #due > 0 then
		PlayerData.Batch(player, function()
			for _, g in due do
				data.Rewards.Claimed.Add(key(g))
				for _, r in rewardList(g) do
					give(data, r)
				end
			end
		end)
		-- one reveal for everything paid now: currencies added up, items each once
		local merged, sums, goals = {}, {}, {}
		for _, g in due do
			table.insert(goals, g.Likes)
			for _, r in rewardList(g) do
				if r.Kind == "Currency" then
					Analytics.Economy(player, "Source", r.Key, r.Amount, Currencies.Data(data, r.Key).Get(), AnalyticsEvents.Transactions.LikeGoal, g.Id)
					if sums[r.Key] then
						sums[r.Key].Amount += r.Amount
					else
						sums[r.Key] = table.clone(r)
						table.insert(merged, sums[r.Key])
					end
				else
					table.insert(merged, r)
				end
			end
		end
		RewardsRemote:Fire(player, { Message = "LikeGoal", Goals = goals, Likes = goals[#goals], Rewards = merged })
	end
	paying[player] = nil
end

local function setReached(n: number)
	n = math.clamp(n, 0, #GOALS)
	if n <= reached then
		return
	end
	reached = n
	ReplicatedStorage:SetAttribute(LikeGoalConstants.REACHED, reached)
	for _, player in Players:GetPlayers() do
		task.spawn(payout, player)
	end
end

local function store(): DataStore?
	local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, LikeGoalConstants.STORE)
	return if ok then s else nil
end

-- a real count: the sign, and any new goal hit is saved for good
local function counted(n: number)
	likes = n
	ReplicatedStorage:SetAttribute(LikeGoalConstants.ATTRIBUTE, n)
	local hits = LikeGoalConstants.Hits(n)
	if hits > reached then
		local s = store()
		if s then
			local ok, saved = pcall(s.UpdateAsync, s, "Reached", function(old)
				return math.max(tonumber(old) or 0, hits)
			end)
			if ok and tonumber(saved) then
				hits = math.max(hits, tonumber(saved) :: number)
			end
		end
		setReached(hits)
	end
end

local function read()
	local url = `{LikeGoalConstants.URL}?universeId={game.GameId}`
	local ok, body = pcall(HttpService.GetAsync, HttpService, url, true)
	if not ok then
		warn("[LikeGoalService] couldn't read the like count:", body)
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	local n = decoded and type(data) == "table" and tonumber(data.likes)
	if not n then
		warn("[LikeGoalService] the Worker sent something unexpected:", body)
		return
	end
	counted(math.floor(n))
end

function LikeGoalService.Set(n: number)
	n = math.max(0, math.floor(n))
	likes = n
	ReplicatedStorage:SetAttribute(LikeGoalConstants.ATTRIBUTE, n)
	setReached(LikeGoalConstants.Hits(n))
end

function LikeGoalService.Start()
	if started then
		return
	end
	started = true
	ReplicatedStorage:SetAttribute(LikeGoalConstants.ATTRIBUTE, likes)
	ReplicatedStorage:SetAttribute(LikeGoalConstants.REACHED, reached)

	local function onJoin(player: Player)
		if PlayerData.WaitForData(player) then
			payout(player)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		paying[player] = nil
	end)

	task.spawn(function()
		-- goals already hit (they count even before the first read, or if likes dropped)
		local s = store()
		if s then
			local ok, saved = pcall(s.GetAsync, s, "Reached")
			if ok and tonumber(saved) then
				setReached(tonumber(saved) :: number)
			end
		end
		if LikeGoalConstants.URL == "" then
			return
		end
		if not HttpService.HttpEnabled then
			if RunService:IsStudio() then
				warn("[LikeGoalService] HTTP requests are off (Game Settings → Security): the like goal can't count")
			end
			return
		end
		while true do
			read()
			task.wait(LikeGoalConstants.REFRESH)
		end
	end)
end

return LikeGoalService
