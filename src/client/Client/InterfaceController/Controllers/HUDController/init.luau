-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Levels = require(ReplicatedStorage.Modules.Levels)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TITLE_PADDING = 14 -- horizontal padding inside the title chip
local TITLE_MIN_WIDTH = 34

-- Slide-out when a menu opens: each corner group leaves through its nearest edge.
local SLIDE = {
	TopLeft = Vector2.new(-480, 0),
	Currency = Vector2.new(480, 0),
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

	self:_bindProfile()
	self:_bindCurrency()
	self:_bindButtons()
	self:_applyStatic()

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

-- [[ Profile card ]]

function HUDController._bindProfile(self: Self)
	local profile = self._hud.Currency.Profile

	-- "Name" clashes with Instance.Name, so look the label up explicitly.
	local nameLabel = profile:FindFirstChild("Name") :: TextLabel
	nameLabel.Text = LOCAL_PLAYER.DisplayName
	task.spawn(function()
		local ok, image = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			LOCAL_PLAYER.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		if ok then
			profile.Avatar.Thumbnail.Image = image
		end
	end)

	self._janitor:Add(PlayerData.Player.XP.Observe(function(xp: number)
		self:SetXP(xp)
	end))

	self._janitor:Add(PlayerData.Inventory.Title.Observe(function(title: string)
		self:SetTitle(if title ~= "" then title else HUDConstants.DEFAULT_TITLE)
	end))
end

function HUDController.SetXP(self: Self, totalXP: number)
	local profile = self._hud.Currency.Profile
	local level, into, need = Levels.FromXP(totalXP)

	profile.Level.Value.Text = tostring(level)
	profile.XPLabel.Text = `{commas(into)} / {commas(need)} XP · Lv {level}`

	local fill = profile.XPBar.Fill
	TweenService:Create(fill, FILL_TWEEN, {
		Size = UDim2.new(math.clamp(into / need, 0, 1), 0, 1, 0),
	}):Play()
end

function HUDController.SetTitle(self: Self, title: string)
	local chip = self._hud.Currency.Profile.Title
	local label = chip.Label
	label.Text = title
	label.Size = UDim2.fromScale(1, 1)

	task.spawn(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = title
		params.Font = label.FontFace
		params.Size = label.TextSize
		params.Width = math.huge
		local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
		if ok and label.Text == title then
			chip.Size = UDim2.fromOffset(math.max(TITLE_MIN_WIDTH, math.ceil(bounds.X) + TITLE_PADDING), chip.Size.Y.Offset)
		end
	end)
end

-- [[ Coins / wins ]]

function HUDController._bindCurrency(self: Self)
	local currency = self._hud.TopLeft

	self._janitor:Add(PlayerData.Currencies.Won.Observe(function(coins: number)
		currency.Coins.Amount.Text = commas(coins)
	end))

	self._janitor:Add(PlayerData.Statistics.Wins.Observe(function(wins: number)
		currency.Wins.Amount.Text = commas(wins)
	end))

	self._janitor:Add(PlayerData.Player.Streak.Observe(function(streak: number)
		currency.Wins.Streak.Visible = streak > 0
		currency.Wins.Streak.Value.Text = tostring(streak)
	end))
end

-- [[ Buttons ]]

function HUDController._open(self: Self, name: string)
	if self._interface:GetController(name) then
		self._interface:Open(name)
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
		self:_open("Shop")
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

	self:SetNewDrop(HUDConstants.NEW_DROP)
	hud.Menu.Tiles.Shop.Sale.Visible = HUDConstants.SHOP_SALE
	self:SetRewardsBadge(0)
end

-- Text under "NEW DROP"; nil hides the card.
function HUDController.SetNewDrop(self: Self, text: string?)
	local topLeft = self._hud.TopLeft
	local visible = text ~= nil
	topLeft.NewDrop.Visible = visible
	topLeft.NewDropShadow.Visible = visible
	if text then
		topLeft.NewDrop.Body.Text = text
	end
end

-- Number of unclaimed rewards on the Rewards tile; 0 hides the badge.
function HUDController.SetRewardsBadge(self: Self, count: number)
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
