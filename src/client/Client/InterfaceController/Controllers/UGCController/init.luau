--| UGCController
-- The UGC screen (Interface.Frames.UGC): the group's own avatar items, sold for Robux. Its own
-- screen, kept apart from the coin shop; opened from the HUD's UGC button. The page itself
-- (big preview on your avatar, All / Dances / Accessories, six a page) is ShopController/Emotes,
-- unchanged; this controller only opens and closes it. Dancing closes the screen so you can
-- see yourself.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local FitPanel = require(ReplicatedStorage.Modules.UI.FitPanel)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local Prices = require(ReplicatedStorage.Modules.Prices)

local Emotes = require(script.Parent.ShopController.Emotes)

-- ---------------------------------- Class --------------------------------- --
local UGCController = {}
UGCController.__index = UGCController

function UGCController.new()
	local self = setmetatable({}, UGCController)
	self.Name = "UGC"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	return (self :: any) :: UITypes.Controller
end

-- -------------------------------- Lifecycle ------------------------------- --

function UGCController:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "UGC")
	self._frame.Visible = false
	local panel = self._frame.Panel
	FitPanel.Watch(self._frame, self._janitor)
	ButtonScale.ApplyToDescendants(panel)

	local j = self._janitor
	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))

	self._emotes = Emotes.new(panel.Pages.UGC, j, function()
		self._interface:Close(self.Name)
	end)

	local function refresh()
		if self.State == "Active" then
			self._emotes:Fill()
		end
	end
	j:Add(Prices.Changed:Connect(refresh))
	j:Add(PlayerData.GamePasses.Observe(refresh))
end

function UGCController:Activate()
	self._frame.Visible = true
	self._emotes:Fill()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function UGCController:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function UGCController:Destroy()
	self._janitor:Destroy()
end

return UGCController
