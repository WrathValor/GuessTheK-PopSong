--| PartyController
-- Party Stages on the client (Engine/PartyService on the server, the "Party Stages" boards):
-- the stage's queue-style card and everything it flips to. Built in Studio by ./Build
-- (Interface.Frames.Party); this finds everything by name.
--   Lobby     setlist (photocards in join order, #1 hosts), INVITE / SETTINGS / START for the
--             host, READY UP for guests, Leave stage. Tapping a player (host) opens Player,
--             tapping an open spot opens Invite. A running countdown shows in the title.
--   Settings  every change is sent straight away (the server echoes the new State)
--   Songs     a local draft of the pool (groups on, single songs out) until SAVE
--   Prompt    one card for: friends only (ask to join), full (spectate), busy, a join
--             request (host), removed from the stage. (An invite is the duel toast: InviteToast.)
--   Results   after a party match (DuelController hands it the End packet)
--   Watch     spectating someone else's match
-- The card stays up while you're on the stage: Escape or another menu closing it brings it
-- back unless a match is on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local PartyConstants = require(ReplicatedStorage.Constants.PartyConstants)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local GroupArt = require(ReplicatedStorage.Modules.UI.GroupArt)

local Build = require(script.Build)
local InviteToast = require(script.Parent.Parent.Parent.InviteToast) -- Client/InviteToast: party invites use the duel toast
local CameraController = require(script.Parent.Parent.Parent.CameraController) -- Client/CameraController: the lobby pan

local LOCAL_PLAYER = Players.LocalPlayer
local PartyRemote = Bridgenet.ReferenceBridge("PartyRemote")
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local SAND = C("F3EBDD")
local YELLOW = C("FFE07A")
local LILAC = C("B9A6FF")
local BLUE = C("9ED8F5")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local GREY = C("EDE4D4")
local MUTED = C("5C566B")
local LINE = C("CFC5B3")
local GREEN = C("1E8A4A")
local GOLDTEXT = C("B8860B")
local AV = { C("FFD2CE"), C("DCD3FF"), C("C8EFD6"), C("CDEBFA"), C("FFE9A8"), C("FFD9EA") }
local MEDAL = { C("FFE07A"), C("E6E2EE"), C("F2C3A0"), C("FBF7F0"), C("FBF7F0"), C("FBF7F0") }
local ORDINAL = { "1st", "2nd", "3rd", "4th", "5th", "6th" }
local PAGES = { "Lobby", "Settings", "Invite", "Player", "Songs", "Prompt", "Results", "Watch" }
-- the lobby's own cards sit on the right (their right edge at ASIDE_RIGHT) while you're on the
-- stage, so the camera's circle of the ring (CameraController.PartyPan) shows everyone's spot
local ASIDE = { Lobby = true, Settings = true, Invite = true, Player = true, Songs = true }
local ASIDE_RIGHT = 1250
local FLIP_OUT = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLIP_IN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local thumbs: { [number]: string } = {}
local function thumb(userId: number, image: ImageLabel, initials: TextLabel?)
	local cached = thumbs[userId]
	if cached then
		image.Image = cached
		if initials then
			initials.Visible = cached == ""
		end
		return
	end
	image.Image = ""
	if initials then
		initials.Visible = true
	end
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		thumbs[userId] = if ok then img else ""
		if image.Parent then
			image.Image = thumbs[userId]
			if initials then
				initials.Visible = thumbs[userId] == ""
			end
		end
	end)
end

local function initialsOf(name: string): string
	return string.upper(string.sub(name, 1, 2))
end

-- the songs grouped for the picker: gens in order, each gen's groups A–Z
local GENS, GROUPS_OF, SONGS_OF = {}, {}, {}
do
	local seen = {}
	for _, song in Songs.All do
		local gen = song.Generation or "?"
		if not GROUPS_OF[gen] then
			GROUPS_OF[gen] = {}
			table.insert(GENS, gen)
		end
		if not seen[song.Artist] then
			seen[song.Artist] = true
			table.insert(GROUPS_OF[gen], song.Artist)
		end
		SONGS_OF[song.Artist] = SONGS_OF[song.Artist] or {}
		table.insert(SONGS_OF[song.Artist], song)
	end
	table.sort(GENS, function(a, b)
		return (tonumber(a:match("%d+")) or 99) < (tonumber(b:match("%d+")) or 99)
	end)
	for _, list in GROUPS_OF do
		table.sort(list, function(a, b)
			return a:lower() < b:lower()
		end)
	end
	for _, list in SONGS_OF do
		table.sort(list, function(a, b)
			return a.Name:lower() < b.Name:lower()
		end)
	end
end

-- --------------------------------- Class ---------------------------------- --
local Party = {}
Party.__index = Party

function Party.new()
	local self = setmetatable({}, Party)
	self.Name = "Party"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self.Info = nil :: any -- the last State packet while you're on a party stage
	self.InParty = false
	self._page = "Lobby"
	self._back = "Lobby" -- where the Prompt goes back to
	return (self :: any) :: UITypes.Controller
end

function Party:_isHost(): boolean
	return self.Info ~= nil and self.Info.Host == LOCAL_PLAYER.UserId
end

function Party:_me()
	for i, m in (self.Info and self.Info.Members) or {} do
		if m.UserId == LOCAL_PLAYER.UserId then
			return m, i
		end
	end
	return nil, nil
end

function Party:_send(packet)
	PartyRemote:Fire(packet)
end

-- [[ Pages ]]

local function setPair(parent: Instance, name: string, visible: boolean)
	local b = parent:FindFirstChild(name)
	if b then
		b.Visible = visible
	end
	local s = parent:FindFirstChild(name .. "Shadow")
	if s then
		s.Visible = visible
	end
end

function Party:_card(name: string): Frame
	return self._frame[name]
end

-- flip from the page showing to `page`
function Party:_show(page: string)
	local frame = self._frame
	local from = self._page
	self._page = page
	local function reveal()
		-- on the stage, the lobby's cards step over to the right (see ASIDE)
		local aside = self.InParty and ASIDE[page] == true
		for f, spots in self._home or {} do
			f.Position = if aside then spots.Aside else spots.Home
		end
		for _, p in PAGES do
			local visible = p == page
			frame[p].Visible = visible
			frame[p .. "Shadow"].Visible = visible
		end
		for _, f in { frame[page], frame[page .. "Shadow"] } do
			f.Flip.Scale = 0.7
			TweenService:Create(f.Flip, FLIP_IN, { Scale = 1 }):Play()
		end
	end
	self:_render()
	local current = frame:FindFirstChild(from)
	if current and current.Visible and from ~= page then
		local t = TweenService:Create(current.Flip, FLIP_OUT, { Scale = 0.7 })
		TweenService:Create(frame[from .. "Shadow"].Flip, FLIP_OUT, { Scale = 0.7 }):Play()
		t.Completed:Once(reveal)
		t:Play()
	else
		reveal()
	end
	self:_countdownLoop(page == "Lobby")
	self:_lobbyCamera()
