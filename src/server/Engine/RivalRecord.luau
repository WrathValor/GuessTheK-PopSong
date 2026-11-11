--| RivalRecord
-- Your all-time record against each rival: 1v1 duels only (not solo, Party or the tutorial).
-- Kept in Statistics.Rivals by the rival's userId as "wins.losses.last.time": last = the last
-- five results oldest → newest ("WLWWL"), time = when you last played them. Only the
-- MAX_RIVALS most recent rivals are kept, so the save stays small. A draw changes nothing.
--   RivalRecord.Get(player, rivalId) -> { W, L, Last } | nil
--   RivalRecord.Pair(a, b) -> { [userId] = record vs the other | nil } (the pre-duel chip)
--   RivalRecord.Add(winner, loser) -> { [userId] = record vs the other, with Delta "Win"/"Loss" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server

local MAX_RIVALS = 100
local LAST = 5

local RivalRecord = {}

export type Record = { W: number, L: number, Last: string, Delta: string? }

local function decode(s: string?): (Record?, number)
	if type(s) ~= "string" or s == "" then
		return nil, 0
	end
	local w, l, last, t = s:match("^(%d+)%.(%d+)%.([WL]*)%.(%d+)$")
	if not w then
		return nil, 0
	end
	return { W = tonumber(w) :: number, L = tonumber(l) :: number, Last = last }, tonumber(t) :: number
end

local function encode(r: Record, t: number): string
	return `{r.W}.{r.L}.{r.Last}.{t}`
end

local function dataOf(player: Player)
	local ok, data = pcall(PlayerData.Get, player)
	return if ok then data else nil
end

function RivalRecord.Get(player: Player, rivalId: number): Record?
	local data = dataOf(player)
	if not data then
		return nil
	end
	return (decode(data.Statistics.Rivals[tostring(rivalId)].Get()))
end

function RivalRecord.Pair(a: Player, b: Player): { [string]: Record? }
	return { [tostring(a.UserId)] = RivalRecord.Get(a, b.UserId), [tostring(b.UserId)] = RivalRecord.Get(b, a.UserId) }
end

-- drops the rivals you played longest ago once there are more than MAX_RIVALS
local function trim(data)
	local all = data.Statistics.Rivals.Get() or {}
	local list = {}
	for id, s in all do
		local _, t = decode(s)
		table.insert(list, { Id = id, T = t })
	end
	if #list <= MAX_RIVALS then
		return
	end
	table.sort(list, function(x, y)
		return x.T < y.T
	end)
	for i = 1, #list - MAX_RIVALS do
		data.Statistics.Rivals.Remove(list[i].Id)
	end
end

local function bump(player: Player, rivalId: number, won: boolean, now: number): Record?
	local data = dataOf(player)
	if not data then
		return nil
	end
	local node = data.Statistics.Rivals[tostring(rivalId)]
	local r = decode(node.Get()) or { W = 0, L = 0, Last = "" }
	if won then
		r.W += 1
	else
		r.L += 1
	end
	r.Last = (r.Last .. (if won then "W" else "L")):sub(-LAST)
	PlayerData.Batch(player, function()
		node.Set(encode(r, now))
		trim(data)
	end)
	r.Delta = if won then "Win" else "Loss"
	return r
end

function RivalRecord.Add(winner: Player, loser: Player): { [string]: Record? }
	local now = os.time()
	return {
		[tostring(winner.UserId)] = bump(winner, loser.UserId, true, now),
		[tostring(loser.UserId)] = bump(loser, winner.UserId, false, now),
	}
end

return RivalRecord
