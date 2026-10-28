--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Signal = require(ReplicatedStorage.Packages.signal)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Levels = require(ReplicatedStorage.Modules.Levels)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server

--| Variables
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")

--| Types
export type Pick = {
	Picked: string?,
	Correct: boolean,
	Points: number,
	Tier: number,
	First: boolean,
	Time: number?,
}
export type RoundLog = { Song: any, Picks: { [Player]: Pick } }
export type Result = {
	Winner: Player?,
	Draw: boolean,
	Forfeit: boolean,
	Leaver: Player?,
	Scores: { [Player]: number },
	Rounds: { RoundLog },
	Stake: number,
	Mode: string,
	Solo: boolean,
}

--| Helpers
local function key(player: Player): string
	return tostring(player.UserId)
end

local function rollStake(): number
	local total = 0
	for _, w in DuelConstants.STAKE_WEIGHTS do
		total += w
	end
	local r = math.random() * total
	for i, w in DuelConstants.STAKE_WEIGHTS do
		r -= w
		if r <= 0 then
			return DuelConstants.STAKES[i]
		end
	end
	return DuelConstants.STAKES[1]
end

local function streakMultiplier(streak: number): number
	for _, row in DuelConstants.STREAK_MULTIPLIERS do
		if streak >= row[1] then
			return row[2]
		end
	end
	return 1
end

local function profileOf(player: Player)
	local ok, data = pcall(PlayerData.Get, player)
	local xp, streak = 0, 0
	if ok and data then
		xp = data.Player.XP.Get()
		streak = data.Player.Streak.Get()
	end
	return {
		UserId = player.UserId,
		Name = player.DisplayName,
		Level = (Levels.FromXP(xp)),
		Streak = streak,
		-- what this player's stake would be multiplied by if they win
		Multiplier = streakMultiplier(streak + 1),
	}
end

-- The songs this player's duel pack would bring (owned songs in it), and the pack id.
local function duelPackOf(player: Player): ({ any }, string?)
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data then
		return {}, nil
	end
	local id = data.Inventory.DuelPack.Get()
	if id == "" or not Packs.Get(id) then
		return {}, nil
	end
	return Packs.SongsFor(id, function(songId)
		return data.Inventory.Songs.Has(songId)
	end), id
end

local function shuffle(list: { any }): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--| Duels
local Duels = {}
Duels.__index = Duels
Duels.StreakMultiplier = streakMultiplier

function Duels.new(stage, playerA: Player?, playerB: Player?, solo: boolean?)
	local self = setmetatable({}, Duels)

	self.Stage = stage
	self.Slots = { A = playerA, B = playerB }
	self.Players = {} :: { Player }
	self.Scores = {} :: { [Player]: number }
	self.CorrectTime = {} :: { [Player]: number } -- tie-break: total seconds to correct answers
	self.Solo = solo == true

	for _, p in { playerA, playerB } do
		if p and not self.Scores[p] then
			table.insert(self.Players, p)
			self.Scores[p] = 0
			self.CorrectTime[p] = 0
			stage.Model:SetAttribute(p.Name, 0)
		end
	end

	self.Stake = 0
	self.Mode = "Song"
	self.Votes = {} :: { [Player]: string }
	self.Phase = "Intro" :: "Intro" | "Vote" | "Round" | "Reveal" | "Done"
	self.Round = 0
	self.Used = {} :: { [string]: boolean }
	-- round -> { Song, From = player, Pack = packId } for rounds that play a pack song
	self.Schedule = {} :: { [number]: any }
	self.PackSongs = {} :: { [Player]: { any } }
	self.PackIds = {} :: { [Player]: string }
	self.SoloPool = "Mix"
	self.Rounds = {} :: { RoundLog }
	self.Current = nil :: any

	self.Ended = Signal.new()
	self._janitor = Janitor.new()
	self._janitor:Add(self.Ended)
	self._running = false

	stage.Model:SetAttribute("Round", 0)
	return self
end

