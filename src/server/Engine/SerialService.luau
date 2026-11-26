--| SerialService
-- Serial numbers and One of Ones for K-POPPED! photocards. Both are shared by every server, so
-- they live in DataStores (AlbumConstants.SERIAL_STORE, ONE_OF_ONE_STORE), not player data.
--
-- Serials: a numbered rarity (AlbumConstants rarity Serial = true) gives every copy pulled the
-- next number for its card id: the first Jisoo · Born Pink · Fansign Benefit anyone pulls is
-- #1, the next #2, and so on. Engine/AlbumService mints them (SerialService.Mint) and saves them
-- in Inventory.Serials ("3,17", lowest first). If the counter can't be reached, the copy is
-- counted in Inventory.SerialsPending and gets its number on the next try (SerialService.Settle,
-- on join and every minute). Selling a copy (Engine/BinderService) gives up the highest number;
-- a copy still waiting for a number goes first.
--
-- One of One: a single copy of each card id in the whole game. When a pull rolls One of One,
-- AlbumService claims it here (SerialService.Claim) before the card is saved; if someone owns
-- it already (or the store can't be reached) the pull lands on AlbumConstants.FALLBACK_RARITY.
-- A One of One reads "1 OF 1" and can't be sold. Every server is told (ONE_OF_ONE_TOPIC), and
-- passes it on to its players as AlbumRemote { Message = "Pull", …, Global = true }
-- (Client/PullChat).
--
-- Trading will move serials between players later: Inventory.Serials is the record of who
-- holds which number.
--   SerialService.Mint(cardId) → number?          (yields)
--   SerialService.Claim(cardId, player) → boolean (yields)
--   SerialService.Settle(player, data)            (yields)
--   SerialService.Rename(player, data)            (cards saved under a renamed album id → its new id)
--   SerialService.Owners(cardIds) → { [card id] = name } (yields; who owns each One of One, for the binder)
--   SerialService.Broadcast(packet)               (a One of One pull, to every other server)
--
-- History: every numbered copy (a serial, One of Ones included) keeps who rolled it and who has
-- owned it since, in AlbumConstants.HISTORY_STORE (Albums.HistoryKey):
--   SerialService.Record(cardId, serial, player)    the roll (AlbumService, after the pull is saved)
--   SerialService.Transfer(cardId, serial, player)  a new owner (Engine/MarketService)
--   SerialService.SetOwner(cardId, player)          a One of One's owner record moves (the Market)
--   SerialService.History(cardId, serial) → { Rolled, Owners }? (yields; cached a minute)

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)

local AlbumRemote = Bridgenet.ReferenceBridge("AlbumRemote")

local SerialService = {}

local TRIES = 3
local claimed: { [string]: boolean } = {} -- One of Ones known to be owned (saves a DataStore read)
local claiming: { [string]: boolean } = {} -- claims in flight on this server
local settling: { [Player]: boolean } = {}
local OWNER_TTL = 120 -- seconds an "unclaimed" answer is trusted (an owner never changes)
local owners: { [string]: { Name: string?, At: number } } = {} -- One of One owners read so far

local function store(name: string): DataStore?
	local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	return if ok then s else nil
end

-- waits (a little) for UpdateAsync budget, so a burst of pulls doesn't throw
local function budget()
	for _ = 1, 10 do
		local ok, left = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, Enum.DataStoreRequestType.UpdateAsync)
		if not ok or left > 0 then
			return
		end
		task.wait(1)
	end
end

-- [[ Serials ]]

-- the next serial for this card id, or nil if the counter couldn't be reached
function SerialService.Mint(cardId: string): number?
	local s = store(AlbumConstants.SERIAL_STORE)
	if not s then
		return nil
	end
	for try = 1, TRIES do
		budget()
		local ok, n = pcall(s.UpdateAsync, s, Albums.StoreKey(cardId), function(old)
			return (tonumber(old) or 0) + 1
		end)
		if ok and tonumber(n) then
			return tonumber(n)
		end
		warn(`[SerialService] couldn't mint a serial for {cardId} (try {try}): {n}`)
		task.wait(try)
	end
	return nil
end

