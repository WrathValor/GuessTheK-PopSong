-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Levels = require(ReplicatedStorage.Modules.Levels)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Effects = require(script.Effects)

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
	self:_applyStatic()
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
			label.Text = commas(value)
			return
		end
		Juice.CountUp(label, old, value, commas)
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

-- [[ Buttons ]]

function HUDController._open(self: Self, name: string, ...: any)
	if self._interface:GetController(name) then
		self._interface:Open(name, ...)
	else
		warn(`HUD: "{name}" screen has no controller yet`)
	end
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

	self._janitor:Add(menu.Tiles.Invite.Activated:Connect(function()
		task.spawn(function()
			local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, LOCAL_PLAYER)
			if ok and canInvite then
				pcall(SocialService.PromptGameInvite, SocialService, LOCAL_PLAYER)
			end
		end)
	end))

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

-- Number of unclaimed rewards on the Rewards tile; 0 hides the badge.
function HUDController.SetRewardsBadge(self: Self, count: number)
	-- RewardsController can call this before the HUD has initialised: keep it for then
	self._rewardsBadge = count
	if not self._hud then
		return
	end
	local badge = self._hud.Menu.Tiles.Rewards.Badge
	badge.Visible = count > 0
	badge.Value.Text = if count > 9 then "9+" else tostring(count)
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

function HUDController.Activate(self: Self)
	self.State = "Active"
	return self:_slide(true)
end

-- Resolves once the HUD has finished sliding out.
function HUDController.Deactivate(self: Self)
	self.State = "Inactive"
	return self:_slide(false)
end

function HUDController.Destroy(self: Self)
	self._janitor:Destroy()
	self._interface = nil
	self._hud = nil
end

return HUDController
