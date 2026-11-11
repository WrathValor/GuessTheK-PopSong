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
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local SoloPicker = require(script.SoloPicker)
local InvitePicker = require(script.InvitePicker)

--------------------------------- Variables --------------------------------- --

local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

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
		if not self._invite.IsOpen then
			self._solo:Open()
		end
	end))
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
	panel.Title.Text = "Waiting for a rival…"
	panel.Subtitle.Text = "Nobody's joined the other spot yet"
	self._invite:Reset()
	self._solo:Close(true)
	if self._soloLayoutOn then
		self:_soloLayout(false)
	end
	self:_setButtons(true)
	self:UpdateOpponent(nil)
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
		if self._rematch then
			-- the rival we were waiting on stepped off: back to an ordinary open queue
			self._rematch = false
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

	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function QueueController.Deactivate(self: typeof(QueueController.new({} :: UITypes.ControllerConfig)))
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end

	self.State = "Deactivating"

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
