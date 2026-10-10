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
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")

--| Types
export type Result = {
	Winner: Player?,
	Scores: { [Player]: number },
	Forfeit: boolean,
}

--| Duels
local Duels = {}
Duels.__index = Duels

function Duels.new(stage, playerA: Player?, playerB: Player?, solostage: boolean?)
	local self = setmetatable({}, Duels)

	self.Stage = stage
	self.Slots = { A = playerA, B = playerB }
	self.Players = {}
	self.Scores = {}

	if playerA then
		table.insert(self.Players, playerA)
		self.Scores[playerA] = 0
		stage.Model:SetAttribute(playerA.Name, 0)
	end

	if playerB then
		table.insert(self.Players, playerB)
		self.Scores[playerB] = 0
		stage.Model:SetAttribute(playerB.Name, 0)
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
	stage.Model:SetAttribute("Round", 0)
	stage.Model:SetAttribute("Round", 0)

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
	
	DuelRemote:Fire(Bridgenet.Players(self.Players), { Message = "Start" })
	local thread = task.spawn(function()
		for round = 1, DuelConstants.ROUNDS do
			self.Stage.Model:SetAttribute("Round", round)
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

	for _ = 1, 3 do
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
	local winner = if self.Slots.A == player then self.Slots.B else self.Slots.A
	self:_finish(winner, true)
end

function Duels:_finish(winner: Player?, forfeit: boolean)
	if not self._running then return end -- only ever finish once
	self._running = false

	if not winner and self.Slots.A and self.Slots.B then
		local p1, p2 = self.Slots.A, self.Slots.B
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