function Duels:_fire(packet)
	DuelRemote:Fire(Bridgenet.Players(self.Players), packet)
end

function Duels:Start()
	if self._running then
		return
	end
	self._running = true
	self:_setInDuel(true)

	local thread = task.spawn(function()
		if not self.Solo then
			QueueRemote:Fire(Bridgenet.Players(self.Players), { Message = "Intermission" })
			task.wait(DuelConstants.START_TIME)
			if not self._running then
				return
			end
		end

		self:_preDuel()
		if not self._running then
			return
		end

		self:_fire({ Message = "Start", Mode = self.Mode })
		task.wait(0.6)

		for round = 1, DuelConstants.ROUNDS do
			self.Round = round
			self.Stage.Model:SetAttribute("Round", round)
			self:_playRound(round)
			if not self._running then
				return
			end
		end
		self:_finish(nil, false)
	end)

	self._janitor:Add(function()
		if coroutine.status(thread) ~= "dead" then
			task.cancel(thread)
		end
	end, true)
end

-- [[ Pre-duel: stake roll + mode vote ]]

function Duels:_preDuel()
	-- solo rolls a stake too; it pays out as XP instead of coins
	self.Stake = rollStake()

	local reel = {}
	for i = 1, 7 do
		reel[i] = DuelConstants.STAKES[math.random(1, #DuelConstants.STAKES)]
	end
	reel[4] = self.Stake -- the chip the pointer lands on

	local profiles = {}
	for slot, p in self.Slots do
		if p then
			profiles[slot] = profileOf(p)
		end
	end

	-- duel packs: they only mix in when every player has one on (solo: always, if on)
	local packsInfo = { On = false, Names = {} }
	local allOn = #self.Players > 0
	for slot, p in self.Slots do
		if p then
			local songs, id = duelPackOf(p)
			if id and #songs > 0 then
				self.PackSongs[p] = songs
				self.PackIds[p] = id
				packsInfo.Names[slot] = Packs.DisplayName(id)
			else
				allOn = false
			end
		end
	end
	packsInfo.On = allOn
	if self.Solo and allOn then
		local me = self.Players[1]
		local ok, data = pcall(PlayerData.Get, me)
		local choice = if ok and data then data.Settings.SoloPool.Get() else "Mix"
		local count = #self.PackSongs[me]
		packsInfo.Solo = {
			Count = count,
			CanOnly = count >= DuelConstants.ROUNDS, -- "only my pack" needs a song per round
			Choice = if choice == "Pack" and count >= DuelConstants.ROUNDS then "Pack" else "Mix",
		}
		self.SoloPool = packsInfo.Solo.Choice
	end
	self.PacksOn = allOn

	self.Phase = "Vote"
	self:_fire({
		Message = "PreDuel",
		Packs = packsInfo,
		Stake = self.Stake,
		Reel = reel,
		Players = profiles,
		Solo = self.Solo,
		SpinTime = DuelConstants.STAKE_SPIN,
		ModeVote = DuelConstants.MODE_VOTE,
		VoteTime = if DuelConstants.MODE_VOTE then DuelConstants.VOTE_TIME else DuelConstants.PRE_DUEL_HOLD,
	})

	if not DuelConstants.MODE_VOTE then
		-- no vote (Choreography isn't out yet): show the stake, then straight into Song rounds.
		-- Phase stays "Vote" meanwhile so the solo song pool picker still works.
		task.wait(DuelConstants.STAKE_SPIN + DuelConstants.PRE_DUEL_HOLD + 0.25)
		self.Mode = DuelConstants.DEFAULT_MODE
		self:_schedulePacks()
		self.Phase = "Intro"
		return
	end

	task.wait(DuelConstants.STAKE_SPIN + DuelConstants.VOTE_TIME + 0.25)

	-- count votes: most votes wins, a draw or no votes is settled at random
	local count = { Song = 0, Choreography = 0 }
	for _, mode in self.Votes do
		count[mode] += 1
	end
	if count.Song > count.Choreography then
		self.Mode = "Song"
	elseif count.Choreography > count.Song then
		self.Mode = "Choreography"
	else
		self.Mode = DuelConstants.MODES[math.random(1, 2)]
	end

	self:_schedulePacks()

	self.Phase = "Intro"
	self:_fire({ Message = "Mode", Mode = self.Mode })
	task.wait(DuelConstants.MODE_REVEAL)
end

function Duels:_broadcastVotes()
	local votes = { Song = {}, Choreography = {} }
	for p, mode in self.Votes do
		table.insert(votes[mode], p.UserId)
	end
	self:_fire({ Message = "Votes", Votes = votes })
end

-- [[ Duel packs ]]

-- Decides which rounds play a pack song. Duel: up to PACK_SONGS_PER_PLAYER random songs
-- from each player's pack, on random rounds 2..ROUNDS (a song both packs share counts once).
-- Solo "Pack": every round from the pack.
function Duels:_schedulePacks()
	self.Schedule = {}
	if not self.PacksOn then
		return
	end
	local picks = {} -- { Song, From, Pack }
	local taken = {}
	if self.Solo and self.SoloPool == "Pack" then
		local me = self.Players[1]
		for i, song in shuffle(self.PackSongs[me]) do
			if i > DuelConstants.ROUNDS then
				break
			end
			self.Schedule[i] = { Song = song, From = me, Pack = self.PackIds[me] }
		end
		return
	end
	for _, p in self.Players do
		local n = 0
		for _, song in shuffle(self.PackSongs[p] or {}) do
			if n >= DuelConstants.PACK_SONGS_PER_PLAYER then
				break
			end
			if not taken[song.Id] then
				taken[song.Id] = true
				n += 1
				table.insert(picks, { Song = song, From = p, Pack = self.PackIds[p] })
			end
		end
	end
	local rounds = {}
	for r = 2, DuelConstants.ROUNDS do
		table.insert(rounds, r)
	end
	rounds = shuffle(rounds)
	for i, pick in picks do
		if rounds[i] then
			self.Schedule[rounds[i]] = pick
		end
	end
end

-- [[ Rounds ]]

function Duels:_playRound(round: number)
	self.RoundNumber = round
	local scheduled = self.Schedule[round]
	local song
	if scheduled and not self.Used[scheduled.Song.Id] then
		song = scheduled.Song
	else
		scheduled = nil
		-- shared pool, never one of the songs saved for a later pack round
		local skip = table.clone(self.Used)
		for r, pick in self.Schedule do
			if r > round then
				skip[pick.Song.Id] = true
			end
		end
		song = SongLibrary.GetRandomSong(skip)
	end
	self.Used[song.Id] = true
	-- tag shown under the round counter: whose pack this song came from
	local packTag = scheduled and {
		From = scheduled.From.UserId,
		FromName = scheduled.From.DisplayName,
		Pack = Packs.DisplayName(scheduled.Pack),
	} or nil

	local options = { song }
	for _, s in SongLibrary.GetWrongOptions(song, 3) do
		table.insert(options, s)
	end
	for i = #options, 2, -1 do
		local j = math.random(1, i)
		options[i], options[j] = options[j], options[i]
	end
	local publicOptions = {}
	for i, s in options do
		publicOptions[i] = SongLibrary.Public(s)
	end

	local per = {}
	for _, p in self.Players do
		per[p] = { Tier = 1, Picked = nil, Correct = false, Time = nil }
	end
	local state = {
		Song = song,
		Per = per,
		Loaded = {} :: { [Player]: boolean },
		Start = os.clock(),
		FirstGuessAt = nil :: number?,
		FirstCorrect = nil :: Player?,
	}
	self.Current = state
	self.Phase = "Loading" -- no guessing until everyone's clip has loaded

	self:_fire({
		Message = "Round",
		Round = round,
		Rounds = DuelConstants.ROUNDS,
		Mode = self.Mode,
		Tiers = DuelConstants.TIERS[self.Mode],
		Points = DuelConstants.TIER_POINTS,
		Options = publicOptions,
		Cap = DuelConstants.ROUND_CAP,
		PackTag = packTag,
		-- the client has to play the clip locally, so it gets the clip assets
		Clip = {
			MusicId = song.MusicId,
			AnimationId = song.AnimationId,
			-- playbackSpeed is the new field; Pitch is the old name for the same thing
			PlaybackSpeed = song.playbackSpeed or song.PlaybackSpeed or song.Pitch or 1,
			Volume = song.Volume or 1,
			Start = song.Start or 0,
			-- where the snippet starts on the sound's own timeline (what Studio's TimePosition shows)
			TimePosition = song.TimePosition,
			-- where the reveal plays the song from (sound timeline seconds)
			ChorusPosition = song.ChorusPosition,
		},
	})

	-- the clock only starts once every player's clip has loaded (or LOAD_TIMEOUT passes),
	-- so a slow download doesn't eat into anyone's time
	local loadDeadline = os.clock() + DuelConstants.LOAD_TIMEOUT
	while self._running and os.clock() < loadDeadline do
		local all = true
		for _, p in self.Players do
			if p.Parent and not state.Loaded[p] then
				all = false
				break
			end
		end
		if all then
			break
		end
		task.wait(0.1)
	end
	if not self._running then
		return
	end
	state.Start = os.clock()
	self.Phase = "Round"
	self:_fire({ Message = "RoundGo", Round = round, Cap = DuelConstants.ROUND_CAP })

	-- wait until everyone has guessed, the answer window closes, or the cap is hit
	while self._running do
		task.wait(0.1)
		local now = os.clock() - state.Start
		local allIn = true
		for _, info in per do
			if not info.Picked then
				allIn = false
				break
			end
		end
		if allIn or now >= DuelConstants.ROUND_CAP then
			break
		end
		if state.FirstGuessAt and now >= state.FirstGuessAt + DuelConstants.ANSWER_WINDOW then
			break
		end
	end
	if not self._running then
		return
	end

	-- score
	self.Phase = "Reveal"
	local picks: { [Player]: Pick } = {}
	local publicPicks = {}
	for _, p in self.Players do
		local info = per[p]
		local points = 0
		if info.Correct then
			points = DuelConstants.TIER_POINTS[info.Tier] or 0
			if state.FirstCorrect == p then
				points += DuelConstants.FIRST_CORRECT_BONUS
			end
			self.CorrectTime[p] += info.Time or 0
		end
		self.Scores[p] += points
		self.Stage.Model:SetAttribute(p.Name, self.Scores[p])
		picks[p] = {
			Picked = info.Picked,
			Correct = info.Correct,
			Points = points,
			Tier = info.Tier,
			First = state.FirstCorrect == p,
			Time = info.Time,
		}
		local picked = info.Picked and SongLibrary.GetById(info.Picked)
		publicPicks[key(p)] = {
			Picked = picked and SongLibrary.Public(picked) or nil,
			Correct = info.Correct,
			Points = points,
			Tier = info.Tier,
			First = state.FirstCorrect == p,
		}
	end
	table.insert(self.Rounds, { Song = song, Picks = picks })

	local scores = {}
	for p, s in self.Scores do
		scores[key(p)] = s
	end
	self:_fire({
		Message = "RoundEnd",
		Round = round,
		Answer = SongLibrary.Public(song),
		Picks = publicPicks,
		Scores = scores,
		Next = if round < DuelConstants.ROUNDS then DuelConstants.REVEAL_TIME else 0,
	})
	task.wait(DuelConstants.REVEAL_TIME)
	self.Current = nil
end

-- [[ Player actions, routed from DuelService ]]

function Duels:Action(player: Player, packet)
	if not self._running or type(packet) ~= "table" then
		return
	end
	local action = packet.Action

	if action == "Vote" and self.Phase == "Vote" and DuelConstants.MODE_VOTE then
		if packet.Mode == "Song" or packet.Mode == "Choreography" then
			self.Votes[player] = packet.Mode
			self:_broadcastVotes()
		end
	elseif action == "SoloPool" and self.Phase == "Vote" and self.Solo and self.PacksOn then
		-- solo pool picker on the pre-duel screen; remembered for next time
		local choice = packet.Choice
		local songs = self.PackSongs[player]
		if choice == "Pack" and not (songs and #songs >= DuelConstants.ROUNDS) then
			choice = "Mix"
		end
		if choice == "Mix" or choice == "Pack" then
			self.SoloPool = choice
			local ok, data = pcall(PlayerData.Get, player)
			if ok and data then
				data.Settings.SoloPool.Set(choice)
			end
			DuelRemote:Fire(player, { Message = "SoloPool", Choice = choice })
		end
	elseif action == "Loaded" and self.Phase == "Loading" then
		local state = self.Current
		if state and state.Per[player] and packet.Round == self.RoundNumber then
			state.Loaded[player] = true
		end
	elseif action == "Unlock" and self.Phase == "Round" then
		local info = self.Current and self.Current.Per[player]
		local tier = tonumber(packet.Tier)
		-- tiers only go up, and not after guessing
		if info and not info.Picked and tier and tier > info.Tier and tier <= #DuelConstants.TIER_POINTS then
			info.Tier = math.floor(tier)
		end
	elseif action == "Guess" and self.Phase == "Round" then
		local state = self.Current
		local info = state and state.Per[player]
		if not info or info.Picked or type(packet.Id) ~= "string" then
			return
		end
		local now = os.clock() - state.Start
		info.Picked = packet.Id
		info.Correct = packet.Id == state.Song.Id
		info.Time = now
		if info.Correct and not state.FirstCorrect and not self.Solo then
			state.FirstCorrect = player
		end
		if not state.FirstGuessAt then
			state.FirstGuessAt = now
			local left = math.min(DuelConstants.ANSWER_WINDOW, DuelConstants.ROUND_CAP - now)
			for _, other in self.Players do
				if other ~= player then
					DuelRemote:Fire(other, { Message = "RivalAnswered", Seconds = left })
				end
			end
		end
	end
end

-- [[ End ]]

function Duels:Forfeit(player: Player)
	if not self._running then
		return
	end
	local winner = if self.Slots.A == player then self.Slots.B else self.Slots.A
	self:_finish(winner, true, player)
end

-- "InDuel" player attribute: lobby name tags hide while it's set.
function Duels:_setInDuel(on: boolean)
	for _, p in self.Players do
		if p.Parent then
			p:SetAttribute("InDuel", if on then true else nil)
		end
	end
end

function Duels:_finish(winner: Player?, forfeit: boolean, leaver: Player?)
	if not self._running then
		return
	end
	self._running = false
	self.Phase = "Done"
	self:_setInDuel(false)

	local draw = false
	if not winner and not self.Solo and self.Slots.A and self.Slots.B then
		local a, b = self.Slots.A, self.Slots.B
		local sa, sb = self.Scores[a], self.Scores[b]
		if sa ~= sb then
			winner = if sa > sb then a else b
		elseif self.CorrectTime[a] ~= self.CorrectTime[b] and sa > 0 then
			-- tie on points: faster correct answers overall wins
			winner = if self.CorrectTime[a] < self.CorrectTime[b] then a else b
		else
			draw = true
		end
	end

	local result: Result = {
		Winner = winner,
		Draw = draw,
		Forfeit = forfeit,
		Leaver = leaver,
		Scores = self.Scores,
		Rounds = self.Rounds,
		Stake = self.Stake,
		Mode = self.Mode,
		Solo = self.Solo,
	}

	-- deferred: the listener destroys this duel, which cancels the round thread
	task.defer(function()
		self.Ended:Fire(result)
	end)
end

function Duels:Destroy()
	self._running = false
	self:_setInDuel(false)
	self._janitor:Destroy()
end

return Duels
