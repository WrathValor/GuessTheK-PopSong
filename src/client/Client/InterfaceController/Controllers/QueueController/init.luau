-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
-- --------------------------------- Imports -------------------------------- --

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local Themes = require(ReplicatedStorage.Modules.Library.Themes)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local SoloPicker = require(script.SoloPicker)
local InvitePicker = require(script.InvitePicker)

--------------------------------- Variables --------------------------------- --

local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

-- the panel shrinks to fit while only the Cancel button sits under the cards
local PANEL_HEIGHT = 383
local PANEL_HEIGHT_COUNTDOWN = 350
-- solo practice starting: Invite / Play Solo hide, Leave moves up into their row (y 280,
-- from 343) and the panel loses that row's height
local PANEL_HEIGHT_SOLO = 320
local LEAVE_Y, LEAVE_Y_SOLO = 343, 280
local PANEL_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- walk-on (rival found): the queue card steps aside for a slim countdown pill
local CHIP_LOCKED = Color3.fromHex("EDE4D4")
-- waiting for a rival: the card steps over to the right, the camera shows you on your stage
local ASIDE_X, ASIDE_Y = 1014, 360
local ASIDE_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CHIP_ON = Color3.fromHex("FFE07A")
local CHIP_OFF = Color3.fromHex("FFFFFF")
-- alone on the stage this long: "No rival yet", and Play Solo turns into a pulsing QUICK SOLO
-- (one tap, last theme) with the "Let rivals join while I practise" chip (Settings.SoloOpen)
-- and "Pick a theme instead" under it; the panel grows for those two
local NUDGE_AFTER = 15
local PANEL_HEIGHT_NUDGE, LEAVE_Y_NUDGE = PANEL_HEIGHT + 76, LEAVE_Y + 76
-- the chip stays white; only its switch shows on (mint, knob right) / off, like Settings
local CHIP_TRACK_ON, CHIP_TRACK_OFF = Color3.fromHex("A7E9B8"), Color3.fromHex("E6DCCB")
local TOGGLE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SOLO_COLOUR, QUICK_COLOUR = Color3.fromHex("B9A6FF"), Color3.fromHex("FFE07A")
local BEAT = { { 1.035, 0.2 }, { 0.99, 0.2 }, { 1.02, 0.2 }, { 1, 0.6 } } -- scale, seconds
local RING_TIME = 1.2

-- --------------------------------- Helpers -------------------------------- --
-- Starts downloading the pre-duel cards' images (both headshots at the size PreDuel asks for
-- + both banners' art) while the "Starting soon" countdown runs, so the stake roll doesn't
-- open on empty squares the first time a player sees it.
local function preloadCards(players: { Player })
	local assets = {}
	for _, p in players do
		table.insert(assets, `rbxthumb://type=AvatarHeadShot&id={p.UserId}&w=150&h=150`)
		local _, _, bannerId = SeasonArt.Of(p)
		local spec = SeasonConstants.Banner(bannerId)
		if spec and spec.Art and spec.Art ~= "" then
			table.insert(assets, spec.Art)
		end
	end
	task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, assets)
end

-- --------------------------------- Tables --------------------------------- --
-- Reusable subcontroller class - NOT a concrete screen. Instantiate one of these per real
-- screen later via QueueController.new({ Name, ScreenGui, Frame }), the same dependency-
-- injection shape Interface.Start's commented registration example already demonstrates.
local QueueController = {}
QueueController.__index = QueueController

-- --------------------------------- Methods -------------------------------- --

