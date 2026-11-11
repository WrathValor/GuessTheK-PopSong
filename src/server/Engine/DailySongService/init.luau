--| DailySongService
-- The Daily Song: one song for every player each UTC day, guessed by typing in up to
-- DailySongConstants.TRIES tries; each miss or skip plays a longer clip. The rules live in
-- Logic (tested in tests/DailySong.spec); this file is the remote, the saving and the rewards.
-- Which song it is never leaves the server until the player is done (the clip assets do, as in
-- a duel round, but no name or Id).
--
-- DailySongRemote, client → server:
--   { Action = "Open" }                 today's state
--   { Action = "Guess", Id = songId }   a typed guess (a Songs Id from the public catalog)
--   { Action = "Skip" }                 use a try to hear the next tier
--   { Action = "Share" }                post your result in chat (once a day, when done)
-- Server → that player, after every action:
--   { Message = "State", Day, Number, Tries, Tier, Tiers, Clip, Guesses = { { Kind =
--     "Wrong" | "Skip" | "Right", Song = Public? } }, Done, Solved, Answer = Public?, Coins,
--     XP, Streak, Best, Stats = { Tries = { n per try }, Missed = n, Total = n }, NextIn, Shared,
--     Result = "Right" | "Wrong" | "Skip" | "Missed" | nil (what this action did) }
-- Server → everyone, when someone shares:
--   { Message = "Shared", UserId, Name, Number, Marks = { "Wrong" | "Skip" | "Right", … }, Solved }
--   (no song in it, so nobody's day is spoiled; client/Client chat posts it)
--
-- Coins, XP, the streak and the "Daily Song" quests (RewardsService.RecordDailySong) are paid
-- when the day is solved. The "How everyone did" counts are kept in a MemoryStore hash map per
-- day, so every server shows the same chart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local DailySongConstants = require(ReplicatedStorage.Constants.DailySongConstants)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local Analytics = require(script.Parent.Analytics)
local RewardsService = require(script.Parent.RewardsService)
local Logic = require(script.Logic)

local DailySongRemote = Bridgenet.ReferenceBridge("DailySongRemote")

local DailySongService = {}

local busy: { [Player]: boolean } = {}
local shares: { [Player]: { Day: number, Count: number } } = {}

-- [[ The day's song ]]

local songByDay: { [number]: any } = {}

local function today(): number
	return RewardsCatalog.Day(os.time())
end

local function songFor(day: number)
	local song = songByDay[day]
	if not song then
		song = Logic.PickSong(SongLibrary.GetAllSongs(), day)
		songByDay[day] = song
		songByDay[day - 2] = nil -- keep only today and yesterday
	end
	return song
end

-- [[ How everyone did (MemoryStore) ]]

local statsMap = nil
pcall(function()
	statsMap = MemoryStoreService:GetHashMap("DailySongStats")
end)
local STAT_KEYS = { "1", "2", "3", "4", "5", "X" }
local statsCache: { Day: number, At: number, Counts: { [string]: number } } = { Day = -1, At = 0, Counts = {} }

local function countFinish(day: number, key: string)
	if not statsMap then
		return
	end
	-- show your own finish straight away, before the next refresh
	if statsCache.Day == day then
		statsCache.Counts[key] = (statsCache.Counts[key] or 0) + 1
	end
	task.spawn(function()
		pcall(function()
			statsMap:UpdateAsync(`{day}:{key}`, function(old)
				return (tonumber(old) or 0) + 1
			end, DailySongConstants.STATS_TTL)
		end)
	end)
end

local function refreshStats(day: number)
	if not statsMap then
		return
	end
	local counts = {}
	for _, key in STAT_KEYS do
		local ok, value = pcall(function()
			return statsMap:GetAsync(`{day}:{key}`)
		end)
		counts[key] = if ok then tonumber(value) or 0 else (statsCache.Day == day and statsCache.Counts[key] or 0)
	end
	statsCache = { Day = day, At = os.clock(), Counts = counts }
end

local function statsFor(day: number)
	if statsCache.Day ~= day then
		refreshStats(day)
	end
	-- (kept as separate fields: a table mixing [1..5] with named keys loses half over a remote)
	local tries, total = {}, 0
	for i = 1, DailySongConstants.TRIES do
		tries[i] = statsCache.Counts[tostring(i)] or 0
		total += tries[i]
	end
	local missed = statsCache.Counts.X or 0
	return { Tries = tries, Missed = missed, Total = total + missed }
end

-- [[ Player state ]]

local function playOf(data): Logic.Play
	return {
		Guesses = table.clone(data.DailySong.Guesses.Get() or {}),
		Solved = data.DailySong.Solved.Get(),
		Done = data.DailySong.Done.Get(),
	}
end

local function marksOf(play: Logic.Play, answerId: string): { string }
	local marks = {}
	for i, id in play.Guesses do
		marks[i] = if id == "" then "Skip" elseif id == answerId then "Right" else "Wrong"
	end
	return marks
end

local function sendState(player: Player, data, result: string?)
	local day = today()
	local song = songFor(day)
	if not song then
		return
	end
	local play = playOf(data)
	local guesses = {}
	for i, kind in marksOf(play, song.Id) do
		local id = play.Guesses[i]
		local guessed = if id ~= "" then SongLibrary.GetById(id) else nil
		guesses[i] = { Kind = kind, Song = if guessed then SongLibrary.Public(guessed) else nil }
	end
	local share = shares[player]
	DailySongRemote:Fire(player, {
		Message = "State",
		Result = result,
		Day = day,
		Number = Logic.Number(day),
		Tries = DailySongConstants.TRIES,
		Tier = Logic.Tier(play),
		Tiers = DailySongConstants.TIERS,
		Clip = SongLibrary.Clip(song),
		Guesses = guesses,
		Done = play.Done,
		Solved = play.Solved,
		Answer = if play.Done then SongLibrary.Public(song) else nil,
		Coins = if play.Solved then Logic.Coins(#play.Guesses) else 0,
		XP = if play.Solved then DailySongConstants.XP else 0,
		Streak = Logic.LiveStreak(data.DailySong.Streak.Get(), data.DailySong.LastSolved.Get(), day),
		Best = data.DailySong.Best.Get(),
		Stats = statsFor(day),
		NextIn = RewardsCatalog.SecondsLeft(os.time()),
		Shared = share ~= nil and share.Day == day and share.Count >= DailySongConstants.SHARE_PER_DAY,
	})
end

-- [[ Actions ]]

local function move(player: Player, data, guess: string?)
	local day = today()
	local song = songFor(day)
	if not song then
		return
	end
	if guess ~= nil and not SongLibrary.GetById(guess) then
		sendState(player, data) -- not a song: nothing changes
		return
	end
	local before = playOf(data)
	local after, result = Logic.Apply(before, song.Id, guess)
	if not result then
		sendState(player, data)
		return
	end

	local coins = if after.Solved then Logic.Coins(#after.Guesses) else 0
	PlayerData.Batch(player, function()
		local d = data.DailySong
		d.Guesses.Set(after.Guesses)
		d.Solved.Set(after.Solved)
		d.Done.Set(after.Done)
		if after.Done then
			d.Played.Increment(1)
			local streak = Logic.Streak(d.Streak.Get(), d.LastSolved.Get(), day, after.Solved)
			d.Streak.Set(streak)
			if after.Solved then
				d.Wins.Increment(1)
				d.LastSolved.Set(day)
				if streak > d.Best.Get() then
					d.Best.Set(streak)
				end
				Currencies.Data(data, "Coins").Increment(coins)
				data.Player.XP.Increment(DailySongConstants.XP)
			end
		end
	end)

	if after.Done then
		local tries = #after.Guesses
		countFinish(day, if after.Solved then tostring(tries) else "X")
		Analytics.Event(player, "DailySong", tries, if after.Solved then "Solved" else "Missed", `Try{tries}`)
		if after.Solved then
			RewardsService.RecordDailySong(player)
			Analytics.Economy(player, "Source", "Coins", coins, Currencies.Data(data, "Coins").Get(), AnalyticsEvents.Transactions.Daily, "DailySong")
		end
	end
	sendState(player, data, result)
end

local function share(player: Player, data)
	local day = today()
	local song = songFor(day)
	local play = playOf(data)
	if not song or not play.Done then
		return
	end
	local mine = shares[player]
	if not mine or mine.Day ~= day then
		mine = { Day = day, Count = 0 }
		shares[player] = mine
	end
	if mine.Count >= DailySongConstants.SHARE_PER_DAY then
		sendState(player, data)
		return
	end
	mine.Count += 1
	DailySongRemote:Fire(Bridgenet.AllPlayers(), {
		Message = "Shared",
		UserId = player.UserId,
		Name = player.DisplayName,
		Number = Logic.Number(day),
		Marks = marksOf(play, song.Id),
		Solved = play.Solved,
	})
	sendState(player, data)
end

local ACTIONS = {
	Open = function(player, data)
		sendState(player, data)
	end,
	Guess = function(player, data, packet)
		if type(packet.Id) == "string" and #packet.Id <= 80 then
			move(player, data, packet.Id)
		end
	end,
	Skip = function(player, data)
		move(player, data, nil)
	end,
	Share = share,
}

-- [[ Public ]]

-- Today's number and chart for the jumbotron slide (Engine/StreetScreens), with yesterday's
-- answer: that day is over everywhere, so it spoils nothing. Never today's song.
function DailySongService.Today(): { Number: number, Stats: { Tries: { number }, Missed: number, Total: number }, Yesterday: string? }
	local day = today()
	local before = songFor(day - 1)
	return {
		Number = Logic.Number(day),
		Stats = statsFor(day),
		Yesterday = if before and Logic.Number(day - 1) >= 1 then `{before.Name} · {before.Artist}` else nil,
	}
end

-- [[ Lifecycle ]]

-- a new day: start a fresh play (on join, and on any action that crosses midnight)
local function startDay(player: Player, data)
	local day = today()
	if data.DailySong.Day.Get() == day then
		return
	end
	PlayerData.Batch(player, function()
		data.DailySong.Day.Set(day)
		data.DailySong.Guesses.Set({})
		data.DailySong.Solved.Set(false)
		data.DailySong.Done.Set(false)
	end)
end

function DailySongService.Start()
	DailySongRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or busy[player] then
			return
		end
		local action = ACTIONS[packet.Action]
		local data = PlayerData.Get(player)
		if not action or not data then
			return
		end
		busy[player] = true
		local ok, err = pcall(function()
			startDay(player, data)
			action(player, data, packet)
		end)
		busy[player] = nil
		if not ok then
			warn("[DailySongService]", packet.Action, err)
		end
	end)

	local function onJoin(player: Player)
		local data = PlayerData.WaitForData(player)
		if data then
			startDay(player, data)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		shares[player] = nil
	end)

	-- keep the chart fresh while anyone is here
	task.spawn(function()
		while true do
			task.wait(DailySongConstants.STATS_REFRESH)
			if #Players:GetPlayers() > 0 then
				refreshStats(today())
			end
		end
	end)
end

return DailySongService