-- gives numbers to this player's copies that are still waiting for one
function SerialService.Settle(player: Player, data)
	if settling[player] then
		return
	end
	-- numbered copies from before serials existed: queue them for a number
	local serials = data.Inventory.Serials.Get() or {}
	local waiting = data.Inventory.SerialsPending.Get() or {}
	local missing = {}
	for cardId, copies in data.Inventory.Cards.Get() or {} do
		if Albums.Numbered(cardId) then
			local short = copies - #Albums.Serials(serials[cardId]) - (waiting[cardId] or 0)
			if short > 0 then
				missing[cardId] = short
			end
		end
	end
	if next(missing) then
		PlayerData.Batch(player, function()
			for cardId, short in missing do
				if string.find(cardId, ":oneofone$") then
					data.Inventory.Serials[cardId].Set("1")
				else
					data.Inventory.SerialsPending[cardId].Set((waiting[cardId] or 0) + short)
				end
			end
		end)
	end

	local pending = data.Inventory.SerialsPending.Get() or {}
	if next(pending) == nil then
		return
	end
	settling[player] = true
	for cardId, count in pending do
		for _ = 1, count do
			local serial = SerialService.Mint(cardId)
			if not serial or not player.Parent then
				settling[player] = nil
				return
			end
			PlayerData.Batch(player, function()
				local waiting = data.Inventory.SerialsPending[cardId].Get() or 0
				if waiting <= 0 then
					return -- the copy was sold while its number was on the way
				end
				local left = waiting - 1
				if left <= 0 then
					data.Inventory.SerialsPending.Remove(cardId)
				else
					data.Inventory.SerialsPending[cardId].Set(left)
				end
				data.Inventory.Serials[cardId].Set(Albums.AddSerial(data.Inventory.Serials[cardId].Get(), serial))
			end)
		end
	end
	settling[player] = nil
end

-- [[ History ]]

local HISTORY_TTL = 60
local histories: { [string]: { Record: any, At: number } } = {}

local function owner(player: Player): { [string]: any }
	return { UserId = player.UserId, Name = player.Name, At = os.time() }
end

-- the roll of a numbered copy: its first owner (a copy that has a history already keeps it)
function SerialService.Record(cardId: string, serial: number, player: Player)
	local s = store(AlbumConstants.HISTORY_STORE)
	if not s or type(serial) ~= "number" then
		return
	end
	local key = Albums.HistoryKey(cardId, serial)
	local me = owner(player)
	budget()
	local ok, record = pcall(s.UpdateAsync, s, key, function(old)
		if type(old) == "table" then
			return nil
		end
		return { Card = cardId, Rolled = me, Owners = { me } }
	end)
	if ok and type(record) == "table" then
		histories[key] = { Record = record, At = os.clock() }
	elseif not ok then
		warn(`[SerialService] couldn't record {cardId} #{serial}: {record}`)
	end
end

-- a numbered copy changes hands (trading): the player is its newest owner
function SerialService.Transfer(cardId: string, serial: number, player: Player)
	local s = store(AlbumConstants.HISTORY_STORE)
	if not s then
		return
	end
	local key = Albums.HistoryKey(cardId, serial)
	local me = owner(player)
	budget()
	local ok, record = pcall(s.UpdateAsync, s, key, function(old)
		local r = if type(old) == "table" then old else { Card = cardId, Owners = {} }
		r.Owners = r.Owners or {}
		table.insert(r.Owners, me)
		while #r.Owners > AlbumConstants.HISTORY_OWNERS_MAX do
			table.remove(r.Owners, 2) -- (the roller stays first)
		end
		return r
	end)
	if ok and type(record) == "table" then
		histories[key] = { Record = record, At = os.clock() }
	end
end

-- who rolled this copy and everyone who has owned it, oldest first (nil if none is saved)
function SerialService.History(cardId: string, serial: number): any
	local key = Albums.HistoryKey(cardId, serial)
	local cached = histories[key]
	if cached and os.clock() - cached.At < HISTORY_TTL then
		return cached.Record
	end
	local s = store(AlbumConstants.HISTORY_STORE)
	if not s then
		return nil
	end
	local ok, record = pcall(s.GetAsync, s, key)
	if not ok then
		return cached and cached.Record
	end
	histories[key] = { Record = record, At = os.clock() }
	return record
end

-- [[ One of One ]]

-- claims this card id's One of One for the player: true only if it's now theirs
function SerialService.Claim(cardId: string, player: Player): boolean
	if claimed[cardId] or claiming[cardId] then
		return false
	end
	local s = store(AlbumConstants.ONE_OF_ONE_STORE)
	if not s then
		return false
	end
	claiming[cardId] = true
	budget()
	local ok, record = pcall(s.UpdateAsync, s, Albums.StoreKey(cardId), function(old)
		if old ~= nil then
			return nil -- someone has it: leave it alone
		end
		return { UserId = player.UserId, Name = player.Name, At = os.time() }
	end)
	claiming[cardId] = nil
	if not ok then
		warn(`[SerialService] couldn't claim the One of One {cardId}: {record}`)
		return false
	end
	claimed[cardId] = true -- either way, nobody else can have it now
	if type(record) == "table" and type(record.Name) == "string" then
		owners[cardId] = { Name = record.Name, At = os.clock() }
	end
	return type(record) == "table" and record.UserId == player.UserId
end

-- a One of One changed hands (bought on the Market): its owner record follows (yields)
function SerialService.SetOwner(cardId: string, player: Player)
	local s = store(AlbumConstants.ONE_OF_ONE_STORE)
	if not s then
		return
	end
	budget()
	local record = { UserId = player.UserId, Name = player.Name, At = os.time() }
	local ok, err = pcall(s.SetAsync, s, Albums.StoreKey(cardId), record)
	if ok then
		claimed[cardId] = true
		owners[cardId] = { Name = player.Name, At = os.clock() }
	else
		warn(`[SerialService] couldn't move the One of One {cardId} to {player.Name}: {err}`)
	end