function QueueController.new(config: UITypes.ControllerConfig)
	local self = setmetatable({}, QueueController)

	self.Name = "Queue"
	self.ScreenGui = "Interface"
	self.FrameName = "Queue"
	-- Exclusive controllers are mutually exclusive with any other Exclusive controller
	-- (matches the Frames ScreenGui's one-full-screen-panel-at-a-time convention). Non-
	-- exclusive controllers (Feedback/Extra overlays) can be open alongside anything else.
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState

	self._interface = nil :: any
	self._frame = nil :: typeof(game.StarterGui.Interface.Frames.Queue)?
	self._janitor = Janitor.new()

	return (self :: any) :: UITypes.Controller
end

function QueueController.Initialize(self: typeof(QueueController.new({} :: UITypes.ControllerConfig)), interface: any)
	self._interface = interface
	self._frame =
		interface:ResolveFrame(self.ScreenGui, self.FrameName) :: typeof(game.StarterGui.Interface.Frames.Queue)?
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)

	local panelFrame = self._frame:FindFirstChild("Panel")
	local walkOn = self._frame:FindFirstChild("WalkOn")
	if walkOn then
		walkOn.Visible = false
	end
	-- where the card + shadow sit normally (waiting moves them aside so the camera can show you)
	local panelShadow = self._frame:FindFirstChild("PanelShadow")
	self._panelHome = panelFrame.Position
	self._shadowHome = panelShadow and panelShadow.Position

	-- Layout comes from the Studio UI (Photocard design); don't resize it here.
	local participantsFrame: Frame = panelFrame:FindFirstChild("Participants")
	local youAvatar = participantsFrame and participantsFrame:FindFirstChild("You")
	local youNameLabel = participantsFrame and participantsFrame:FindFirstChild("YouName")

	local opponentAvatar = participantsFrame and participantsFrame:FindFirstChild("Opponent")
	local opponentNameLabel = opponentAvatar and opponentAvatar:FindFirstChild("OpponentName")

	local invitePlayersBtn = panelFrame and panelFrame:FindFirstChild("InvitePlayers")
	if invitePlayersBtn then
		invitePlayersBtn.Visible = true
	end
	local playSoloBtn = panelFrame and panelFrame:FindFirstChild("PlaySolo")
	if playSoloBtn then
		playSoloBtn.Visible = true
	end
	local leaveBtn = panelFrame and panelFrame:FindFirstChild("Leave")
	if leaveBtn then
		leaveBtn.Visible = true
	end

	youNameLabel.Text = LOCAL_PLAYER.DisplayName
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LOCAL_PLAYER.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		if ok then
			youAvatar.Thumbnail.Image = img
		end
	end)
	-- Play Solo flips the card over to the theme picker (./SoloPicker), which starts the game
	self._solo = SoloPicker.new(self._frame, self._janitor)

	-- Invite flips it to the player picker (./InvitePicker); while an invite is out it cancels it
	self._invite = InvitePicker.new(self._frame, self._janitor, self._solo)

	self._janitor:Add(playSoloBtn.Activated:Connect(function()
		if self._invite.IsOpen then
			return
		end
		if self._nudged then
			-- QUICK SOLO: straight in with the theme the picker would play (last pick / All songs)
			Sounds.Play("Click")
			self:_stopWait()
			QueueRemote:Fire({ Request = "Solo", Theme = self._solo:_playable(), Mix = self._solo._mix, From = "Quick" })
		else
			self._solo:Open()
		end
	end))
	local pickTheme = panelFrame:FindFirstChild("PickTheme")
	if pickTheme then
		self._janitor:Add(pickTheme.Activated:Connect(function()
			if not self._invite.IsOpen then
				Sounds.Play("Click")
				self._solo:Open()
			end
		end))
	end
	-- "Let rivals join while I practise": flips Settings.SoloOpen (same as the Settings row);
	-- painted from the saved value, so the server's answer is what sticks
	local rivalsChip = panelFrame:FindFirstChild("RivalsChip")
	if rivalsChip then
		self._janitor:Add(rivalsChip.Activated:Connect(function()
			local nextValue = not self:_soloOpen()
			self:_paintRivalsChip(nextValue)
			SettingsRemote:Fire({ Action = "SetSoloOpen", Value = nextValue })
			Sounds.Play("Click")
		end))
		local ok, setting = pcall(function()
			return PlayerData.Settings.SoloOpen
		end)
		if ok and setting then
			self._janitor:Add(setting.Observe(function()
				self:_paintRivalsChip(self:_soloOpen())
			end))
		end
	end

	-- the beat pauses while the mouse is over the button (ButtonScale owns its UIScale then)
	self._janitor:Add(playSoloBtn.MouseEnter:Connect(function()
		self._hoverSolo = true
	end))
	self._janitor:Add(playSoloBtn.MouseLeave:Connect(function()
		self._hoverSolo = false
	end))
	self._janitor:Add(function()
		self:_stopWait()
	end, true)
	if invitePlayersBtn then
		self._janitor:Add(invitePlayersBtn.Activated:Connect(function()
			self._invite:Pressed()
		end))
	end
	self._janitor:Add(leaveBtn.Activated:Connect(function()
		QueueRemote:Fire("Leave")
		--self._interface:Close(self.Name)
	end))

	-- Cancel (intermission only): leaves the stage; the server calls the match off with no
	-- forfeit and sends the rival back to waiting
	local pill = walkOn and walkOn:FindFirstChild("Pill", true)
	for _, cancelBtn in { panelFrame:FindFirstChild("Cancel") or false, pill and pill:FindFirstChild("Cancel") or false } do
		if not cancelBtn then
			continue
		end
		self._janitor:Add(cancelBtn.Activated:Connect(function()
			if self._countdown and not self._cancelLocked then
				self:_setCancel(false)
				QueueRemote:Fire("Leave")
			end
		end))
	end
