--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Signal = require(ReplicatedStorage.Packages.signal)

--| Constants
local ROUNDS = 7
local ROUND_TIME = 15
local INTERMISSION = 3
local POINT_TIERS = { -- { within seconds, points }
	{ 0.5, 10 }, { 2, 7 }, { 4, 5 }, { 8, 2 }, { 15, 1 },
}

--| Types
export type Result = {
	Winner: Player?,
	Scores: { [Player]: number },
	Forfeit: boolean,
}

--| Duels
local Duels = {}
Duels.__index = Duels

function Duels.new(stage, player1: Player, player2: Player)
	local self = setmetatable({}, Duels)

	self.Stage = stage
	self.Players = { player1, player2 }
	self.Scores = { [player1] = 0, [player2] = 0 }
	self.SelectedSong = "";
	self.ChosenSongs = {};
    self.RoundData = {};
	self.Round = 0

	self.Ended = Signal.new()
	self._janitor = Janitor.new()
	self._janitor:Add(self.Ended)
	self._running = false

	return self
end

function Duels.PointsFor(elapsed: number): number
	for _, tier in POINT_TIERS do
		if elapsed <= tier[1] then
			return tier[2]
		end
	end
	return 0
end

function Duels:Start()
	if self._running then return end
	self._running = true

	local thread = task.spawn(function()
		for round = 1, ROUNDS do
			self.Round = round
			self:_playRound()
			if not self._running then return end
			task.wait(INTERMISSION)
		end
		self:_finish(nil, false)
	end)

	-- if the duel is destroyed mid-round, kill the loop
	self._janitor:Add(function()
		if coroutine.status(thread) ~= "dead" then
			task.cancel(thread)
		end
	end, true)
end

function Duels:GetSong()
	return Library.Songs.GetRandomSong()
end

function Duels:_playRound()
	

	-- TODO (yours):
	--  1. pick a song from Library.Songs + 3 wrong options
	--  2. tell both clients (remote) and save local startTime = os.clock()
	--  3. accept ONE guess per player, elapsed = os.clock() - startTime
	--  4. correct → self.Scores[player] += Duels.PointsFor(elapsed)
	--  5. end early once both guessed, otherwise after ROUND_TIME
	task.wait(ROUND_TIME)
end

function Duels:Forfeit(player: Player)
	if not self._running then return end
	local winner = if self.Players[1] == player then self.Players[2] else self.Players[1]
	self:_finish(winner, true)
end

function Duels:_finish(winner: Player?, forfeit: boolean)
	if not self._running then return end -- only ever finish once
	self._running = false

	if not winner then
		local p1, p2 = self.Players[1], self.Players[2]
		local s1, s2 = self.Scores[p1], self.Scores[p2]
		winner = if s1 > s2 then p1 elseif s2 > s1 then p2 else nil -- nil = draw
	end

	local result: Result = { Winner = winner, Scores = self.Scores, Forfeit = forfeit }

	-- deferred: the listener destroys this duel, which cancels the round thread.
	-- If we fired directly from inside that thread, it would cancel itself mid-call.
	task.defer(function()
		self.Ended:Fire(result)
	end)
end

function Duels:Destroy()
	self._running = false
	self._janitor:Destroy()
end

return Duels