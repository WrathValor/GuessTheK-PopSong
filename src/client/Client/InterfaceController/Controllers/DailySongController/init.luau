--| DailySongController ("DailySong")
-- The Daily Song screen (Interface.Frames.DailySong, built by ./Build from the "Daily Song"
-- boards). The server (Engine/DailySongService) owns every rule: this sends
-- Open / Guess / Skip / Share on DailySongRemote and draws each State it gets back.
--   • Body.Play while today is still going: the clip (GameController/Snippet, up to the
--     current tier), the ladder, your guesses and the search box over the public catalog
--   • Body.Result once you're done: the revealed song, your squares, how everyone did,
--     coins + streak, and Share in chat (Client/DailySongChat posts the line everyone sees)
-- It opens from the listening booth on the plaza (Client/StreetScreens wires its prompt and
-- jukebox screen, and the jumbotron reminder); there's no HUD button.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local DailySongConstants = require(ReplicatedStorage.Constants.DailySongConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local GroupArt = require(ReplicatedStorage.Modules.UI.GroupArt)
local SongCard = require(ReplicatedStorage.Modules.UI.SongCard)

local Snippet = require(script.Parent.GameController.Snippet)
local BackgroundMusic = require(script.Parent.Parent.Parent.BackgroundMusic) -- Client/BackgroundMusic
local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local DailySongRemote = Bridgenet.ReferenceBridge("DailySongRemote")
local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local LILAC = C("B9A6FF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local PINK = C("FF9EC4")
local BLUSH = C("FFD2CE")
local SAND = C("EDE4D4")
local LINE = C("CFC5B3")
local MUTED = C("5C566B")
local BLUE = C("9ED8F5")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

-- the mark on a guess row / result square, per kind (white icons tinted ink; source PNGs in assets/ui/dailysong)
local MARKS = {
	Wrong = { Icon = "rbxassetid://91092504127857", Fill = PINK },
	Skip = { Icon = "rbxassetid://139120141257824", Fill = LINE },
	Right = { Icon = "rbxassetid://103354531145979", Fill = MINT },
}

-- ---------------------------------- Helpers --------------------------------- --

local function seconds(len: number): string
	return (if len < 1 then string.format("%.1f", len) else tostring(math.floor(len))) .. " s"
end

local function countdown(left: number): string
	left = math.max(0, math.floor(left))
	local h, m = left // 3600, (left % 3600) // 60
	return if h > 0 then `{h}h {m}m` else `{math.max(m, 1)}m`
end

local function fold(s: string): string
	return string.lower((s:gsub("[%s%p]", "")))
end

-- ---------------------------------- Class --------------------------------- --
local DailySong = {}
DailySong.__index = DailySong

function DailySong.new()
	local self = setmetatable({}, DailySong)
	self.Name = "DailySong"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._state = nil :: any -- the last State packet
	self._selected = nil :: string? -- song Id picked from the suggestions
	self._snippet = nil :: any
	self._clipKey = nil :: string?
	self._deadline = 0 -- os.clock() when the next song starts
	self._chorusOn = false
	return (self :: any) :: UITypes.Controller
end

-- [[ Clip ]]

function DailySong:_ensureSnippet()
	local s = self._state
	if not s or not s.Clip then
		return nil
	end
	local key = tostring(s.Clip.MusicId)
	if self._snippet and self._clipKey == key then
		return self._snippet
	end
	if self._snippet then
		self._snippet:Destroy()
	end
	self._snippet = Snippet.new(s.Clip, "Song")
	self._clipKey = key
	return self._snippet
end

function DailySong:_stopClip()
	if self._snippet then
		self._snippet:Stop()
	end
	self._chorusOn = false
end

-- [[ Drawing: shared ]]

function DailySong:_paintMark(m: Frame, kind: string?)
	local spec = kind and MARKS[kind]
	m.BackgroundColor3 = if spec then spec.Fill else WHITE
	m.Icon.Image = if spec then spec.Icon else ""
end

function DailySong:_paintHeader()
	local s = self._state
	local header = self._frame.Panel.Header
	header.BackgroundColor3 = if s.Done then MINT else LILAC
	header.Fill.BackgroundColor3 = header.BackgroundColor3
	header.TitleRow.Chip.Text = `#{s.Number} · {os.date("!%a %d %b", os.time())}`
	header.TitleRow.Sub.Visible = not s.Done
	header.NextIn.Visible = s.Done
end

-- [[ Drawing: play view ]]

function DailySong:_paintPlay()
	local s = self._state
	local view = self._frame.Panel.Body.Play
	local tiers = s.Tiers
	local tier = s.Tier

	view.Mystery.Plays.Text = `Plays {seconds(tiers[tier])}`
	view.TryLabel.Text = `Try {math.min(#s.Guesses + 1, s.Tries)} of {s.Tries}`
	for i = 1, Build.TRIES do
		local t = view.Ladder["Tier" .. i]
		local shadow = view.Ladder["Tier" .. i .. "Shadow"]
		local used, now = i < tier, i == tier
		t.Len.Text = seconds(tiers[i] or 0)
		t.Coins.Text = `{DailySongConstants.COINS[i] or 0} coins`
		t.BackgroundColor3 = if used then LINE elseif now then YELLOW else WHITE
		t.Len.TextColor3 = if used then MUTED else INK
		t.Coins.TextColor3 = if used then MUTED else INK
		shadow.Visible = not used
	end

	local coins = DailySongConstants.COINS[tier] or 0
	view.Note.Text.Text = if s.Streak > 0
		then `Get it now for {coins} coins and keep your {s.Streak}-day streak`
		else `Get it now for {coins} coins`
	view.Note.Streak.Text = `Streak {s.Streak}`

	for i = 1, Build.TRIES do
		local row = view.Guesses["Guess" .. i]
		local g = s.Guesses[i]
		local stroke = row:FindFirstChildOfClass("UIStroke")
		self:_paintMark(row.Mark, g and g.Kind)
		row.Mark.Visible = g ~= nil
		if g then
			row.BackgroundColor3 = if g.Kind == "Wrong" then BLUSH elseif g.Kind == "Skip" then SAND else MINT
			stroke.Color = INK
			row.Title.Text = if g.Song then g.Song.Name elseif g.Kind == "Skip" then "Skipped" else ""
			row.Title.TextColor3 = if g.Kind == "Skip" then MUTED else INK
			row.Artist.Text = if g.Song then g.Song.Artist else ""
			row.Len.Text = seconds(tiers[i] or 0)
		else
			row.BackgroundColor3 = WHITE
			stroke.Color = LINE
			row.Title.Text = ""
			row.Artist.Text = ""
			row.Len.Text = ""
		end
	end

	local last = #s.Guesses + 1 >= s.Tries
	view.Guesses.Skip.Text = if last then "Skip · reveal it" else `Skip · hear {seconds(tiers[math.min(tier + 1, #tiers)])}`
	self:_refreshSearch()
end

-- [[ Search ]]

function DailySong:_matches(query: string): { any }
	local s = self._state
	local guessed = {}
	for _, g in (s and s.Guesses or {}) do
		if g.Song then
			guessed[g.Song.Id] = true
		end
	end
	local q = fold(query)
	local starts, contains = {}, {}
	for _, song in SongLibrary.GetAllSongs() do
		if not guessed[song.Id] then
			local name, artist = fold(song.Name), fold(song.Artist)
			if q == "" then
				continue
			elseif string.sub(name, 1, #q) == q then
				table.insert(starts, song)
			elseif string.find(name, q, 1, true) or string.find(artist, q, 1, true) then
				table.insert(contains, song)
			end
		end
	end
	for _, song in contains do
		table.insert(starts, song)
	end
	return starts
end

function DailySong:_refreshSearch()
	local view = self._frame.Panel.Body.Play
	local guesses = view.Guesses
	local input = guesses.SearchBox.Input
	local query = input.Text
	local list = if query ~= "" and not self._selected then self:_matches(query) else {}
	local open = #list > 0 and input:IsFocused()
	guesses.Suggestions.Visible = open
	guesses.SuggestionsShadow.Visible = open
	for i = 1, Build.SUGGESTIONS do
		local option = guesses.Suggestions.List["Option" .. i]
		local song = list[i]
		option.Visible = song ~= nil
		option.BackgroundColor3 = if i == 1 then C("E8DEFF") else WHITE
		option.Title.Text = if song then song.Name else ""
		option.Artist.Text = if song then song.Artist else ""
		option:SetAttribute("SongId", if song then song.Id else nil)
	end
	local total = #SongLibrary.GetAllSongs()
	guesses.SearchBox.Count.Text = if query == "" then `{total} songs` elseif self._selected then "picked" else `{#list} found`
	local canGuess = self._selected ~= nil or #list > 0
	guesses.Guess.BackgroundColor3 = if canGuess then YELLOW else SAND
	guesses.Guess.TextColor3 = if canGuess then INK else MUTED
end

function DailySong:_pick(songId: string)
	local song = SongLibrary.GetById(songId)
	if not song then
		return
	end
	self._selected = songId
	local input = self._frame.Panel.Body.Play.Guesses.SearchBox.Input
	-- (Text change signals are deferred, so a flag set around this would already be gone
	-- when the signal fires: remember the text instead)
	self._pickedText = `{song.Name} · {song.Artist}`
	input.Text = self._pickedText
	input:ReleaseFocus()
	self:_refreshSearch()
end

function DailySong:_submitGuess()
	local s = self._state
	if not s or s.Done then
		return
	end
	local id = self._selected
	if not id then
		local first = self:_matches(self._frame.Panel.Body.Play.Guesses.SearchBox.Input.Text)[1]
		id = first and first.Id
	end
	if not id then
		Juice.Shake(self._frame.Panel.Body.Play.Guesses.SearchBox, 0.2) -- (strength scales a 6° wobble: wide boxes want it small)
		return
	end
	DailySongRemote:Fire({ Action = "Guess", Id = id })
end

function DailySong:_clearInput()
	self._selected = nil
	self._pickedText = nil
	self._frame.Panel.Body.Play.Guesses.SearchBox.Input.Text = ""
end

-- [[ Drawing: result view ]]

function DailySong:_paintResult()
	local s = self._state
	local view = self._frame.Panel.Body.Result
	local answer = s.Answer or {}
	local n = #s.Guesses

	local songCard = view.SongHolder.Song
	songCard.Title.Text = answer.Name or ""
	songCard.Artist.Text = if answer.Year then `{answer.Artist} · {answer.Year}` else (answer.Artist or "")
	-- the Index's look: the group's colours + the song's initials
	if answer.Id then
		GroupArt.Paint(songCard.Art, answer)
	end
	songCard.Art.Initials.Text = SongCard.Initials(answer.Name or "")
	view.SongHolder.Sticker.Visible = s.Solved and s.Streak > 0
	view.SongHolder.Sticker.Text = `DAY {s.Streak}`

	local summary = view.Summary
	local stats = s.Stats or { Tries = {}, Missed = 0, Total = 0 }
	if s.Solved then
		summary.Headline.Text = if n == 1 then "FIRST TRY!" else `GOT IT IN {n}!`
		local slower = stats.Missed or 0
		for i = n + 1, s.Tries do
			slower += stats.Tries[i] or 0
		end
		local beat = if (stats.Total or 0) > 1 then math.floor(slower / stats.Total * 100 + 0.5) else nil
		summary.Sub.Text = `From a {seconds(s.Tiers[n] or 0)} clip.` .. (if beat then ` Faster than {beat}% of players today.` else "")
	else
		summary.Headline.Text = "OUT OF TRIES"
		summary.Sub.Text = "Back tomorrow for a new one. Your streak starts again."
	end

	for i = 1, Build.TRIES do
		local sq = summary.Squares["Square" .. i]
		local g = s.Guesses[i]
		self:_paintMark(sq, g and g.Kind)
		sq.BackgroundTransparency = if g then 0 else 1
		sq:FindFirstChildOfClass("UIStroke").Color = if g then INK else LINE
		summary.Squares["Square" .. i .. "Shadow"].Visible = g ~= nil
	end
	summary.Share.Text = if s.Shared then "SHARED ✓" else "SHARE IN CHAT"
	summary.Share.FontFace = if s.Shared then BODY else HEAD
	summary.Share.BackgroundColor3 = if s.Shared then SAND else YELLOW

	local chart = summary.Chart
	local total = math.max(stats.Total or 0, 0)
	chart.Players.Text = if total == 1 then "1 player today" else `{total} players today`
	local counts = {}
	for i = 1, s.Tries do
		counts[i] = stats.Tries[i] or 0
	end
	counts[Build.STAT_ROWS] = stats.Missed or 0
	local most = 1
	for _, c in counts do
		most = math.max(most, c)
	end
	local mine = if s.Solved then n else Build.STAT_ROWS
	for i = 1, Build.STAT_ROWS do
		local row = chart["Row" .. i]
		local c = counts[i] or 0
		row.Pct.Text = if total > 0 then `{math.floor(c / total * 100 + 0.5)}%` else "–"
		local bar = row.Track.Bar
		bar.Size = UDim2.fromScale(math.max(c / most, 0.03), 1)
		bar.BackgroundColor3 = if i == mine then MINT elseif i == Build.STAT_ROWS then SAND else BLUE
		row.Label.FontFace = if i == mine then HEAD else BODY
	end

	summary.Coins.Amount.Text = if s.Solved then `+{s.Coins} coins` else "No coins today"
	summary.Coins.XP.Text = if s.Solved then `+{s.XP} XP` else ""
	summary.Streak.Days.Text = if s.Streak == 0 then "Streak reset" elseif s.Streak == 1 then "1-day streak" else `{s.Streak}-day streak`
	summary.Streak.Best.Text = `Best: {s.Best} {if s.Best == 1 then "day" else "days"}`
	view.Chorus.Text = if self._chorusOn then "■  Stop" else "▶  Play the chorus"
end

-- [[ State ]]

function DailySong:_apply(packet)
	local before = self._state
	self._state = packet
	self._deadline = os.clock() + (packet.NextIn or 0)
	if not self._frame.Visible then
		return
	end

	-- sounds + motion for what this action did
	local result = packet.Result
	if result == "Right" then
		Sounds.Play("Correct")
	elseif result == "Wrong" or result == "Missed" then
		Sounds.Play("Wrong")
		local row = self._frame.Panel.Body.Play.Guesses:FindFirstChild("Guess" .. #packet.Guesses)
		if row and result == "Wrong" then
			-- a gentle nudge (about 1°: the row is wide, so more swings its ends a long way)
			-- and a pop on the X so the miss still reads
			Juice.Shake(row, 0.2)
			Juice.Pop(row.Mark, 0.25)
		end
	elseif result == "Skip" then
		Sounds.Play("Click")
	end
	if result then
		self:_clearInput()
	end

	local becameDone = packet.Done and not (before and before.Done and before.Day == packet.Day)
	self:_show()
	if becameDone and result then
		local summary = self._frame.Panel.Body.Result.Summary
		local list = {}
		for i = 1, Build.TRIES do
			table.insert(list, summary.Squares["Square" .. i])
		end
		Juice.Stagger(list, 0.06)
		Juice.Pop(self._frame.Panel.Body.Result.SongHolder, 0.15)
		-- play the answer once it's revealed
		local snippet = self:_ensureSnippet()
		if snippet then
			snippet:PlayFull()
			self._chorusOn = true
			self:_paintResult()
		end
	elseif result == "Wrong" or result == "Skip" then
		-- the next, longer clip plays straight away
		local snippet = self:_ensureSnippet()
		if snippet then
			snippet:Play(packet.Tiers[packet.Tier])
		end
	end
end

function DailySong:_show()
	local s = self._state
	if not s then
		return
	end
	self:_paintHeader()
	local body = self._frame.Panel.Body
	body.Play.Visible = not s.Done
	body.Result.Visible = s.Done
	if s.Done then
		self:_paintResult()
	else
		self:_paintPlay()
	end
end

function DailySong:_tick()
	local s = self._state
	if not s then
		return
	end
	local left = self._deadline - os.clock()
	self._frame.Panel.Header.NextIn.Text = `Next song in {countdown(left)}`
	if left <= 0 and not self._asked then
		-- a new day: ask for it
		self._asked = true
		DailySongRemote:Fire({ Action = "Open" })
		task.delay(10, function()
			self._asked = false
		end)
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function DailySong:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "DailySong")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local j = self._janitor
	local play = panel.Body.Play
	local guesses = play.Guesses
	local result = panel.Body.Result

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(play.Mystery.PlayClip.Activated:Connect(function()
		local s, snippet = self._state, self:_ensureSnippet()
		if s and snippet then
			snippet:Play(s.Tiers[s.Tier])
			Juice.Pop(play.Mystery.PlayClip, 0.2)
		end
	end))
	j:Add(guesses.Skip.Activated:Connect(function()
		DailySongRemote:Fire({ Action = "Skip" })
	end))
	j:Add(guesses.Guess.Activated:Connect(function()
		self:_submitGuess()
	end))
	j:Add(result.Summary.Share.Activated:Connect(function()
		if self._state and not self._state.Shared then
			DailySongRemote:Fire({ Action = "Share" })
		end
	end))
	j:Add(result.Chorus.Activated:Connect(function()
		local snippet = self:_ensureSnippet()
		if not snippet then
			return
		end
		if self._chorusOn then
			snippet:Stop()
			self._chorusOn = false
		else
			snippet:PlayFull()
			self._chorusOn = true
		end
		self:_paintResult()
	end))

	-- search box
	local input = guesses.SearchBox.Input
	j:Add(input:GetPropertyChangedSignal("Text"):Connect(function()
		if self._selected and input.Text == self._pickedText then
			return -- the text we just wrote for a pick
		end
		self._selected = nil -- typing again drops the pick
		self._pickedText = nil
		self:_refreshSearch()
	end))
	j:Add(input.Focused:Connect(function()
		self:_refreshSearch()
	end))
	j:Add(input.FocusLost:Connect(function(enter: boolean)
		if enter then
			self:_submitGuess()
		end
		-- let a suggestion click land before the list hides
		task.delay(0.15, function()
			self:_refreshSearch()
		end)
	end))
	for i = 1, Build.SUGGESTIONS do
		local option = guesses.Suggestions.List["Option" .. i]
		j:Add(option.Activated:Connect(function()
			local id = option:GetAttribute("SongId")
			if id then
				self:_pick(id)
			end
		end))
	end

	-- the server's replies (Shared broadcasts are Client/DailySongChat's)
	j:Add(DailySongRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "State" then
			self:_apply(packet)
		end
	end), "Disconnect") -- (a BridgeNet connection has no Destroy)

	-- today's state straight away: the booth's jukebox and the jumbotron reminder use it too
	task.defer(function()
		DailySongRemote:Fire({ Action = "Open" })
	end)

	local ticker = task.spawn(function()
		while true do
			task.wait(15)
			self:_tick()
		end
	end)
	j:Add(function()
		task.cancel(ticker)
	end, true)
end

function DailySong:Activate()
	self._frame.Visible = true
	self:_clearInput()
	self:_show()
	self:_tick()
	DailySongRemote:Fire({ Action = "Open" }) -- fresh state (and the latest chart)
	BackgroundMusic.Duck()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function DailySong:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self:_stopClip()
	BackgroundMusic.Resume()
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function DailySong:Destroy()
	if self._snippet then
		self._snippet:Destroy()
	end
	self._janitor:Destroy()
end

return DailySong
