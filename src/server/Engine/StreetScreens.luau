--| StreetScreens
-- Gathers what the screens around the street show and publishes it as one JSON attribute
-- ("Feed") on Map.Landmarks.BigScreen, which every client reads (Client/StreetScreens):
--   Live        the closest 1v1 duel in progress (names, scores, round, ENCORE)
--   New         this week's new songs (Constants/StreetScreens.NEW_SONGS, else the newest by Year)
--   Highlights  recent moments: ENCORE comebacks, Rainbow pulls, win streaks
--   Top         the most wins on this server since it started
--   Pulls       the last Gold / Rainbow card pulls (the gacha machine's ticker)
--   Merch       the merch pop-up's featured UGC item
--   Daily       today's Daily Song number + how everyone did, and yesterday's answer
--               (Engine/DailySongService.Today; never today's song)
-- Other services report moments with StreetScreens.Win / .Pull / .Comeback.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Constants.StreetScreens)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)

local LIVE_EVERY = 2 -- seconds between live-duel checks

local StreetScreens = {}

local highlights = {} -- { { Kind, Text, At } } newest first
local pulls = {} -- { string } newest first
local wins: { [number]: { Name: string, UserId: number, Wins: number } } = {}
local newSongs = {}
local lastJson = ""

local function stageLabel(name: string): string
	local n = name:match("(%d+)$")
	return if n then `Stage {n}` else name
end

-- the most exciting 1v1 in progress: later rounds first, then the smallest gap
local function liveDuel()
	local ok, DuelService = pcall(require, script.Parent.DuelService)
	if not ok then
		return nil
	end
	local best, bestKey = nil, nil
	for name, stage in DuelService.Stages do
		local duel = stage.Duel
		if duel and not duel.Solo and not duel.Party and not duel.Tutorial and duel.Slots and duel.Slots.A and duel.Slots.B and (duel.RoundNumber or 0) > 0 then
			local a, b = duel.Slots.A, duel.Slots.B
			local sa, sb = duel.Scores[a] or 0, duel.Scores[b] or 0
			local key = (duel.RoundNumber or 0) * 1000 - math.abs(sa - sb)
			if not bestKey or key > bestKey then
				local mult = if duel._multiplier then duel:_multiplier(duel.RoundNumber) else 1
				bestKey = key
				best = {
					Stage = stageLabel(name),
					Round = duel.RoundNumber,
					Rounds = duel.RoundCount,
					Mult = mult,
					A = { Name = a.DisplayName, UserId = a.UserId, Score = sa },
					B = { Name = b.DisplayName, UserId = b.UserId, Score = sb },
				}
			end
		end
	end
	return best
end

local function topWins()
	local list = {}
	for _, w in wins do
		table.insert(list, w)
	end
	table.sort(list, function(x, y)
		return x.Wins > y.Wins
	end)
	local out = {}
	for i = 1, math.min(3, #list) do
		out[i] = list[i]
	end
	return out
end

local function merch()
	local ok, UGCService = pcall(require, script.Parent.UGCService)
	if not ok or not UGCService.Items or #UGCService.Items == 0 then
		return nil
	end
	local dances = {}
	for _, item in UGCService.Items do
		if item.Kind == "Dance" then
			table.insert(dances, item)
		end
	end
	local pool = if #dances > 0 then dances else UGCService.Items
	local week = math.floor(os.time() / Constants.MERCH_SECONDS)
	local item = pool[(week % #pool) + 1]
	return { Id = item.Id, Name = item.Name, Artist = item.Artist, Price = item.Price, Count = #UGCService.Items }
end

-- this week's new songs, or the newest releases in the library (the library may still be
-- loading when the service starts, so this runs until it finds some)
local function loadNewSongs()
	local list = {}
	for _, id in Constants.NEW_SONGS do
		local song = Songs.GetById(id)
		if song then
			table.insert(list, song)
		end
	end
	if #list == 0 then
		list = table.clone(Songs.GetAllSongs() or {})
		table.sort(list, function(a, b)
			if (a.Year or 0) ~= (b.Year or 0) then
				return (a.Year or 0) > (b.Year or 0)
			end
			return a.Id < b.Id
		end)
	end
	for i = 1, math.min(Constants.NEW_SHOWN, #list) do
		newSongs[i] = { Name = list[i].Name, Artist = list[i].Artist, Colour = list[i].Colour }
	end
end

local function daily()
	local ok, DailySongService = pcall(require, script.Parent.DailySongService)
	if not ok then
		return nil
	end
	local ok2, today = pcall(DailySongService.Today)
	return if ok2 then today else nil
end

local function publish()
	if #newSongs == 0 then
		loadNewSongs()
	end
	local feed = {
		Live = liveDuel(),
		New = newSongs,
		Highlights = highlights,
		Top = topWins(),
		Pulls = pulls,
		Merch = merch(),
		Daily = daily(),
	}
	local json = HttpService:JSONEncode(feed)
	if json ~= lastJson then
		lastJson = json
		local screen = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Landmarks") and workspace.Map.Landmarks:FindFirstChild("BigScreen")
		if screen then
			screen:SetAttribute("Feed", json)
		end
	end
end

local function highlight(kind: string, text: string)
	table.insert(highlights, 1, { Kind = kind, Text = text, At = os.time() })
	while #highlights > Constants.HIGHLIGHTS do
		table.remove(highlights)
	end
	publish()
end

-- [[ Reported by other services ]]

-- a duel win (DuelService, after Rewards): counts towards Top; streak milestones make Highlights
function StreetScreens.Win(player: Player, streak: number?)
	local w = wins[player.UserId] or { Name = player.DisplayName, UserId = player.UserId, Wins = 0 }
	w.Wins += 1
	wins[player.UserId] = w
	if streak and streak > 0 and streak % Constants.STREAK_EVERY == 0 then
		highlight("STREAK", `{player.DisplayName} is on a {streak}-win streak`)
	else
		publish()
	end
end

-- a card pull reaching Gold or Rainbow (RollService)
function StreetScreens.Pull(player: Player, songName: string, level: string)
	table.insert(pulls, 1, `{player.DisplayName} pulled a {level} {songName}`)
	while #pulls > Constants.PULLS do
		table.remove(pulls)
	end
	if level == "Rainbow" then
		highlight("RAINBOW PULL", `{player.DisplayName} pulled a Rainbow {songName}`)
	else
		publish()
	end
end

-- the winner was behind going into the ENCORE round (DuelService)
function StreetScreens.Comeback(player: Player, behind: number)
	highlight("COMEBACK", `{player.DisplayName} came back from {behind} behind in the ENCORE!`)
end

function StreetScreens.Start()
	Players.PlayerRemoving:Connect(function(player)
		-- keep their wins on the board (they earned them), just stop growing it unbounded
		local count = 0
		for _ in wins do
			count += 1
		end
		if count > 50 then
			wins[player.UserId] = nil
		end
	end)

	task.spawn(function()
		while true do
			publish()
			task.wait(LIVE_EVERY)
		end
	end)
end

return StreetScreens
