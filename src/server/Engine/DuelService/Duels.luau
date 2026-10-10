--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Signal = require(ReplicatedStorage.Packages.signal)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)

--| Variables

local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

--| Types
export type Result = {
	Winner: Player?,
	Scores: { [Player]: number },
	Forfeit: boolean,
}

--| Duels
local Duels = {}
Duels.__index = Duels

function Duels.new(stage, player1: Player, player2: Player, solostage: boolean?)
	
	local self = setmetatable({}, Duels)

	self.Stage = stage
	self.Players = { player1, player2 }
	

	if player1 == nil then
		self.Scores = {[player2] = 0 }
	else
		self.Scores = { [player1] = 0}
	end

	self.SelectedSong = "";
	self.SelectedOptions = {};
	self.ChosenSongs = {};
    self.RoundData = {};
	self.Round = 0

	self.Solo = solostage
	self.Ended = Signal.new()
	self._janitor = Janitor.new()
	self._janitor:Add(self.Ended)
	self._running = false

	return self
end

function Duels.PointsFor(elapsed: number): number
	for _, tier in DuelConstants.POINT_TIERS do
		if elapsed <= tier[1] then
			return tier[2]
		end
	end
	return 0
end

function Duels:Start()
	if self._running then return end
	self._running = true

	QueueRemote:Fire(Bridgenet.Players(self.Players), { Message = "Intermission" })
	task.wait(DuelConstants.START_TIME)

	local thread = task.spawn(function()
		for round = 1, DuelConstants.ROUNDS do
			self.Round = round
			self:_playRound()
			if not self._running then return end
			task.wait(DuelConstants.ROUND_INTERMISSION)
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
	local SelectedSong = SongLibrary.GetRandomSong()
	if table.find(self.ChosenSongs, SelectedSong) then
		repeat 
			SelectedSong = SongLibrary.GetRandomSong()
		until table.find(self.ChosenSongs, SelectedSong) == nil
	end

	for i = 1, 3 do
		local RandomOption = SongLibrary.GetRandomSong()
		if self.SelectedOptions[RandomOption] then
			repeat
				RandomOption = SongLibrary.GetRandomSong()
			until self.SelectedOptions[RandomOption] == nil
		end
		self.SelectedOptions[RandomOption] = {}
	end
end

function Duels:_playRound()
	self:GetSong();


	-- TODO (yours):
	--  1. pick a song from Library.Songs + 3 wrong options
	--  2. tell both clients (remote) and save local startTime = os.clock()
	--  3. accept ONE guess per player, elapsed = os.clock() - startTime
	--  4. correct → self.Scores[player] += Duels.PointsFor(elapsed)
	--  5. end early once both guessed, otherwise after ROUND_TIME
	task.wait(DuelConstants.ROUND_TIME)
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