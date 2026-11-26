--| BinderController/Songs
-- The Binder's Songs tab (Interface.Frames.Binder.Songs, built by ./Build), from design board
-- "46 · Binder · Songs tab with sub-tabs". How well you know each song (Inventory.Mastery,
-- Modules/Library/Mastery), filled for ../init:
--   Group     one group's songs: banner (kicker, the songs ladder's rung "SILVER → GOLD",
--             PRACTISE <GROUP>), the songs ladder (Modules/Library/Ladders, board 48: a node
--             per rung, its coins or PAID under it), the star key, "Next: …" and a row per song
--   AllSongs  every song: Most stars / Nearly mastered / A–Z
--   Music     the panel in My pins' place: songs mastered, the share of every star you have,
--             and your lobby music (STOP)
-- A song row: name, MASTERED once ★★★, "x / y right · fastest 0.5 s", its stars, and the
-- lobby music pills: USE on a mastered song, PLAYING + STOP on the one in use (ProfileRemote
-- SetBgMusic → Engine/ProfileService; it plays from Client/BackgroundMusic, "BgMusic" attribute).
-- PRACTISE starts solo with only that group's songs (QueueRemote "Practise" →
-- Engine/DuelService practiseGroup, theme "G:<artist>"; needs Themes.GROUP_MIN songs).

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Mastery = require(ReplicatedStorage.Modules.Library.Mastery)
local Ladders = require(ReplicatedStorage.Modules.Library.Ladders)
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)
local Themes = require(ReplicatedStorage.Modules.Library.Themes)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)

local ProfileRemote = Bridgenet.ReferenceBridge("ProfileRemote")
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

local fmt = ShopCatalog.Format
local C = Color3.fromHex
local player = Players.LocalPlayer

-- --------------------------------- Tables --------------------------------- --
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")

local ROW_BATCH = 30 -- song rows made per frame (All songs has every song)
local SONG_TIERS = DuelConstants.TIERS.Song

-- --------------------------------- Helpers -------------------------------- --
local function mastery(): { [string]: string }
	return PlayerData.Inventory.Mastery.Get() or {}
end

local function bgMusic(): string
	return player:GetAttribute("BgMusic") or ""
end

local function seconds(tier: number): string
	local s = SONG_TIERS[tier]
	return if s then `{s} s` else ""
end

local function tint(colour: string?): Color3
	local ok, c = pcall(Color3.fromHex, colour or "")
	return if ok then c else C("9ED8F5")
end

local function setStars(holder: Instance, n: number)
	for i = 1, 3 do
		local star = holder:FindFirstChild("Star" .. i)
		if star then
			star.ImageColor3 = if i <= n then YELLOW else INK
			star.ImageTransparency = if i <= n then 0 else 0.86
		end
	end
end

-- [[ Module ]]

local Songs = {}

-- every group with songs, A–Z (cached: the song list doesn't change in a session)
local artistList = nil
function Songs.Artists(): { string }
	if artistList then
		return artistList
	end
	local seen, out = {}, {}
	for _, song in SongLibrary.GetAllSongs() do
		if song.Artist and not seen[song.Artist] then
			seen[song.Artist] = true
			table.insert(out, song.Artist)
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	artistList = out
	return out
end

-- a group's songs (the song tables), A–Z
local bySongs = {}
function Songs.Of(artist: string): { any }
	if bySongs[artist] then
		return bySongs[artist]
	end
	local out = {}
	for _, id in Mastery.GroupSongs(artist) do
		local song = SongLibrary.GetById(id)
		if song then
			table.insert(out, song)
		end
	end
	table.sort(out, function(a, b)
		return (a.Name or ""):lower() < (b.Name or ""):lower()
	end)
	bySongs[artist] = out
	return out
end

-- "Girl" / "Boy" from the group's songs (for the list's filters; "" if unknown)
function Songs.GroupType(artist: string): string
	local first = Songs.Of(artist)[1]
	return first and first.GroupType or ""
