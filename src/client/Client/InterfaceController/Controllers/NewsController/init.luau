--| NewsController ("News")
-- The What's New card (Interface.Frames.News, built in Studio by ./Build from the "What's
-- New" boards). Updates come from Constants/News, newest first.
--   • On join it pops up once per update, LAST: after the loading screen, the tutorial (a
--     brand-new player sees it once they've finished it) and any other pop-up, once the
--     lobby has been quiet for QUIET seconds and the player isn't on a stage. It shows the
--     newest update with the big "Let's go!" button.
--   • The HUD News button opens it on the newest update with ‹ › to page back through
--     older ones (and a red dot until the newest has been seen).
--   Showing the newest marks it seen (Settings.NewsSeen, SettingsRemote "SeenNews").
--   Interface:Open("News")          -- from the News button
--   Interface:Open("News", "Join")  -- the pop-up on join (Open does nothing once seen)

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local News = require(ReplicatedStorage.Constants.News)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")
local LOCAL_PLAYER = Players.LocalPlayer
local C = Color3.fromHex
local UPDATES = News.Updates

-- the pop-up on join waits for the lobby to be this quiet (no screen open, not on a stage)
local QUIET = 2
-- and comes no sooner than this after the loading screen, so other join pop-ups go first
local JOIN_DELAY = 6

local INK = C("1E1B2E")
local GREY = C("D8D2C4")

-- ---------------------------------- Class --------------------------------- --
local NewsScreen = {}
NewsScreen.__index = NewsScreen

function NewsScreen.new()
	local self = setmetatable({}, NewsScreen)
	self.Name = "News"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._shown = Janitor.new() -- the rows + chips cloned for the update on screen
	self._index = 1
	self._mode = "Button" :: "Button" | "Join"
	return (self :: any) :: UITypes.Controller
end

-- an icon from Constants/News: a SeasonConstants.ICONS key, or an asset id as it is
local function icon(name: string?): string
	if type(name) ~= "string" or name == "" then
		return ""
	end
	return SeasonConstants.ICONS[name] or name
end

local function seenId(): string?
	local ok, seen = pcall(PlayerData.Settings.NewsSeen.Get)
	return if ok then seen else nil
end

local function unread(): boolean
	local newest = UPDATES[1]
	local seen = seenId()
	return newest ~= nil and seen ~= nil and seen ~= newest.Id
end

-- [[ Drawing ]]

function NewsScreen:_fillArt(update)
	local art = self._frame.Panel.Art
	local a = update.Art or {}
	local tint = ColorSequence.new(C(a.Top or "B9A6FF"), C(a.Bottom or "FF9EC4"))
	art.Tint.Color = tint
	art.Square.Tint.Color = tint
	local cards = art.Cards
	cards.Back.BackgroundColor3 = C(a.Back or "FFE07A")
	cards.Front.BackgroundColor3 = C(a.Front or "FAF6E9")
	cards.Front.Icon.Image = icon(a.Icon)
	cards.Version.Text = update.Version or ""
	cards.Version.Visible = update.Version ~= nil
	art.UpdateName.Text = update.Name or ""
	art.Date.Text = update.Date or ""

	-- codes: expired ones grey out and say so
	local codes = art.Codes
	local list = update.Codes or {}
	codes.Visible = #list > 0
	art.CodesShadow.Visible = #list > 0
	local now = os.time()
	for i, entry in list do
		local chip = codes.List.CodeTemplate:Clone()
		chip.Name = "Code" .. i
		chip.LayoutOrder = i
		local expired = type(entry.Expires) == "number" and now >= entry.Expires
		chip.Code.Text = entry.Code or ""
		chip.Reward.Text = if expired then "EXPIRED" else (entry.Reward or "")
		chip.Code.BackgroundColor3 = if expired then GREY else chip.Code.BackgroundColor3
		chip.Code.TextTransparency = if expired then 0.45 else 0
		chip.Reward.TextTransparency = if expired then 0.3 else 0
		chip.Visible = true
		chip.Parent = codes.List
		self._shown:Add(chip)
		-- a row sizes itself to its words, which on a phone (text rounded up after the canvas
		-- shrinks) can run past the card: shrink that row until it fits the list
		local fit = Instance.new("UIScale")
		fit.Name = "FitWidth"
		fit.Parent = chip
		local function fitRow()
			local avail = codes.List.AbsoluteSize.X
			local width = chip.AbsoluteSize.X / math.max(fit.Scale, 0.01) -- its unscaled width
			fit.Scale = if width > avail and avail > 0 then math.max(0.6, avail / width) else 1
		end
		task.defer(fitRow)
		self._shown:Add(chip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			task.defer(fitRow)
		end))
	end
