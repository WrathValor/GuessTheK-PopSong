--| ReferralService
-- Invite friends (Constants/ReferralConstants; design boards "Invite friends" + "Referral
-- moments"). Who invited a new player comes from their join data: the LaunchData our Invite
-- button puts on Roblox's invite ("ref:<userId>"), else Roblox's own ReferredByPlayerId (share
-- links). Only a player's very first load counts (Referral.Seen, and nothing played yet), and
-- InvitedBy is set once, so each new player counts for one inviter, once.
--   1. the friend joins: + FRIEND_GIFT straight away, and they're listed as "Joined" with the
--      inviter. The client shows the "You were invited!" card (Referral.Welcomed).
--   2. their first game ends (a duel, solo practice or the tutorial): listed as "Played".
--   3. the inviter is paid INVITER_GIFT per played friend not yet in Referral.Paid: now if
--      they're online (here or in another server, through MessagingService), else the next
--      time they join. #Paid is the milestone count; milestones are claimed from the screen.
-- Each inviter's friends live in a DataStore (ReferralConstants.STORE, key = their UserId)
-- written with UpdateAsync, because the inviter's own profile is locked to their server.
--
-- ReferralRemote, client → server: { Action = "State" }      (the Invite Friends screen opened)
--                                  { Action = "Welcomed" }   (the welcome card was collected)
--                                  { Action = "Claim", Need = n }
-- server → client: { Message = "State", Friends = { { UserId, Name, Played } } (newest first), Played = n }
--                  { Message = "Paid", Friends = { { UserId, Name } }, Coins = n, Played = n }
--                  { Message = "Claimed", Ok = bool, Need = n, Text = string, Items = { ... } }
--   Items (as RewardsService toasts): { Kind = "Title" | "Mic" | "Stage" | "Banner" | "Photocard", Name, Id }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local HttpService = game:GetService("HttpService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local ReferralConstants = require(ReplicatedStorage.Constants.ReferralConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local Analytics = require(script.Parent.Analytics)

local ReferralRemote = Bridgenet.ReferenceBridge("ReferralRemote")
local TX = AnalyticsEvents.Transactions

--| Constants

local MIN_GAP = 0.5 -- between requests from one player
local STATE_GAP = 8 -- a State request re-reads the DataStore at most this often
local RETRIES = 3

--| Variables

local ReferralService = {}

local store: DataStore? = nil
local last: { [Player]: number } = {}
local lastSync: { [Player]: number } = {}
local syncing: { [Player]: boolean } = {}
local crediting: { [Player]: boolean } = {}

--| Helpers

local function getStore(): DataStore?
	if not store then
		local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, ReferralConstants.STORE)
		store = if ok then ds else nil
	end
	return store
end

local function withRetries(fn: () -> any): (boolean, any)
	local ok, result
	for attempt = 1, RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(attempt)
	end
	warn("[Referral]", result)
	return false, result
end

local function count(list: { any }?): number
	return if type(list) == "table" then #list else 0
end

local function displayName(userId: number): string
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, { userId })
	if ok and type(infos) == "table" and infos[1] and infos[1].DisplayName then
		return infos[1].DisplayName
	end
	local ok2, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return if ok2 and type(name) == "string" then name else "A friend"
end

-- who invited this player, from their join data (nil = nobody), and how
local function inviterOf(player: Player): (number?, string?)
	local ok, join = pcall(player.GetJoinData, player)
	if not ok or type(join) ~= "table" then
		join = {}
	end
	local launch = join.LaunchData
	if type(launch) == "string" and launch ~= "" then
		local id = tonumber(string.match(launch, "^ref:(%d+)$"))
		if not id then
			local decoded = select(2, pcall(HttpService.JSONDecode, HttpService, launch))
			id = type(decoded) == "table" and tonumber(decoded.ref) or nil
		end
		if id and id > 0 then
			return id, "LaunchData"
		end
	end
	local referred = tonumber(join.ReferredByPlayerId)
	if referred and referred > 0 then
		return referred, "Referred"
	end
	if RunService:IsStudio() and ReferralConstants.STUDIO_INVITER > 0 then
		return ReferralConstants.STUDIO_INVITER, "Studio"
	end
	return nil, nil
end

-- nothing played or earned yet: a brand-new account in this game
local function fresh(data): boolean
	return not data.Referral.Seen.Get()
		and data.Statistics.PlayTime.Get() == 0
		and data.Player.XP.Get() == 0
		and data.Statistics.Duels.Get() == 0
		and data.Statistics.SoloGames.Get() == 0
		and not data.Settings.TutorialDone.Get()
end

-- the friend has finished a game of any kind
local function hasPlayed(data): boolean
	return data.Statistics.Duels.Get() > 0 or data.Statistics.SoloGames.Get() > 0 or data.Rewards.Claimed.Has("Tutorial")
end

