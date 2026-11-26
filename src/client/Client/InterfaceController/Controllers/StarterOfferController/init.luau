--| StarterOfferController
-- The starter offer (design board "Money 2"): for ShopCatalog.DebutPack.Bonus.Hours after a
-- new player's first duel, the Debut Pack comes with +Bonus.GenPacks gen packs, sold as its
-- own product at the same price.
--   • Back in the lobby with the tutorial done (or the moment it's finished / skipped), no
--     Debut Pack and no offer yet: the server
--     starts the clock (ShopRemote "StarterStart" → Rewards.StarterAt) and the card opens
--     once by itself (Settings.Hints "Starter").
--   • HUD.Buttons.Starter (under the top-right buttons) is the one offer button (design board
--     "Money 6 · HUD offer button"), showing the next thing you don't own, once the tutorial
--     is done:
--       Bonus  – while the bonus lasts: the roll ticket, "Bonus ends 47:59:12", the countdown
--                bar and a red +3 FREE sticker; tapping it opens the card
--       Debut  – the Debut Pack after that, until it's bought: its own gift icon, the price
--                sticker; tapping it opens the card
--       DoubleCoins / VIP – the passes in turn (blue "2×", lilac crown), the price sticker;
--                tapping it opens Roblox's pass prompt
--     Hidden once you own all of them.
--   • GET IT prompts the bonus product (the plain pack once the bonus is over); the purchase
--     reveal is PurchasedController's.
-- Bonus.ProductId 0 = off; in Studio it still runs, selling the plain pack, for testing.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local Prices = require(ReplicatedStorage.Modules.Prices)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

local PACK = ShopCatalog.DebutPack
local BONUS = PACK and PACK.Bonus
local ROBUX_GLYPH = utf8.char(0xE002) -- Roblox fonts draw this as the Robux sign

-- the HUD offer button's looks, by what it offers
local C = Color3.fromHex
local OFFERS = {
	Bonus = { Colour = C("FFE07A"), Icon = Currencies.Tickets.Icon, Title = "Debut Pack" },
	Debut = { Colour = C("FFE07A"), Icon = "rbxassetid://115794843985239", Title = "Debut Pack", Sub = "2,500 coins + a set" }, -- assets/ui/DebutPack.png
	DoubleCoins = { Colour = C("9ED8F5"), Icon = "rbxassetid://113425820963640", Title = "2× Coins", Sub = "Every win, forever", Pass = "DoubleCoins" },
	VIP = { Colour = C("B9A6FF"), Icon = "rbxassetid://127211190617908", Title = "VIP Pass", Sub = "Gold tag + daily perks", Pass = "VIP" },
}
local RED, WHITE, INK = C("FF5A4E"), C("FFFFFF"), C("1E1B2E")
local HINT = "Starter"
local DELAY = 1.5 -- seconds back in the lobby before it opens

-- --------------------------------- Helpers -------------------------------- --
local function get(path, default: any): any
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else default
end

local function has(set, id: string): boolean
	local ok, v = pcall(set.Has, id)
	return ok and v == true
end

local function enabled(): boolean
	return BONUS ~= nil and ((BONUS.ProductId or 0) > 0 or RunService:IsStudio())
end

local function owned(): boolean
	return has(PlayerData.Rewards.Claimed, PACK.Id)
end

local function startedAt(): number
	return get(PlayerData.Rewards.StarterAt, 0)
end

local function left(): number
	local at = startedAt()
	if at <= 0 then
		return 0
	end
	return math.max(0, at + BONUS.Hours * 3600 - workspace:GetServerTimeNow())
end

-- the bonus is running for you
local function live(): boolean
	return enabled() and not owned() and left() > 0
end

local function hasPass(id: string): boolean
	return has(PlayerData.GamePasses, id)
end

-- what the HUD offer button shows right now (nil = nothing left to offer, or still in the tutorial)
local function nextOffer(): string?
	if get(PlayerData.Settings.Onboard, "") ~= "Done" then
		return nil
	end
	if PACK and ((PACK.ProductId or 0) > 0 or RunService:IsStudio()) and not owned() then
		return if live() then "Bonus" else "Debut"
	end
	for _, id in { "DoubleCoins", "VIP" } do
		local pass = ShopCatalog.GetPass(id)
		if pass and (pass.GamePassId or 0) > 0 and not hasPass(id) then
			return id
		end
	end
	return nil
end

local function clock(seconds: number): string
	seconds = math.floor(seconds)
	return string.format("%02d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60)
end

-- ---------------------------------- Class --------------------------------- --
local StarterOffer = {}
StarterOffer.__index = StarterOffer

function StarterOffer.new()
	local self = setmetatable({}, StarterOffer)
	self.Name = "StarterOffer"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._chip = nil :: any
	self._janitor = Janitor.new()
	self._from = "Popup"
	self._shownThisSession = false
	return (self :: any) :: UITypes.Controller
end

function StarterOffer:Initialize(interface)
	self._interface = interface
	local j = self._janitor
	self._frame = interface:ResolveFrame("Interface", "StarterOffer")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	local panel = self._frame.Panel

	j:Add(panel.Later.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(panel.Buy.Activated:Connect(function()
		local product = self:_product()
		AnalyticsClient.Event("MoneyOffer", 1, "Starter", self._from)
		MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, product)
	end))
	j:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, bought)
		if bought and userId == LOCAL_PLAYER.UserId and (productId == PACK.ProductId or productId == BONUS.ProductId) then
			self._interface:Close(self.Name)
		end
	end))

	-- the prices, once: the card shows the one GET IT will sell (the bonus product while the
	-- bonus lasts, the plain pack after)
	self._prices = {}
	task.spawn(function()
		for _, id in { PACK.ProductId, BONUS and BONUS.ProductId or 0 } do
			if id > 0 then
				local ok, info = Prices.Fetch(id, Enum.InfoType.Product) -- (regional price)
				if ok and info and info.PriceInRobux then
					self._prices[id] = tostring(info.PriceInRobux)
				end
			end
		end
		self:_tick()
	end)

	-- the HUD chip, under the top-right buttons (HUD.Buttons: Invite · News · Settings)
	task.spawn(function()
		local hud = LOCAL_PLAYER:WaitForChild("PlayerGui"):WaitForChild("Interface"):WaitForChild("HUD")
		local tl = hud:WaitForChild("Buttons")
		local chip, shadow = tl:WaitForChild("Starter", 10), tl:WaitForChild("StarterShadow", 10)
		if not chip then
			return
		end
		self._chip = chip
		ButtonScale.Apply(chip)
		local invite = tl:FindFirstChild("Invite")
		local function place()
			if invite then
				-- under the top row (Invite · News · Settings), keeping its own X
				chip.Position = UDim2.new(chip.Position.X, invite.Position.Y + UDim.new(0, 74))
				shadow.Position = chip.Position + UDim2.fromOffset(4, 4)
			end
		end
		place()
		if invite then
			j:Add(invite:GetPropertyChangedSignal("Position"):Connect(place))
		end
		j:Add(chip.Activated:Connect(function()
			local offer = nextOffer()
			local spec = offer and OFFERS[offer]
			if spec and spec.Pass then
				-- a pass: straight to Roblox's prompt
				local pass = ShopCatalog.GetPass(spec.Pass)
				AnalyticsClient.Event("MoneyOffer", 1, spec.Pass, "HUD")
				MarketplaceService:PromptGamePassPurchase(LOCAL_PLAYER, pass.GamePassId)
				return
			end
			self._from = "HUD"
			self._interface:Open(self.Name)
		end))
	end)

	-- once a second: the chip, and the card's timer while it's open
	j:Add(task.spawn(function()
		while true do
			self:_tick()
			task.wait(1)
		end
	end))

	-- back in the lobby: start the offer / show the card
	j:Add(interface.ModeChanged:Connect(function(mode)
		if mode == "Gameplay" then
			self:_try()
		end
	end))
	task.delay(5, function()
		self:_try()
	end)
	-- the onboarding just finished or was skipped: don't wait for the next menu to close
	j:Add(PlayerData.Settings.Onboard.Observe(function(done)
		-- (on join this fires straight away: the 5 s try above covers that, after the loading screen)
		if done == "Done" and LOCAL_PLAYER:GetAttribute("LoadingDone") then
			self:_try()
		end
	end))