end

-- who owns each of these One of One card ids: { [card id] = name } (unclaimed ones are left out).
-- Owners are cached for good, unclaimed answers for OWNER_TTL seconds. (yields)
function SerialService.Owners(cardIds: { string }): { [string]: string }
	local out = {}
	local s = nil
	for _, cardId in cardIds do
		local known = owners[cardId]
		if known and (known.Name or os.clock() - known.At < OWNER_TTL) then
			out[cardId] = known.Name
			continue
		end
		s = s or store(AlbumConstants.ONE_OF_ONE_STORE)
		if not s then
			break
		end
		local ok, left = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, Enum.DataStoreRequestType.GetAsync)
		if ok and left < 1 then
			break -- out of budget: show what we know, the rest reads "Unclaimed" for now
		end
		local got, record = pcall(s.GetAsync, s, Albums.StoreKey(cardId))
		if not got then
			warn(`[SerialService] couldn't read the One of One {cardId}: {record}`)
			break
		end
		local name = if type(record) == "table" and type(record.Name) == "string" then record.Name else nil
		owners[cardId] = { Name = name, At = os.clock() }
		if name then
			claimed[cardId] = true
		end
		out[cardId] = name
	end
	return out
end

-- [[ Broadcast ]]

-- tells the other servers about a Signed Polaroid or One of One pull (this server's players
-- already know)
function SerialService.Broadcast(packet: { [string]: any })
	task.spawn(function()
		local message = table.clone(packet)
		message.JobId = game.JobId
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, AlbumConstants.ONE_OF_ONE_TOPIC, message)
		if not ok then
			warn(`[SerialService] couldn't broadcast a rare pull: {err}`)
		end
	end)
end

-- [[ Renamed albums ]]

-- moves cards (and their serials) saved under an old album id (AlbumConstants.RENAMED_ALBUMS)
-- to the album's current id. Runs on join, before Settle.
function SerialService.Rename(player: Player, data)
	local moves = {}
	for cardId in data.Inventory.Cards.Get() or {} do
		local new = Albums.Current(cardId)
		if new ~= cardId then
			table.insert(moves, { cardId, new })
		end
	end
	for cardId in data.Inventory.SerialsPending.Get() or {} do
		local new = Albums.Current(cardId)
		if new ~= cardId and not data.Inventory.Cards[cardId].Get() then
			table.insert(moves, { cardId, new })
		end
	end
	if #moves == 0 then
		return
	end
	PlayerData.Batch(player, function()
		for _, move in moves do
			local old, new = move[1], move[2]
			local copies = data.Inventory.Cards[old].Get()
			if copies then
				local total = math.min((data.Inventory.Cards[new].Get() or 0) + copies, AlbumConstants.RAINBOW_COPIES)
				data.Inventory.Cards[new].Set(total)
				data.Inventory.Cards.Remove(old)
			end
			local serials = data.Inventory.Serials[old].Get()
			if serials then
				local merged = data.Inventory.Serials[new].Get()
				for _, n in Albums.Serials(serials) do
					merged = Albums.AddSerial(merged, n)
				end
				data.Inventory.Serials[new].Set(merged)
				data.Inventory.Serials.Remove(old)
			end
			local pending = data.Inventory.SerialsPending[old].Get()
			if pending then
				data.Inventory.SerialsPending[new].Set((data.Inventory.SerialsPending[new].Get() or 0) + pending)
				data.Inventory.SerialsPending.Remove(old)
			end
		end
	end)
end

-- [[ Lifecycle ]]

local function onPlayerAdded(player: Player)
	local data = PlayerData.WaitForData(player)
	if data and player.Parent then
		SerialService.Rename(player, data)
		SerialService.Settle(player, data)
	end
end

function SerialService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		settling[player] = nil
	end)
	-- retry waiting serials now and then
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.Get(player)
				if data then
					task.spawn(SerialService.Settle, player, data)
				end
			end
		end
	end)
	-- One of Ones pulled in other servers
	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, AlbumConstants.ONE_OF_ONE_TOPIC, function(message)
			local packet = type(message) == "table" and message.Data
			if type(packet) ~= "table" or packet.JobId == game.JobId then
				return
			end
			if type(packet.Card) == "string" and packet.Rarity == "oneofone" then
				claimed[packet.Card] = true -- (only a One of One is claimed for the whole game)
			end
			packet.JobId = nil
			packet.Global = true
			AlbumRemote:Fire(Bridgenet.AllPlayers(), packet)
		end)
		if not ok then
			warn(`[SerialService] couldn't listen for One of Ones: {err}`)
		end
	end)
end

return SerialService
