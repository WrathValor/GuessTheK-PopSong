--| VictoryController
-- A short victory shot between the last round and the results card (mock-up: UI canvas,
-- "Stage showcase" #3): the camera goes low and close on the winner on their own spot, so
-- their stage + mic frame them (CameraController.Victory), with letterbox bars and a
-- "YOU WIN!" / "NAME WINS!" banner. Both players see it. After VICTORY_TIME (or a click)
-- it opens the results. Exclusive, so the round screen closes and the HUD stays hidden.
-- DuelController opens it for 1v1 duels with a winner (not solo, a draw or the tutorial) and
-- for Party Stage matches (whoever came first), which then go on to the party results card.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local CameraController = require(script.Parent.Parent.Parent.CameraController) -- Client/CameraController

-- -------------------------------- Constants ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local VICTORY_TIME = 2.8 -- seconds before the results open on their own
local BAR_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BAR_DEPTH = 70 -- how far the letterbox bars reach in
local WIN_COLOUR = Color3.fromHex("FFE07A")
local THEIRS_COLOUR = Color3.fromHex("FF9EC4")

-- --------------------------------- Class ---------------------------------- --
local Victory = {}
Victory.__index = Victory

function Victory.new()
	local self = setmetatable({}, Victory)
	self.Name = "Victory"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._showJanitor = Janitor.new()
	return (self :: any) :: UITypes.Controller
end

function Victory:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Victory")
	self._frame.Visible = false
	self._janitor:Add(self._frame.Skip.Activated:Connect(function()
		self:_toResults()
	end))
end

-- Opens the results (once): the camera hands back as the card comes up
function Victory:_toResults()
	local pending = self._pending
	if not pending then
		return
	end
	self._pending = nil
	if pending.Packet.Party then
		-- Party Stage: its own placement + coins card (opens the Party screen)
		local party = self._interface:GetController("Party")
		if party then
			party:ShowResults(pending.Packet)
		else
			self._interface:Close("Victory")
		end
		return
	end
	self._interface:Open("Results", pending.Packet, pending.Info)
end

-- packet = the duel's End packet, info = its PreDuel info (both passed on to Results)
function Victory:Activate(packet, info)
	local frame = self._frame
	-- the winner: a duel names them; a party match's placement has them first (still here)
	local winnerId = packet and packet.Winner
	if packet and packet.Party then
		for _, p in packet.Party.Placement or {} do
			if p.Place == 1 and not p.Left then
				winnerId = p.UserId
				break
			end
		end
	end
	local winner = winnerId and Players:GetPlayerByUserId(winnerId)
	self._pending = { Packet = packet, Info = info }
	if not (winner and CameraController.Victory(winner)) then
		-- nobody to film (they left, no character): straight to the results
		task.defer(function()
			self:_toResults()
		end)
		return Promise.resolve()
	end
	self.State = "Active"

	local mine = winner == LOCAL_PLAYER
	frame.Banner.Text = if mine then "YOU WIN!" else `{string.upper(winner.DisplayName)} WINS!`
	frame.Banner.BackgroundColor3 = if mine then WIN_COLOUR else THEIRS_COLOUR
	frame.Visible = true

	-- bars slide in, the banner pops
	frame.BarTop.Position = UDim2.fromOffset(640, 0)
	frame.BarBottom.Position = UDim2.fromOffset(640, 720)
	TweenService:Create(frame.BarTop, BAR_TWEEN, { Position = UDim2.fromOffset(640, BAR_DEPTH) }):Play()
	TweenService:Create(frame.BarBottom, BAR_TWEEN, { Position = UDim2.fromOffset(640, 720 - BAR_DEPTH) }):Play()
	frame.Banner.Visible, frame.BannerShadow.Visible = false, false
	self._showJanitor:Add(task.delay(0.35, function()
		frame.Banner.Visible, frame.BannerShadow.Visible = true, true
		Juice.Stagger({ frame.Banner, frame.BannerShadow }, 0, 0.4)
		Sounds.Play("SpinLand")
	end))
	self._showJanitor:Add(task.delay(VICTORY_TIME, function()
		self:_toResults()
	end))
	return Promise.resolve()
end

function Victory:Deactivate()
	self._showJanitor:Cleanup()
	self._frame.Visible = false
	self.State = "Inactive"
	if CameraController.Mode == "Victory" then
		CameraController.Reset()
	end
	return Promise.resolve()
end

function Victory:Destroy()
	self._showJanitor:Destroy()
	self._janitor:Destroy()
end

return Victory
