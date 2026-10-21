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
	self._janitor:Add(panel.NoThanks.Activated:Connect(function()
		self:Hide()
	end))
	self._janitor:Add(panel.Save.Activated:Connect(function()
		local id = DuelConstants.SAVE_STREAK_PRODUCT_ID
		if id and id > 0 then
			MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, id)
		end
		self:Hide()
	end))
end

function SaveStreak:Show(streak: number)
	local panel = self._frame.Panel
	panel.Badge.Value.Text = tostring(streak)
	panel.Body.Text = `Keep your <b>{streak}-win streak</b>. The match still counts as a loss.`
	local enabled = (DuelConstants.SAVE_STREAK_PRODUCT_ID or 0) > 0
	panel.Save.Active = enabled
	panel.Save.AutoButtonColor = enabled
	self._frame.Visible = true
	self.State = "Active"
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