-- an inviter's friends, newest first: { { UserId, Name, Played, Time } }
local function listOf(record): { any }
	local out = {}
	for id, f in (type(record) == "table" and type(record.F) == "table" and record.F) or {} do
		table.insert(out, { UserId = tonumber(id), Name = f.N or "A friend", Played = f.P == 1, Time = f.T or 0 })
	end
	table.sort(out, function(a, b)
		return a.Time > b.Time
	end)
	return out
end

-- tell the inviter's server (this one or another) to look at their friends again
local function ping(inviterId: number)
	local here = Players:GetPlayerByUserId(inviterId)
	if here then
		task.spawn(ReferralService.Sync, here, true)
		return
	end
	pcall(MessagingService.PublishAsync, MessagingService, ReferralConstants.TOPIC, { To = inviterId })
end

--| Public

-- Adds / updates `friendId` in the inviter's list (played = their first game is done).
-- Returns false if the DataStore couldn't be written.
function ReferralService.Record(inviterId: number, friendId: number, name: string, played: boolean): boolean
	local ds = getStore()
	if not ds then
		return false
	end
	local ok = withRetries(function()
		ds:UpdateAsync(tostring(inviterId), function(old)
			local record = if type(old) == "table" then old else {}
			record.F = if type(record.F) == "table" then record.F else {}
			local key = tostring(friendId)
			local entry = record.F[key] or { N = name, P = 0, T = os.time() }
			entry.N = name
			if played then
				entry.P = 1
			end
			record.F[key] = entry
			-- keep the list bounded: the oldest friends who never played go first
			local list = listOf(record)
			local excess = #list - ReferralConstants.MAX_RECORDS
			for i = #list, 1, -1 do
				if excess <= 0 then
					break
				end
				if not list[i].Played then
					record.F[tostring(list[i].UserId)] = nil
					excess -= 1
				end
			end
			return record
		end)
	end)
	if ok then
		ping(inviterId)
	end
	return ok
end

