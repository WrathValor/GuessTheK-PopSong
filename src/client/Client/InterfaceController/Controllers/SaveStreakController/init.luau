-- "Save your streak" popup after a loss. It sits on top of the results screen (not exclusive).
-- Buying restores the streak through the Save Streak developer product (PlayerData Products);
-- until the product id is set in DuelConstants the Save button is greyed out.
--   Offer   Panel.Title / Body / Chips / No thanks / Save it: the body says what the streak's
--           worth (its coin bonus, or how close it is to one). Save waits on the purchase
--           prompt: cancelled = back to the offer, bought = Saved.
--   Saved   Panel.Saved: STREAK SAVED!, the badge turns mint, LET'S GO closes it (or it closes
--           itself after SAVED_HOLD).
-- Logs ScreenOpened (SaveStreak) when it shows and SaveStreakOffer (Bought / Cancelled /
-- NoThanks, value = the streak) when it's answered.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Prices = require(ReplicatedStorage.Modules.Prices)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local LOCAL_PLAYER = Players.LocalPlayer

local RED = Color3.fromHex("FF5A4E")
local MINT = Color3.fromHex("A7E9B8")
local OFFER = { "Title", "Body", "Chip1", "Chip2", "NoThanks", "SaveShadow", "Save" }
local SAVED_HOLD = 4 -- seconds the Saved card stays up before it closes itself
local FADE = TweenInfo.new(0.25)

-- the coin bonus a streak of `n` wins gets (DuelConstants.STREAK_MULTIPLIERS, highest first)
local function bonusFor(n: number): number?
	for _, pair in DuelConstants.STREAK_MULTIPLIERS do
		if n >= pair[1] then
			return pair[2]
		end
	end
	return nil
end

-- the smallest streak that gets a bonus
local function firstBonus(): (number, number)
	local list = DuelConstants.STREAK_MULTIPLIERS
	local last = list[#list]
	return last[1], last[2]
end

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
	self._scrimAlpha = self._frame.Scrim.BackgroundTransparency
	self._streak = 0
	self._buying = false
	Prices.Get("Product", DuelConstants.SAVE_STREAK_PRODUCT_ID) -- start loading before it's needed
	self._janitor:Add(Prices.Changed:Connect(function()
		if self._frame.Visible then
			self:_price()
		end
	end))
	self._janitor:Add(panel.NoThanks.Activated:Connect(function()
		if self._buying then
			return
		end
		AnalyticsClient.Event("SaveStreakOffer", self._streak, "NoThanks")
		self:Hide()
	end))
	self._janitor:Add(panel.Save.Activated:Connect(function()
		local id = DuelConstants.SAVE_STREAK_PRODUCT_ID
		if not (id and id > 0 and panel.Save.Active) or self._buying then
			return
		end
		-- stays up while the prompt is open: the answer decides what it shows next
		self:_setBuying(true)
		MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, id)
	end))
	self._janitor:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= LOCAL_PLAYER.UserId or productId ~= DuelConstants.SAVE_STREAK_PRODUCT_ID or not self._buying then
			return
		end
		self:_setBuying(false)
		if not self._frame.Visible then
			return
		end
		if purchased then
			AnalyticsClient.Event("SaveStreakOffer", self._streak, "Bought")
			self:_showSaved()
		else
			AnalyticsClient.Event("SaveStreakOffer", self._streak, "Cancelled")
			Juice.Shake(panel.Save, 0.5)
		end
	end))
	self._janitor:Add(panel.Saved.Done.Activated:Connect(function()
		self:Hide()
	end))
end

function SaveStreak:Show(streak: number)
	local panel = self._frame.Panel
	self._streak = streak
	self._token = (self._token or 0) + 1
	self:_setBuying(false)
	-- back to the offer (the Saved card from last time put away)
	for _, name in OFFER do
		panel[name].Visible = true
	end
	panel.Saved.Visible = false
	panel.Badge.BackgroundColor3 = RED
	panel.Badge.Value.Text = tostring(streak)

	-- what the streak is worth: its coin bonus, or how close it is to the first one
	local bonus = bonusFor(streak)
	local first, firstMult = firstBonus()
	if bonus then
		panel.Body.Text = `Keep your <b>{streak}-win streak</b> and its <b>×{bonus}</b> coin bonus.\nThe match still counts as a loss.`
	else
		local more = first - streak
		panel.Body.Text = `Keep your <b>{streak}-win streak</b>: {more} more win{if more == 1 then "" else "s"} for a <b>×{firstMult}</b> coin bonus.\nThe match still counts as a loss.`
	end
	panel.Saved.Body.Text = if bonus
		then `Your <b>{streak}-win streak</b> is back, ×{bonus} coin bonus and all.\nWin the next duel to keep it going.`
		else `Your <b>{streak}-win streak</b> is back.\nWin the next duel to keep it going.`
	self:_price()

	-- in: the scrim fades up, the card pops, then the badge
	local scrim = self._frame.Scrim
	scrim.BackgroundTransparency = 1
	self._frame.Visible = true
	self.State = "Active"
	TweenService:Create(scrim, FADE, { BackgroundTransparency = self._scrimAlpha }):Play()
	Juice.Stagger({ panel, self._frame.PanelShadow }, 0, 0.6)
	task.delay(0.25, function()
		if self._frame.Visible then
			Juice.Pop(panel.Badge, 0.2)
		end
	end)
	Sounds.Play("Open")
	AnalyticsClient.Event("ScreenOpened", 1, "SaveStreak")
end

-- Save it while the purchase prompt is open: greyed and not pressable
function SaveStreak:_setBuying(on: boolean)
	self._buying = on
	local panel = self._frame.Panel
	panel.Save.BackgroundTransparency = if on then 0.35 else 0
	panel.NoThanks.Active = not on
	if not on then
		self:_price()
	end
end

-- bought: the Saved card in place of the offer
function SaveStreak:_showSaved()
	local panel = self._frame.Panel
	for _, name in OFFER do
		panel[name].Visible = false
	end
	panel.Saved.Visible = true
	TweenService:Create(panel.Badge, FADE, { BackgroundColor3 = MINT }):Play()
	Juice.Pop(panel, 0.08)
	Juice.Pop(panel.Badge, 0.3)
	Sounds.Play("Success")
	local token = self._token
	task.delay(SAVED_HOLD, function()
		if self._token == token and self._frame.Visible and panel.Saved.Visible then
			self:Hide()
		end
	end)
end

-- the live price on the Save button (Modules/Prices); off until it's known
function SaveStreak:_price()
	local panel = self._frame.Panel
	local price, forSale = Prices.Get("Product", DuelConstants.SAVE_STREAK_PRODUCT_ID)
	local value = panel.Save:FindFirstChild("Value", true)
	if value then
		value.Text = if price then tostring(price) elseif forSale == nil then "…" else "—"
	end
	panel.Save.Active = price ~= nil and not self._buying
	panel.Save.AutoButtonColor = price ~= nil
end

function SaveStreak:Hide()
	self._token = (self._token or 0) + 1
	self._frame.Visible = false
	self.State = "Inactive"
	-- (a prompt still open answers into nothing: PromptProductPurchaseFinished checks Visible)
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
