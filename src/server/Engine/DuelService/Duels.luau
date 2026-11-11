--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Signal = require(ReplicatedStorage.Packages.signal)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Themes = require(ReplicatedStorage.Modules.Library.Themes)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local Levels = require(ReplicatedStorage.Modules.Levels)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Analytics = require(script.Parent.Parent.Analytics)

--| Variables
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
-- song ids whose audio failed to fetch on a client (402: this experience can't use it, or the
-- asset is gone). Audio permissions are per experience, so they're skipped by every duel on
-- this server from then on.
local BrokenAudio = {} :: { [string]: boolean }

--| Types
export type Pick = {
	Picked: string?,
	Correct: boolean,
	Points: number,
	Tier: number,
	First: boolean,
	Time: number?,
}
export type RoundLog = { Song: any, Picks: { [Player]: Pick }, Owners: any?, Multiplier: number? }
export type Result = {
	Winner: Player?,
	Draw: boolean,
	Forfeit: boolean,
	Leaver: Player?,
	Scores: { [Player]: number },
	Rounds: { RoundLog },
	Stake: number,
	StakeRoll: number?,
	Mode: string,
	Solo: boolean,
}

--| Helpers
local function key(player: Player): string
	return tostring(player.UserId)
end

-- a weighted pick from `stakes` (defaults to the duel table)
local function rollStake(stakes: { number }?, weights: { number }?): number
	stakes = stakes or DuelConstants.STAKES
	weights = weights or DuelConstants.STAKE_WEIGHTS
	local total = 0
	for _, w in weights :: { number } do
		total += w
	end
	local r = math.random() * total
	for i, w in weights :: { number } do
		r -= w
		if r <= 0 then
			return (stakes :: { number })[i]
		end
	end
	return (stakes :: { number })[1]
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
	local xp, streak, title, tier = 0, 0, nil, nil
	if ok and data then
		xp = data.Player.XP.Get()
		streak = data.Player.Streak.Get()
		title = data.Inventory.Title.Get()
		tier = Cards.LEVELS[(data.Inventory.TitleTiers.Get() or {})[title] or 1]
	end
	return {
		Title = if title and title ~= "" then title else nil,
		TitleTier = tier, -- "Normal" / "Gold" / "Rainbow"
		UserId = player.UserId,
		Name = player.DisplayName,
		Level = (Levels.FromXP(xp)),
		Streak = streak,
		-- what this player's stake would be multiplied by if they win
		Multiplier = streakMultiplier(streak + 1),
	}
end

-- Every song this player owns (Inventory.Songs), as a list, and a lookup of id → card level
-- ("Normal" / "Gold" / "Rainbow", Modules/Library/Cards).
local function ownedOf(player: Player): ({ any }, { [string]: string })
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data then
		return {}, {}
	end
	local list = Packs.SongsFor(Packs.MY, function(songId)
		return data.Inventory.Songs.Has(songId)
	end)
	local copies = data.Inventory.Copies.Get()
	local levels = {}
	for _, song in list do
		levels[song.Id] = Cards.Level(Cards.Copies(copies, true, song.Id)) or "Normal"
	end
	return list, levels
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
-- set by Engine/ShutdownService when the server is closing: leaving then cancels a match (no
-- result, no streak or stake change) instead of forfeiting it
Duels.Halted = false
Duels.StreakMultiplier = streakMultiplier
Duels.ProfileOf = profileOf -- the invite cards show the same Level / Streak

