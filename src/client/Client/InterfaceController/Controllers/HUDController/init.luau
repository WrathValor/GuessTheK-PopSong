-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local EventRsvp = require(ReplicatedStorage.Modules.EventRsvp)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local CardDecor = require(ReplicatedStorage.Modules.UI.CardDecor)
local Levels = require(ReplicatedStorage.Modules.Levels)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Notify = require(ReplicatedStorage.Modules.UI.Notify)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local Upgrades = require(ReplicatedStorage.Modules.Library.Upgrades)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Ladders = require(ReplicatedStorage.Modules.Library.Ladders)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Effects = require(script.Effects)
local Nudges = require(script.Nudges)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local BinderRemote = Bridgenet.ReferenceBridge("BinderRemote")

local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Slide-out when a menu opens: each corner group leaves through its nearest edge.
local SLIDE = {
	TopLeft = Vector2.new(-480, 0),
	BottomLeft = Vector2.new(-480, 0),
	Buttons = Vector2.new(480, 0),
	Menu = Vector2.new(0, 340),
	TopCenter = Vector2.new(0, -260), -- the server restart banner (RestartController)
}
local SLIDE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local SLIDE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Frames opened by the HUD buttons. Missing controllers are skipped with a warning, so
-- buttons start working as soon as the matching controller is added.
-- (v3 layout, HUDController/BuildV3: the left column in TopLeft, Profile + Gifts in Buttons)
local TILE_TARGETS = {
	Shop = "Shop",
	Binder = "Binder",
	Packs = "Albums",
	Quests = "Rewards",
	Daily = "DailyLogin",
	Market = "Market",
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
	-- a "Not enough coins" notification's button opens the Shop's coins
	Notify.OnGetCoins(function()
		self:_open("Shop", "Coins")
	end)

	self:_bindXP()
	self:_bindCurrency()
	self:_bindButtons()
	self:_bindSeason()
	self:_bindEvent()
	-- (the active boost potions are off the v3 HUD: BottomLeft is hidden, Boosts isn't started)
	self:_bindExtras()
	self:_bindKPopped()
	self:_applyStatic()
	-- one-time lobby hints: Packs once you can afford one, Rewards once one's earned
	self._nudges = Nudges.new(hud, self._janitor, self._interface)
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
-- Menu.XPBar, under Quick Play: "LEVEL 7 [620/1,000]", the fill tweening to the level's progress.
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

-- [[ Coins ]]
-- Menu.Coins: the amount + coin on the dark band over Quick Play (tap: Shop › Coins)

function HUDController._bindCurrency(self: Self)
	local band = self._hud.Menu.Coins

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
		animateNumber("Coins", band, band.Amount, coins)
	end))
end

-- [[ Roll tickets: the coins wallet ]]

-- The coins card always shows its wallet tab (Coins.WalletTab, SeasonController/Build.WalletTab):
-- each wallet currency's icon + count (Constants/Currencies.Wallet: roll tickets; 0 too, "99+"
-- past 99). Tapping it opens the Wallet card under it (a row each, hidden at 0);
-- with nothing to use the tab just shakes. Tap a row to use it (WALLET_USE). Claiming one never
-- opens anything.
-- The card (and its shadow) is as tall as the rows showing; its top edge stays put.
local WALLET_USE = {
	Tickets = { "Albums", { Page = "Shop" } }, -- a ticket opens a pack
}

-- a wallet count as shown: "99+" past 99 (the tab has room for two digits each)
local function capped(n: number): string
	return if n > 99 then "99+" else tostring(n)
end

function HUDController._bindExtras(self: Self)
	local topLeft = self._hud.TopLeft
	-- (the v3 HUD has no coins card, so no wallet: tickets show in Packs and the Shop)
	if not topLeft:FindFirstChild("Coins") then
		return
	end
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
			row.Count.Text = tostring(n) -- (exact here: the open wallet has the room)
			local chip = tab:FindFirstChild(key)
			if chip then
				chip.Count.Text = capped(n)
			end
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
		tab.Visible = true
		local count = tab:FindFirstChild("Count") -- (the old "+n" tab, before Build.WalletTab)
		if count then
			count.Text = `+{total}`
		end
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
		local total = 0
		for _, currency in Currencies.Wallet do
			total += Currencies.Count(LOCAL_PLAYER, currency.Id)
		end
		if total == 0 then
			Juice.Shake(tab, 0.6) -- nothing to use yet
			return
		end
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

