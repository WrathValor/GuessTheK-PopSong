-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
-- --------------------------------- Imports -------------------------------- --

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)

--------------------------------- Variables --------------------------------- --

local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

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

	youAvatar.Thumbnail.Image =
		Players:GetUserThumbnailAsync(LOCAL_PLAYER.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	youNameLabel.Text = LOCAL_PLAYER.DisplayName

	self._janitor:Add(playSoloBtn.MouseButton1Click:Connect(function()
		QueueRemote:Fire("Solo")
	end))
	self._janitor:Add(leaveBtn.MouseButton1Click:Connect(function()
		QueueRemote:Fire("Leave")
		--self._interface:Close(self.Name)
	end))
end

function QueueController:UpdateOpponent(opponent: Player?)
	local panelFrame = self._frame:FindFirstChild("Panel")
	local participantsFrame: Frame = panelFrame:FindFirstChild("Participants")
	if not participantsFrame then
		return
	end

	local opponentAvatar = participantsFrame and participantsFrame:FindFirstChild("Opponent")
	local opponentNameLabel = participantsFrame and participantsFrame:FindFirstChild("OpponentName")

	if opponent then
		panelFrame.Title.Text = "Opponent Found!"
		Sounds.Play("RivalFound")
		panelFrame.Subtitle.Text = "Starting soon..."

		opponentAvatar.Visible = true
		opponentAvatar.Thumbnail.Visible = true
		opponentAvatar.Unknown.Visible = false

		opponentNameLabel.Text = opponent.DisplayName
		opponentAvatar.Thumbnail.Image =
			Players:GetUserThumbnailAsync(opponent.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	else
		opponentAvatar.Thumbnail.Visible = false
		opponentAvatar.Unknown.Visible = true
		opponentNameLabel.Text = "Open Slot"
	end
end

function QueueController:StartIntermission()
	local panelFrame = self._frame:FindFirstChild("Panel")
	if not panelFrame then
		return
	end
	local participantsFrame: Frame = panelFrame:FindFirstChild("Participants")
	if not participantsFrame then
		return
	end

	local invitePlayersBtn = panelFrame and panelFrame:FindFirstChild("InvitePlayers")
	if invitePlayersBtn then
		invitePlayersBtn.Visible = false
	end
	local playSoloBtn = panelFrame and panelFrame:FindFirstChild("PlaySolo")
	if playSoloBtn then
		playSoloBtn.Visible = false
	end
	local leaveBtn = panelFrame and panelFrame:FindFirstChild("Leave")
	if leaveBtn then
		leaveBtn.Visible = false
	end

	local SubtitleLabel = panelFrame:FindFirstChild("Subtitle")
	if not SubtitleLabel then
		return
	end

	panelFrame.Title.Text = "Starting Round in..."
	for i = DuelConstants.START_TIME, 1, -1 do
		panelFrame.Subtitle.Text = i
		if i <= 3 then
			Sounds.Play("Countdown")
		end
		task.wait(1)
	end
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
		self.State = "Inactive"
	end)
end

function QueueController.Destroy(self: typeof(QueueController.new({} :: UITypes.ControllerConfig)))
	self._janitor:Destroy()
	self._interface = nil
	self._frame = nil
end

return QueueController