end

-- Shows or hides the intermission Cancel button (+ shadow) and fits the panel around it.
function QueueController:_setCancel(visible: boolean)
	local panel = self._frame:FindFirstChild("Panel")
	if not panel then
		return
	end
	for _, n in { "Cancel", "CancelShadow" } do
		local inst = panel:FindFirstChild(n)
		if inst then
			inst.Visible = visible
		end
	end
	-- pin the shadow to the button in pixels so the panel resize can't drag a scaled one off
	local cancel, cancelShadow = panel:FindFirstChild("Cancel"), panel:FindFirstChild("CancelShadow")
	if cancel and cancelShadow then
		cancelShadow.AnchorPoint = cancel.AnchorPoint
		cancelShadow.Size = cancel.Size
		cancelShadow.Position = cancel.Position + UDim2.fromOffset(4, 4)
	end
	-- the panel and its shadow resize together
	local height = if visible then PANEL_HEIGHT_COUNTDOWN else PANEL_HEIGHT
	for _, frame in { panel, self._frame:FindFirstChild("PanelShadow") } do
		TweenService:Create(frame, PANEL_TWEEN, { Size = UDim2.fromOffset(frame.Size.X.Offset, height) }):Play()
	end
end

-- --------------------------------- Walk-on -------------------------------- --
-- While the intermission counts down, the camera (CameraController.WalkOn) shows both stages
-- then each player on theirs; the chips at the bottom say who's who: name, title, level, streak.

-- a chip's badge row: [TITLE] [Lv N] [N win streak] from the player's attributes (DataService)
local function fillBadges(badges: Frame, player: Player?)
	badges.Visible = player ~= nil
	if not player then
		return
	end
	local title = player:GetAttribute("Title")
	badges.Title.Visible = type(title) == "string" and title ~= ""
	if badges.Title.Visible then
		TitleChip.Paint(badges.Title, title, player:GetAttribute("TitleTier") or "Normal")
	end
	local level = player:GetAttribute("Level")
	badges.Level.Visible = type(level) == "number"
	badges.Level.Text = `Lv {level or 1}`
	local streak = player:GetAttribute("Streak") or 0
	badges.Streak.Visible = streak > 0
	badges.Streak.Text = `{streak} win streak`
end

-- ------------------------------ Waiting aside ------------------------------- --
-- While you wait for a rival (CameraController.Showcase), the card sits on the right so the
-- camera can show you on your stage.

function QueueController:ShowAside()
	local panel, shadow = self._frame:FindFirstChild("Panel"), self._frame:FindFirstChild("PanelShadow")
	if not (panel and shadow and self._panelHome) then
		return
	end
	self._aside = true
	local dx, dy = ASIDE_X - self._panelHome.X.Offset, ASIDE_Y - self._panelHome.Y.Offset
	TweenService:Create(panel, ASIDE_TWEEN, { Position = self._panelHome + UDim2.fromOffset(dx, dy) }):Play()
	TweenService:Create(shadow, ASIDE_TWEEN, { Position = self._shadowHome + UDim2.fromOffset(dx, dy) }):Play()
end

function QueueController:_hideAside()
	if not self._aside then
		return
	end
	self._aside = false
	local panel, shadow = self._frame:FindFirstChild("Panel"), self._frame:FindFirstChild("PanelShadow")
	if panel and shadow then
		panel.Position = self._panelHome
		shadow.Position = self._shadowHome
	end
end