end

-- lobby music back to the playlist
function Songs.StopMusic()
	ProfileRemote:Fire({ Action = "SetBgMusic", Id = "" })
end

-- a group's share of stars (0–1)
function Songs.Percent(artist: string, map: { [string]: string }?): number
	return Mastery.Percent(map or mastery(), Mastery.GroupSongs(artist))
end

-- how many songs are mastered, of how many
function Songs.Counts(map: { [string]: string }?): (number, number, number)
	map = map or mastery()
	local mastered, stars, total = 0, 0, 0
	for _, song in SongLibrary.GetAllSongs() do
		total += 1
		local n = Mastery.Stars(map[song.Id])
		stars += n
		if n >= Mastery.MAX_STARS then
			mastered += 1
		end
	end
	return mastered, stars, total
end

-- [[ Song rows ]]

-- the "x / y right · fastest" line
local function subLine(entry, artist: string?): string
	local parts = {}
	if artist then
		table.insert(parts, artist)
	end
	if entry.Plays == 0 then
		table.insert(parts, "Not played yet")
	else
		table.insert(parts, `{entry.Rights} / {entry.Plays} right`)
		if entry.Best > 0 then
			table.insert(parts, `fastest {seconds(entry.Best)}`)
		end
	end
	return table.concat(parts, " · ")
end

local function fillRow(row: Frame, song, map, withArtist: boolean)
	local value = map[song.Id]
	local entry = Mastery.Parse(value)
	local n = Mastery.Stars(value)
	local info = row.Card.Info
	local title = info.Top:FindFirstChild("Name") :: TextLabel -- (.Name is the property)
	title.Text = song.Name or "?"
	info.Top.Mastered.Visible = n >= Mastery.MAX_STARS
	info.Sub.Text = subLine(entry, if withArtist then song.Artist else nil)
	setStars(info.Right.Stars, n)
	local right = info.Right
	local playing = n >= Mastery.MAX_STARS and bgMusic() == song.Id
	right.Music.Visible = n >= Mastery.MAX_STARS
	right.Music.Text = if playing then "PLAYING" else "USE"
	right.Music.BackgroundColor3 = if playing then YELLOW else WHITE
	right.Stop.Visible = playing
	-- the group's colour: the note square, and a light wash of it on the card
	local colour = tint(song.Colour)
	row.Card.Note.BackgroundColor3 = colour
	row.Card.BackgroundColor3 = colour:Lerp(WHITE, if n >= Mastery.MAX_STARS then 0.55 else 0.78)
end

-- a pooled row for a list (made from its Template, hooked once)
local function rowFor(self, list: ScrollingFrame, pool: { Frame }, i: number): Frame
	local row = pool[i]
	if row then
		return row
	end
	row = list.Template:Clone()
	row.Name = "Song"
	local right = row.Card.Info.Right
	ButtonScale.Apply(right.Music)
	ButtonScale.Apply(right.Stop)
	right.Music.Activated:Connect(function()
		local id = row:GetAttribute("Song")
		if id and bgMusic() ~= id then
			Sounds.Play("Click")
			ProfileRemote:Fire({ Action = "SetBgMusic", Id = id })
		end
	end)
	right.Stop.Activated:Connect(function()
		Sounds.Play("Click")
		Songs.StopMusic()
	end)
	row.Parent = list
	pool[i] = row
	return row
end

-- fills a list with these songs, making rows a batch a frame (token: stop if refilled)
local function fillList(self, list: ScrollingFrame, pool: { Frame }, songs: { any }, withArtist: boolean, key: string)
	self._songToken = (self._songToken or 0) + 1
	local token = self._songToken
	local map = mastery()
	for i = #songs + 1, #pool do
		pool[i].Visible = false
	end
	for i, song in songs do
		if not pool[i] and i > 1 and (i - 1) % ROW_BATCH == 0 then
			task.wait()
			if self._songToken ~= token then
				return
			end
		end
		local row = rowFor(self, list, pool, i)
		row:SetAttribute("Song", song.Id)
		row.LayoutOrder = i
		fillRow(row, song, map, withArtist)
		row.Visible = true
	end
	self._songShown[key] = true
