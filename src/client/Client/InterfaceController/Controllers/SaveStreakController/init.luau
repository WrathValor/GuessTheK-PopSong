-- "Save your streak" popup after a loss. It sits on top of the results screen (not exclusive).
-- Buying restores the streak through the Save Streak developer product; until the product id
-- is set in DuelConstants the Save button is greyed out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Prices = require(ReplicatedStorage.Modules.Prices)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local LOCAL_PLAYER = Players.LocalPlayer

local SaveStreak = {}
SaveStreak.__index = SaveStreak

function SaveStreak.new()
	local self = setmetatable({}, SaveStreak)
	self.Name = "SaveStreak"
	self.Exclusive = false
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	return (self :: any) :: UITypes.Controller
end

function SaveStreak:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "SaveStreak")
	self._frame.Visible = false
	-- draw above the results screen
	self._frame.ZIndex = 50
	ButtonScale.ApplyToDescendants(self._frame)
	local panel = self._frame.Panel
	Prices.Get("Product", DuelConstants.SAVE_STREAK_PRODUCT_ID) -- start loading before it's needed
	self._janitor:Add(Prices.Changed:Connect(function()
		if self._frame.Visible then
			self:_price()
		end
	end))
	self._janitor:Add(panel.NoThanks.Activated:Connect(function()
		self:Hide()
	end))
	self._janitor:Add(panel.Save.Activated:Connect(function()
		local id = DuelConstants.SAVE_STREAK_PRODUCT_ID
		if id and id > 0 and panel.Save.Active then
			MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, id)
		end
		self:Hide()
	end))
end

function SaveStreak:Show(streak: number)
	local panel = self._frame.Panel
	panel.Badge.Value.Text = tostring(streak)
	panel.Body.Text = `Keep your <b>{streak}-win streak</b>. The match still counts as a loss.`
	self:_price()
	self._frame.Visible = true
	self.State = "Active"
end

-- the live price on the Save button (Modules/Prices); off until it's known
function SaveStreak:_price()
	local panel = self._frame.Panel
	local price, forSale = Prices.Get("Product", DuelConstants.SAVE_STREAK_PRODUCT_ID)
	local value = panel.Save:FindFirstChild("Value", true)
	if value then
		value.Text = if price then tostring(price) elseif forSale == nil then "…" else "—"
	end
	panel.Save.Active = price ~= nil
	panel.Save.AutoButtonColor = price ~= nil
end

function SaveStreak:Hide()
	self._frame.Visible = false
	self.State = "Inactive"
end

function SaveStreak:Activate(streak)
	if streak then
		self:Show(streak)
	end
	return Promise.resolve()
end

function SaveStreak:Deactivate()
	self:Hide()
	return Promise.resolve()
end

function SaveStreak:Destroy()
	self._janitor:Destroy()
end

return SaveStreak
