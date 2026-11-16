--| InvitedController
-- "YOU WERE INVITED!" (design board "Referral moments", left; built by InviteController/Build
-- as Interface.Frames.Invited): shown once to a brand-new player who joined from someone's
-- invite, before the tutorial's Welcome card. The welcome gift is already in their coins
-- (Engine/ReferralService); COLLECT just rolls the coins up and marks it seen
-- (Referral.Welcomed), and the tutorial goes on from there (TutorialController waits for it).
--   Interface:Open("Invited")

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ReferralConstants = require(ReplicatedStorage.Constants.ReferralConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ReferralRemote = Bridgenet.ReferenceBridge("ReferralRemote")

-- --------------------------------- Helpers -------------------------------- --
local function get(path, default: any): any
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else default
end

-- invited and not welcomed yet (false while the data hasn't loaded)
local function pending(): boolean
	return get(PlayerData.Referral.InvitedBy, "") ~= "" and get(PlayerData.Referral.Welcomed, true) == false
end

-- ---------------------------------- Class --------------------------------- --
local Invited = {}
Invited.__index = Invited

-- TutorialController asks this before its Welcome card
Invited.Pending = pending

function Invited.new()
	local self = setmetatable({}, Invited)
	self.Name = "Invited"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._collected = false
	return (self :: any) :: UITypes.Controller
end

function Invited:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Invited")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	local panel = self._frame.Panel

	self._janitor:Add(panel.Collect.Activated:Connect(function()
		if self._collected then
			return
		end
		self._collected = true
		Sounds.Play("Coins")
		Juice.Pop(panel.Gift, 0.15)
		ReferralRemote:Fire({ Action = "Welcomed" })
		task.delay(0.35, function()
			self._interface:Close(self.Name)
		end)
	end))

	-- first join: once the loading screen has gone and the data says so (the server sets
	-- InvitedBy while the data loads, so it's there before the tutorial looks)
	task.spawn(function()
		local deadline = os.clock() + 60
		while not LOCAL_PLAYER:GetAttribute("LoadingDone") and os.clock() < deadline do
			task.wait(0.1)
		end
		deadline = os.clock() + 15
		while os.clock() < deadline do
			if pending() then
				break
			end
			task.wait(0.25)
		end
		if pending() and not LOCAL_PLAYER:GetAttribute("Stage") then
			-- wait for anything already open (it won't be long on a first join)
			local until_ = os.clock() + 30
			while self._interface.ActiveController ~= nil and os.clock() < until_ do
				task.wait(0.25)
			end
			self._interface:Open(self.Name)
		end
	end)
end

function Invited:Activate()
	local panel = self._frame.Panel
	local inviterId = tonumber(get(PlayerData.Referral.InvitedBy, ""))
	local name = get(PlayerData.Referral.InviterName, "")
	if name == "" then
		name = "A friend"
	end
	panel.Inviter.Names.InviterName.Text = name
	panel.Inviter.Avatar.Image = if inviterId then `rbxthumb://type=AvatarHeadShot&id={inviterId}&w=150&h=150` else ""
	panel.Gift.Amount.Text = `+{ReferralConstants.FRIEND_GIFT}`
	panel.Note.Text = `Play your first game and {name} gets a reward too.`
	self._collected = false
	self._frame.Visible = true
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Invited:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Invited:Destroy()
	self._janitor:Destroy()
end

return Invited
