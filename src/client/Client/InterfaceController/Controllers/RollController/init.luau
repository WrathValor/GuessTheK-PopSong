--| RollController
-- The Song Roll screen (Interface.Frames.Roll): pull random photocards for coins. Its own
-- screen now that the shop is one scrolling page; opened from the HUD's Roll button, the
-- Index's ROLL SONGS and the Inventory's "Roll for more". The page itself (collection, odds,
-- ROLL ×1 / ×10, the reveal) is ShopController/Roll; this controller opens and closes it, keeps
-- the coin balance and the roll-ticket counter in the header up to date, and runs the Pick a
-- Group overlay (./Picker) that ROLL A GROUP opens.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local FitPanel = require(ReplicatedStorage.Modules.UI.FitPanel)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Roll = require(script.Parent.ShopController.Roll)
local Picker = require(script.Picker)
local Players = game:GetService("Players")

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
	-- the ticket counter sits left of the coins while you have any
	local tickets = self._frame.Panel.Header:FindFirstChild("Tickets")
	if tickets then
		local n = Currencies.Count(Players.LocalPlayer, "Tickets")
		tickets.Visible = n > 0
		tickets.Amount.Text = tostring(n)
		task.defer(function()
			local panelScale = self._frame.Panel.AbsoluteSize.X / self._frame.Panel.Size.X.Offset
			local w = if panelScale > 0 then balance.AbsoluteSize.X / panelScale else 120
			tickets.Position = UDim2.fromOffset(balance.Position.X.Offset - w - 10, balance.Position.Y.Offset)
		end)
	end
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

	-- roll tickets: the header counter, ROLL A GROUP → Pick a Group → a ticket roll
	local picker = self._frame:FindFirstChild("Picker")
	if picker then
		self._picker = Picker.new(picker, j, function(groupId)
			self._roll:RollGroup(groupId)
		end)
		local strip = panel.Pages.Roll.Stage:FindFirstChild("TicketStrip")
		if strip then
			j:Add(strip.RollGroup.Activated:Connect(function()
				self._picker:Open()
			end))
		end
	end
	j:Add(Players.LocalPlayer:GetAttributeChangedSignal(Currencies.Tickets.Attribute):Connect(function()
		self:_balance()
	end))

	j:Add(PlayerData.Currencies.Won.Observe(function()
		self:_balance()
		if self.State == "Active" then
			self._roll:Fill() -- the roll buttons grey out when you can't afford them
		end
	end))
end

-- opts.Picker = open Pick a Group too (the HUD's roll tickets).
-- opts.Upgrade = a pull (from the Index's card upgrade): play its Gold / Rainbow reveal, then
-- go back to the Index (still in upgrade mode while upgrades are left)
function RollController:Activate(opts: any?)
	self._frame.Visible = true
	self:_balance()
	self._roll:Fill()
	-- opts.Picker = straight to Pick a Group (the HUD's roll tickets)
	if type(opts) == "table" and opts.Picker and self._picker then
		task.defer(function()
			self._picker:Open()
		end)
	end
	if type(opts) == "table" and type(opts.Upgrade) == "table" then
		self._roll:ShowUpgrade(opts.Upgrade, function()
			local left = (Currencies.Count(Players.LocalPlayer, "Upgrades")) > 0
			self._interface:Open("Index", { Upgrade = left })
		end)
	end
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
	if self._picker and self._picker:IsOpen() then
		self._picker:Close()
	end
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function RollController:Destroy()
	self._janitor:Destroy()
end

return RollController