-- the season card under the coins card: season name, how much of it has gone, days left; opens
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

-- the event button under the season card (in its slot while seasons are off), for whichever
-- Roblox event Configs points at (Constants/EventConstants, Modules/EventRsvp). Before the
-- event: white, the event's icon and title, "in 14d" + NEW, and a tap opens Roblox's sign-up. Once the
-- player is going it hides. While live it shows only if EventConstants.EVENTS[id].Live says
-- what to open (pale blue, yellow tile). Hidden when there's no event or it's over.
function HUDController._bindEvent(self: Self)
	local topLeft = self._hud.TopLeft
	-- (top right in the K-POPPED! layout, under your bias)
	local group = if self._hud.Buttons:FindFirstChild("Event") then self._hud.Buttons else topLeft
	local card = group:FindFirstChild("Event")
	if not card then
		return
	end
	local shadow = group:FindFirstChild("EventShadow")
	if not SeasonConstants.ENABLED and group == topLeft then
		local season, seasonShadow = topLeft:FindFirstChild("Season"), topLeft:FindFirstChild("SeasonShadow")
		if season then
			card.Position = season.Position
		end
		if shadow and seasonShadow then
			shadow.Position = seasonShadow.Position
		end
	end
	local WHITE = card.BackgroundColor3
	local TILE = card.Tile.BackgroundColor3
	local SUB = card.Sub.TextColor3
	local LIVE_BG, LIVE_TILE, INK = Color3.fromHex("DCEFF9"), Color3.fromHex("FFE07A"), Color3.fromHex("1E1B2E")
	local info: EventRsvp.Info? = nil

	local function show(on: boolean)
		card.Visible = on
		if shadow then
			shadow.Visible = on
		end
	end
	local function paint()
		local phase = info and EventRsvp.Phase(info)
		if info then
			card.Tile.Icon.Image = info.Icon
		end
		if info and phase == "Before" and not info.Going then
			show(true)
			card.BackgroundColor3 = WHITE
			card.Tile.BackgroundColor3 = TILE
			card.Title.Text = info.Title
			card.Sub.Text = `in {EventRsvp.Countdown(info)}`
			card.Sub.TextColor3 = SUB
			card.New.Visible = true
		elseif info and phase == "Live" and info.Live then
			show(true)
			card.BackgroundColor3 = LIVE_BG
			card.Tile.BackgroundColor3 = LIVE_TILE
			card.Title.Text = info.Live.Name
			card.Sub.Text = "Open"
			card.Sub.TextColor3 = INK
			card.New.Visible = false
		else
			show(false)
		end
	end
	-- Roblox's answer can take a moment: hidden until it's in
	local function refresh()
		info = EventRsvp.Info()
		paint()
	end
	show(false)
	task.spawn(refresh)
	self._janitor:Add(EventRsvp.Changed:Connect(function()
		task.spawn(refresh)
	end))
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
		if not info then
			return
		end
		local phase = EventRsvp.Phase(info)
		if phase == "Live" and info.Live then
			self:_open(info.Live.Opens)
		elseif phase == "Before" then
			task.spawn(EventRsvp.Prompt)
		end
	end))
end