end

-- what GET IT sells right now
function StarterOffer:_product(): number
	return if live() and (BONUS.ProductId or 0) > 0 then BONUS.ProductId else PACK.ProductId
end

function StarterOffer:_tick()
	local on = live()
	local chip = self._chip
	if chip then
		local offer = nextOffer()
		local spec = offer and OFFERS[offer]
		chip.Visible = spec ~= nil
		chip.Parent.StarterShadow.Visible = spec ~= nil
		if spec then
			chip.BackgroundColor3 = spec.Colour
			chip.Title.Text = spec.Title
			local icon, glyph = chip.IconBox.Icon, chip.IconBox:FindFirstChild("Glyph")
			icon.Visible = spec.Icon ~= nil
			icon.Image = spec.Icon or ""
			if glyph then
				glyph.Visible = spec.Glyph ~= nil
				glyph.Text = spec.Glyph or ""
			end
			chip.Info.Bar.Visible = offer == "Bonus"
			if offer == "Bonus" then
				chip.Info.Timer.Text = `Bonus ends {clock(left())}`
				chip.Sticker.Text = `+{BONUS.GenPacks} PACKS`
				chip.Sticker.BackgroundColor3, chip.Sticker.TextColor3 = RED, WHITE
				chip.Info.Bar.Fill.Size = UDim2.fromScale(math.clamp(left() / (BONUS.Hours * 3600), 0, 1), 1)
				-- the bar as wide as the timer line (screen px back to the HUD's design px)
				local scale = chip.AbsoluteSize.X / chip.Size.X.Offset
				if scale > 0 then
					chip.Info.Bar.Size = UDim2.fromOffset(math.floor(chip.Info.Timer.AbsoluteSize.X / scale + 0.5), 5)
				end
			else
				-- the plain offers: a line about it, and its price on a white sticker
				chip.Info.Timer.Text = spec.Sub
				local price = if spec.Pass
					then Prices.Get("GamePass", ShopCatalog.GetPass(spec.Pass).GamePassId)
					else Prices.Get("Product", PACK.ProductId)
				chip.Sticker.Visible = price ~= nil
				chip.Sticker.Text = `{ROBUX_GLYPH} {price or ""}`
				chip.Sticker.BackgroundColor3, chip.Sticker.TextColor3 = WHITE, INK
			end
			if offer == "Bonus" then
				chip.Sticker.Visible = true
			end
		end
	end
	if self.State == "Active" or self.State == "Activating" then
		local panel = self._frame.Panel
		panel.Timer.Text = if on then `Bonus ends in {clock(left())}` else "The starter bonus has ended"
		panel.Bonus.Visible = on
		panel.Buy.Inner.Price.Text = self._prices[self:_product()] or "…"
	end
end

function StarterOffer:_free(): boolean
	local i = self._interface
	return i.Mode == "Gameplay" and i.ActiveController == nil and not LOCAL_PLAYER:GetAttribute("Stage")
end

function StarterOffer:_try()
	if self._waiting or self._shownThisSession or not enabled() or owned() then
		return
	end
	if get(PlayerData.Settings.Onboard, "") ~= "Done" or has(PlayerData.Settings.Hints, HINT) then
		return
	end
	self._waiting = true
	task.delay(DELAY, function()
		self._waiting = false
		if self._shownThisSession or not self:_free() then
			return -- the next time the lobby comes back
		end
		if startedAt() <= 0 then
			ShopRemote:Fire({ Action = "StarterStart" })
			-- wait for the server's clock to land
			local t = os.clock()
			while startedAt() <= 0 and os.clock() - t < 5 do
				task.wait(0.2)
			end
		end
		if not live() or not self:_free() then
			return
		end
		self._shownThisSession = true
		SettingsRemote:Fire({ Action = "HintSeen", Id = HINT })
		self._from = "Popup"
		self._interface:Open(self.Name)
	end)
end

function StarterOffer:Activate()
	local panel = self._frame.Panel
	CosmeticView.Show(panel.Stage.Face.Art, "Stage", PACK.Stage)
	CosmeticView.Show(panel.Mic.Face.Art, "Mic", PACK.Mic)
	self:_tick()
	self._frame.Visible = true
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	self:_tick()
	Juice.Pop(panel.Bonus, 0.25)
	Sounds.Play("Success")
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function StarterOffer:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function StarterOffer:Destroy()
	self._janitor:Destroy()
end

return StarterOffer
