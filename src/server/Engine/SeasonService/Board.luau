--| Board
-- The season's Ranks boards, one OrderedDataStore each per season ("Season<Kind>_<season id>"),
-- the top SeasonConstants.BOARD_SIZE read back every BOARD_REFRESH seconds. Kinds (KINDS):
--   "SP"   – Season Rating: Season Points
--   "Wins" – Season Wins: duels won this season
--   Board.Mark(player, kind, value) -- SeasonService after it changes; written in batches (BOARD_FLUSH)
--   Board.Flush(player)             -- write this player's pending values now (they're leaving)
--   Board.Packet(player, kind)      -- what the Ranks tab shows: { Kind, Season, Entries (top 10), Rank?, Cutoff?, Size }
--   Board.Start()                   -- the flush + refresh loops
-- Every DataStore call is pcall'd: in Studio without API access the board just stays empty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")
local Players = game:GetService("Players")

local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)

local Board = {}

local SHOWN = 10 -- top 3 cards + 7 rows on the Ranks tab

local KINDS = { "SP", "Wins" }
Board.KINDS = KINDS

-- per kind: userId → value waiting to be written / the last read (best first) and its season
local pending: { [string]: { [number]: number } } = {}
local top: { [string]: { { UserId: number, Value: number } } } = {}
local topSeason: { [string]: string } = {}
for _, kind in KINDS do
	pending[kind], top[kind], topSeason[kind] = {}, {}, ""
end
local names: { [number]: string } = {} -- userId → display name (cached for the server's life)

local function store(kind: string)
	local id = SeasonConstants.Current().Id
	local ok, ds = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, `Season{kind}_{id}`)
	return if ok then ds else nil, id
end

local function write(kind: string, userId: number, value: number)
	local ds = store(kind)
	if ds then
		local ok, err = pcall(ds.SetAsync, ds, tostring(userId), math.floor(value))
		if not ok then
			warn("[SeasonBoard] write failed:", kind, err)
		end
	end
end

function Board.Mark(player: Player, kind: string, value: number)
	if pending[kind] then
		pending[kind][player.UserId] = value
	end
end

function Board.Flush(player: Player)
	for _, kind in KINDS do
		local value = pending[kind][player.UserId]
		if value then
			pending[kind][player.UserId] = nil
			write(kind, player.UserId, value)
		end
	end
end

local function flushAll()
	for _, kind in KINDS do
		local batch = pending[kind]
		pending[kind] = {}
		for userId, value in batch do
			write(kind, userId, value)
		end
	end
end

-- display names for the ids we don't know yet (one web call for the lot)
local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] then
			local online = Players:GetPlayerByUserId(id)
			if online then
				names[id] = online.DisplayName
			else
				table.insert(missing, id)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and infos then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	end
end

local function refresh(kind: string)
	local ds, id = store(kind)
	if not ds then
		return
	end
	local ok, pages = pcall(ds.GetSortedAsync, ds, false, SeasonConstants.BOARD_SIZE, 1)
	if not ok or not pages then
		return
	end
	local list = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(list, { UserId = userId, Value = entry.value })
		end
	end
	top[kind], topSeason[kind] = list, id
	local ids = {}
	for i = 1, math.min(SHOWN, #list) do
		table.insert(ids, list[i].UserId)
	end
	resolveNames(ids)
end

function Board.Packet(player: Player, kind: string)
	if not top[kind] then
		kind = "SP"
	end
	local id = SeasonConstants.Current().Id
	local list = top[kind]
	local entries = {}
	local rank: number? = nil
	if topSeason[kind] == id then
		for i, row in list do
			if row.UserId == player.UserId then
				rank = i
			end
			if i <= SHOWN then
				local online = Players:GetPlayerByUserId(row.UserId)
				table.insert(entries, {
					Rank = i,
					UserId = row.UserId,
					Name = names[row.UserId] or "Player",
					Value = row.Value,
					-- an online player's equipped banner; the client picks one for anyone else
					Banner = if online then online:GetAttribute("Banner") else nil,
				})
			end
		end
	end
	local full = #list >= SeasonConstants.BOARD_SIZE
	return {
		Kind = kind,
		Season = id,
		Entries = entries,
		Rank = rank, -- nil = not in the top BOARD_SIZE (yet)
		Cutoff = if full then list[#list].Value else nil, -- what it takes to get onto the board
		Size = SeasonConstants.BOARD_SIZE,
	}
end

function Board.Start()
	task.spawn(function()
		while true do
			task.wait(SeasonConstants.BOARD_FLUSH)
			flushAll()
		end
	end)
	task.spawn(function()
		while true do
			for _, kind in KINDS do
				refresh(kind)
			end
			task.wait(SeasonConstants.BOARD_REFRESH)
		end
	end)
	game:BindToClose(flushAll)
end

return Board