-- the walk-on hides the queue card (its slim top pill has the countdown + Cancel instead)
-- Solo practice starting: the button row goes, Leave takes its place and the panel shrinks.
-- Off puts Leave and the panel back (Reset).
function QueueController:_soloLayout(on: boolean)
	local panel = self._frame:FindFirstChild("Panel")
	if not panel then
		return
	end
	for _, n in { "InvitePlayers", "InvitePlayersShadow", "PlaySolo", "PlaySoloShadow" } do
		local inst = panel:FindFirstChild(n)
		if inst then
			inst.Visible = not on
		end
	end
	local leave = panel:FindFirstChild("Leave")
	if leave then
		leave.Position = UDim2.new(leave.Position.X, UDim.new(0, if on then LEAVE_Y_SOLO else LEAVE_Y))
	end
	local height = if on then PANEL_HEIGHT_SOLO else PANEL_HEIGHT
	for _, frame in { panel, self._frame:FindFirstChild("PanelShadow") } do
		if frame and frame.Size.Y.Offset ~= height then
			TweenService:Create(frame, PANEL_TWEEN, { Size = UDim2.fromOffset(frame.Size.X.Offset, height) }):Play()
		end
	end
	self._soloLayoutOn = on
end

function QueueController:_compact(on: boolean)
	for _, n in { "Panel", "PanelShadow" } do
		local frame = self._frame:FindFirstChild(n)
		if frame then
			frame.Visible = not on
		end
	end
end

-- Cancel in its last second: greyed "Starting…" and dead, so it doesn't just vanish
function QueueController:_lockCancel(locked: boolean)
	self._cancelLocked = locked
	local panel = self._frame:FindFirstChild("Panel")
	local pill = self._frame:FindFirstChild("Pill", true)
	for _, b in { panel and panel:FindFirstChild("Cancel") or false, pill and pill:FindFirstChild("Cancel") or false } do
		if not b then
			continue
		end
		local home = b:GetAttribute("HomeColour")
		if not home then
			b:SetAttribute("HomeColour", b.BackgroundColor3)
			home = b.BackgroundColor3
		end
		b.BackgroundColor3 = if locked then CHIP_LOCKED else home
		b.Active = not locked
		local label = b:FindFirstChild("Label") or b:FindFirstChildWhichIsA("TextLabel")
		if label then
			if not label:GetAttribute("HomeText") then
				label:SetAttribute("HomeText", label.Text)
			end
			label.Text = if locked then "Starting…" else label:GetAttribute("HomeText")
		elseif b:IsA("TextButton") and b.Text ~= "" then
			if not b:GetAttribute("HomeText") then
				b:SetAttribute("HomeText", b.Text)
			end
			b.Text = if locked then "Starting…" else b:GetAttribute("HomeText")
		end
	end
end

-- spots = { A = Player?, B = Player? }; aLeft = spot A is on the left of the screen
function QueueController:ShowWalkOn(spots, aLeft: boolean)
	local w = self._frame:FindFirstChild("WalkOn")
	if not w then
		return
	end
	self._walkOnSlots = { ChipA = if aLeft then "A" else "B", ChipB = if aLeft then "B" else "A" }
	for chipName, slot in self._walkOnSlots do
		local chip = w[chipName]
		local player = spots[slot]
		chip.PlayerName.Text = if player then player.DisplayName else "…"
		fillBadges(chip.Badges, player)
		chip.BackgroundColor3 = CHIP_OFF
	end
	w.Visible = true
	self:_compact(true)
	Juice.Stagger({ w.Top.Pill, w.Top.PillShadow, w.ChipA, w.ChipAShadow, w.VS, w.VSShadow, w.ChipB, w.ChipBShadow }, 0.04, 0.5)
end

-- the camera moved to a new shot: light up that player's chip ("Wide" lights none)
function QueueController:HighlightWalkOn(shot: string)
	local w = self._frame:FindFirstChild("WalkOn")
	if not (w and w.Visible and self._walkOnSlots) then
		return
	end
	for chipName, slot in self._walkOnSlots do
		local on = slot == shot
		w[chipName].BackgroundColor3 = if on then CHIP_ON else CHIP_OFF
		if on then
			Juice.Pop(w[chipName], 0.1)
			Sounds.Play("SpinTick", { Pitch = if slot == "A" then 1 else 1.12 })
		end
	end
end

function QueueController:_hideWalkOn()
	local w = self._frame and self._frame:FindFirstChild("WalkOn")
	if w then
		w.Visible = false
	end
	self._walkOnSlots = nil
	self:_compact(false)
end

function QueueController:_stopCountdown()
	if self._countdown then
		pcall(task.cancel, self._countdown)
		self._countdown = nil
	end
	self:_setCancel(false)
end

-- Shows or hides the Invite / Play Solo / Leave buttons together with their shadows.
function QueueController:_setButtons(visible: boolean)
	local panel = self._frame:FindFirstChild("Panel")
	for _, name in { "InvitePlayers", "PlaySolo", "Leave" } do
		for _, n in { name, name .. "Shadow" } do
			local inst = panel and panel:FindFirstChild(n)
			if inst then
				inst.Visible = visible
			end
		end
	end