end

function NewsScreen:_fillList(update)
	local list = self._frame.Panel.List
	list.CanvasPosition = Vector2.zero
	for i, f in update.Featured or {} do
		local row = list.FeatureTemplate:Clone()
		row.Name = "Feature" .. i
		row.LayoutOrder = 10 + i
		row.Face.IconBox.BackgroundColor3 = C(f.Colour or "B9A6FF")
		row.Face.IconBox.Icon.Image = icon(f.Icon)
		row.Face.Title.Text = f.Title or ""
		row.Face.Body.Text = f.Body or ""
		row.Visible = true
		row.Parent = list
		self._shown:Add(row)
	end
	local also = update.Also or {}
	list.AlsoHeader.Visible = #also > 0
	for i, a in also do
		local line = list.AlsoTemplate:Clone()
		line.Name = "Also" .. i
		line.LayoutOrder = 60 + i
		line.Tag.Text = a.Tag or "NEW"
		line.Tag.BackgroundColor3 = C(News.TAG_COLOURS[a.Tag or "NEW"] or "FFE07A")
		line.Text.Text = a.Text or ""
		line.Visible = true
		line.Parent = list
		self._shown:Add(line)
	end
end

function NewsScreen:_fillPager()
	local f = self._frame
	local pager = f.Panel.Art.Pager
	local paging = self._mode == "Button" and #UPDATES > 1
	pager.Visible = paging
	f.Count.Visible = paging
	f.Ok.Visible = self._mode == "Join"
	f.OkShadow.Visible = self._mode == "Join"
	if not paging then
		return
	end
	f.Count.Text = `Update {#UPDATES - self._index + 1} of {#UPDATES}`
	local older, newer = self._index < #UPDATES, self._index > 1
	pager.Prev.Active, pager.Next.Active = older, newer
	pager.Prev.TextTransparency = if older then 0 else 0.6
	pager.Next.TextTransparency = if newer then 0 else 0.6
	-- dots oldest → newest, left to right, the one on screen filled
	for i = #UPDATES, 1, -1 do
		local dot = pager.Dots.DotTemplate:Clone()
		dot.Name = "Dot" .. i
		dot.LayoutOrder = #UPDATES - i + 1
		local on = i == self._index
		dot.Size = if on then UDim2.fromOffset(14, 14) else UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = if on then INK else dot.BackgroundColor3
		dot.Visible = true
		dot.Parent = pager.Dots
		self._shown:Add(dot)
	end
end