function HUDController._bindButtons(self: Self)
	local hud = self._hud
	local menu = hud.Menu

	self._janitor:Add(menu.QuickPlay.Activated:Connect(function()
		QueueRemote:Fire("QuickPlay")
	end))

	for tile, target in TILE_TARGETS do
		self._janitor:Add(hud.TopLeft[tile].Activated:Connect(function()
			self:_open(target)
		end))
	end
	-- Gifts: the inbox (GiftsController); the red count is how many are waiting to be claimed
	local gifts = hud.Buttons:FindFirstChild("Gifts")
	if gifts then
		self._janitor:Add(gifts.Activated:Connect(function()
			self:_open("Gifts")
		end))
		local count = gifts:FindFirstChild("Count")
		if count then
			self._janitor:Add(PlayerData.Inventory.Gifts.Observe(function(map)
				local n = 0
				for _ in (if type(map) == "table" then map else {}) do
					n += 1
				end
				local was = count.Visible
				count.Visible = n > 0
				count.Text = if n > 9 then "9+" else tostring(n)
				if n > 0 and not was then
					Juice.Pop(count, 0.3)
				end
			end))
		end
	end
	self._janitor:Add(menu.Coins.Activated:Connect(function()
		self:_open("Shop", "Coins")
	end))
	-- the group's UGC (top right in the K-POPPED! layout)
	local ugc = hud.Buttons:FindFirstChild("UGC") or hud.TopLeft:FindFirstChild("UGC")
	if ugc then
		self._janitor:Add(ugc.Activated:Connect(function()
			ugc.New.Visible = false -- the NEW sticker goes once you've looked
			self:_open("UGC")
		end))
	end
	local profile = hud.Buttons:FindFirstChild("Profile")
	if profile then
		self._janitor:Add(profile.Activated:Connect(function()
			self:_open("Profile")
		end))
	end
	self._janitor:Add(hud.Buttons.News.Activated:Connect(function()
		self:_open("News")
	end))
	self._janitor:Add(hud.Buttons.Settings.Activated:Connect(function()
		self:_open("Settings")
	end))
end

-- [[ K-POPPED!: the Binder card, your bias, the Packs / Binder badges ]]
-- (HUDController/BuildKPopped made them; a HUD without them is skipped)

local function rate(n: number): string
	return if n % 1 == 0 then ShopCatalog.Format(n) else string.format("%.1f", n)
end

