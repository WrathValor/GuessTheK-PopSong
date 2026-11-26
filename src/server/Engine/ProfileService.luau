--| ProfileService
-- The Profile screen (design boards "Profile 1 · your card" + "Profile 2 · clicking another
-- player"). Saves the showcase, and mirrors the public bits other players' clients show on the
-- player card as attributes (like DataService does for name tags):
--   Showcase    5 lines, "<songId>|<Level>" or "-" per slot (Modules/Showcase)
--   BgMusic     the mastered song (★★★, Modules/Library/Mastery) the player uses as lobby music
--               (song id, "" = none)
--   Wins, Duels, BestStreak, Perfect, SongsOwned
--   CardShowcase  K-POPPED!: the photocard showcase, "<cardId>*<copies>" per slot, "|" between
--                 ("" = empty; cards you no longer own show empty)
--   CardsOwned    different photocards owned
--   Sets          completed albums, "<albumId>" ("<albumId>!" = ALL-KILL), "," between, ALL-KILLs
--                 first, at most MAX_SETS of them; SetsDone / AllKills = the full counts
--   Correct, SoloBest  (for their profile's Stats tab)
-- (Level, Title, TitleTier and Streak come from DataService.)
--
-- ProfileRemote requests: { Action = "SetShowcase", Songs = { songId or "", ×5 } }
--   by slot; a slot that isn't an owned song (or repeats an earlier slot) is saved empty
--                   { Action = "SetBgMusic", Id = songId or "" } – a song you've mastered, or ""
--   to go back to the game's playlist
--                   { Action = "SetCards", Cards = { cardId or "", ×5 } } – the photocard showcase
--   by slot; a slot that isn't an owned card (or repeats an earlier slot) is saved empty

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Showcase = require(ReplicatedStorage.Modules.Showcase)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local Mastery = require(ReplicatedStorage.Modules.Library.Mastery)
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)

local ProfileRemote = Bridgenet.ReferenceBridge("ProfileRemote")

local MIN_GAP = 0.5 -- requests closer together than this are dropped
local MAX_SETS = 24 -- completed albums listed in the Sets attribute

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

-- the photocard showcase as other players see it (only cards still owned)
local function showCards(player: Player, data)
	local owned = data.Inventory.Cards.Get() or {}
	local out = {}
	for i, id in Albums.Showcase(data.Profile.Cards.Get()) do
		local copies = owned[id] or 0
		out[i] = if id ~= "" and copies > 0 then `{id}*{copies}` else ""
	end
	player:SetAttribute("CardShowcase", table.concat(out, "|"))

	-- their collection, for their profile when someone else opens it
	local count = 0 -- (cards of albums you can pull, like the binder counts them)
	local sets, allKills = {}, 0
	for _, artist in Albums.PullArtists() do
		for _, album in Albums.PullAlbums(artist) do
			for _, member in album.Members do
				for _, rarity in AlbumConstants.RARITIES do
					if (owned[Albums.CardId(album.Id, member.Key, rarity.Key)] or 0) > 0 then
						count += 1
					end
				end
			end
			if Albums.Complete(owned, album) then
				local kill = Albums.AllKill(owned, album)
				allKills += if kill then 1 else 0
				table.insert(sets, { Id = album.Id, Kill = kill, Artist = album.Artist })
			end
		end
	end
	table.sort(sets, function(a, b)
		if a.Kill ~= b.Kill then
			return a.Kill
		end
		return a.Artist:lower() < b.Artist:lower()
	end)
	local list = {}
	for i = 1, math.min(#sets, MAX_SETS) do
		list[i] = sets[i].Id .. (if sets[i].Kill then "!" else "")
	end
	player:SetAttribute("CardsOwned", count)
	player:SetAttribute("Sets", table.concat(list, ","))
	player:SetAttribute("SetsDone", #sets)
	player:SetAttribute("AllKills", allKills)
end

-- a song id that can be background music: owned, and a Rainbow card
-- lobby music: any song you've mastered (★★★)
local function isRainbow(data, id: string): boolean
	if id == "" then
		return false
	end
	return Mastery.Mastered(data.Inventory.Mastery[id].Get())
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
	for attribute, path in { Wins = stats.Wins, Duels = stats.Duels, BestStreak = stats.HighestStreak, Perfect = stats.PerfectGames, Correct = stats.CorrectAnswers, SoloBest = stats.SoloBest2 } do
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
	data.Inventory.Mastery.Observe(refresh)
	for _, key in Showcase.KEYS do
		data.Profile.Showcase[key].Observe(refresh)
	end
	data.Profile.BgMusic.Observe(refresh)
	refresh()

	-- the photocard showcase follows the saved slots and the cards you own
	local cardsPending = false
	local function refreshCards()
		if cardsPending then
			return
		end
		cardsPending = true
		task.defer(function()
			cardsPending = false
			if player.Parent then
				showCards(player, data)
			end
		end)
	end
	data.Inventory.Cards.Observe(refreshCards)
	data.Profile.Cards.Observe(refreshCards)
	refreshCards()
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

local function setCards(player: Player, list: any)
	local data = PlayerData.Get(player)
	if not data or type(list) ~= "table" then
		return
	end
	local owned = data.Inventory.Cards.Get() or {}
	local picks, seen = {}, {}
	for i = 1, AlbumConstants.SHOWCASE_SLOTS do
		local id = list[i]
		picks[i] = ""
		if type(id) == "string" and id ~= "" and #id <= 80 and not seen[id] and Albums.Card(id) and (owned[id] or 0) > 0 then
			seen[id] = true
			picks[i] = id
		end
	end
	data.Profile.Cards.Set(Albums.ShowcaseValue(picks))
end

local function setBgMusic(player: Player, id: any)
	local data = PlayerData.Get(player)
	if not data or type(id) ~= "string" or #id > 80 then
		return
	end
	if id ~= "" and not isRainbow(data, id) then
		return -- only a song you've mastered
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
		elseif packet.Action == "SetCards" then
			setCards(player, packet.Cards)
		elseif packet.Action == "SetBgMusic" then
			setBgMusic(player, packet.Id)
		end
	end)
end

return ProfileService
