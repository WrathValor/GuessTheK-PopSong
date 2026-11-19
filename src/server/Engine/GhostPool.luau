--| GhostPool
-- The ghost rival's recordings (GhostRecorder saves them): a few kept loaded per level band
-- so a ghost can step up the moment someone has waited long enough, with no DataStore wait.
--   • Take picks from the player's level band, then the bands either side. Never their own
--     recording, never one they've already played this session, never one whose songs have
--     left the library.
--   • The pool refills in the background, one band at a time, inside the DataStore read budget.
--   • Nothing recorded to hand out (a new game, a quiet band, Studio without API access):
--     Synthetic makes a believable one from random songs, so a ghost always steps up.
--   GhostPool.Take(player, level) -> recording   -- removed from the pool
--   GhostPool.Usable(record) -> boolean          -- pure (tests/GhostPool.spec)
--   GhostPool.Synthetic(level) -> recording      -- pure apart from math.random

--| Services
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--| Imports
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)
local GhostRecorder = require(script.Parent.GhostRecorder)

--| Constants
local STORE = "Ghosts_v1" -- the same store GhostRecorder writes
local POOL_SIZE = 6 -- recordings kept ready per band
local REFILL_EVERY = 20 -- seconds between background refill passes
local TRIES = 4 -- random key prefixes tried per band per pass
local MIN_BUDGET = 20 -- reads left in the budget before the pool stops reading

-- synthetic ghosts, per level band (1–5): how often they're right, and the snippet tier they
-- usually answer on (weights for tiers 1..5)
local SYNTH_ACCURACY = { 0.5, 0.6, 0.68, 0.75, 0.82 }
local SYNTH_TIERS = {
	{ 0, 1, 3, 4, 2 },
	{ 0, 2, 4, 3, 1 },
	{ 1, 3, 4, 2, 1 },
	{ 1, 4, 3, 2, 0 },
	{ 2, 4, 3, 1, 0 },
}

--| Variables
local GhostPool = {}

local pools: { [number]: { any } } = {}
for band = 1, #GhostRecorder.BANDS + 1 do
	pools[band] = {}
end
-- recordings each player has had this session (by the recorded player's userId)
local seen: { [Player]: { [number]: boolean } } = {}
local refilling = false
local store = nil

--| Helpers
local function getStore()
	if not store then
		local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
		store = if ok then ds else nil
	end
	return store
end

local function budget(kind: Enum.DataStoreRequestType): number
	local ok, n = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
	return if ok then n else 0
end

local function weighted(weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = math.random() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then
			return i
		end
	end
	return #weights
end

-- the band order to look through: the player's, then one either side, then two...
local function bandOrder(band: number): { number }
	local order, count = { band }, #GhostRecorder.BANDS + 1
	for d = 1, count do
		for _, b in { band - d, band + d } do
			if b >= 1 and b <= count then
				table.insert(order, b)
			end
		end
	end
	return order
end

--| Pure parts (tests/GhostPool.spec)

-- A recording the ghost can replay: the current format, a full game, and every song still in
-- the library (a ghost plays the exact songs it was recorded on).
function GhostPool.Usable(record: any): boolean
	if type(record) ~= "table" or record.V ~= 1 or type(record.R) ~= "table" then
		return false
	end
	if #record.R ~= DuelConstants.ROUNDS or type(record.U) ~= "number" or type(record.L) ~= "number" then
		return false
	end
	for _, round in record.R do
		if type(round) ~= "table" or type(round.Id) ~= "string" or not SongLibrary.GetById(round.Id) then
			return false
		end
	end
	return true
end

-- A made-up recording for when there's nothing real to hand out: random songs, answered
-- about as well as a player of that level. U = 0, so it can't match anyone's own recording.
function GhostPool.Synthetic(level: number): any
	local band = GhostRecorder.Band(level)
	local tiers = DuelConstants.TIERS[DuelConstants.DEFAULT_MODE]
	local used, rounds = {}, {}
	for i = 1, DuelConstants.ROUNDS do
		local song = SongLibrary.GetRandomSong(used)
		used[song.Id] = true
		local tier = weighted(SYNTH_TIERS[band])
		local heard = tiers[tier] or 0
		local ok = math.random() < SYNTH_ACCURACY[band]
		local wrong = (not ok) and SongLibrary.GetWrongOptions(song, 1)[1] or nil
		rounds[i] = {
			Id = song.Id,
			Tier = tier,
			Ok = ok,
			-- heard the snippet, then thought about it (a miss sometimes never answers)
			Time = if not ok and math.random() < 0.2 then nil else math.floor((heard + 1.5 + math.random() * 3) * 100) / 100,
			Pick = if wrong then wrong.Id else nil,
		}
	end
	return { V = 1, U = 0, T = os.time(), L = level, SP = 0, S = 0, W = "Lose", R = rounds, Synthetic = true }
end

--| Loading

-- One random recording from this band's store (nil when none was found or the budget is low).
local function fetch(band: number): any
	local ds = getStore()
	if not ds then
		return nil
	end
	if budget(Enum.DataStoreRequestType.ListAsync) < MIN_BUDGET or budget(Enum.DataStoreRequestType.GetAsync) < MIN_BUDGET then
		return nil
	end
	local prefix = string.format("B%d/%02d/", band, math.random(0, 99))
	local ok, pages = pcall(ds.ListKeysAsync, ds, prefix, 20)
	if not ok or not pages then
		return nil
	end
	local keys = pages:GetCurrentPage()
	if #keys == 0 then
		return nil
	end
	local key = keys[math.random(1, #keys)].KeyName
	local got, record = pcall(ds.GetAsync, ds, key)
	if got and GhostPool.Usable(record) then
		return record
	end
	return nil
end

local function has(pool: { any }, userId: number): boolean
	for _, r in pool do
		if r.U == userId then
			return true
		end
	end
	return false
end

local function refill()
	if refilling then
		return
	end
	refilling = true
	for band, pool in pools do
		for _ = 1, TRIES do
			if #pool >= POOL_SIZE then
				break
			end
			local record = fetch(band)
			if record and not has(pool, record.U) then
				table.insert(pool, record)
			end
		end
	end
	refilling = false
end

--| Public

-- A recording for this player's ghost rival, taken out of the pool (always returns one:
-- a synthetic ghost when nothing recorded fits).
function GhostPool.Take(player: Player, level: number): any
	local mine = seen[player] or {}
	seen[player] = mine
	for _, band in bandOrder(GhostRecorder.Band(level)) do
		local pool = pools[band]
		for i, record in pool do
			if record.U ~= player.UserId and not mine[record.U] and GhostPool.Usable(record) then
				table.remove(pool, i)
				mine[record.U] = true
				task.spawn(refill)
				return record
			end
		end
	end
	task.spawn(refill)
	return GhostPool.Synthetic(level)
end

function GhostPool.Start()
	if not DuelConstants.GHOST_ENABLED then
		return
	end
	Players.PlayerRemoving:Connect(function(player)
		seen[player] = nil
	end)
	task.spawn(function()
		-- (Studio reads the live store only with API access on; it falls back to synthetic)
		if RunService:IsStudio() then
			local ok = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
			if not ok then
				return
			end
		end
		while true do
			refill()
			task.wait(REFILL_EVERY)
		end
	end)
end

return GhostPool