end

-- On the stage before a match: the camera circles the ring (CameraController.PartyPan). Never
-- over the round camera or the victory shot; Left hands it back.
function Party:_lobbyCamera()
	if not (self.InParty and self.Info and self.Info.Status ~= "InMatch") then
		return
	end
	local mode = CameraController.Mode
	if mode == "PartyPan" or mode == "Victory" or mode == "Song" or mode == "Choreography" then
		return
	end
	CameraController.PartyPan()
end

function Party:_render()
	local page = self._page
	if page == "Lobby" then
		self:_renderLobby()
	elseif page == "Settings" then
		self:_renderSettings()
	elseif page == "Invite" then
		self:_renderInvite()
	elseif page == "Player" then
		self:_renderPlayer()
	elseif page == "Songs" then
		self:_renderSongs()
	end
end

-- [[ Lobby ]]

local function modeName(mode: string): string
	return if mode == "Duel" then "1v1 duel" else "free-for-all"
end

function Party:_songsText(): string
	local pool = self.Info and self.Info.Settings.Pool
	return if pool then `{pool.Count} custom songs` else "every song"
end

function Party:_countdownLoop(on: boolean)
	if self._cdConn then
		self._cdConn:Disconnect()
		self._cdConn = nil
	end
	if not on then
		return
	end
	local last = -1
	self._cdConn = RunService.Heartbeat:Connect(function()
		local info = self.Info
		if not info or info.Status ~= "Countdown" or not info.CountdownEnds then
			return
		end
		local left = math.max(0, math.ceil(info.CountdownEnds - workspace:GetServerTimeNow()))
		if left ~= last then
			last = left
			self:_card("Lobby").Title.Text = `Starting in {left}…`
			if left > 0 then
				Sounds.Play("Countdown")
			end
		end
	end)
end

function Party:_renderLobby()
	local info = self.Info
	local c = self:_card("Lobby")
	if not info then
		return
	end
	local s = info.Settings
	local members = info.Members
	local n, spots = #members, s.Spots
	local me = self:_me()
	local host = self:_isHost()
	local ready = 0
	for i, m in members do
		if i > 1 and m.Ready then
			ready += 1
		end
	end

	c.Tag.Text = string.upper(info.Title)
	if info.Status == "Countdown" then
		c.Title.Text = "Starting…"
	elseif host then
		c.Title.Text = if n < (if s.Mode == "Duel" then 2 else PartyConstants.MIN_FFA_PLAYERS) then "Waiting for players…"
			elseif ready == n - 1 then "Everyone's ready!"
			else "Waiting for ready-ups…"
	else
		c.Title.Text = if me and me.Ready then "Waiting for host…" else "Ready up!"
	end
	c.Sub.Text = `{n} / {spots} · {modeName(s.Mode)} · {self:_songsText()}`

	-- the setlist: only as many photocards as there are spots, centred
	local SW, GAP = 74, 10
	local x0 = (540 - (spots * SW + (spots - 1) * GAP)) / 2
	for i = 1, Build.SLOTS do
		local slot = c.Setlist["Slot" .. i]
		slot.Visible = i <= spots
		slot.Position = UDim2.fromOffset(x0 + (i - 1) * (SW + GAP), 0)
		local m = members[i]
		local photo = slot.Photo
		photo.Num.Text = tostring(i)
		photo.Crown.Visible = m ~= nil and m.Host
		local line = photo:FindFirstChildOfClass("UIStroke")
		if m then
			local isMe = m.UserId == LOCAL_PLAYER.UserId
			photo.BackgroundColor3 = AV[i]
			photo.Num.BackgroundColor3 = INK
			photo.Num.TextColor3 = WHITE
			line.Color = if isMe and not host then C("E0382C") else INK
			photo.Initials.Text = initialsOf(m.Name)
			photo.Initials.TextColor3 = INK
			thumb(m.UserId, photo.Avatar, photo.Initials)
			slot.PlayerName.Text = if isMe then "You" else m.Name
			slot.PlayerName.TextColor3 = if isMe then C("E0382C") else INK
			slot.State.Text = if m.Host then "Host" elseif m.Ready then "Ready" else "Not ready"
			slot.State.TextColor3 = if m.Host then GOLDTEXT elseif m.Ready then GREEN else MUTED
		else
			photo.BackgroundColor3 = SAND
			photo.Num.BackgroundColor3 = SAND
			photo.Num.TextColor3 = C("A39A8C")
			line.Color = LINE
			photo.Avatar.Image = ""
			photo.Initials.Visible = true
			photo.Initials.Text = "?"
			photo.Initials.TextColor3 = C("8A8396")
			slot.PlayerName.Text = if host then "Invite" else "Open"
			slot.PlayerName.TextColor3 = MUTED
			slot.State.Text = ""
		end
	end

	-- buttons
	local counting = info.Status == "Countdown"
	setPair(c, "Invite", host)
	setPair(c, "Settings", host)
	setPair(c, "Start", host)
	setPair(c, "Ready", not host)
	c.Rules.Visible = not host
	local open = spots - n
	c.Invite.Sub.Text = if open > 0 then `{open} spot{if open == 1 then "" else "s"} open` else "Stage is full"
	c.Settings.Sub.Text = `{if s.Mode == "Duel" then "1v1" else "FFA"} · {self:_songsText()} · ×{info.Multiplier} coins`
	local needed = if s.Mode == "Duel" then 2 else PartyConstants.MIN_FFA_PLAYERS
	local canStart = n >= needed and (s.Mode ~= "Duel" or n == 2) and ready == n - 1 and not counting
	c.Start.BackgroundColor3 = if canStart or counting then MINT else GREY
	c.Start.Title.Text = if counting then "STARTING…" else "START"
	c.Start.Sub.Text = if counting then "Removing players is locked from here on"
		elseif n < needed then `{if s.Mode == "Duel" then "A duel needs 2" else `FFA needs {needed}+`} players`
		else `{ready} / {n - 1} ready · {PartyConstants.COUNTDOWN} s countdown`
	if me and not host then
		c.Ready.BackgroundColor3 = if me.Ready then MINT else YELLOW
		c.Ready.Title.Text = if me.Ready then "READY ✓" else "READY UP"
		c.Ready.Sub.Text = if counting then "Un-ready stops the countdown" elseif me.Ready then "Tap to un-ready" else "Everyone's waiting on you"
		local bits = { if s.Mode == "Duel" then "1v1 duel" else "Free-for-all", self:_songsText(), if s.Boost then "owned songs count" else "owned songs off", if s.FriendsOnly then "friends only" else "open to all", `×{info.Multiplier} coins` }
		c.Rules.Text = table.concat(bits, " · ") .. (if info.Eligible then "" else `\nCustom pools under {PartyConstants.MIN_POOL_REWARDS} songs pay no coins or XP`)
	end
