--| GhostRecorder
-- Saves finished 1v1 duels so a "ghost" opponent can replay them later (nothing reads them
-- yet: this only records, so the ghost has real games to draw on the day it's built).
-- Players see nothing; DuelConstants.GHOST_RECORDING turns it off.
--   • recorded: each player's side of a full 1v1 duel (the songs, and per round their tier,
--     answer time, pick and whether it was right), with their level and Season Points
--   • not recorded: solo, the tutorial, party matches, forfeits, a player who answered fewer
--     than GHOST_MIN_ANSWERS rounds or has left, a game Scoring.Suspect flagged, and Studio
--   • stored: DataStore STORE, one recording per player per level band (their latest game
--     there replaces the last), under "B<band>/<userId % 100>/<userId>". So no player fills
--     the pool, a random ghost is ListKeysAsync on a random "B<band>/<00–99>/" prefix, and
--     wiping a player (a data-deletion request) is one RemoveAsync per band:
--     GhostRecorder.Purge / the purgeghosts command
-- A recording (V = 1):
--   { V, U = userId, T = os.time(), L = level, SP, S = score, W = "Win" | "Lose" | "Draw",
--     R = { { Id = songId, Tier, Ok, Time? (nil = no answer), Pick? (the wrong song picked) } } }
-- Song ids are "Name - Artist": a reader has to skip recordings whose songs are gone.
--   GhostRecorder.Record(result, players)   -- from DuelService, after Rewards.Apply
--   GhostRecorder.Purge(userId) -> number   -- recordings removed (yields)

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Levels = require(ReplicatedStorage.Modules.Levels)
local Scoring = require(script.Parent.DuelService.Scoring)

local STORE = "Ghosts_v1"
-- level bands: 1–4, 5–9, 10–19, 20–34, 35+ (each number is where the next band starts)
local BANDS = table.freeze({ 5, 10, 20, 35 })

local GhostRecorder = {}
GhostRecorder.BANDS = BANDS

local store = nil
local function getStore()
	if not store then
		local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
		store = if ok then ds else nil
	end
	return store
end

-- [[ Pure parts (tests/GhostRecorder.spec) ]]

function GhostRecorder.Band(level: number): number
	for i, start in BANDS do
		if level < start then
			return i
		end
	end
	return #BANDS + 1
end

function GhostRecorder.Key(band: number, userId: number): string
	return string.format("B%d/%02d/%d", band, userId % 100, userId)
end

-- One player's recording of a finished duel, or nil when the game isn't worth keeping.
-- `player` only has to be the key used in result.Scores / round.Picks, with a UserId.
function GhostRecorder.Build(result, player, level: number, sp: number)
	if result.Solo or result.Tutorial or result.Party or result.Forfeit then
		return nil
	end
	if #result.Rounds ~= DuelConstants.ROUNDS then
		return nil
	end
	local rounds, picks, answered = {}, {}, 0
	for i, round in result.Rounds do
		local pick = round.Picks[player]
		if not pick then
			return nil
		end
		local did = pick.Picked ~= nil
		answered += if did then 1 else 0
		picks[i] = pick
		rounds[i] = {
			Id = round.Song.Id,
			Tier = pick.Tier,
			Ok = pick.Correct == true,
			Time = if did and pick.Time then math.floor(pick.Time * 100 + 0.5) / 100 else nil,
			Pick = if did and not pick.Correct then pick.Picked else nil,
		}
	end
	if answered < DuelConstants.GHOST_MIN_ANSWERS or Scoring.Suspect(picks) then
		return nil
	end
	return {
		V = 1,
		U = player.UserId,
		T = os.time(),
		L = level,
		SP = sp,
		S = result.Scores[player] or 0,
		W = if result.Draw then "Draw" elseif result.Winner == player then "Win" else "Lose",
		R = rounds,
	}
end

-- [[ Saving ]]

local function save(record)
	local ds = getStore()
	if not ds then
		return
	end
	-- never eat into the write budget other saves need
	local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, Enum.DataStoreRequestType.SetIncrementAsync)
	if not ok or budget < 10 then
		return
	end
	local key = GhostRecorder.Key(GhostRecorder.Band(record.L), record.U)
	-- (the userId list tags the key with its player, for Roblox's data-deletion tooling)
	local saved, err = pcall(ds.SetAsync, ds, key, record, { record.U })
	if not saved then
		warn(`[GhostRecorder] couldn't save {key}: {err}`)
	end
end

function GhostRecorder.Record(result, players: { Player })
	if not DuelConstants.GHOST_RECORDING or RunService:IsStudio() or #players ~= 2 then
		return
	end
	-- (required here, not at the top, so the pure parts above can be tested without player data)
	local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
	for _, player in players do
		if not player.Parent then
			continue
		end
		local ok, data = pcall(PlayerData.Get, player)
		if not ok or not data then
			continue
		end
		local built, record = pcall(GhostRecorder.Build, result, player, (Levels.FromXP(data.Player.XP.Get())), data.Season.SP.Get())
		if built and record then
			task.spawn(save, record)
		elseif not built then
			warn(`[GhostRecorder] {record}`)
		end
	end
end

-- Removes every recording of this player (one per band). Returns how many there were.
function GhostRecorder.Purge(userId: number): number
	local ds = getStore()
	if not ds then
		return 0
	end
	local removed = 0
	for band = 1, #BANDS + 1 do
		local ok, old = pcall(ds.RemoveAsync, ds, GhostRecorder.Key(band, userId))
		if ok and old ~= nil then
			removed += 1
		elseif not ok then
			warn(`[GhostRecorder] couldn't remove band {band} for {userId}: {old}`)
		end
	end
	return removed
end

return GhostRecorder
