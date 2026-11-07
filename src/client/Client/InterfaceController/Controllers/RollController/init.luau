--| RollController
-- The Song Roll screen (Interface.Frames.Roll): pull random photocards for coins. Its own
-- screen now that the shop is one scrolling page; opened from the HUD's Roll button, the
-- Index's ROLL SONGS and the Inventory's "Roll for more". The page itself (collection, odds,
-- ROLL ×1 / ×10, the reveal) is ShopController/Roll, unchanged; this controller only opens and
-- closes it and keeps the coin balance in the header up to date.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local FitPanel = require(ReplicatedStorage.Modules.UI.FitPanel)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Roll = require(script.Parent.ShopController.Roll)

local fmt = ShopCatalog.Format

-- ---------------------------------- Class --------------------------------- --
local RollController = {}
RollController.__index = RollController

function RollController.new()
	local self = setmetatable({}, RollController)
	self.Name = "Roll"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	return (self :: any) :: UITypes.Controller
end

function RollController:_toast(message: string)
	local toast = self._frame:FindFirstChild("Toast")
	if not toast or message == "" then
		return
	end
	toast.Text = message
	toast.Visible = true
	Juice.SlideIn(toast, 24)
	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(2.2, function()
		if self._toastToken == token then
			toast.Visible = false
		end
	end)
end

function RollController:_balance()
	local coins = PlayerData.Currencies.Won.Get()
	local balance = self._frame.Panel.Header.Balance
	if self._shownCoins and self._shownCoins ~= coins and self.State == "Active" then
		Juice.CountUp(balance.Amount, self._shownCoins, coins, fmt)
		Juice.Pop(balance, if coins > self._shownCoins then 0.18 else 0.1)
	else
		balance.Amount.Text = fmt(coins)
	end
	self._shownCoins = coins
end

-- -------------------------------- Lifecycle ------------------------------- --

function RollController:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Roll")
	self._frame.Visible = false
	local panel = self._frame.Panel
	FitPanel.Watch(self._frame, self._janitor)
	ButtonScale.ApplyToDescendants(panel.Header)

	local j = self._janitor
	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))

	-- Roll wants the container holding its page (Pages.Roll) and the frame holding RollReveal
	self._roll = Roll.new(panel.Pages, self._frame, j, function(message)
		self:_toast(message)
	end)

	j:Add(PlayerData.Currencies.Won.Observe(function()
		self:_balance()
		if self.State == "Active" then
			self._roll:Fill() -- the roll buttons grey out when you can't afford them
		end
	end))
end

function RollController:Activate()
	self._frame.Visible = true
	self:_balance()
	self._roll:Fill()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function RollController:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self._roll:Hide()
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function RollController:Destroy()
	self._janitor:Destroy()
end

return RollController