end

-- [[ Settings ]]

local toggleTweens: { [Instance]: Tween } = setmetatable({}, { __mode = "k" }) :: any
local TOGGLE_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function paintToggle(t: GuiButton, on: boolean)
	local knob = t.Knob
	local previous = toggleTweens[knob]
	if previous then
		previous:Cancel()
	end
	knob.AnchorPoint = Vector2.new(0, 0.5)
	local goal = {
		Position = if on then UDim2.new(1, -19, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = WHITE,
	}
	toggleTweens[knob] = TweenService:Create(knob, TOGGLE_TWEEN, goal)
	toggleTweens[knob]:Play()
	TweenService:Create(t, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = if on then MINT else GREY,
	}):Play()
end

local function paintSegment(seg: Frame, selected: number)
	for _, b in seg:GetChildren() do
		if b:IsA("TextButton") then
			local on = b.Name == "Option" .. selected
			b.BackgroundTransparency = if on then 0 else 1
			b.TextColor3 = if on then YELLOW else INK
		end
	end
end

function Party:_renderSettings()
	local info = self.Info
	if not info then
		return
	end
	local c = self:_card("Settings")
	local s = info.Settings
	paintSegment(c.Mode, if s.Mode == "Duel" then 1 else 2)
	c.SongsRow.Value.Text = if s.Pool then `{s.Pool.Count} songs · custom` else `Every song · {info.LibrarySize}`
	paintToggle(c.OwnedRow.Toggle, s.Boost)
	c.SpotsRow.Value.Text = tostring(s.Spots)
	local duel = s.Mode == "Duel"
	for _, n in { "Minus", "Plus" } do
		local b = c.SpotsRow[n]
		local can = not duel and (if n == "Minus" then s.Spots > math.max(PartyConstants.MIN_SPOTS, #info.Members) else s.Spots < PartyConstants.MAX_SPOTS)
		b.TextColor3 = if can then INK else C("A39A8C")
		b:FindFirstChildOfClass("UIStroke").Color = if can then INK else LINE
	end
	c.SpotsRow.Note.Text = if duel then "a duel is always 2" else `FFA: {PartyConstants.MIN_SPOTS}–{PartyConstants.MAX_SPOTS}`
	paintToggle(c.Every.FriendsRow.Toggle, s.FriendsOnly)
	paintToggle(c.Every.SpectatorsRow.Toggle, s.Spectators)
	c.Done.Sub.Text = if info.MultiplierText ~= "" then `Coins ×{info.Multiplier} · {info.MultiplierText}` else `Coins ×{info.Multiplier}`
end

-- [[ Invite ]]

function Party:_renderInvite()
	local c = self:_card("Invite")
	local info = self.Info
	local list = {}
	for _, p in self._inviteList or {} do
		if self._inviteFilter ~= "Friends" or p.Friend then
			table.insert(list, p)
		end
	end
	local per = Build.INVITE_ROWS
	local pages = math.max(1, math.ceil(#list / per))
	self._invitePage = math.clamp(self._invitePage or 1, 1, pages)
	paintSegment(c.Filter, if self._inviteFilter == "Friends" then 1 else 2)
	local open = if info then info.Settings.Spots - #info.Members else 0
	c.Sub.Text = `{open} spot{if open == 1 then "" else "s"} open · invites skip Friends only`
	c.Empty.Visible = #list == 0
	c.Empty.Text = if self._inviteList == nil then "Loading…" elseif self._inviteFilter == "Friends" then "None of your friends are in this server · try Everyone here" else "Nobody else is in this server right now"
	for i = 1, per do
		local r = c["Row" .. i]
		local p = list[(self._invitePage - 1) * per + i]
		r.Visible = p ~= nil
		if p then
			r.PlayerName.Text = p.Name
			local where = if p.Status == "Here" then "on this stage" elseif p.Status == "Busy" then "in a match" else "on the street"
			r.Sub.Text = `Lv {p.Level}{if p.Friend then " · friend" else ""} · {where}`
			thumb(p.UserId, r.Avatar)
			local b = r.Send
			b.Text = if p.Status == "Open" then "Invite" elseif p.Status == "Sent" then "Sent ✓" elseif p.Status == "Here" then "Here" else "Busy"
			b.BackgroundColor3 = if p.Status == "Open" then BLUE elseif p.Status == "Sent" then MINT else SAND
			b.TextColor3 = if p.Status == "Open" or p.Status == "Sent" then INK else C("A39A8C")
			b:SetAttribute("UserId", p.UserId)
			b:SetAttribute("Status", p.Status)
		end
	end
	c.Page.Text = `{self._invitePage} / {pages}`
	c.Prev.Visible = pages > 1
	c.Next.Visible = pages > 1
	c.Page.Visible = pages > 1
end

-- [[ Player (host) ]]

function Party:_renderPlayer()
	local info = self.Info
	local target, index = nil, nil
	for i, m in (info and info.Members) or {} do
		if m.UserId == self._playerId then
			target, index = m, i
		end
	end
	if not target then
		self:_show("Lobby")
		return
	end
	local c = self:_card("Player")
	c.Tag.Text = string.upper(target.Name)
	c.Photo.BackgroundColor3 = AV[index]
	c.Photo.Num.Text = tostring(index)
	c.Photo.Initials.Text = initialsOf(target.Name)
	thumb(target.UserId, c.Photo.Avatar, c.Photo.Initials)
	c.PlayerName.Text = target.Name
	c.Sub.Text = `Lv {target.Level} · joined {ORDINAL[index] or index} · {if target.Ready then "ready" else "not ready"}`
	local locked = info.Status ~= "Waiting"
	c.Kick.BackgroundColor3 = if locked then GREY else RED
	c.Kick.Sub.Text = if locked then "Locked once it starts" else "Back to the street"
	c.MakeHost.BackgroundColor3 = if locked then GREY else YELLOW
	paintToggle(c.BlockRow.Toggle, self._block == true)
end

-- [[ Songs ]]

function Party:_openSongs()
	local pool = self.Info and self.Info.Settings.Pool
	self._groups, self._out = {}, {}
	if pool then
		for _, g in pool.Groups do
			self._groups[g] = true
		end
		for _, id in pool.Out do
			self._out[id] = true
		end
	else
		for _, gen in GENS do
			for _, g in GROUPS_OF[gen] do
				self._groups[g] = true
			end
		end
	end
	self._view = "Gens"
	self._gen = self._gen or 1
	self._songPage = 1
	self:_show("Songs")
end

function Party:_draftSongs(): { any }
	local list = {}
	for _, gen in GENS do
		for _, g in GROUPS_OF[gen] do
			if self._groups[g] then
				for _, song in SONGS_OF[g] do
					table.insert(list, song)
				end
			end
		end
	end
	return list
end

function Party:_draftCount(): number
	local n = 0
	for _, song in self:_draftSongs() do
		if not self._out[song.Id] then
			n += 1
		end
	end
	return n
end

function Party:_draftIsAll(): boolean
	for _, gen in GENS do
		for _, g in GROUPS_OF[gen] do
			if not self._groups[g] then
				return false
			end
		end
	end
	return next(self._out) == nil
end

function Party:_renderSongs()
	local c = self:_card("Songs")
	local gensView, songsView = c.GensView, c.SongsView
	paintSegment(c.View, if self._view == "Songs" then 2 else 1)
	gensView.Visible = self._view ~= "Songs"
	songsView.Visible = self._view == "Songs"

	for i = 1, Build.GENS do
		local tile = gensView["Gen" .. i]
		local gen = GENS[i]
		tile.Visible = gen ~= nil
		if gen then
			local groups = GROUPS_OF[gen]
			local on, songs = 0, 0
			for _, g in groups do
				if self._groups[g] then
					on += 1
					songs += #SONGS_OF[g]
				end
			end
			local viewing = self._gen == i
			tile.GenName.Text = `Gen {gen:match("%d+") or gen}`
			tile.State.Text = if on == #groups then `All · {songs}` elseif on == 0 then "Off" else `{on} of {#groups}`
			tile.BackgroundColor3 = if on == #groups then LILAC else WHITE
			tile.Part.Enabled = on > 0 and on < #groups
			-- filled left to right as far as the share of its groups that are on
			local share = math.clamp(on / math.max(#groups, 1), 0.02, 0.98)
			tile.Part.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, LILAC),
				ColorSequenceKeypoint.new(share, LILAC),
				ColorSequenceKeypoint.new(share + 0.001, WHITE),
				ColorSequenceKeypoint.new(1, WHITE),
			})
			tile.GenName.TextColor3 = if on == 0 then C("8A8396") else INK
			tile.State.TextColor3 = if on == 0 then C("A39A8C") else INK
			local line = tile:FindFirstChildOfClass("UIStroke")
			line.Color = if on == 0 and not viewing then LINE else INK
			line.Thickness = if viewing then 4 else 3
			tile.Arrow.Visible = viewing
		end
	end
	local gen = GENS[self._gen]
	local groups = (gen and GROUPS_OF[gen]) or {}
	local on = 0
	for _, g in groups do
		if self._groups[g] then
			on += 1
		end
	end
	gensView.GroupsHeading.Text = `Gen {gen and (gen:match("%d+") or gen) or "?"} groups`
	gensView.GroupsSub.Text = `{on} of {#groups} on · tap a gen to see its groups`
	for i = 1, Build.CHIPS do
		local chip = gensView.Chips["Chip" .. i]
		local g = groups[i]
		chip.Visible = g ~= nil
		if g then
			local yes = self._groups[g] == true
			chip.Text = g
			chip.BackgroundColor3 = if yes then INK else WHITE
			chip.TextColor3 = if yes then WHITE else C("8A8396")
			chip:FindFirstChildOfClass("UIStroke").Color = if yes then INK else C("A39A8C")
		end
	end

	-- songs view: every song of the groups that are on
	local list = self:_draftSongs()
	local per = Build.SONG_ROWS
	local pages = math.max(1, math.ceil(#list / per))
	self._songPage = math.clamp(self._songPage or 1, 1, pages)
	for i = 1, per do
		local r = songsView["Row" .. i]
		local song = list[(self._songPage - 1) * per + i]
		r.Visible = song ~= nil
		if song then
			local inPool = not self._out[song.Id]
			r.SongName.Text = song.Name
			r.Artist.Text = song.Artist
			GroupArt.Paint(r.Art, song)
			paintToggle(r.Toggle, inPool)
			r.BackgroundColor3 = if inPool then WHITE else C("FBF7F0")
			r:FindFirstChildOfClass("UIStroke").Color = if inPool then INK else LINE
			r:SetAttribute("SongId", song.Id)
		end
	end
	songsView.Page.Text = `{self._songPage} / {pages}`

	local count = self:_draftCount()
	local all = self:_draftIsAll()
	local okToSave = all or count >= PartyConstants.MIN_POOL
	local pays = all or count >= PartyConstants.MIN_POOL_REWARDS
	c.Pool.Check.BackgroundColor3 = if pays then MINT elseif okToSave then YELLOW else RED
	c.Pool.Check.Text = if pays then "✓" else "!"
	c.Pool.Text.Text = if all then `Every song · {count} songs`
		elseif not okToSave then `{count} songs · pick at least {PartyConstants.MIN_POOL}`
		elseif not pays then `{count} songs · under {PartyConstants.MIN_POOL_REWARDS} pays no coins or XP`
		else `{count} songs · {PartyConstants.MIN_POOL_REWARDS}+ keeps coins + XP on`
	c.Save.BackgroundColor3 = if okToSave then MINT else GREY
	c.Save.Title.Text = if all then "SAVE · EVERY SONG" else `SAVE · {count} SONGS`
	c.Save.Sub.Text = if all then "No coin cut" else `Custom pool · ×{PartyConstants.CUSTOM_POOL_MULTIPLIER} coins`
	self:_fitSongs()
end

-- the Songs card is only as tall as what's on it (a gen with 9 groups doesn't keep room
-- for 18); its bottom edge stays put, level with the other party cards
local SONGS_BOTTOM = 705 -- canvas y of the card's bottom edge (lined up with the lobby's)
local SONGS_VIEW_Y = 140 -- where the gens / songs views start inside the card
local SONGS_LIST_H = 304 -- the songs view: 5 rows + the pager

function Party:_fitSongs()
	local c = self:_card("Songs")
	local body = SONGS_LIST_H
	if not c.SongsView.Visible then
		local chips = c.GensView.Chips
		local layout = chips:FindFirstChildOfClass("UIListLayout")
		-- AbsoluteContentSize is in screen pixels; turn it back into canvas units
		local scale = if chips.AbsoluteSize.Y > 0 then chips.Size.Y.Offset / chips.AbsoluteSize.Y else 1
		body = chips.Position.Y.Offset + math.max(math.ceil(layout.AbsoluteContentSize.Y * scale), 30)
	end
	local poolY = SONGS_VIEW_Y + body + 14
	local buttonsY = poolY + 36
	local h = buttonsY + 54 + 22
	c.Pool.Position = UDim2.fromOffset(c.Pool.Position.X.Offset, poolY)
	c.Back.Position = UDim2.fromOffset(c.Back.Position.X.Offset, buttonsY + 27)
	c.Save.Position = UDim2.fromOffset(c.Save.Position.X.Offset, buttonsY + 27)
	local saveShadow = c:FindFirstChild("SaveShadow")
	if saveShadow then
		saveShadow.Position = UDim2.fromOffset(saveShadow.Position.X.Offset, buttonsY + 4)
	end
	c.Size = UDim2.fromOffset(c.Size.X.Offset, h)
	c.Position = UDim2.fromOffset(640, SONGS_BOTTOM - h / 2)
	local shadow = self._frame:FindFirstChild("SongsShadow")
	if shadow then
		shadow.Size = c.Size
		shadow.Position = UDim2.fromOffset(646, SONGS_BOTTOM - h / 2 + 6)
	end
end

function Party:_saveSongs()
	local count = self:_draftCount()
	if self:_draftIsAll() then
		self:_send({ Action = "Pool", All = true })
	elseif count < PartyConstants.MIN_POOL then
		Sounds.Play("Wrong")
		Juice.Shake(self:_card("Songs").Save)
		return
	else
		local groups, out = {}, {}
		for g in self._groups do
			table.insert(groups, g)
		end
		for id in self._out do
			local song = Songs.GetById(id)
			if song and self._groups[song.Artist] then
				table.insert(out, id)
			end
		end
		self:_send({ Action = "Pool", Groups = groups, Out = out })
	end
	Sounds.Play("Success")
	self:_show("Settings")
end

-- [[ Prompt ]]

-- opts = { Tag, TagColour, Title, Sub, Photo = { UserId?, Text?, Colour? }, Primary = { Title, Sub, Colour, Run },
--          Secondary = { Title, Run }?, Back = page to return to }
function Party:_prompt(opts)
	local c = self:_card("Prompt")
	c.Tag.Text = opts.Tag or "PARTY STAGE"
	c.Tag.BackgroundColor3 = opts.TagColour or LILAC
	c.Title.Text = opts.Title or ""
	c.Sub.Text = opts.Sub or ""
	local photo = opts.Photo or {}
	c.Photo.BackgroundColor3 = photo.Colour or C("DCD3FF")
	c.Photo.Initials.Text = photo.Text or "?"
	c.Photo.Initials.TextSize = if photo.Big then 40 else 20
	if photo.UserId then
		thumb(photo.UserId, c.Photo.Avatar, c.Photo.Initials)
	else
		c.Photo.Avatar.Image = ""
		c.Photo.Initials.Visible = true
	end
	c.Primary.Title.Text = opts.Primary.Title
	c.Primary.Sub.Text = opts.Primary.Sub or ""
	c.Primary.BackgroundColor3 = opts.Primary.Colour or BLUE
	self._primary = opts.Primary.Run
	local second = opts.Secondary
	setPair(c, "Secondary", second ~= nil)
	if second then
		c.Secondary.Title.Text = second.Title
		c.Secondary.Title.TextColor3 = second.Colour or INK
		self._secondary = second.Run
	else
		self._secondary = nil
	end
	self._back = opts.Back
	if self.State ~= "Active" and self.State ~= "Activating" then
		self._interface:Open("Party", "Prompt")
	else
		self:_show("Prompt")
	end
	Sounds.Play("Notify")
end

-- close the prompt: back to where you were, or close the card
function Party:_closePrompt()
	self._primary, self._secondary = nil, nil
	local back = self._back
	self._back = nil
	if back and self.InParty then
		self:_show(back)
	elseif self.InParty then
		self:_show("Lobby")
	else
		self._interface:Close("Party")
	end
end

-- [[ Results ]]

function Party:ShowResults(packet)
	local party = packet.Party
	local c = self:_card("Results")
	local myPlace, mine = nil, nil
	for _, p in party.Placement do
		if p.UserId == LOCAL_PLAYER.UserId then
			myPlace, mine = p.Place, p
		end
	end
	local duel = party.Kind == "Duel"
	c.Tag.Text = if duel then "DUEL RESULTS" else "FFA RESULTS"
	c.Title.Text = if myPlace == 1 then "You win!" elseif myPlace then `{ORDINAL[myPlace]} place!` else "Match over"
	c.Sub.Text = `{party.Title} · {party.Players} players · {party.Rounds} rounds`
	for i = 1, Build.SLOTS do
		local cell = c.Places["Place" .. i]
		local p = party.Placement[i]
		cell.Visible = p ~= nil
		if p then
			local isMe = p.UserId == LOCAL_PLAYER.UserId
			local photo = cell.Photo
			photo.BackgroundColor3 = if p.Left then SAND else AV[i]
			photo.Num.Text = tostring(i)
			photo.Num.BackgroundColor3 = MEDAL[i]
			photo.Num.TextColor3 = INK
			photo.Initials.Text = initialsOf(p.Name)
			thumb(p.UserId, photo.Avatar, photo.Initials)
			photo:FindFirstChildOfClass("UIStroke").Color = if isMe then C("E0382C") elseif p.Left then LINE else INK
			cell.PlayerName.Text = if isMe then "You" else p.Name
			cell.PlayerName.TextColor3 = if isMe then C("E0382C") else INK
			cell.Points.Text = `{p.Points} pts`
			cell.Note.Text = if p.Left then "left early" elseif p.Firsts > 0 then `{p.Firsts} first{if p.Firsts == 1 then "" else "s"}` else ""
			cell.Note.TextColor3 = if p.Left then C("E0382C") else MUTED
		end
	end
	local reward = packet.Rewards and packet.Rewards[tostring(LOCAL_PLAYER.UserId)]
	local box = c.Coins
	local share = myPlace and (party.Payout[myPlace] or party.Payout[#party.Payout]) or 0
	if not party.Eligible then
		box.Line1.Text = `Custom pool under {PartyConstants.MIN_POOL_REWARDS} songs`
		box.Value1.Text = "0"
		box.Line2.Text = "Pick more songs to earn coins + XP"
		box.Value2.Text = ""
	else
		box.Line1.Text = `{ORDINAL[myPlace or 1]} place pays {math.floor(share * 100 + 0.5)}% of {party.Base}`
		box.Value1.Text = tostring(math.floor(party.Base * share + 0.5))
		-- the pot is the stake roll × the stage multiplier (shown on the pre-match reel)
		local roll = if party.Roll and party.Roll > 0 then `Rolled {party.Roll}` else "Pot"
		box.Line2.Text = if party.MultiplierText ~= "" then `{roll} · {party.MultiplierText}` else `{roll} · no multiplier`
		box.Value2.Text = `×{party.Multiplier}`
	end
	box.CoinsChip.Text = `+{reward and reward.Coins or 0} coins`
	box.XPChip.Text = `+{reward and reward.XP or 0} XP`
	c.Rule.Text = if duel then "1st 100% · 2nd 30% · leaving early pays 0" else "1st 100% · 2nd 70% · 3rd 50% · everyone else who finishes 30% · leaving early pays 0"
	if mine and myPlace == 1 then
		Sounds.Play("Win")
	else
		Sounds.Play("Coins")
	end
	if self.State ~= "Active" and self.State ~= "Activating" then
		self._interface:Open("Party", "Results")
	else
		self:_show("Results")
	end
end

-- [[ Watching ]]

function Party:_renderWatch(packet)
	local c = self:_card("Watch")
	c.Title.Text = `{packet.Title} · round {math.max(packet.Round or 1, 1)} / {packet.Rounds or 7}`
	for i = 1, Build.SLOTS do
		local chip = c.Scores["P" .. i]
		local p = packet.Players[i]
		chip.Visible = p ~= nil
		if p then
			chip.Text = `{i}. {p.Name} <b>{p.Score}</b>`
			chip.BackgroundColor3 = if p.Left then GREY elseif i == 1 then YELLOW else C("FBF7F0")
		end
	end
end

-- [[ Toast ]]

function Party:_toast(text: string)
	local t = self._frame.Toast
	t.Text = text
	t.Visible = true
	Juice.SlideIn(t, -10)
	local token = {}
	self._toastToken = token
	task.delay(2.6, function()
		if self._toastToken == token then
			t.Visible = false
		end
	end)
	-- the toast lives in the Party frame: show the frame even when the card is closed
	if not self._frame.Visible then
		self._frame.Visible = true
		for _, p in PAGES do
			self._frame[p].Visible = false
			self._frame[p .. "Shadow"].Visible = false
		end
		task.delay(2.7, function()
			if self._toastToken == token and self.State == "Inactive" then
				self._frame.Visible = false
			end
		end)
	end
end

-- [[ Packets ]]

function Party:_onPacket(packet)
	local m = packet.Message
	if m == "State" then
		local was = self.InParty
		self.Info = packet
		self.InParty = true
		if packet.Status == "InMatch" then
			return -- the round screen takes over (DuelController)
		end
		self:_lobbyCamera()
		local active = self.State == "Active" or self.State == "Activating"
		if not was and not active then
			self._interface:Open("Party", "Lobby")
		elseif active and self._page ~= "Prompt" and self._page ~= "Results" then
			self:_render()
		elseif not active and self._interface.ActiveController == nil and self._page ~= "Results" then
			self._interface:Open("Party", "Lobby")
		end
	elseif m == "Left" then
		self.InParty = false
		self.Info = nil
		if CameraController.Mode == "PartyPan" then
			CameraController.Reset()
		end
		if packet.Reason == "Removed" then
			self:_prompt({
				Tag = "LEFT THE STAGE",
				TagColour = WHITE,
				Title = "The host removed you",
				Sub = "Nothing lost: no coins, no streak. Find a duel, join another stage or practise solo.",
				Photo = { Text = "♪", Colour = LILAC, Big = true },
				Primary = { Title = "FIND A DUEL", Sub = "Quick play", Colour = MINT, Run = function()
					self._interface:Close("Party")
					QueueRemote:Fire("QuickPlay")
				end },
				Secondary = { Title = "OK", Run = function()
					self._interface:Close("Party")
				end },
			})
		elseif self.State == "Active" and self._page ~= "Prompt" then
			self._interface:Close("Party")
		end
	elseif m == "Prompt" then
		self:_onWalkUp(packet)
	elseif m == "Request" then
		local back = if self.InParty then (if self._page == "Prompt" then "Lobby" else self._page) else nil
		self:_prompt({
			Tag = "JOIN REQUEST",
			TagColour = BLUE,
			Title = `{packet.Name} wants to join`,
			Sub = `Lv {packet.Level} · they skip Friends only if you say yes`,
			Photo = { UserId = packet.UserId, Text = initialsOf(packet.Name), Colour = C("CDEBFA") },
			Primary = { Title = "LET THEM IN", Sub = "They join the setlist", Colour = MINT, Run = function()
				self:_send({ Action = "Request", UserId = packet.UserId, Accept = true })
				self:_closePrompt()
			end },
			Secondary = { Title = "Not now", Run = function()
				self:_send({ Action = "Request", UserId = packet.UserId, Accept = false })
				self:_closePrompt()
			end },
			Back = back,
		})
	elseif m == "RequestResult" then
		if packet.Result == "Sent" then
			self:_toast(`Asked {packet.Host} · waiting for an answer`)
		elseif packet.Result == "Declined" then
			self:_toast(`{packet.Title}: the host said not now`)
		else
			self:_toast(`Couldn't join {packet.Title}`)
		end
	elseif m == "Invited" then
		if self.InParty then
			return
		end
		-- the same toast as a duel invite (InviteToast), not a full card
		InviteToast.Show({
			Kind = "Party",
			From = packet.From,
			Friend = packet.Friend,
			Title = `{packet.Name} invited you`,
			Sub = `{packet.Title} · {if packet.Mode == "Duel" then "1v1 duel" else "Free-for-all"} · {packet.Count} / {packet.Spots} on the stage`,
			Expires = packet.Expires,
			Answer = function(accept)
				if accept then
					self:_send({ Action = "Answer", Stage = packet.Stage, Accept = true })
				end
			end,
		})
	elseif m == "InviteGone" then
		self:_toast("That invite isn't open any more")
	elseif m == "InviteList" then
		self._inviteList = packet.Players
		if self._page == "Invite" then
			self:_renderInvite()
		end
	elseif m == "Toast" then
		self:_toast(packet.Text)
	elseif m == "Watch" then
		self._watching = packet.Stage
		self:_renderWatch(packet)
		if self.State ~= "Active" and self.State ~= "Activating" then
			self._interface:Open("Party", "Watch")
		elseif self._page ~= "Watch" then
			self:_show("Watch")
		end
	elseif m == "WatchEnd" then
		self._watching = nil
		if self._page == "Watch" and not self.InParty then
			self._interface:Close("Party")
		end
	end
end

-- walked up to a stage you can't just step onto
function Party:_onWalkUp(packet)
	if packet.Kind == "FriendsOnly" then
		self:_prompt({
			Tag = string.upper(packet.Title),
			Title = "Friends only",
			Sub = `{packet.Host} is hosting for friends. Ask and they'll get a pop-up.`,
			Photo = { Text = initialsOf(packet.Host or "?"), Colour = C("DCD3FF") },
			Primary = { Title = "ASK TO JOIN", Sub = `{packet.Count} / {packet.Spots} on the stage`, Colour = BLUE, Run = function()
				self:_send({ Action = "Ask", Stage = packet.Stage })
				self:_closePrompt()
			end },
			Secondary = { Title = "Not now", Run = function()
				self:_closePrompt()
			end },
		})
	elseif packet.Kind == "Full" then
		self:_prompt({
			Tag = string.upper(packet.Title),
			Title = if packet.Status == "InMatch" then "Match on" else `Stage full · {packet.Count} / {packet.Spots}`,
			Sub = `Round {math.max(packet.Round or 1, 1)} / 7. You'll see the scores live, but can't answer.`,
			Photo = { Text = "?", Colour = SAND, Big = true },
			Primary = { Title = "SPECTATE", Sub = "Watch the scores", Colour = LILAC, Run = function()
				self:_send({ Action = "Spectate", Stage = packet.Stage })
				self._primary, self._secondary = nil, nil
			end },
			Secondary = { Title = "Not now", Run = function()
				self:_closePrompt()
			end },
		})
	else
		self:_prompt({
			Tag = string.upper(packet.Title),
			Title = if packet.Status == "Countdown" then "Starting right now" elseif packet.Status == "InMatch" then "Match on" else `Stage full · {packet.Count} / {packet.Spots}`,
			Sub = "Try another Party Stage, or come back after this match.",
			Photo = { Text = "♪", Colour = SAND, Big = true },
			Primary = { Title = "OK", Colour = WHITE, Run = function()
				self:_closePrompt()
			end },
		})
	end
end

-- --------------------------------- Lifecycle ------------------------------ --

function Party:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Party")
	local frame = self._frame
	frame.Visible = false
	local songRows = frame.Songs.SongsView
	for i = 1, Build.SONG_ROWS do
		songRows["Row" .. i]:SetAttribute("NoButtonScale", true)
	end
	ButtonScale.ApplyToDescendants(frame)
	local j = self._janitor
	-- each card's (and shadow's) home spot, and where it sits aside
	self._home = {}
	for page in ASIDE do
		for _, f in { frame[page], frame[page .. "Shadow"] } do
			local home = f.Position
			local dx = (ASIDE_RIGHT - frame[page].Size.X.Offset / 2) - frame[page].Position.X.Offset
			self._home[f] = { Home = home, Aside = home + UDim2.fromOffset(dx, 0) }
		end
	end

	-- the spot prompts are for people walking up: hide them on the stage you're on
	-- (the server never sets Enabled, so this local change sticks)
	local function hidePrompt(prompt: Instance)
		if prompt:IsA("ProximityPrompt") and prompt.Name == "PartyPrompt" then
			local stage = prompt:FindFirstAncestorWhichIsA("Model")
			prompt.Enabled = not (stage and stage.Name == LOCAL_PLAYER:GetAttribute("PartyStage"))
		end
	end
	local map = workspace:FindFirstChild("Map")
	local partyStages = map and map:FindFirstChild("PartyStages")
	if partyStages then
		j:Add(partyStages.DescendantAdded:Connect(hidePrompt))
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal("PartyStage"):Connect(function()
			for _, d in partyStages:GetDescendants() do
				hidePrompt(d)
			end
		end))
	end

	local function on(button: GuiButton, fn: () -> ())
		j:Add(button.Activated:Connect(function()
			Sounds.Play("Click")
			fn()
		end))
	end

	-- lobby
	local lobby = frame.Lobby
	on(lobby.Invite, function()
		self._inviteList = nil
		self._inviteFilter = self._inviteFilter or "Friends"
		self:_send({ Action = "InviteList" })
		self:_show("Invite")
	end)
	on(lobby.Settings, function()
		self:_show("Settings")
	end)
	on(lobby.Start, function()
		self:_send({ Action = "Start" })
	end)
	on(lobby.Ready, function()
		local me = self:_me()
		self:_send({ Action = "Ready", On = not (me and me.Ready) })
	end)
	on(lobby.Leave, function()
		self:_send({ Action = "Leave" })
	end)
	for i = 1, Build.SLOTS do
		on(lobby.Setlist["Slot" .. i].Hit, function()
			if not self:_isHost() or not self.Info then
				return
			end
			local m = self.Info.Members[i]
			if not m then
				self._inviteList = nil
				self._inviteFilter = self._inviteFilter or "Friends"
				self:_send({ Action = "InviteList" })
				self:_show("Invite")
			elseif m.UserId ~= LOCAL_PLAYER.UserId then
				self._playerId = m.UserId
				self._block = false
				self:_show("Player")
			end
		end)
	end

	-- settings
	local settings = frame.Settings
	on(settings.Mode.Option1, function()
		self:_send({ Action = "Settings", Mode = "Duel" })
	end)
	on(settings.Mode.Option2, function()
		self:_send({ Action = "Settings", Mode = "FFA" })
	end)
	on(settings.SongsRow.Edit, function()
		self:_openSongs()
	end)
	on(settings.OwnedRow.Toggle, function()
		self:_send({ Action = "Settings", Boost = not (self.Info and self.Info.Settings.Boost) })
	end)
	on(settings.SpotsRow.Minus, function()
		local s = self.Info and self.Info.Settings
		if s and s.Mode == "FFA" then
			self:_send({ Action = "Settings", Spots = s.FFASpots - 1 })
		end
	end)
	on(settings.SpotsRow.Plus, function()
		local s = self.Info and self.Info.Settings
		if s and s.Mode == "FFA" then
			self:_send({ Action = "Settings", Spots = s.FFASpots + 1 })
		end
	end)
	on(settings.Every.FriendsRow.Toggle, function()
		self:_send({ Action = "Settings", FriendsOnly = not (self.Info and self.Info.Settings.FriendsOnly) })
	end)
	on(settings.Every.SpectatorsRow.Toggle, function()
		self:_send({ Action = "Settings", Spectators = not (self.Info and self.Info.Settings.Spectators) })
	end)
	on(settings.Done, function()
		self:_show("Lobby")
	end)

	-- invite
	local invite = frame.Invite
	on(invite.Filter.Option1, function()
		self._inviteFilter = "Friends"
		self._invitePage = 1
		self:_renderInvite()
	end)
	on(invite.Filter.Option2, function()
		self._inviteFilter = "Everyone"
		self._invitePage = 1
		self:_renderInvite()
	end)
	on(invite.Prev, function()
		self._invitePage = (self._invitePage or 1) - 1
		self:_renderInvite()
	end)
	on(invite.Next, function()
		self._invitePage = (self._invitePage or 1) + 1
		self:_renderInvite()
	end)
	for i = 1, Build.INVITE_ROWS do
		local b = invite["Row" .. i].Send
		on(b, function()
			if b:GetAttribute("Status") == "Open" then
				self:_send({ Action = "Invite", Target = b:GetAttribute("UserId") })
			end
		end)
	end
	on(invite.Back, function()
		self:_show("Lobby")
	end)

	-- player
	local player = frame.Player
	on(player.MakeHost, function()
		self:_send({ Action = "MakeHost", UserId = self._playerId })
		self:_show("Lobby")
	end)
	on(player.Kick, function()
		if self.Info and self.Info.Status == "Waiting" then
			self:_send({ Action = "Remove", UserId = self._playerId, Block = self._block == true })
			self:_show("Lobby")
		else
			Sounds.Play("Wrong")
		end
	end)
	on(player.BlockRow.Toggle, function()
		self._block = not self._block
		self:_renderPlayer()
	end)
	on(player.Back, function()
		self:_show("Lobby")
	end)

	-- songs
	local songs = frame.Songs
	-- chips wrap onto more rows (or fewer) once they're laid out: refit the card then
	j:Add(songs.GensView.Chips:FindFirstChildOfClass("UIListLayout"):GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if songs.Visible then
			self:_fitSongs()
		end
	end))
	on(songs.View.Option1, function()
		self._view = "Gens"
		self:_renderSongs()
	end)
	on(songs.View.Option2, function()
		self._view = "Songs"
		self._songPage = 1
		self:_renderSongs()
	end)
	for i = 1, Build.GENS do
		on(songs.GensView["Gen" .. i], function()
			local gen = GENS[i]
			if not gen then
				return
			end
			if self._gen == i then
				-- tapping the gen you're looking at switches all of it
				local all = true
				for _, g in GROUPS_OF[gen] do
					all = all and self._groups[g] == true
				end
				for _, g in GROUPS_OF[gen] do
					self._groups[g] = if all then nil else true
				end
			end
			self._gen = i
			self:_renderSongs()
		end)
	end
	local function setGen(value: boolean)
		local gen = GENS[self._gen]
		for _, g in (gen and GROUPS_OF[gen]) or {} do
			self._groups[g] = if value then true else nil
		end
		self:_renderSongs()
	end
	on(songs.GensView.AllOn, function()
		setGen(true)
	end)
	on(songs.GensView.AllOff, function()
		setGen(false)
	end)
	for i = 1, Build.CHIPS do
		on(songs.GensView.Chips["Chip" .. i], function()
			local gen = GENS[self._gen]
			local g = gen and GROUPS_OF[gen][i]
			if g then
				self._groups[g] = if self._groups[g] then nil else true
				self:_renderSongs()
			end
		end)
	end
	for i = 1, Build.SONG_ROWS do
		local r = songs.SongsView["Row" .. i]
		local function toggleSong()
			local id = r:GetAttribute("SongId")
			if id then
				self._out[id] = if self._out[id] then nil else true
				self:_renderSongs()
			end
		end
		r.Toggle.Active = true
		on(r, toggleSong)
		on(r.Toggle, toggleSong)
	end
	on(songs.SongsView.Prev, function()
		self._songPage -= 1
		self:_renderSongs()
	end)
	on(songs.SongsView.Next, function()
		self._songPage += 1
		self:_renderSongs()
	end)
	on(songs.Back, function()
		self:_show("Settings")
	end)
	on(songs.Save, function()
		self:_saveSongs()
	end)

	-- prompt
	local prompt = frame.Prompt
	on(prompt.Primary, function()
		local run = self._primary
		if run then
			run()
		end
	end)
	on(prompt.Secondary, function()
		local run = self._secondary
		if run then
			run()
		else
			self:_closePrompt()
		end
	end)

	-- results
	local results = frame.Results
	on(results.Back, function()
		if self.InParty then
			self:_show("Lobby")
		else
			self._interface:Close("Party")
		end
	end)
	on(results.Leave, function()
		self:_send({ Action = "Leave" })
		self._interface:Close("Party")
	end)

	-- watch
	on(frame.Watch.Stop, function()
		self:_send({ Action = "StopWatching" })
		self._interface:Close("Party")
	end)

	j:Add(PartyRemote:Connect(function(packet)
		if type(packet) == "table" then
			self:_onPacket(packet)
		end
	end), "Disconnect")
end

function Party:Activate(page: string?)
	if self.State == "Active" or self.State == "Activating" then
		if page then
			self:_show(page)
		end
		return Promise.resolve()
	end
	self.State = "Activating"
	self._frame.Visible = true
	self._frame.Toast.Visible = false
	for _, p in PAGES do
		self._frame[p].Visible = false
		self._frame[p .. "Shadow"].Visible = false
	end
	self._page = ""
	self:_show(page or (if self.InParty then "Lobby" else "Prompt"))
	self.State = "Active"
	return Promise.resolve()
end

function Party:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Inactive"
	self._frame.Visible = false
	self:_countdownLoop(false)
	-- still on the stage (Escape, or a menu opened over it): the card comes back once nothing
	-- else is open, unless a match took over
	task.delay(0.5, function()
		if self.InParty and self.State == "Inactive" and self.Info and self.Info.Status ~= "InMatch" and self._interface.ActiveController == nil then
			self._interface:Open("Party", "Lobby")
		end
	end)
	return Promise.resolve()
end

function Party:Destroy()
	self:_countdownLoop(false)
	self._janitor:Destroy()
end

return Party
