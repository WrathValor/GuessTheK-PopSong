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
Duels.StreakMultiplier = streakMultiplier
Duels.ProfileOf = profileOf -- the invite cards show the same Level / Streak

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

		if self.Tutorial then
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
		Players = profiles,
		Solo = self.Solo,
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

function Duels:_playRound(round: number)
	self.RoundNumber = round
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
		else nil
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
		Rounds = self.RoundCount,
		Tutorial = self.Tutorial or nil,
		Mode = self.Mode,
		Tiers = DuelConstants.TIERS[self.Mode],
		Points = DuelConstants.TIER_POINTS,
		Options = publicOptions,
		Cap = self.Cap,
		OwnedTag = ownedTag,
		Theme = if self.Solo and self.Theme ~= Themes.DEFAULT and self.Theme ~= Themes.PACK
			then Themes.Get(self.Theme).Name
			else nil,
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
	self:_fire({ Message = "RoundGo", Round = round, Cap = self.Cap, Tutorial = self.Tutorial or nil })

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
	table.insert(self.Rounds, { Song = song, Picks = picks, Owners = owners })
	self:_logRound(round, song, picks, owners)

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
		Next = if round < self.RoundCount then self:_revealTime(round) else 0,
		Tutorial = self.Tutorial or nil,
	})
	task.wait(self:_revealTime(round))
	self.Current = nil
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
		Packs = self.Boost == true,
		Tutorial = self.Tutorial,
		Sessions = self.Sessions,
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