function NewsScreen:_show(index: number)
	self._index = math.clamp(index, 1, math.max(1, #UPDATES))
	self._shown:Cleanup()
	local update = UPDATES[self._index]
	if not update then
		return
	end
	self:_fillArt(update)
	self:_fillList(update)
	self:_fillPager()
	-- the newest on screen counts as read
	if self._index == 1 then
		SettingsRemote:Fire({ Action = "SeenNews", Id = update.Id })
		local dot = self:_hudDot()
		if dot then
			dot.Visible = false
		end
	end
end

function NewsScreen:_page(step: number)
	local to = self._index + step
	if to < 1 or to > #UPDATES then
		return
	end
	Sounds.Play("Click")
	self:_show(to)
	local panel = self._frame.Panel
	Juice.Pop(panel.Art.Cards, 0.12)
end

-- [[ Unread dot on the HUD ]]

function NewsScreen:_hudDot(): GuiObject?
	local gui = LOCAL_PLAYER:FindFirstChild("PlayerGui")
	local interface = gui and gui:FindFirstChild("Interface")
	local hud = interface and interface:FindFirstChild("HUD")
	local button = hud and hud:FindFirstChild("Buttons") and hud.Buttons:FindFirstChild("News")
	return button and button:FindFirstChild("Dot")
end

function NewsScreen:_updateDot()
	local dot = self:_hudDot()
	if not dot then
		return
	end
	local on = unread()
	if on and not dot.Visible then
		dot.Visible = true
		Juice.Pop(dot, 0.4)
	elseif not on then
		dot.Visible = false
	end
end

-- [[ The pop-up on join ]]

-- Waits for the right moment, then opens the newest update if it hasn't been seen: after
-- the loading screen, after the tutorial, and once nothing else has been open (and the
-- player hasn't been on a stage) for QUIET seconds, so every other join pop-up goes first.
function NewsScreen:_joinPopup()
	local deadline = os.clock() + 60
	while not LOCAL_PLAYER:GetAttribute("LoadingDone") and os.clock() < deadline do
		task.wait(0.25)
	end
	task.wait(JOIN_DELAY)
	-- the player's data (NewsSeen, TutorialDone) has to be there to know anything
	while seenId() == nil do
		task.wait(0.5)
	end
	if not unread() then
		return
	end
	local quietSince = os.clock()
	while true do
		task.wait(0.5)
		if not unread() then
			return -- opened from the News button meanwhile
		end
		local okTut, onboard = pcall(PlayerData.Settings.Onboard.Get)
		local tutorialDone = onboard == "Done" -- (the onboarding, TutorialController/Flow)
		local busy = self._interface.ActiveController ~= nil
			or self._interface.Mode ~= "Gameplay"
			or LOCAL_PLAYER:GetAttribute("Stage") ~= nil
			or not (okTut and tutorialDone)
		if busy then
			quietSince = os.clock()
		elseif os.clock() - quietSince >= QUIET then
			self._interface:Open(self.Name, "Join")
			return
		end
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function NewsScreen:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "News")
	self._frame.Visible = false
	local f = self._frame
	local pager = f.Panel.Art.Pager
	for _, b in { f.Close, f.Ok, pager.Prev, pager.Next } do
		ButtonScale.Apply(b)
	end
	local j = self._janitor
	j:Add(self._shown, "Destroy")

	j:Add(f.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(f.Ok.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Close(self.Name)
	end))
	j:Add(pager.Prev.Activated:Connect(function()
		self:_page(1) -- older
	end))
	j:Add(pager.Next.Activated:Connect(function()
		self:_page(-1) -- newer
	end))

	j:Add(PlayerData.Settings.NewsSeen.Observe(function()
		self:_updateDot()
	end))
	task.defer(function()
		self:_updateDot()
	end)
	j:Add(task.spawn(function()
		self:_joinPopup()
	end))
end

function NewsScreen:Activate(mode: string?)
	self._mode = if mode == "Join" then "Join" else "Button"
	self._frame.Visible = true
	self:_show(1)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local f = self._frame
	Juice.Stagger({ f.StickerShadow, f.Sticker, f.Panel.Art.Cards }, 0.04)
	if self._mode == "Join" then
		Juice.Pop(f.Ok, 0.3)
	end
	return FrameTransition.Open(f):andThen(function()
		self.State = "Active"
	end)
end

function NewsScreen:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function NewsScreen:Destroy()
	self._janitor:Destroy()
end

return NewsScreen