end

-- --------------------------- No rival yet (nudge) -------------------------- --
-- Counts how long you've been alone on the stage; at NUDGE_AFTER it switches the card to
-- "No rival yet" + timer and turns Play Solo into QUICK SOLO. Anything that ends the wait
-- (a rival, solo starting, the countdown, leaving) calls _stopWait.
function QueueController:_startWait()
	self:_stopWait()
	local started = os.clock()
	self._waitThread = task.spawn(function()
		while true do
			task.wait(1)
			local seconds = math.floor(os.clock() - started)
			if seconds >= NUDGE_AFTER and not self._nudged then
				self:_nudge(true)
			end
			if self._nudged then
				local timer = self._frame.Panel:FindFirstChild("WaitRow")
				local label = timer and timer:FindFirstChild("Time", true)
				if label then
					label.Text = string.format("%d:%02d", seconds // 60, seconds % 60)
				end
			end
		end
	end)
end

function QueueController:_stopWait()
	if self._waitThread then
		pcall(task.cancel, self._waitThread)
		self._waitThread = nil
	end
	if self._nudged then
		self:_nudge(false)
	end
end

function QueueController:_nudge(on: boolean)
	local panel = self._frame and self._frame:FindFirstChild("Panel")
	if not panel then
		return
	end
	self._nudged = on
	local playSolo = panel:FindFirstChild("PlaySolo")
	local row, pick = panel:FindFirstChild("WaitRow"), panel:FindFirstChild("PickTheme")
	if row then
		row.Visible = on
		local label = row:FindFirstChild("Time", true)
		if label then
			label.Text = string.format("0:%02d", NUDGE_AFTER)
		end
	end
	panel.Subtitle.Visible = not on
	if pick then
		pick.Visible = on
	end
	for _, n in { "RivalsChip", "RivalsChipShadow" } do
		local inst = panel:FindFirstChild(n)
		if inst then
			inst.Visible = on
		end
	end
	if on then
		panel.Title.Text = "No rival yet"
	elseif panel.Title.Text == "No rival yet" then
		panel.Title.Text = "Waiting for a rival…"
	end
	if playSolo then
		playSolo.BackgroundColor3 = if on then QUICK_COLOUR else SOLO_COLOUR
		for _, n in { "QuickTitle", "Tap" } do
			local inst = playSolo:FindFirstChild(n)
			if inst then
				inst.Visible = on
			end
		end
		playSolo.Title.Visible = not on
		if on then
			self:_paintRivalsChip(self:_soloOpen())
		elseif self._solo then
			self._solo:RenderFront()
		end
	end
	-- room for "Pick a theme instead": Leave moves down and the card grows (not over solo layout)
	if not self._soloLayoutOn then
		local leave = panel:FindFirstChild("Leave")
		if leave then
			leave.Position = UDim2.new(leave.Position.X, UDim.new(0, if on then LEAVE_Y_NUDGE else LEAVE_Y))
		end
		local height = if on then PANEL_HEIGHT_NUDGE else PANEL_HEIGHT
		for _, frame in { panel, self._frame:FindFirstChild("PanelShadow") } do
			if frame then
				TweenService:Create(frame, PANEL_TWEEN, { Size = UDim2.fromOffset(frame.Size.X.Offset, height) }):Play()
			end
		end
	end
	self:_pulse(on)
	if on then
		Sounds.Play("Notify")
	end
end

-- Settings.SoloOpen ("Rivals can join my practice"), on by default
function QueueController:_soloOpen(): boolean
	local ok, on = pcall(function()
		return PlayerData.Settings.SoloOpen.Get()
	end)
	return not ok or on ~= false
end

-- The chip under QUICK SOLO, and QUICK SOLO's line: on = your stage stays open while you play
function QueueController:_paintRivalsChip(on: boolean)
	local panel = self._frame and self._frame:FindFirstChild("Panel")
	local chip = panel and panel:FindFirstChild("RivalsChip")
	if chip then
		chip.Track.BackgroundColor3 = if on then CHIP_TRACK_ON else CHIP_TRACK_OFF
		TweenService:Create(chip.Track.Knob, TOGGLE_TWEEN, {
			Position = if on then UDim2.new(1, -19, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end
	local playSolo = panel and panel:FindFirstChild("PlaySolo")
	if playSolo and self._nudged then
		local theme = self._solo and self._solo:_playable()
		local info = theme and Themes.Get(theme)
		playSolo.Sub.Text = if on then "Starts now · stage stays open" else `Starts now · {if info then info.Name else "All songs"}`
	end
end

-- -------------------------- Open practice (rival) -------------------------- --
-- You stepped onto a stage where someone's practising with their stage open (DuelService
-- join): the card shows them in the rival spot and a bar fills while they finish their round
-- (QueueRemote "RivalFinishing", then "RivalReady" once their "A rival stepped up!" card
-- counts down). Leave stays; the pre-duel screen takes over when the duel starts.

function QueueController:_finishing(on: boolean)
	local panel = self._frame and self._frame:FindFirstChild("Panel")
	local f = panel and panel:FindFirstChild("Finishing")
	if f then
		f.Visible = on
	end
	if self._finishTween then
		self._finishTween:Cancel()
		self._finishTween = nil
	end
	self._isFinishing = on
end

function QueueController:_fillTo(scale: number, seconds: number)
	local f = self._frame.Panel:FindFirstChild("Finishing")
	if not f then
		return
	end
	if self._finishTween then
		self._finishTween:Cancel()
	end
	self._finishTween = TweenService:Create(f.Bar.Fill, TweenInfo.new(math.max(seconds, 0.1), Enum.EasingStyle.Linear), { Size = UDim2.fromScale(scale, 1) })
	self._finishTween:Play()
end

function QueueController:RivalFinishing(opponent: Player?, seconds: number?)
	local panel = self._frame:FindFirstChild("Panel")
	if not (panel and opponent) then
		return
	end
	self:UpdateOpponent(opponent)
	self._invite:Reset()
	self._solo:Close(true)
	self:_setButtons(false)
	for _, n in { "Leave", "LeaveShadow" } do
		local inst = panel:FindFirstChild(n)
		if inst then
			inst.Visible = true
		end
	end
	panel.Title.Text = "Rival found!"
	panel.Subtitle.Text = `{opponent.DisplayName} is finishing a practice round…`
	self:_finishing(true)
	local f = panel:FindFirstChild("Finishing")
	if f then
		local s = math.max(1, math.floor(tonumber(seconds) or DuelConstants.SOLO_HANDOVER))
		f.Label.Text = "Duel starts after their round"
		f.Time.Text = `~{s} s`
		f.Bar.Fill.Size = UDim2.fromScale(0.04, 1)
		-- most of the bar fills over their round; the last bit is the hand-over countdown
		self:_fillTo(0.8, s)
	end
end

function QueueController:RivalReady(count: number?)
	local panel = self._frame:FindFirstChild("Panel")
	local f = panel and panel:FindFirstChild("Finishing")
	if not f then
		return
	end
	if not self._isFinishing then
		self:_finishing(true)
	end
	local s = math.max(1, math.floor(tonumber(count) or DuelConstants.HANDOVER_COUNT))
	panel.Subtitle.Text = "Their round's done. Get ready!"
	f.Label.Text = "Duel starting…"
	f.Time.Text = `{s} s`
	self:_fillTo(1, s)
	Sounds.Play("RivalFound")
end

-- the heartbeat on QUICK SOLO + two yellow rings rippling out of it, half a beat apart
function QueueController:_pulse(on: boolean)
	if self._pulseThread then
		pcall(task.cancel, self._pulseThread)
		self._pulseThread = nil
	end
	local panel = self._frame.Panel
	local playSolo = panel:FindFirstChild("PlaySolo")
	local scale = playSolo and playSolo:FindFirstChildOfClass("UIScale")
	local rings = { panel:FindFirstChild("QuickRing1"), panel:FindFirstChild("QuickRing2") }
	for _, ring in rings do
		if ring then
			ring.Visible = on
			ring.Size = UDim2.fromOffset(playSolo.Size.X.Offset + 8, playSolo.Size.Y.Offset + 8)
			ring.UIStroke.Transparency = if on then 0 else 1
		end
	end
	if not on then
		if scale and not self._hoverSolo then
			scale.Scale = 1
		end
		return
	end
	local w, h = playSolo.Size.X.Offset, playSolo.Size.Y.Offset
	local ringInfo = TweenInfo.new(RING_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function ripple(ring)
		if not ring then
			return
		end
		ring.Size = UDim2.fromOffset(w + 8, h + 8)
		ring.UIStroke.Transparency = 0.35
		TweenService:Create(ring, ringInfo, { Size = UDim2.fromOffset(w * 1.15, h * 1.3) }):Play()
		TweenService:Create(ring.UIStroke, ringInfo, { Transparency = 1 }):Play()
	end
	self._pulseThread = task.spawn(function()
		while true do
			ripple(rings[1])
			task.delay(RING_TIME / 2, ripple, rings[2])
			for _, step in BEAT do
				if scale and not self._hoverSolo then
					TweenService:Create(scale, TweenInfo.new(step[2], Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = step[1] }):Play()
				end
				task.wait(step[2])
			end
		end
	end)
end

-- Back to "waiting for a rival": called every time you join a stage, so a second match
-- doesn't start with the last one's countdown and hidden buttons.
function QueueController:Reset()
	self:_stopCountdown()
	self:_hideWalkOn()
	local panel = self._frame:FindFirstChild("Panel")
	if not panel then
		return
	end
	self._rematch = false
	self:_finishing(false)
	panel.Title.Text = "Waiting for a rival…"
	panel.Subtitle.Text = "Nobody's joined the other spot yet"
	self._invite:Reset()
	self._solo:Close(true)
	if self._soloLayoutOn then
		self:_soloLayout(false)
	end
	self:_setButtons(true)
	self:UpdateOpponent(nil)
	self:_startWait()
end

function QueueController:UpdateOpponent(opponent: Player?)
	local panelFrame = self._frame:FindFirstChild("Panel")
	local participantsFrame = panelFrame and panelFrame:FindFirstChild("Participants")
	if not participantsFrame then
		return
	end

	local opponentAvatar = participantsFrame:FindFirstChild("Opponent")
	local opponentNameLabel = participantsFrame:FindFirstChild("OpponentName")
	local dashes = opponentAvatar:FindFirstChild("Dashes")

	if opponent then
		self:_stopWait() -- someone's on the other spot (or solo is starting): no more nudging
		-- solo practice: the server puts you in the rival spot (you vs you)
		local solo = opponent == LOCAL_PLAYER
		if self._opponent ~= opponent then
			preloadCards(if solo then { LOCAL_PLAYER } else { LOCAL_PLAYER, opponent })
		end
		if self._opponent ~= opponent and not solo then
			Sounds.Play("RivalFound")
		end
		if not solo then
			self._solo:Close() -- a rival joined while you were picking a theme
			self._invite:Reset() -- or while you were inviting someone
		end
		if solo then
			panelFrame.Title.Text = "Solo practice"
			panelFrame.Subtitle.Text = "Starting soon…"
			-- Invite / Play Solo don't apply once it's starting (Leave stays as the way out)
			self:_soloLayout(true)
		elseif not self._rematch then
			panelFrame.Title.Text = "Opponent found!"
			panelFrame.Subtitle.Text = "Starting soon…"
		end
		opponentAvatar.Visible = true
		opponentAvatar.Thumbnail.Visible = true
		opponentAvatar.Unknown.Visible = false
		if dashes then
			dashes.Visible = false
		end
		opponentNameLabel.Text = opponent.DisplayName
		opponentAvatar.Thumbnail.Image = ""
		task.spawn(function()
			local ok, img = pcall(Players.GetUserThumbnailAsync, Players, opponent.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
			if ok and self._opponent == opponent then
				opponentAvatar.Thumbnail.Image = img
			end
		end)
	else
		opponentAvatar.Thumbnail.Visible = false
		opponentAvatar.Unknown.Visible = true
		if dashes then
			dashes.Visible = true
		end
		opponentNameLabel.Text = "Open spot"
		if self._soloLayoutOn then
			-- a solo game ended or was cancelled: the full card comes back
			self:_soloLayout(false)
		end
		if self._rematch or self._isFinishing then
			-- the rival we were waiting on stepped off: back to an ordinary open queue
			self._rematch = false
			self:_finishing(false)
			self:_setButtons(true)
		end
		if self._opponent then
			-- they left (or cancelled) before the countdown finished: back to waiting
			if self._countdown then
				self:_stopCountdown()
				self:_setButtons(true)
			end
			-- and the walk-on (countdown pill + chips) goes, the card comes back
			self:_hideWalkOn()
			self:_lockCancel(false)
			panelFrame.Title.Text = "Waiting for a rival…"
			panelFrame.Subtitle.Text = "Nobody's joined the other spot yet"
			if self.State == "Active" or self.State == "Activating" then
				self:_startWait() -- alone again: the clock starts over
			end
		end
	end
	self._opponent = opponent
end

-- A rematch is asked for (Results' Rematch, or stepping back on while the rival is still on
-- their results screen): wait here for them to accept. Only Leave stays, which drops it.
function QueueController:ShowRematch()
	local panel = self._frame:FindFirstChild("Panel")
	if not panel then
		return
	end
	local rival = self._opponent
	if not rival or rival == LOCAL_PLAYER or not rival.Parent then
		self:Reset() -- they've already stepped off: just an open queue
		return
	end
	self:_stopCountdown()
	self:_hideWalkOn()
	self._invite:Reset()
	self._solo:Close(true)
	self:_setButtons(false)
	for _, n in { "Leave", "LeaveShadow" } do
		local inst = panel:FindFirstChild(n)
		if inst then
			inst.Visible = true
		end
	end
	self:_stopWait()
	panel.Title.Text = "Rematch requested"
	panel.Subtitle.Text = `Waiting for {rival.DisplayName} to accept…`
	self._rematch = true
end

function QueueController:StartIntermission()
	local panelFrame = self._frame:FindFirstChild("Panel")
	if not panelFrame then
		return
	end
	self._rematch = false
	self:_stopWait()
	self:_setButtons(false)
	self._invite:Reset()
	self._solo:Close(true)
	panelFrame.Title.Text = "Starting round in…"
	self:_stopCountdown()
	self:_setCancel(true)
	self:_lockCancel(false)
	local pill = self._frame:FindFirstChild("Pill", true)
	self._countdown = task.spawn(function()
		for i = DuelConstants.START_TIME, 1, -1 do
			panelFrame.Subtitle.Text = tostring(i)
			if pill then
				pill.Count.Text = `Starting in {i}`
			end
			if i <= 3 then
				Sounds.Play("Countdown")
			end
			if i == 1 then
				-- locked for the last second so a late tap can't land after the server has
				-- moved on (leaving then would be a forfeit); it greys out rather than vanishing
				self:_lockCancel(true)
			end
			task.wait(1)
		end
		self._countdown = nil
	end)
end

function QueueController.Activate(self: typeof(QueueController.new({} :: UITypes.ControllerConfig)), ...: any)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end

	self.State = "Activating"
	self._frame.Visible = true
	self:_bindPad()

	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

-- Controller: B backs out (Modules/UI/PadBinds): closes the solo / invite picker if one's
-- open, else cancels the intermission countdown, else leaves the stage.
function QueueController:_bindPad()
	if self._unpad then
		return
	end
	local frame = self._frame
	local panel = frame.Panel
	local solo, invite = frame:FindFirstChild("Solo"), frame:FindFirstChild("Invite")
	self._unpad = PadBinds.Bind("Queue", {
		{ Key = Enum.KeyCode.ButtonB, Chip = solo and solo:FindFirstChild("Back"), When = function()
			return self._solo ~= nil and self._solo.IsOpen
		end, Run = function()
			self._solo:Close()
		end },
		{ Key = Enum.KeyCode.ButtonB, Chip = invite and invite:FindFirstChild("Back"), When = function()
			return self._invite ~= nil and self._invite.IsOpen
		end, Run = function()
			self._invite:Close()
		end },
		{ Key = Enum.KeyCode.ButtonB, Chip = panel:FindFirstChild("Cancel"), When = function()
			local cancel = panel:FindFirstChild("Cancel")
			return self._countdown ~= nil and not self._cancelLocked and cancel ~= nil and cancel.Visible
		end, Run = function()
			self:_setCancel(false)
			QueueRemote:Fire("Leave")
		end },
		{ Key = Enum.KeyCode.ButtonB, Chip = panel:FindFirstChild("Leave"), When = function()
			local leave = panel:FindFirstChild("Leave")
			return leave ~= nil and leave.Visible
		end, Run = function()
			QueueRemote:Fire("Leave")
		end },
	})
end

function QueueController.Deactivate(self: typeof(QueueController.new({} :: UITypes.ControllerConfig)))
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end

	self.State = "Deactivating"
	self:_stopWait()
	if self._unpad then
		self._unpad()
		self._unpad = nil
	end

	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self:_hideWalkOn()
		self:_hideAside()
		self.State = "Inactive"
	end)
end

function QueueController.Destroy(self: typeof(QueueController.new({} :: UITypes.ControllerConfig)))
	self._janitor:Destroy()
	self._interface = nil
	self._frame = nil
end

return QueueController