end

-- the pills after BgMusic changed (no rebuild)
function Songs.RefreshMusic(self)
	local map = mastery()
	for _, pool in { self._songRows.Group, self._songRows.All } do
		for _, row in pool do
			local id = row:GetAttribute("Song")
			local song = row.Visible and id and SongLibrary.GetById(id)
			if song then
				fillRow(row, song, map, pool == self._songRows.All)
			end
		end
	end
	Songs.FillPanel(self)
end

-- [[ Panels ]]

-- the Music panel in My pins' place
function Songs.FillPanel(self)
	local panel = self._frame.Binder.Groups.Music
	local mastered, stars, total = Songs.Counts()
	panel.Stat.Text = `{fmt(mastered)} mastered`
	local share = if total > 0 then stars / (total * Mastery.MAX_STARS) else 0
	panel.Known.Fill.Size = UDim2.fromScale(share, 1)
	panel.KnownText.Text = `You know {math.floor(share * 100 + 0.5)}% of every song`
	local id = bgMusic()
	local song = if id ~= "" then SongLibrary.GetById(id) else nil
	panel.Lobby.Song.Text = if song then `{song.Name} · {song.Artist}` else "The lobby playlist"
	panel.Lobby.Stop.Visible = song ~= nil
end

-- one group's page
function Songs.FillGroup(self, artist: string?)
	local page = self._frame.Songs.Group
	if not artist then
		page.Visible = false
		return
	end
	local list = Songs.Of(artist)
	local map = mastery()
	local head = page.Head
	local gen = list[1] and list[1].Generation
	head.Kicker.Text = string.upper(`{artist}{if gen then ` · {gen} GEN` else ""} · {#list} SONGS`)
	local rung, nextRung = Ladders.SongsRung(map, artist)
	local saved = (PlayerData.Inventory.Ladders.Get() or {})[Ladders.Key("Songs", artist)] or 0
	rung = math.max(rung, saved) -- (a rung once reached is kept)
	head.Percent.Text = Songs.RungText(rung, Ladders.Eligible(artist))
	self.DressIcon(head.Icon, artist)
	-- the banner in the group's colour
	local colour = tint(list[1] and list[1].Colour)
	local wash = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colour),
		ColorSequenceKeypoint.new(0.6, colour:Lerp(WHITE, 0.6)),
		ColorSequenceKeypoint.new(1, CREAM),
	})
	head.Tint.Color = wash
	head.Square.Tint.Color = wash
	local open = Themes.IsOpen(Themes.ForGroup(artist))
	head.Practise.Text = string.upper(`PRACTISE {artist}`)
	head.Practise.Visible = open
	head.PractiseShadow.Visible = open

	-- the songs ladder: filled up to the rung reached, each chip its coins or PAID
	local track = head.Milestones
	local steps = #Ladders.RUNGS - 1
	track.Fill.Size = UDim2.fromScale(math.clamp((rung - 1) / steps, 0, 1), 1)
	track.Fill.Visible = rung >= 1
	for i, name in Ladders.RUNGS do
		local reached = rung >= i
		local node = track:FindFirstChild("R" .. i)
		if node then
			node.BackgroundColor3 = if reached then Ladders.COLOURS[name] else CREAM
		end
		local chip = track:FindFirstChild("C" .. i)
		if chip then
			chip.Text = if reached then `{string.upper(name)} · PAID` else `{string.upper(name)} · {fmt(Ladders.COINS.Songs[i])}`
			chip.BackgroundColor3 = if reached or i == rung + 1 then Ladders.COLOURS[name] else CREAM
			local sheen = chip:FindFirstChild("Sheen")
			if sheen then
				sheen.Enabled = name == "Diamond" and (reached or i == rung + 1)
			end
		end
	end
	page.Hint.Text = Songs.NextText(nextRung, open, Ladders.Eligible(artist))
	if self._songGroupShown ~= artist then
		page.List.CanvasPosition = Vector2.zero
	end
	self._songGroupShown = artist
	task.spawn(fillList, self, page.List, self._songRows.Group, list, false, "Group")
