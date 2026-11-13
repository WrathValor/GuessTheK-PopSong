-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Levels = require(ReplicatedStorage.Modules.Levels)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Effects = require(script.Effects)
local Nudges = require(script.Nudges)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Slide-out when a menu opens: each corner group leaves through its nearest edge.
local SLIDE = {
	TopLeft = Vector2.new(-480, 0),
	Buttons = Vector2.new(480, 0),
	Menu = Vector2.new(0, 340),
}
local SLIDE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local SLIDE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Frames opened by the HUD buttons. Missing controllers are skipped with a warning, so
-- buttons start working as soon as the matching controller is added.
local TILE_TARGETS = {
	Profile = "Profile",
	Index = "Index",
	Shop = "Shop",
	Inventory = "Inventory",
	Rewards = "Rewards",
}

-- --------------------------------- Helpers -------------------------------- --
local function commas(n: number): string
	local s = tostring(math.floor(n))
	local formatted, k = s, 0
	repeat
		formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

-- Coins / wins on the HUD cards: commas up to 99,999, then short ("123K", "1.01M", "12.5B"),
-- so it never runs under the coins card's + button. Rounds down, so 999,999 is "999K",
-- never "1000K".
local SHORT_UNITS = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
local function short(n: number): string
	n = math.floor(n)
	if n < 100000 then
		return commas(n)
	end
	for _, unit in SHORT_UNITS do
		if n >= unit[1] then
			local hundredths = n // (unit[1] / 100) -- whole-number maths: no 1.01 → "1.00"
			if hundredths >= 10000 then
				return `{hundredths // 100}{unit[2]}`
			elseif hundredths >= 1000 then
				return `{hundredths // 100}.{(hundredths // 10) % 10}{unit[2]}`
			end
			return string.format("%d.%02d%s", hundredths // 100, hundredths % 100, unit[2])
		end
	end
	return commas(n)
end

-- --------------------------------- Tables --------------------------------- --
-- Lobby HUD. Non-exclusive: it lives at PlayerGui.Interface.HUD (not under Frames), shows
-- while the UI is in "Gameplay" mode and hides whenever an exclusive frame (Queue, Game,
-- Shop...) puts the UI into "Menu" mode.
local HUDController = {}
HUDController.__index = HUDController

type Self = typeof(setmetatable({} :: {
	Name: string,
	Exclusive: boolean,
	State: UITypes.ControllerState,
	_interface: any,
	_hud: any,
	_janitor: any,
	_closeWallet: (() -> ())?,
}, HUDController))

-- --------------------------------- Methods -------------------------------- --

function HUDController.new()
	local self = setmetatable({}, HUDController)

	self.Name = "HUD"
	self.Exclusive = false
	self.State = "Inactive" :: UITypes.ControllerState

	self._interface = nil :: any
	self._hud = nil :: typeof(game.StarterGui.Interface.HUD)?
	self._janitor = Janitor.new()

	return (self :: any) :: UITypes.Controller
end

function HUDController.Initialize(self: Self, interface: any)
	self._interface = interface
	local screenGui = interface.PlayerGui:WaitForChild("Interface")
	local hud = screenGui:WaitForChild("HUD") :: typeof(game.StarterGui.Interface.HUD)
	self._hud = hud

	ButtonScale.ApplyToDescendants(hud)

	self:_bindXP()
	self:_bindCurrency()
	self:_bindButtons()
	self:_bindSeason()
	self:_bindExtras()
	self:_applyStatic()
	-- one-time lobby hints: Roll / Shop once you can afford something, Rewards once one's earned
	self._nudges = Nudges.new(hud, self._janitor)
	self._nudges:RewardsEarned(self._rewardsEarned or 0)
	-- looping eye-catchers: rainbow Shop outline, Quick Play sheen, Rewards badge hop
	Effects.Start(hud, self._janitor, function(gui)
		Juice.Pop(gui, 0.18)
	end)

	-- Show/hide with the global UI mode.
	self._janitor:Add(interface.ModeChanged:Connect(function(mode: UITypes.UIMode)
		if mode == "Menu" then
			interface:BlockMode(self:Deactivate())
		else
			self:Activate()
		end
	end))

	if interface.Mode == "Gameplay" then
		self:Activate()
	else
		hud.Visible = false
	end
end

-- [[ XP bar ]]
-- Menu.XPBar, under the tiles: "LEVEL 7 [620/1,000]", the fill tweening to the level's progress.
-- (The old profile card with the avatar, name and title chip is gone: titles still show on
-- name tags and in duels.)

function HUDController._bindXP(self: Self)
	self._janitor:Add(PlayerData.Player.XP.Observe(function(xp: number)
		self:SetXP(xp)
	end))
end

function HUDController.SetXP(self: Self, totalXP: number)
	local bar = self._hud.Menu.XPBar
	local level, into, need = Levels.FromXP(totalXP)
	local maxed = level >= Levels.MAX_LEVEL

	bar.Label.Text = if maxed then `LEVEL {level} [MAX]` else `LEVEL {level} [{commas(into)}/{commas(need)}]`
	-- Fill sits in a rounded CanvasGroup ("Clip") so it can't poke past the bar's outline
	TweenService:Create(bar.Clip.Fill, FILL_TWEEN, {
		Size = UDim2.new(if maxed then 1 else math.clamp(into / need, 0, 1), 0, 1, 0),
	}):Play()
end

-- [[ Coins / wins ]]

function HUDController._bindCurrency(self: Self)
	local currency = self._hud.TopLeft

	-- numbers roll to their new value and the card gets a punch (not on the first load)
	local shown: { [string]: number } = {}
	local function animateNumber(key: string, card: GuiObject, label: TextLabel, value: number)
		local old = shown[key]
		shown[key] = value
		if old == nil or old == value then
			label.Text = short(value)
			return
		end
		Juice.CountUp(label, old, value, short)
		Juice.Pop(card, if value > old then 0.1 else 0.05)
	end

	self._janitor:Add(PlayerData.Currencies.Won.Observe(function(coins: number)
		animateNumber("Coins", currency.Coins, currency.Coins.Amount, coins)
	end))

	self._janitor:Add(PlayerData.Statistics.Wins.Observe(function(wins: number)
		animateNumber("Wins", currency.Wins, currency.Wins.Amount, wins)
	end))

	self._janitor:Add(PlayerData.Player.Streak.Observe(function(streak: number)
		local was = currency.Wins.Streak.Visible
		currency.Wins.Streak.Visible = streak > 0
		currency.Wins.Streak.Value.Text = tostring(streak)
		if streak > 0 and (was or streak == 1) then
			Juice.Pop(currency.Wins.Streak, 0.25)
		end
	end))
end

-- [[ Roll tickets / card upgrades: the coins wallet ]]

-- While you hold any wallet currency (Constants/Currencies.Wallet: roll tickets, card upgrades)
-- the coins card shows a "+n" tab (Coins.WalletTab); tapping it opens the Wallet card under it
-- (a row each, hidden at 0). Tap a row to use it (WALLET_USE). Claiming one never opens anything.
-- The card (and its shadow) is as tall as the rows showing; its top edge stays put.
local WALLET_USE = {
	Tickets = { "Roll", { Picker = true } }, -- Pick a Group
	Upgrades = { "Index", { Upgrade = true } }, -- the Index's card picker
}

function HUDController._bindExtras(self: Self)
	local topLeft = self._hud.TopLeft
	local tab = topLeft.Coins:FindFirstChild("WalletTab")
	local wallet = topLeft:FindFirstChild("Wallet")
	if not tab or not wallet then
		return
	end
	local shadow = topLeft:FindFirstChild("WalletShadow")
	local sink = topLeft:FindFirstChild("WalletSink")
	local open = false
	local shown: { [string]: number } = {}
	-- height = padding + header + one row per currency showing (from the Studio layout)
	local list = wallet:FindFirstChildOfClass("UIListLayout")
	local padding = wallet:FindFirstChildOfClass("UIPadding")
	local header = wallet:FindFirstChild("Header")
	local gap = if list then list.Padding.Offset else 4
	local function fit(rows: { GuiObject })
		local h = (if padding then padding.PaddingTop.Offset + padding.PaddingBottom.Offset else 0)
			+ (if header then header.Size.Y.Offset else 0)
		for _, row in rows do
			h += gap + row.Size.Y.Offset
		end
		-- keep the top edge where it is (Juice.Pop may have centred the anchor)
		local top = wallet.Position.Y.Offset - wallet.AnchorPoint.Y * wallet.Size.Y.Offset
		wallet.Size = UDim2.new(wallet.Size.X.Scale, wallet.Size.X.Offset, 0, h)
		wallet.Position = UDim2.new(wallet.Position.X.Scale, wallet.Position.X.Offset, wallet.Position.Y.Scale, top + wallet.AnchorPoint.Y * h)
		if shadow then
			shadow.Size = UDim2.new(shadow.Size.X.Scale, shadow.Size.X.Offset, 0, h)
		end
	end
	local function paint()
		local total = 0
		local rows = {}
		for _, currency in Currencies.Wallet do
			local key = currency.Id
			local n = Currencies.Count(LOCAL_PLAYER, key)
			local row = wallet:FindFirstChild(key)
			if not row then
				continue -- not built yet (SeasonController/Build.HUDExtras)
			end
			row.Visible = n > 0
			row.Count.Text = tostring(n)
			if n > 0 then
				table.insert(rows, row)
			end
			total += n
			if shown[key] and n > shown[key] then
				Juice.Pop(tab, 0.25) -- a new one landed
			end
			shown[key] = n
		end
		if total == 0 then
			open = false
		end
		fit(rows)
		tab.Visible = total > 0
		tab.Count.Text = `+{total}`
		tab.Chevron.Rotation = if open then 180 else 0
		wallet.Visible = open
		if shadow then
			shadow.Visible = open
		end
		if sink then
			sink.Visible = open -- swallows taps so the buttons under the wallet can't be pressed
		end
	end
	local function setOpen(on: boolean)
		open = on
		paint()
		if on then
			Juice.Pop(wallet, 0.08)
		end
	end
	paint()
	for _, currency in Currencies.Wallet do
		self._janitor:Add(LOCAL_PLAYER:GetAttributeChangedSignal(currency.Attribute):Connect(paint))
		local row = wallet:FindFirstChild(currency.Id)
		local use = WALLET_USE[currency.Id]
		if row and use then
			self._janitor:Add(row.Activated:Connect(function()
				setOpen(false)
				self:_open(use[1], use[2])
			end))
		end
	end
	self._janitor:Add(tab.Activated:Connect(function()
		setOpen(not open)
	end))
	self._closeWallet = function()
		if open then
			setOpen(false)
		end
	end
end

-- [[ Buttons ]]

function HUDController._open(self: Self, name: string, ...: any)
	-- the HUD is already on its way out (a screen like Queue is opening, e.g. you just stepped
	-- on a stage): a click now would queue up behind it and replace it, leaving you on the
	-- stage with only the HUD once that screen is closed
	if self._interface.Mode ~= "Gameplay" then
		return
	end
	if self._interface:GetController(name) then
		if self._nudges then
			self._nudges:Opened(name)
		end
		self._interface:Open(name, ...)
	else
		warn(`HUD: "{name}" screen has no controller yet`)
	end
end

-- the season card under Roll / UGC: season name, how much of it has gone, days left; opens
-- Season. It shows no rank on purpose.
function HUDController._bindSeason(self: Self)
	local card = self._hud.TopLeft:FindFirstChild("Season")
	if not card then
		return
	end
	-- seasons off: no card, so the Season screen can't be opened
	local shadow = self._hud.TopLeft:FindFirstChild("SeasonShadow")
	card.Visible = SeasonConstants.ENABLED
	if shadow then
		shadow.Visible = SeasonConstants.ENABLED
	end
	if not SeasonConstants.ENABLED then
		return
	end
	local function paint()
		local season = SeasonConstants.Current()
		local now = os.time()
		if season.Ends <= 0 then
			card.SeasonName.Text = "PRE-SEASON"
			card.Bar.Fill.Size = UDim2.fromScale(0, 1)
			card.Days.Text = "Season 1 soon"
			return
		end
		local span = math.max(1, season.Ends - season.Starts)
		local days = math.max(0, math.ceil((season.Ends - now) / 86400))
		card.SeasonName.Text = `SEASON {string.gsub(season.Badge, "%D", "")}`
		card.Bar.Fill.Size = UDim2.fromScale(math.clamp((now - season.Starts) / span, 0, 1), 1)
		card.Days.Text = if days == 1 then "1 day left" else `{days} days left`
	end
	paint()
	local ticker = task.spawn(function()
		while true do
			task.wait(60)
			paint()
		end
	end)
	self._janitor:Add(function()
		task.cancel(ticker)
	end, true)
	self._janitor:Add(card.Activated:Connect(function()
		self:_open("Season")
	end))
end

function HUDController._bindButtons(self: Self)
	local hud = self._hud
	local menu = hud.Menu

	self._janitor:Add(menu.QuickPlay.Activated:Connect(function()
		QueueRemote:Fire("QuickPlay")
	end))

	for tile, target in TILE_TARGETS do
		self._janitor:Add(menu.Tiles[tile].Activated:Connect(function()
			self:_open(target)
		end))
	end


	self._janitor:Add(hud.TopLeft.Coins.Buy.Activated:Connect(function()
		self:_open("Shop", "Coins")
	end))
	-- the two small buttons under the currencies: the song roll, and the group's UGC
	self._janitor:Add(hud.TopLeft.Roll.Activated:Connect(function()
		self:_open("Roll")
	end))
	self._janitor:Add(hud.TopLeft.UGC.Activated:Connect(function()
		hud.TopLeft.UGC.New.Visible = false -- the NEW sticker goes once you've looked
		self:_open("UGC")
	end))
	self._janitor:Add(hud.Buttons.News.Activated:Connect(function()
		self:_open("News")
	end))
	self._janitor:Add(hud.Buttons.Settings.Activated:Connect(function()
		self:_open("Settings")
	end))
end

-- [[ Static content ]]

function HUDController._applyStatic(self: Self)
	local hud = self._hud

	hud.Menu.Tiles.Shop.Sale.Visible = HUDConstants.SHOP_SALE
	self:SetRewardsBadge(self._rewardsBadge or 0)
end

-- Number of unclaimed rewards on the Rewards tile; 0 hides the badge. `earned`: how many of
-- them are level rewards / quests (the Rewards nudge waits for one of those).
function HUDController.SetRewardsBadge(self: Self, count: number, earned: number?)
	-- RewardsController can call this before the HUD has initialised: keep it for then
	self._rewardsBadge = count
	if earned ~= nil then
		self._rewardsEarned = earned
	end
	if self._nudges and self._rewardsEarned then
		self._nudges:RewardsEarned(self._rewardsEarned)
	end
	if not self._hud then
		return
	end
	local badge = self._hud.Menu.Tiles.Rewards.Badge
	badge.Visible = count > 0
	badge.Value.Text = if count > 9 then "9+" else tostring(count)
end

-- A short line over Quick Play (HUD.Menu.Toast), e.g. every stage is busy.
function HUDController.Toast(self: Self, message: string)
	local toast = self._hud and self._hud.Menu:FindFirstChild("Toast") :: TextLabel?
	if not toast then
		return
	end
	toast.Text = message
	toast.Visible = true
	Juice.SlideIn(toast, 24)
	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(2.6, function()
		if self._toastToken == token then
			toast.Visible = false
		end
	end)
end

-- [[ Lifecycle ]]

-- Slides the HUD groups in or out. Resting spots come from AutoScale (HomeX/HomeY).
function HUDController._slide(self: Self, show: boolean): any
	local hud = self._hud
	self._slideToken = (self._slideToken or 0) + 1
	local token = self._slideToken
	local last: Tween? = nil

	for name, offset in SLIDE do
		local group = hud:FindFirstChild(name) :: GuiObject?
		if group then
			-- groups AutoScale doesn't pin (Menu) rest where they were placed in Studio
			if group:GetAttribute("HomeX") == nil then
				group:SetAttribute("HomeX", group.Position.X.Offset)
				group:SetAttribute("HomeY", group.Position.Y.Offset)
			end
			group:SetAttribute("Hidden", not show)
			local home = UDim2.fromOffset(group:GetAttribute("HomeX") or 0, group:GetAttribute("HomeY") or 0)
			local away = home + UDim2.fromOffset(offset.X, offset.Y)
			if show and not hud.Visible then
				group.Position = away
			end
			last = TweenService:Create(group, if show then SLIDE_IN else SLIDE_OUT, { Position = if show then home else away })
			last:Play()
		end
	end

	if show then
		hud.Visible = true
		return Promise.resolve()
	elseif last then
		local tween = last
		return Promise.new(function(resolve)
			tween.Completed:Once(function()
				if self._slideToken == token then
					hud.Visible = false
				end
				resolve()
			end)
		end)
	else
		hud.Visible = false
		return Promise.resolve()
	end
end

-- Controller shortcuts in the lobby (Modules/UI/PadBinds): Y Quick Play, RB Shop, D-pad
-- ← Profile, ↑ Index, → Inventory, ↓ Rewards. A, B and X stay free: A jumps and X is the stage
-- prompt. Bound while the HUD is up.
function HUDController._bindPad(self: Self)
	if self._unpad then
		return
	end
	local menu = self._hud.Menu
	local tiles = menu.Tiles
	local function open(name: string)
		return function()
			self:_open(name)
		end
	end
	self._unpad = PadBinds.Bind("HUD", {
		{ Key = Enum.KeyCode.ButtonY, Chip = menu.QuickPlay, Run = function()
			QueueRemote:Fire("QuickPlay")
		end },
		{ Key = Enum.KeyCode.ButtonR1, Chip = tiles.Shop, Run = open("Shop") },
		{ Key = Enum.KeyCode.DPadLeft, Chip = tiles.Profile, Run = open("Profile") },
		{ Key = Enum.KeyCode.DPadUp, Chip = tiles.Index, Run = open("Index") },
		{ Key = Enum.KeyCode.DPadRight, Chip = tiles.Inventory, Run = open("Inventory") },
		{ Key = Enum.KeyCode.DPadDown, Chip = tiles.Rewards, Run = open("Rewards") },
	})
end

function HUDController.Activate(self: Self)
	self.State = "Active"
	self:_bindPad()
	return self:_slide(true)
end

-- Resolves once the HUD has finished sliding out.
function HUDController.Deactivate(self: Self)
	self.State = "Inactive"
	if self._unpad then
		self._unpad()
		self._unpad = nil
	end
	if self._closeWallet then
		self._closeWallet() -- a menu opened: the wallet folds away
	end
	return self:_slide(false)
end

function HUDController.Destroy(self: Self)
	self._janitor:Destroy()
	self._interface = nil
	self._hud = nil
end

return HUDController