function HUDController._bindKPopped(self: Self)
	local hud = self._hud
	-- (v3: the Binder card and bias are off the HUD; the Binder tile shows the coins waiting)
	local card = nil :: any
	local biasButton = hud.Buttons:FindFirstChild("Bias")
	local tiles = hud.TopLeft
	local packs, binderTile = tiles:FindFirstChild("Packs"), tiles:FindFirstChild("Binder")
	local collecting = false

	local function cards(): { [string]: number }
		return PlayerData.Inventory.Cards.Get() or {}
	end
	local function waiting(): (number, number)
		local lv = Upgrades.Levels(PlayerData)
		local r = Albums.Rate(cards(), PlayerData.Inventory.Bias.Get(), PlayerData.Inventory.Pins.Get(), Albums.Boost(PlayerData.GamePasses, lv), lv)
		local coins = Albums.Waiting(PlayerData.Rewards.BinderBank.Get() or 0, PlayerData.Rewards.BinderAt.Get() or os.time(), r, os.time(), nil, lv)
		return coins, r
	end

	-- the Binder card: coins waiting, the rate from your pins, the pins as tiny cards
	local function fillBinder()
		if not card then
			return
		end
		local coins, r = waiting()
		card.Label.Text = `BINDER · {rate(r)}/HR`
		card.Amount.Text = `+{ShopCatalog.Format(coins)}`
		card.Collect.BackgroundColor3 = if coins >= 1 then Color3.fromHex("FFE07A") else Color3.fromHex("E9E2CF")
	end
	local function fillPins()
		if not card then
			return
		end
		local owned = cards()
		local list = Albums.Pins(PlayerData.Inventory.Pins.Get())
		local slots = Albums.PinSlots(Upgrades.Levels(PlayerData))
		for i = 1, AlbumConstants.PIN_SLOTS_MAX do
			local slot = card.Pins:FindFirstChild("Pin" .. i)
			if not slot then
				continue
			end
			local id = list[i]
			local info = if i <= slots and id and (owned[id] or 0) > 0 then Albums.Card(id) else nil
			slot.Art.Visible = info ~= nil
			slot.Empty.Visible = info == nil
			CardDecor.PaintMini(slot, if info then id else nil) -- the rarity's frame
			if info then
				slot.Art.Image = info.Member.Art or ""
				slot.Art.BackgroundColor3 = Color3.fromHex(info.Album.Colour or "FFD2E5")
				slot.UIStroke.Transparency = 0
			else
				slot.Empty.Mark.Text = if i > slots then "" else "+"
				slot.UIStroke.Transparency = if i > slots then 0.7 else 0.35
			end
		end
	end
	-- your bias: their card art from your best owned card of them (else the newest album's)
	local function fillBias()
		if not biasButton then
			return
		end
		local artist, memberKey = Albums.BiasParts(PlayerData.Inventory.Bias.Get())
		local albums = artist and Albums.PullAlbums(artist) or {}
		local member, art = nil, ""
		for i = #albums, 1, -1 do
			local m = Albums.Member(albums[i], memberKey :: string)
			if m then
				member = member or m
				if art == "" and (m.Art or "") ~= "" then
					art = m.Art
				end
			end
		end
		if member then
			biasButton.Label.Text = "MY BIAS"
			biasButton.Member.Text = `{string.upper(member.Name)} <font color="#FF5A4E">♥</font>`
			biasButton.Group.Text = artist
			biasButton.Bonus.Visible = true
			biasButton.Bonus.Text = `{AlbumConstants.BIAS_PULL_WEIGHT}× PULLS · {AlbumConstants.BIAS_EARN}× COINS`
		else
			biasButton.Label.Text = "NO BIAS YET"
			biasButton.Member.Text = "PICK ONE"
			biasButton.Group.Text = "Their cards come 2× as often"
			biasButton.Bonus.Visible = false
		end
		biasButton.Card.Art.Image = art
	end
	-- the badges: free packs ready on Packs (the red count), coins waiting on the Binder ("+412")
	local function fillBadges()
		if packs and packs:FindFirstChild("Count") then
			local free = Albums.FreePacks(PlayerData.Inventory.FreePacks.Get() or 0, PlayerData.Inventory.FreePackAt.Get() or 0, os.time(), Upgrades.Levels(PlayerData))
			packs.Count.Visible = free > 0
			packs.Count.Text = if free > 9 then "9+" else tostring(free)
		end
		if binderTile and binderTile:FindFirstChild("Waiting") then
			local coins = waiting()
			binderTile.Waiting.Visible = coins >= 1
			binderTile.Waiting.Text = `+{ShopCatalog.Format(coins)}`
		end
	end

	local function all()
		fillBinder()
		fillPins()
		fillBias()
		fillBadges()
	end
	for _, field in { PlayerData.Inventory.Cards, PlayerData.Inventory.Pins, PlayerData.Inventory.Bias, PlayerData.Inventory.FreePacks, PlayerData.Rewards.BinderAt } do
		self._janitor:Add(field.Observe(all))
	end
	-- the coins waiting tick up; the free-pack clock refills
	local ticker = task.spawn(function()
		while true do
			task.wait(1)
			fillBinder()
			fillBadges()
		end
	end)
	self._janitor:Add(function()
		task.cancel(ticker)
	end, true)

	if card then
		self._janitor:Add(card.Activated:Connect(function()
			self:_open("Binder")
		end))
		self._janitor:Add(card.Collect.Activated:Connect(function()
			if collecting then
				return
			end
			if (waiting()) < 1 then
				Sounds.Play("Wrong")
				Juice.Shake(card.Collect)
				self:Toast(if #Albums.Pins(PlayerData.Inventory.Pins.Get()) == 0 then "Pin cards in your binder to earn coins" else "Nothing to collect yet")
				return
			end
			collecting = true
			Sounds.Play("Click")
			BinderRemote:Fire({ Action = "Collect" })
		end))
	end
	if biasButton then
		self._janitor:Add(biasButton.Activated:Connect(function()
			self:_open("Albums", { Page = "Bias" })
		end))
	end
	self._janitor:Add(BinderRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Binder" then
			return
		end
		if packet.Action == "Collect" and collecting then
			collecting = false
			if packet.Ok then
				Sounds.Play("Coins")
				if card then
					Juice.Pop(card, 0.1)
				end
			end
			fillBinder()
		elseif packet.Action == "SetBonus" and self.State == "Active" and type(packet.Albums) == "table" then
			local album = Albums.Get(packet.Albums[1])
			self:Toast(`{album and album.Name or "Album"} complete! +{ShopCatalog.Format(packet.Coins or 0)} coins`)
		elseif packet.Action == "Badge" and type(packet.Badges) == "table" and packet.Badges[1] then
			-- group badge rungs reached (Engine/LadderService), best first
			local best = packet.Badges[1]
			local label = Ladders.Label(best.Ladder, best.Artist, best.Rung)
			local more = #packet.Badges - 1
			local text = `New badge: {label}!`
			if more > 0 then
				text ..= ` (+{more} more)`
			end
			if (packet.Coins or 0) > 0 then
				text ..= ` +{ShopCatalog.Format(packet.Coins)} coins`
			end
			self._badgeToast = text -- (shown once the lobby is back, if a screen's open now)
			if self.State == "Active" then
				Notify.Toast(text, { Kind = "Notify" })
				self._badgeToast = nil
			end
		end
	end), "Disconnect")
	all()
end

-- [[ Static content ]]

function HUDController._applyStatic(self: Self)
	local hud = self._hud

	hud.TopLeft.Shop.Sale.Visible = HUDConstants.SHOP_SALE
	self:SetRewardsBadge(self._rewardsBadge or 0)
	self:SetDailyBadge(self._dailyReady or false)
end

-- Number of unclaimed rewards on the Quests tile (the daily login has its own, SetDailyBadge);
-- 0 hides the badge. `earned`: how many of them are level rewards / quests (the Rewards nudge
-- waits for one of those).
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
	local badge = self._hud.TopLeft.Quests.Count
	local n = math.max(0, count - (if self._dailyReady then 1 else 0))
	badge.Visible = n > 0
	badge.Text = if n > 9 then "9+" else tostring(n)
end

-- Today's login reward waiting: the red 1 on Daily Rewards (RewardsController keeps it right).
function HUDController.SetDailyBadge(self: Self, ready: boolean)
	self._dailyReady = ready
	if not self._hud then
		return
	end
	local badge = self._hud.TopLeft.Daily.Count
	badge.Visible = ready
	badge.Text = "1"
	self:SetRewardsBadge(self._rewardsBadge or 0)
end

-- A one-line notification (Modules/UI/Notify), e.g. every stage is busy. opts as Notify.Toast.
function HUDController.Toast(self: Self, message: string, opts: any?)
	Notify.Toast(message, opts)
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
			-- a group AutoScale doesn't pin rests where it was placed in Studio
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
-- ← Binder, ↑ Packs, → Daily Rewards, ↓ Quests. A, B and X stay free: A jumps and X is the stage
-- prompt. Bound while the HUD is up.
function HUDController._bindPad(self: Self)
	if self._unpad then
		return
	end
	local menu = self._hud.Menu
	local tiles = self._hud.TopLeft
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
		{ Key = Enum.KeyCode.DPadLeft, Chip = tiles.Binder, Run = open("Binder") },
		{ Key = Enum.KeyCode.DPadUp, Chip = tiles.Packs, Run = open("Albums") },
		{ Key = Enum.KeyCode.DPadRight, Chip = tiles.Daily, Run = open("DailyLogin") },
		{ Key = Enum.KeyCode.DPadDown, Chip = tiles.Quests, Run = open("Rewards") },
	})
end

function HUDController.Activate(self: Self)
	self.State = "Active"
	self:_bindPad()
	-- a badge reached while a screen was up (a duel's stars): say so now
	local badge = self._badgeToast
	if badge then
		self._badgeToast = nil
		task.delay(0.6, function()
			Notify.Toast(badge, { Kind = "Notify" })
		end)
	end
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