-- Reads the inviter's friends, pays for any who played and aren't paid yet, and sends the
-- client the list. `force` skips the STATE_GAP throttle.
function ReferralService.Sync(player: Player, force: boolean?)
	if syncing[player] then
		return
	end
	local now = os.clock()
	if not force and lastSync[player] and now - lastSync[player] < STATE_GAP then
		return
	end
	local data = PlayerData.Get(player)
	local ds = getStore()
	if not data or not ds then
		return
	end
	syncing[player] = true
	lastSync[player] = now
	local ok, record = withRetries(function()
		return ds:GetAsync(tostring(player.UserId))
	end)
	syncing[player] = nil
	if not ok or not player.Parent then
		return
	end

	local list = listOf(record)
	local newlyPaid = {}
	for _, f in list do
		if f.Played and f.UserId and not data.Referral.Paid.Has(tostring(f.UserId)) then
			table.insert(newlyPaid, f)
		end
	end
	if #newlyPaid > 0 then
		local coins = ReferralConstants.INVITER_GIFT * #newlyPaid
		PlayerData.Batch(player, function()
			for _, f in newlyPaid do
				data.Referral.Paid.Add(tostring(f.UserId))
			end
			data.Currencies.Won.Increment(coins)
		end)
		local played = count(data.Referral.Paid.Get())
		Analytics.Event(player, "ReferralPaid", #newlyPaid)
		Analytics.Economy(player, "Source", "Coins", coins, data.Currencies.Won.Get(), TX.Referral, "Inviter")
		local friends = {}
		for _, f in newlyPaid do
			table.insert(friends, { UserId = f.UserId, Name = f.Name })
		end
		ReferralRemote:Fire(player, { Message = "Paid", Friends = friends, Coins = coins, Played = played })
	end

	local out = {}
	for _, f in list do
		table.insert(out, { UserId = f.UserId, Name = f.Name, Played = f.Played })
	end
	ReferralRemote:Fire(player, { Message = "State", Friends = out, Played = count(data.Referral.Paid.Get()) })
end

--| Joining + first games

local function onLoaded(player: Player, data)
	if not data.Referral.Seen.Get() then
		local isFresh = fresh(data)
		data.Referral.Seen.Set(true)
		local inviterId, how = nil, nil
		if isFresh and data.Referral.InvitedBy.Get() == "" then
			inviterId, how = inviterOf(player)
		end
		if inviterId and inviterId ~= player.UserId then
			local name = displayName(inviterId)
			if not player.Parent then
				return
			end
			PlayerData.Batch(player, function()
				data.Referral.InvitedBy.Set(tostring(inviterId))
				data.Referral.InviterName.Set(string.sub(name, 1, 40))
				data.Currencies.Won.Increment(ReferralConstants.FRIEND_GIFT)
			end)
			Analytics.Event(player, "ReferralJoined", 1, how)
			Analytics.Economy(player, "Source", "Coins", ReferralConstants.FRIEND_GIFT, data.Currencies.Won.Get(), TX.Referral, "Welcome")
			task.spawn(ReferralService.Record, inviterId, player.UserId, player.DisplayName, false)
		end
	end
	-- the inviter side: anything earned while away
	task.delay(3, ReferralService.Sync, player, true)
end

-- a referred player's first game: tell their inviter (once it's written, it's Credited)
local function checkCredit(player: Player)
	if crediting[player] then
		return
	end
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local inviter = tonumber(data.Referral.InvitedBy.Get())
	if not inviter or data.Referral.Credited.Get() or not hasPlayed(data) then
		return
	end
	crediting[player] = true
	task.spawn(function()
		if ReferralService.Record(inviter, player.UserId, player.DisplayName, true) and player.Parent then
			data.Referral.Credited.Set(true)
		end
		crediting[player] = nil
	end)
end

--| Claims

local function claim(player: Player, need: any)
	local data = PlayerData.Get(player)
	local milestone = type(need) == "number" and ReferralConstants.Milestone(need)
	if not data or not milestone then
		return
	end
	local function fail(text: string)
		ReferralRemote:Fire(player, { Message = "Claimed", Ok = false, Need = need, Text = text })
	end
	if data.Referral.Claimed.Has(milestone.Key) then
		return fail("Already claimed")
	end
	local played = count(data.Referral.Paid.Get())
	if played < milestone.Need then
		return fail(`{milestone.Need - played} more friends to go`)
	end

	local items = {}
	PlayerData.Batch(player, function()
		data.Referral.Claimed.Add(milestone.Key)
		if milestone.Title and not data.Inventory.Titles.Has(milestone.Title) then
			data.Inventory.Titles.Add(milestone.Title)
		end
		if milestone.Mic and not data.Inventory.Mics.Has(milestone.Mic) then
			data.Inventory.Mics.Add(milestone.Mic)
		end
		if milestone.Stage and not data.Inventory.Stages.Has(milestone.Stage) then
			data.Inventory.Stages.Add(milestone.Stage)
		end
		if milestone.Banner and not data.Inventory.Banners.Has(milestone.Banner) then
			data.Inventory.Banners.Add(milestone.Banner)
		end
		if milestone.Photocard and not data.Inventory.Photocards.Has(milestone.Photocard) then
			data.Inventory.Photocards.Add(milestone.Photocard)
		end
	end)
	if milestone.Title then
		table.insert(items, { Kind = "Title", Name = milestone.Title, Id = milestone.Title })
	end
	if milestone.Mic then
		local item = ShopCatalog.GetItem("Mic", milestone.Mic)
		table.insert(items, { Kind = "Mic", Name = if item then item.Name else milestone.Mic, Id = milestone.Mic })
	end
	if milestone.Stage then
		local item = ShopCatalog.GetItem("Stage", milestone.Stage)
		table.insert(items, { Kind = "Stage", Name = if item then item.Name else milestone.Stage, Id = milestone.Stage })
	end
	if milestone.Banner then
		table.insert(items, { Kind = "Banner", Name = SeasonConstants.Banner(milestone.Banner).Name, Id = milestone.Banner })
	end
	if milestone.Photocard then
		table.insert(items, { Kind = "Photocard", Name = SeasonConstants.Banner(milestone.Photocard).Name, Id = milestone.Photocard })
	end
	Analytics.Event(player, "ReferralClaimed", played, milestone.Key)
	ReferralRemote:Fire(player, { Message = "Claimed", Ok = true, Need = milestone.Need, Text = milestone.Text, Items = items })
end

--| Start

function ReferralService.Start()
	ReferralRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" then
			return
		end
		local now = os.clock()
		if last[player] and now - last[player] < MIN_GAP then
			return
		end
		last[player] = now
		if packet.Action == "State" then
			task.spawn(ReferralService.Sync, player, false)
		elseif packet.Action == "Welcomed" then
			local data = PlayerData.Get(player)
			if data and data.Referral.InvitedBy.Get() ~= "" and not data.Referral.Welcomed.Get() then
				data.Referral.Welcomed.Set(true)
			end
		elseif packet.Action == "Claim" then
			claim(player, packet.Need)
		end
	end)

	local function added(player: Player)
		local data = PlayerData.WaitForData(player)
		if data and player.Parent then
			onLoaded(player, data)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		last[player], lastSync[player], syncing[player], crediting[player] = nil, nil, nil, nil
	end)

	-- another server says one of our players has a friend update
	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, ReferralConstants.TOPIC, function(message)
			local to = type(message.Data) == "table" and tonumber(message.Data.To)
			local player = to and Players:GetPlayerByUserId(to)
			if player then
				ReferralService.Sync(player, true)
			end
		end)
		if not ok then
			warn("[Referral] couldn't subscribe:", err)
		end
	end)

	-- first games of referred players, and a slow re-read for everyone online
	task.spawn(function()
		local sinceSync = 0
		while true do
			task.wait(ReferralConstants.CHECK_SECONDS)
			sinceSync += ReferralConstants.CHECK_SECONDS
			local resync = sinceSync >= ReferralConstants.SYNC_SECONDS
			if resync then
				sinceSync = 0
			end
			for _, player in Players:GetPlayers() do
				checkCredit(player)
				if resync then
					task.spawn(ReferralService.Sync, player, true)
				end
			end
		end
	end)
end

return ReferralService
