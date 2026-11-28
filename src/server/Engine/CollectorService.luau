--| CollectorService
-- The photocard flex (design boards "69 · Leaderboard · Top Collectors", "69b · Big screen ·
-- Showcase slide"). For every player, whenever their cards, pins or serials change (and once on
-- join):
--   • Statistics.CollectionPoints = Albums.CollectionPoints (the TopCollectors Scribe board)
--   • the player's "FlexCard" attribute = their flex card (Albums.FlexCard: the rarest pinned
--     card, else the rarest owned) as Albums.FlexValue "<cardId>*<copies>*<serial>". The big
--     screen's SHOWCASE slide reads it (Engine/StreetScreens).
--   • the same value saved in FLEX_STORE by UserId (every SAVE_EVERY s when it changed, and on
--     leaving), so the leaderboard can show the card of someone who isn't in this server.
-- The board's top BOARD_ROWS players' flex cards go onto ReplicatedStorage as JSON
-- (ATTRIBUTE: { [userId] = flex value }) for the sign (client/Client/Leaderboards), on every
-- board update and every few minutes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Albums = require(ReplicatedStorage.Modules.Library.Albums)

local FLEX_STORE = "FlexCardsV1"
local ATTRIBUTE = "CollectorCards"
local BOARD = "TopCollectors"
local BOARD_ROWS = 10
local SAVE_EVERY = 120
local CACHE_SECONDS = 600
local SETTLE = 1 -- seconds to gather a burst of changes (a 10-pack)

local CollectorService = {}

local pending: { [Player]: boolean } = {}
local dirty: { [Player]: string } = {} -- flex values not saved to FLEX_STORE yet
local cache: { [number]: { Value: string, At: number } } = {}
local scanning = false

local function store(): DataStore?
	local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, FLEX_STORE)
	return if ok then s else nil
end

local function save(userId: number, value: string)
	local s = store()
	if s then
		local ok, err = pcall(s.SetAsync, s, tostring(userId), value)
		if not ok then
			warn(`[CollectorService] couldn't save {userId}'s flex card: {err}`)
		end
	end
	cache[userId] = { Value = value, At = os.clock() }
end

local function update(player: Player)
	pending[player] = nil
	local data = PlayerData.Get(player)
	if not data or not player.Parent then
		return
	end
	local cards = data.Inventory.Cards.Get() or {}
	local points = Albums.CollectionPoints(cards)
	if data.Statistics.CollectionPoints.Get() ~= points then
		PlayerData.Batch(player, function()
			data.Statistics.CollectionPoints.Set(points)
		end)
	end
	local id, copies = Albums.FlexCard(cards, data.Inventory.Pins.Get())
	local serial = id and Albums.Serials(data.Inventory.Serials[id].Get())[1]
	local value = Albums.FlexValue(id, copies, serial)
	if player:GetAttribute("FlexCard") ~= value then
		player:SetAttribute("FlexCard", value)
		dirty[player] = value
	end
end

local function queue(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(SETTLE, update, player)
end

-- the top rows' flex cards, onto ReplicatedStorage for the sign
local function scan()
	if scanning then
		return
	end
	scanning = true
	local ok, entries = pcall(PlayerData.GetLeaderboard, BOARD, BOARD_ROWS)
	local out = {}
	for _, entry in (if ok and type(entries) == "table" then entries else {}) do
		local id = tonumber(entry.UserId)
		if not id or id <= 0 then
			continue
		end
		local online = Players:GetPlayerByUserId(id)
		local value = online and online:GetAttribute("FlexCard")
		if type(value) ~= "string" then
			local hit = cache[id]
			if hit and os.clock() - hit.At < CACHE_SECONDS then
				value = hit.Value
			else
				local s = store()
				local got, saved = false, nil
				if s then
					got, saved = pcall(s.GetAsync, s, tostring(id))
				end
				value = if got and type(saved) == "string" then saved else ""
				cache[id] = { Value = value, At = os.clock() }
			end
		end
		if value ~= "" then
			out[tostring(id)] = value
		end
	end
	ReplicatedStorage:SetAttribute(ATTRIBUTE, HttpService:JSONEncode(out))
	scanning = false
end

function CollectorService.Start()
	ReplicatedStorage:SetAttribute(ATTRIBUTE, "{}")

	local function joined(player: Player)
		local ok, data = pcall(PlayerData.WaitForData, player)
		if not ok or not data or not player.Parent then
			return
		end
		update(player)
		dirty[player] = nil -- (nothing new to save until it changes)
		for _, path in { data.Inventory.Cards, data.Inventory.Pins, data.Inventory.Serials } do
			path.Observe(function()
				queue(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(joined, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(joined, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		local value = dirty[player]
		dirty[player] = nil
		if value then
			task.spawn(save, player.UserId, value)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SAVE_EVERY)
			for player, value in dirty do
				dirty[player] = nil
				save(player.UserId, value)
			end
		end
	end)

	PlayerData.OnLeaderboard:Connect(function()
		task.defer(scan)
	end)
	task.spawn(function()
		while true do
			pcall(scan)
			task.wait(300)
		end
	end)
end

return CollectorService