end

-- the ladder's heading: "SILVER → GOLD" (rich text), "DIAMOND", "NOT STARTED → BRONZE"
function Songs.RungText(rung: number, has: boolean?): string
	if has == false then
		return "NO BADGES"
	end
	local now = Ladders.RUNGS[rung]
	local nextName = Ladders.RUNGS[rung + 1]
	local head = if now then string.upper(now) else "NOT STARTED"
	if not nextName then
		return head
	end
	return `{head} <font transparency="0.5" size="18">→ {string.upper(nextName)}</font>`
end

-- what the next songs rung needs: "Next: every song ★★ · 2 to go (Black Mamba, Whiplash)"
function Songs.NextText(nextRung, practise: boolean, has: boolean): string
	if not has then
		return `Badges need {Ladders.SONGS_MIN}+ songs and photocards for this group.`
	end
	if not nextRung then
		return "Diamond! Every song mastered."
	end
	local left = math.max(0, nextRung.Need - nextRung.Have)
	local text = `Next: {nextRung.Text} · {left} to go`
	local names = {}
	for _, id in nextRung.Missing or {} do
		local song = SongLibrary.GetById(id)
		if song and #names < 2 then
			table.insert(names, song.Name)
		end
	end
	if #names > 0 then
		text ..= ` <font transparency="0.35">({table.concat(names, ", ")}{if left > #names then ", …" else ""})</font>`
	end
	if not practise then
		text ..= " · duels only"
	end
	return text
end

-- every song, in the sort
function Songs.FillAll(self)
	local page = self._frame.Songs.AllSongs
	for _, b in page.Sorts:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == self._songSort
			b.BackgroundColor3 = if on then INK else CREAM
			b.TextColor3 = if on then CREAM else INK
		end
	end
	local map = mastery()
	local list = table.clone(SongLibrary.GetAllSongs())
	local starsOf, fastOf = {}, {}
	for _, song in list do
		local v = map[song.Id]
		starsOf[song.Id] = Mastery.Stars(v)
		fastOf[song.Id] = Mastery.Parse(v).Fast
	end
	local sort = self._songSort
	table.sort(list, function(a, b)
		local sa, sb = starsOf[a.Id], starsOf[b.Id]
		if sort == "Stars" and sa ~= sb then
			return sa > sb
		elseif sort == "Near" then
			-- not mastered yet, closest first (stars, then fast guesses toward FAST_COUNT)
			local ma, mb = sa >= Mastery.MAX_STARS, sb >= Mastery.MAX_STARS
			if ma ~= mb then
				return mb
			end
			if sa ~= sb then
				return sa > sb
			end
			if fastOf[a.Id] ~= fastOf[b.Id] then
				return fastOf[a.Id] > fastOf[b.Id]
			end
		end
		return (a.Name or ""):lower() < (b.Name or ""):lower()
	end)
	local mastered = Songs.Counts(map)
	page.Summary.Text = `{fmt(#list)} songs · {fmt(mastered)} mastered`
	task.spawn(fillList, self, page.List, self._songRows.All, list, true, "All")
end

-- PRACTISE: solo with this group's songs
function Songs.Practise(self, artist: string)
	Sounds.Play("Click")
	QueueRemote:Fire({ Request = "Practise", Group = artist })
	self._interface:Close(self.Name)
end

return Songs
