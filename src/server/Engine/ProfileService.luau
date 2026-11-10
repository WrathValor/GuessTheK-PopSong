--| ProfileService
-- The Profile screen (design boards "Profile 1 · your card" + "Profile 2 · clicking another
-- player"). Saves the showcase, and mirrors the public bits other players' clients show on the
-- player card as attributes (like DataService does for name tags):
--   Showcase    5 lines, "<songId>|<Level>" or "-" per slot (Modules/Showcase)
--   BgMusic     the Rainbow card the player uses as background music (song id, "" = none)
--   Wins, Duels, BestStreak, Perfect, SongsOwned
-- (Level, Title, TitleTier and Streak come from DataService.)
--
-- ProfileRemote requests: { Action = "SetShowcase", Songs = { songId or "", ×5 } }
--   by slot; a slot that isn't an owned song (or repeats an earlier slot) is saved empty
--                   { Action = "SetBgMusic", Id = songId or "" } – a Rainbow card you own, or ""
--   to go back to the game's playlist

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Showcase = require(ReplicatedStorage.Modules.Showcase)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)

local ProfileRemote = Bridgenet.ReferenceBridge("ProfileRemote")

local MIN_GAP = 0.5 -- requests closer together than this are dropped

local ProfileService = {}

local last: { [Player]: number } = {}

-- [[ Mirrors ]]

local function pinsOf(data): { string }
	local pins = {}
	for _, key in Showcase.KEYS do
		table.insert(pins, data.Profile.Showcase[key].Get())
	end
	return pins
end

local function showShowcase(player: Player, data)
	local cards = Showcase.Resolve(pinsOf(data), function(id: string): boolean
		return data.Inventory.Songs.Has(id)
	end, data.Inventory.Copies.Get())
	player:SetAttribute("Showcase", Showcase.Encode(cards))
end

-- a song id that can be background music: owned, and a Rainbow card
local function isRainbow(data, id: string): boolean
	if id == "" or not data.Inventory.Songs.Has(id) then
		return false
	end
	return Cards.Level(Cards.Copies(data.Inventory.Copies.Get(), true, id)) == "Rainbow"
end

local function countOwned(data): number
	local n = 0
	for _, song in Songs.GetAllSongs() do
		if data.Inventory.Songs.Has(song.Id) then
			n += 1
		end
	end
	return n
end

local function onPlayerAdded(player: Player)
	local data = PlayerData.WaitForData(player)
	if not data or not player.Parent then
		return
	end
	local stats = data.Statistics
	for attribute, path in { Wins = stats.Wins, Duels = stats.Duels, BestStreak = stats.HighestStreak, Perfect = stats.PerfectGames } do
		path.Observe(function(value: number)
			player:SetAttribute(attribute, value)
		end)
	end
	-- the showcase and the owned count follow the songs and their copies; deferred so a roll
	-- that adds several songs redraws once
	local pending = false
	local function refresh()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if player.Parent then
				player:SetAttribute("SongsOwned", countOwned(data))
				showShowcase(player, data)
				local bg = data.Profile.BgMusic.Get()
				player:SetAttribute("BgMusic", if isRainbow(data, bg) then bg else "")
			end
		end)
	end
	data.Inventory.Songs.Observe(refresh)
	data.Inventory.Copies.Observe(refresh)
	for _, key in Showcase.KEYS do
		data.Profile.Showcase[key].Observe(refresh)
	end
	data.Profile.BgMusic.Observe(refresh)
	refresh()
end

-- [[ Requests ]]

local function setShowcase(player: Player, list: any)
	local data = PlayerData.Get(player)
	if not data or type(list) ~= "table" then
		return
	end
	local pins, seen = {}, {}
	for i = 1, Showcase.SLOTS do
		local id = list[i]
		pins[i] = ""
		if type(id) == "string" and id ~= "" and #id <= 80 and not seen[id] and Songs.GetById(id) and data.Inventory.Songs.Has(id) then
			seen[id] = true
			pins[i] = id
		end
	end
	PlayerData.Batch(player, function()
		for i, key in Showcase.KEYS do
			data.Profile.Showcase[key].Set(pins[i])
		end
	end)
end

local function setBgMusic(player: Player, id: any)
	local data = PlayerData.Get(player)
	if not data or type(id) ~= "string" or #id > 80 then
		return
	end
	if id ~= "" and not isRainbow(data, id) then
		return -- only a Rainbow card you own
	end
	data.Profile.BgMusic.Set(id)
end

function ProfileService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		last[player] = nil
	end)

	ProfileRemote:Connect(function(player: Player, packet: any)
		if type(packet) ~= "table" then
			return
		end
		local now = os.clock()
		if last[player] and now - last[player] < MIN_GAP then
			return
		end
		last[player] = now
		if packet.Action == "SetShowcase" then
			setShowcase(player, packet.Songs)
		elseif packet.Action == "SetBgMusic" then
			setBgMusic(player, packet.Id)
		end
	end)
end

return ProfileService