-- party = a Party Stage match (Engine/PartyService), nil for duels + solo:
--   { Kind = "FFA" | "Duel", Players = { Player } (setlist order), Pool = { song }? (the
--     host's custom pool, nil = every song), Boost = bool (owned songs count),
--     Multiplier = number, MultiplierText = string, Eligible = bool (pays out at all) }
-- A party match rolls its pot (PartyConstants.STAKES × Multiplier) but has no vote, any
-- number of players (each their own score),
-- and someone leaving only drops them: the rest play on while two or more are left.
function Duels.new(stage, playerA: Player?, playerB: Player?, solo: boolean?, party: any?)
	local self = setmetatable({}, Duels)

	self.Stage = stage
	self.Slots = { A = playerA, B = playerB }
	self.Players = {} :: { Player }
	self.Scores = {} :: { [Player]: number }
	self.CorrectTime = {} :: { [Player]: number } -- tie-break: total seconds to correct answers
	self.Solo = solo == true
	self.Party = party
	self.Everyone = {} :: { Player } -- everyone who started (party: leavers stay in here)
	self.Left = {} :: { [Player]: boolean }
	self.Firsts = {} :: { [Player]: number } -- rounds each player answered correctly first

	local starters = { playerA, playerB }
	if party then
		self.Slots = {}
		starters = party.Players
		for i, p in party.Players do
			self.Slots[tostring(i)] = p
		end
	end
	for _, p in starters do
		if p and not self.Scores[p] then
			table.insert(self.Players, p)
			table.insert(self.Everyone, p)
			self.Scores[p] = 0
			self.CorrectTime[p] = 0
			self.Firsts[p] = 0
			stage.Model:SetAttribute(p.Name, 0)
		end
	end

	self.Stake = 0
	self.Mode = "Song"
	self.Votes = {} :: { [Player]: string }
	self.Phase = "Intro" :: "Intro" | "Vote" | "Round" | "Reveal" | "Done"
	self.Round = 0
	self.Used = {} :: { [string]: boolean }
	-- owned songs (see DuelConstants.OWNED_WEIGHT): each player's list + lookup, whether this
	-- game boosts them, and how many rounds have played one so far
	self.OwnedSongs = {} :: { [Player]: { any } }
	self.Owned = {} :: { [Player]: { [string]: string } } -- song id → card level
	self.Boost = false
	self.OwnedRounds = 0
	self.Theme = Themes.DEFAULT -- solo: the theme picked on the queue card
	self.Rounds = {} :: { RoundLog }
	self.Current = nil :: any
	self.Sessions = {} :: { [Player]: string } -- analytics funnel id per player (set by DuelService)
	-- the first-join tutorial: fewer rounds, easy songs, no clock pressure (set by DuelService)
	self.Tutorial = false
	self.RoundCount = DuelConstants.ROUNDS -- how many rounds this game plays
	self.Cap = DuelConstants.ROUND_CAP
	self.Record = nil :: any -- { [userId] = record vs the other } (DuelService, RivalRecord)

	self.Ended = Signal.new()
	self._janitor = Janitor.new()
	self._janitor:Add(self.Ended)
	self._running = false
	self.Started = false
	-- true during the queue intermission countdown: leaving then cancels the match, no forfeit
	self.Intermission = false

	stage.Model:SetAttribute("Round", 0)
	return self
end

function Duels:_fire(packet)
	if #self.Players > 0 then
		DuelRemote:Fire(Bridgenet.Players(self.Players), packet)
	end
	-- Party Stages forward round + score packets to spectators
	if self.OnPacket then
		task.spawn(self.OnPacket, packet)
	end
end

function Duels:Start()
	if self._running or self.Started then
		return
	end
	self.Started = true
	self._running = true
	self:_setInDuel(true)

	local thread = task.spawn(function()
		if self.Party then
			self:_partyIntro() -- the lobby's countdown already happened: no intermission or vote
		elseif not self.Solo then
			self.Intermission = true
			QueueRemote:Fire(Bridgenet.Players(self.Players), { Message = "Intermission" })
			task.wait(DuelConstants.START_TIME)
			self.Intermission = false
			if not self._running then
				return
			end
		end

		if self.Party then
			-- set up in _partyIntro
		elseif self.Tutorial then
			-- no stake roll or vote: straight into 3 relaxed Song rounds
			self.RoundCount = DuelConstants.TUTORIAL_ROUNDS
			self.Cap = DuelConstants.TUTORIAL_CAP
			self.Stake = 0
			self.Mode = DuelConstants.DEFAULT_MODE
			local profiles = {}
			for slot, p in self.Slots do
				if p then
					profiles[slot] = profileOf(p)
				end
			end
			-- the round + results screens read the players from this; the client skips the
			-- stake-roll screen for a tutorial
			self:_fire({ Message = "PreDuel", Tutorial = true, Solo = true, Stake = 0, Players = profiles, Packs = { On = false, Names = {} } })
		else
			self:_preDuel()
		end
		if not self._running then
			return
		end
		if self.Solo and not self.Tutorial then
			-- practice is at your own pace: no 20 s round clock, so no countdown either
			self.Cap = DuelConstants.SOLO_CAP
			local me = self.Players[1]
			Analytics.Event(me, "SoloStarted", 1, self.Theme, if self.Boost then "On" else "Off")
			Analytics.Funnel(me, "Solo", self.Sessions[me] or Analytics.SoloSession(me), "Started")
		end

		self:_fire({ Message = "Start", Mode = self.Mode })
		task.wait(0.6)

		for round = 1, self.RoundCount do
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

-- [[ Party Stage intro ]]

-- Who's playing (the round + results screens read the players from PreDuel), owned songs
-- when the host left them on, the pot roll, then straight into Song rounds. The reel shows
-- PartyConstants.STAKES already times the match multiplier (FFA size, custom pool), so the
-- number it lands on is the pot. A pool too small to pay out skips the roll.
function Duels:_partyIntro()
	local PartyConstants = require(ReplicatedStorage.Constants.PartyConstants)
	local party = self.Party
	local mult = party.Multiplier or 1
	local function pot(n: number): number
		return math.floor(n * mult + 0.5)
	end
	local reel, chips = nil, nil
	self.Stake = 0
	self.StakeRoll = 0
	if party.Eligible ~= false then
		self.StakeRoll = rollStake(PartyConstants.STAKES, PartyConstants.STAKE_WEIGHTS)
		self.Stake = pot(self.StakeRoll)
		chips = {}
		for i, n in PartyConstants.STAKES do
			chips[i] = pot(n)
		end
		reel = {}
		for i = 1, 7 do
			reel[i] = chips[math.random(1, #chips)]
		end
		reel[4] = self.Stake -- the chip the pointer lands on
	end
	self.Mode = DuelConstants.DEFAULT_MODE
	local profiles = {}
	for slot, p in self.Slots do
		profiles[slot] = profileOf(p)
	end
	self.Boost = party.Boost == true
	if self.Boost then
		for _, p in self.Players do
			local list, set = ownedOf(p)
			self.OwnedSongs[p] = list
			self.Owned[p] = set
		end
	end
	self:_fire({
		Message = "PreDuel",
		Party = true,
		Kind = party.Kind,
		Solo = false,
		Stake = self.Stake,
		Reel = reel, -- nil: no roll (nothing pays out), the client skips the screen
		Chips = chips, -- every chip the reel can show, for the spinning strip
		Multiplier = mult,
		MultiplierText = party.MultiplierText or "",
		Players = profiles,
		Packs = { On = self.Boost, Owned = {} },
		SpinTime = DuelConstants.STAKE_SPIN,
		ModeVote = false,
		VoteTime = DuelConstants.PRE_DUEL_HOLD,
	})
	if reel then
		task.wait(DuelConstants.STAKE_SPIN + DuelConstants.PRE_DUEL_HOLD + 0.25)
	end
end

-- [[ Pre-duel: stake roll + mode vote ]]

function Duels:_preDuel()
	-- solo rolls a stake too, from its own lower table; it pays out as XP instead of coins
	local stakes = if self.Solo then DuelConstants.SOLO_STAKES else DuelConstants.STAKES
	self.Stake = rollStake(stakes, DuelConstants.STAKE_WEIGHTS)

	local reel = {}
	for i = 1, 7 do
		reel[i] = stakes[math.random(1, #stakes)]
	end
	reel[4] = self.Stake -- the chip the pointer lands on

	local profiles = {}
	for slot, p in self.Slots do
		if p then
			profiles[slot] = profileOf(p)
		end
	end

	-- owned songs: whatever a player owns comes up more often, nothing to equip. Solo can turn
	-- that off (Settings.SoloPool) or play only owned songs (the "My songs" theme).
	local packsInfo = { On = false, Owned = {} }
	for slot, p in self.Slots do
		if p then
			local list, set = ownedOf(p)
			self.OwnedSongs[p] = list
			self.Owned[p] = set
			if #list > 0 then
				packsInfo.Owned[slot] = #list
				packsInfo.On = true
			end
		end
	end
	-- solo: the theme from the queue card (Settings.SoloTheme)
	if self.Solo then
		local me = self.Players[1]
		local ok, data = pcall(PlayerData.Get, me)
		local theme = if ok and data then data.Settings.SoloTheme.Get() else Themes.DEFAULT
		local mix = not (ok and data) or data.Settings.SoloPool.Get() ~= "Off"
		if theme == Themes.PACK then
			if #(self.OwnedSongs[me] or {}) < DuelConstants.ROUNDS then
				theme = Themes.DEFAULT
			end
		elseif not Themes.IsOpen(theme) then
			theme = Themes.DEFAULT
		end
		self.Theme = theme
		if not mix or theme == Themes.PACK then
			packsInfo.On = false -- "My songs" is every round already
		end
		packsInfo.Theme = Themes.Get(theme).Name
	end
	self.Boost = packsInfo.On

	self.Phase = "Vote"
	self:_fire({
		Message = "PreDuel",
		Packs = packsInfo,
		Stake = self.Stake,
		Reel = reel,
		Chips = if self.Solo then stakes else nil, -- solo's lower table (nil: the duel strip)
		Players = profiles,
		Solo = self.Solo,
		Record = self.Record,
		SpinTime = DuelConstants.STAKE_SPIN,
		ModeVote = DuelConstants.MODE_VOTE,
		VoteTime = if DuelConstants.MODE_VOTE then DuelConstants.VOTE_TIME else DuelConstants.PRE_DUEL_HOLD,
	})

	if not DuelConstants.MODE_VOTE then
		-- no vote (Choreography isn't out yet): show the stake, then straight into Song rounds.
		task.wait(DuelConstants.STAKE_SPIN + DuelConstants.PRE_DUEL_HOLD + 0.25)
		self.Mode = DuelConstants.DEFAULT_MODE
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

-- [[ Owned songs ]]

-- How likely `song` is this round: 1, plus (OWNED_WEIGHT[level] - 1) for each player who owns it.
function Duels:_weightOf(song): number
	local w = 1
	for _, p in self.Players do
		local level = self.Owned[p] and self.Owned[p][song.Id]
		if level then
			w += (DuelConstants.OWNED_WEIGHT[level] or 1) - 1
		end
	end
	return w
end

-- [[ Rounds ]]

-- the final round counts FINAL_ROUND_MULTIPLIER times over (not in the tutorial)
function Duels:_multiplier(round: number): number
	return if not self.Tutorial and round == self.RoundCount then DuelConstants.FINAL_ROUND_MULTIPLIER else 1
end

-- what each tier pays this round (+) and what a wrong answer on it costs (as a positive number)
function Duels:_roundPoints(round: number): ({ number }, { number })
	local mult = self:_multiplier(round)
	local pays, costs = {}, {}
	for i, p in DuelConstants.TIER_POINTS do
		pays[i] = p * mult
		costs[i] = if self.Tutorial then 0 else (DuelConstants.WRONG_PENALTY[i] or 0) * mult
	end
	return pays, costs
end

function Duels:_playRound(round: number)
	self.RoundNumber = round
	-- the final ENCORE round gets its own moment first: every client shows the neon sign with
	-- what's at stake for them (scores + the most this round can pay), then the round starts
	local mult = self:_multiplier(round)
	if mult > 1 then
		local scores = {}
		for p, s in self.Scores do
			scores[key(p)] = s
		end
		self:_fire({
			Message = "Encore",
			Multiplier = mult,
			Scores = scores,
			-- the top tier, plus the first-correct bonus where there's a rival to beat
			Max = DuelConstants.TIER_POINTS[1] * mult + (if self.Solo then 0 else DuelConstants.FIRST_CORRECT_BONUS * mult),
			Solo = self.Solo or nil,
			Party = if self.Party then true else nil,
		})
		task.wait(DuelConstants.ENCORE_INTRO)
		if not self._running then
			return
		end
	end
	-- a clip that won't load gets swapped for another song (Song mode, up to AUDIO_SWAPS times);
	-- past that the round plays on as before
	local swaps = 0
	local state, owners
	repeat
		local canSwap = self.Mode == "Song" and swaps < DuelConstants.AUDIO_SWAPS
		state, owners = self:_startRound(round, swaps > 0, canSwap)
		if not state then
			return
		end
		swaps += 1
	until not (state.Failed and canSwap)
	local song, per = state.Song, state.Per

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
		if allIn or now >= self.Cap then
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
	local pays, costs = self:_roundPoints(round)
	for _, p in self.Players do
		local info = per[p]
		local points = 0
		if info.Correct then
			points = pays[info.Tier] or 0
			if state.FirstCorrect == p then
				points += DuelConstants.FIRST_CORRECT_BONUS * self:_multiplier(round)
				self.Firsts[p] = (self.Firsts[p] or 0) + 1
			end
			self.CorrectTime[p] += info.Time or 0
		elseif info.Picked and (costs[info.Tier] or 0) > 0 then
			-- a wrong guess on an early tier costs points (can take a score below 0)
			points = -costs[info.Tier]
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
	table.insert(self.Rounds, { Song = song, Picks = picks, Owners = owners, Multiplier = self:_multiplier(round) })
	self:_logRound(round, song, picks, owners)

	local scores = {}
	for p, s in self.Scores do
		scores[key(p)] = s
	end
	local left = nil
	if self.Party then
		left = {}
		for p in self.Left do
			table.insert(left, p.UserId)
		end
	end
	self:_fire({
		Message = "RoundEnd",
		Left = left,
		Round = round,
		Answer = SongLibrary.Public(song),
		Picks = publicPicks,
		Scores = scores,
		Next = if round < self.RoundCount then self:_revealTime(round) else 0,
		Tutorial = self.Tutorial or nil,
		Multiplier = self:_multiplier(round),
	})
	task.wait(self:_revealTime(round))
	self.Current = nil
end

-- Picks the round's song, sends it and waits for everyone's clip to load. Returns the round
-- state (nil if the duel stopped). If a clip failed and `canSwap`, returns before RoundGo so
-- _playRound can try another song; otherwise the round clock starts here.
function Duels:_startRound(round: number, swapped: boolean, canSwap: boolean)
	for id in BrokenAudio do
		self.Used[id] = true -- every picker skips used songs
	end
	local song
	if self.Tutorial then
		-- well-known songs, in a random order
		local pool = {}
		for _, id in DuelConstants.TUTORIAL_SONGS do
			local s = SongLibrary.GetById(id)
			if s and not self.Used[s.Id] then
				table.insert(pool, s)
			end
		end
		song = SongLibrary.Pick(pool)
	end
	-- owned songs are likelier until OWNED_ROUNDS_MAX rounds have played one
	local weight = if self.Boost and not self.Tutorial and self.OwnedRounds < DuelConstants.OWNED_ROUNDS_MAX
		then function(s)
			return self:_weightOf(s)
		end
		else nil
	local onlyMine = self.Solo and self.Theme == Themes.PACK
	local partyPool = self.Party and self.Party.Pool
	if not song and partyPool then
		-- the host's custom pool: every round from it (the same pool for everyone)
		local pool = {}
		for _, s in partyPool do
			if not self.Used[s.Id] then
				table.insert(pool, s)
			end
		end
		song = SongLibrary.Pick(pool, weight)
	end
	if not song and onlyMine then
		-- "My songs": every round from what the player owns
		local pool = {}
		for _, s in self.OwnedSongs[self.Players[1]] or {} do
			if not self.Used[s.Id] then
				table.insert(pool, s)
			end
		end
		song = SongLibrary.Pick(pool)
	end
	if not song and not self.Solo then
		-- duels spread across the generations: each round takes the next generation from
		-- a shuffled bag (refilled when empty), so 7 rounds cover every gen at least once
		if not self.GenBag or #self.GenBag == 0 then
			self.GenBag = shuffle(SongLibrary.Generations())
		end
		song = SongLibrary.GetRandomSongOfGeneration(table.remove(self.GenBag), self.Used, weight)
	end
	song = song or (self.Solo and Themes.RandomSong(self.Theme, self.Used, weight)) or SongLibrary.GetRandomSong(self.Used, weight)
	self.Used[song.Id] = true

	-- who owns it: they get the "♪ YOUR SONG" tag, and +OWNED_XP for guessing it in a duel
	local owners = {} :: { [Player]: boolean }
	local ownedTag = nil
	if not self.Tutorial and not onlyMine then
		local list = {}
		for _, p in self.Players do
			if self.Owned[p] and self.Owned[p][song.Id] then
				owners[p] = true
				table.insert(list, { UserId = p.UserId, Name = p.DisplayName, Tier = self.Owned[p][song.Id] })
			end
		end
		if #list > 0 then
			self.OwnedRounds += 1
			ownedTag = { Owners = list, XP = if self.Solo then nil else DuelConstants.OWNED_XP }
		end
	end

	local options = { song }
	-- a themed solo game keeps its options in the theme ("Pack" answers use the whole library)
	local within = if self.Solo and self.Theme ~= Themes.DEFAULT and self.Theme ~= Themes.PACK
		then Themes.SongsFor(self.Theme)
		else partyPool
	for _, s in SongLibrary.GetWrongOptions(song, 3, within) do
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
	self.Attempt = (self.Attempt or 0) + 1
	local state = {
		Song = song,
		Per = per,
		Attempt = self.Attempt, -- a late "Loaded" from a swapped-out song doesn't count
		Failed = false, -- someone's clip failed to load
		Loaded = {} :: { [Player]: boolean },
		Start = os.clock(),
		FirstGuessAt = nil :: number?,
		FirstCorrect = nil :: Player?,
	}
	self.Current = state
	self.Phase = "Loading" -- no guessing until everyone's clip has loaded

	local pays, costs = self:_roundPoints(round)
	self:_fire({
		Message = "Round",
		Round = round,
		Attempt = state.Attempt,
		Swapped = swapped or nil, -- the last song's clip wouldn't load
		Rounds = self.RoundCount,
		Tutorial = self.Tutorial or nil,
		Mode = self.Mode,
		Tiers = DuelConstants.TIERS[self.Mode],
		Points = pays,
		Penalty = costs, -- tier → points a wrong answer loses
		Multiplier = self:_multiplier(round), -- 2 on the final ENCORE round
		Options = publicOptions,
		Cap = self.Cap,
		OwnedTag = ownedTag,
		Theme = if self.Solo and self.Theme ~= Themes.DEFAULT and self.Theme ~= Themes.PACK
			then Themes.Get(self.Theme).Name
			else nil,
		-- the client has to play the clip locally, so it gets this round's clip assets (only
		-- this one: the library's audio ids stay on the server, see ServerScriptService.Songs)
		Clip = SongLibrary.Clip(song),
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
		if all or (state.Failed and canSwap) then
			break
		end
		task.wait(0.1)
	end
	if not self._running then
		return nil
	end
	if state.Failed and canSwap then
		return state, owners
	end
	state.Start = os.clock()
	self.Phase = "Round"
	self:_fire({ Message = "RoundGo", Round = round, Cap = self.Cap, Tutorial = self.Tutorial or nil })

	return state, owners
end

function Duels:_revealTime(round: number): number
	return DuelConstants.REVEAL_TIME + (if self.Tutorial and round == 1 then DuelConstants.TUTORIAL_REVEAL_EXTRA else 0)
end

-- [[ Analytics: one RoundResult per player, plus funnel steps ]]

local FUNNEL_ROUNDS = { Duel = { [1] = "Round1", [4] = "Round4", [7] = "Round7" }, Solo = { [1] = "Round1", [7] = "Round7" } }

function Duels:_logRound(round: number, song, picks: { [Player]: Pick }, owners: { [Player]: boolean })
	local funnel = if self.Solo then "Solo" else "Duel"
	for p, pick in picks do
		local result = if pick.Correct then "Correct" elseif pick.Picked then "Wrong" else "NoAnswer"
		Analytics.Event(p, "RoundResult", pick.Time or 0, song.Id, result, `Tier{pick.Tier}`)
		if pick.Picked then
			Analytics.Onboarding(p, "AnsweredRound")
		end
		if next(owners) then
			Analytics.Event(p, "OwnedRound", 1, if owners[p] then "Mine" else "Rival")
		end
		local step = FUNNEL_ROUNDS[funnel][round]
		if step and self.Sessions[p] then
			Analytics.Funnel(p, funnel, self.Sessions[p], step)
		end
	end
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
	elseif action == "Loaded" and self.Phase == "Loading" then
		local state = self.Current
		if state and state.Per[player] and packet.Round == self.RoundNumber and packet.Attempt == state.Attempt then
			state.Loaded[player] = true
			if packet.Failed then
				state.Failed = true
				-- a fetch failure (402 / gone) is the asset, not the player's connection
				if packet.Failed == "FetchFailed" then
					BrokenAudio[state.Song.Id] = true
				end
				warn(`[Duels] {state.Song.Id} didn't load for {player.Name} ({packet.Failed})`)
			end
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
		if self.Party then
			-- the FFA scoreboard marks each player as they answer
			self:_fire({ Message = "PlayerAnswered", UserId = player.UserId })
		end
		if not state.FirstGuessAt then
			state.FirstGuessAt = now
			local left = math.min(DuelConstants.ANSWER_WINDOW, self.Cap - now)
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
	if Duels.Halted then
		self:Destroy() -- the server is closing: nobody wins or loses this one
		return
	end
	if self.Party then
		-- a party match plays on without them while 2+ are left; they score 0 from here and
		-- are paid nothing (PartyService)
		local i = table.find(self.Players, player)
		if not i then
			return
		end
		table.remove(self.Players, i)
		self.Left[player] = true
		if player.Parent then
			player:SetAttribute("InDuel", nil)
		end
		if self.Current then
			self.Current.Per[player] = nil
			self.Current.Loaded[player] = nil
		end
		if #self.Players < 2 then
			self:_finish(self.Players[1], true, player)
		end
		return
	end
	local winner = if self.Slots.A == player then self.Slots.B else self.Slots.A
	self:_finish(winner, true, player)
end

-- Party: everyone who started, best first: players still in by points, then total seconds
-- to their correct answers (faster wins a tie), then whoever left (last).
function Duels:Placement(): { Player }
	local list = table.clone(self.Everyone)
	table.sort(list, function(a, b)
		if (self.Left[a] == true) ~= (self.Left[b] == true) then
			return not self.Left[a]
		end
		local sa, sb = self.Scores[a] or 0, self.Scores[b] or 0
		if sa ~= sb then
			return sa > sb
		end
		local ta, tb = self.CorrectTime[a] or 0, self.CorrectTime[b] or 0
		if ta ~= tb then
			return ta < tb
		end
		return a.UserId < b.UserId
	end)
	return list
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
	local placement = nil
	if self.Party then
		placement = self:Placement()
		winner = winner or placement[1]
	elseif not winner and not self.Solo and self.Slots.A and self.Slots.B then
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
		StakeRoll = self.StakeRoll, -- party: the rolled amount before the multiplier
		Mode = self.Mode,
		Solo = self.Solo,
		Packs = self.Boost == true,
		Tutorial = self.Tutorial,
		Sessions = self.Sessions,
		-- party matches: placement (best first), who left, rounds answered first
		Party = self.Party,
		Placement = placement,
		Left = self.Left,
		Firsts = self.Firsts,
		Everyone = self.Everyone,
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
