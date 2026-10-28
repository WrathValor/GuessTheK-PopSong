--| NewsController ("News")
-- The update log (Interface.Frames.News, built by ./Build from the "News" board). Entries
-- come from Constants/News: the newest fills the big card, the rest page through "Earlier"
-- three at a time. The HUD News button shows a red dot until the newest entry has been
-- opened (Settings.NewsSeen, saved through SettingsRemote "SeenNews").

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local News = require(ReplicatedStorage.Constants.News)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")
local C = Color3.fromHex
local PER_PAGE = Build.PER_PAGE

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
	self._page = 1
	return (self :: any) :: UITypes.Controller
end

local function tagColour(tag: string?): Color3
	return C(News.TAG_COLOURS[tag or "NEW"] or "FFE07A")
end

-- [[ Drawing ]]

function NewsScreen:_fillLatest()
	local entry = News.Entries[1]
	local card = self._frame.Panel.Latest
	card.Visible = entry ~= nil
	self._frame.Panel.LatestShadow.Visible = entry ~= nil
	if not entry then
		return
	end
	local art = card.Art
	art.BackgroundColor3 = C(entry.Colour or "B9A6FF")
	art.Image.Visible = entry.Image ~= nil
	art.Image.Image = entry.Image or ""
	art.Card1.Visible = entry.Image == nil
	art.Card2.Visible = entry.Image == nil
	card.Meta.Version.Visible = entry.Version ~= nil
	card.Meta.Version.Text = entry.Version or ""
	card.Meta.Date.Text = entry.Date or ""
	card.Title.Text = entry.Title or ""
	card.Body.Text = entry.Body or ""
	local tags = entry.Tags or {}
	for i = 1, Build.MAX_TAGS do
		local chip = card.Tags["Tag" .. i]
		chip.Visible = tags[i] ~= nil
		chip.Text = tags[i] or ""
	end
end

function NewsScreen:_pages(): number
	return math.max(1, math.ceil((#News.Entries - 1) / PER_PAGE))
end

function NewsScreen:_fillEarlier()
	local earlier = self._frame.Panel.Earlier
	local pages = self:_pages()
	self._page = math.clamp(self._page, 1, pages)
	earlier.Prev.Visible = pages > 1
	earlier.Next.Visible = pages > 1
	earlier.Prev.Active = self._page > 1
	earlier.Next.Active = self._page < pages
	earlier.Prev.TextTransparency = if self._page > 1 then 0 else 0.6
	earlier.Next.TextTransparency = if self._page < pages then 0 else 0.6
	earlier.Empty.Visible = #News.Entries <= 1
	for i = 1, PER_PAGE do
		local entry = News.Entries[1 + (self._page - 1) * PER_PAGE + i]
		local item = earlier["Item" .. i]
		item.Visible = entry ~= nil
		earlier["Item" .. i .. "Shadow"].Visible = entry ~= nil
		if entry then
			item.IconBox.BackgroundColor3 = C(entry.Colour or "B9A6FF")
			item.IconBox.Glyph.Text = entry.Glyph or "★"
			item.TagRow.Tag.Text = entry.Tag or "NEW"
			item.TagRow.Tag.BackgroundColor3 = tagColour(entry.Tag)
			item.TagRow.Date.Text = entry.Date or ""
			item.Title.Text = entry.Title or ""
			item.Body.Text = entry.Body or ""
		end
	end
end

function NewsScreen:_animateEarlier()
	local earlier = self._frame.Panel.Earlier
	local list = {}
	for i = 1, PER_PAGE do
		table.insert(list, earlier["Item" .. i .. "Shadow"])
		table.insert(list, earlier["Item" .. i])
	end
	Juice.Stagger(list, 0.04)
end

-- [[ Unread dot on the HUD ]]

function NewsScreen:_hudDot(): GuiObject?
	local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local interface = gui and gui:FindFirstChild("Interface")
	local hud = interface and interface:FindFirstChild("HUD")
	local button = hud and hud:FindFirstChild("Buttons") and hud.Buttons:FindFirstChild("News")
	return button and button:FindFirstChild("Dot")
end

function NewsScreen:_updateDot()
	local dot = self:_hudDot()
	local newest = News.Entries[1]
	if not dot then
		return
	end
	local ok, seen = pcall(PlayerData.Settings.NewsSeen.Get)
	local unread = newest ~= nil and ok and seen ~= newest.Id
	if unread and not dot.Visible then
		dot.Visible = true
		Juice.Pop(dot, 0.4)
	elseif not unread then
		dot.Visible = false
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function NewsScreen:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "News")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local j = self._janitor

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(panel.Earlier.Prev.Activated:Connect(function()
		if self._page > 1 then
			self._page -= 1
			self:_fillEarlier()
			self:_animateEarlier()
		end
	end))
	j:Add(panel.Earlier.Next.Activated:Connect(function()
		if self._page < self:_pages() then
			self._page += 1
			self:_fillEarlier()
			self:_animateEarlier()
		end
	end))

	j:Add(PlayerData.Settings.NewsSeen.Observe(function()
		self:_updateDot()
	end))
	task.defer(function()
		self:_updateDot()
	end)
end

function NewsScreen:Activate()
	self._frame.Visible = true
	self._page = 1
	self:_fillLatest()
	self:_fillEarlier()
	-- opening it marks the newest entry as read
	local newest = News.Entries[1]
	if newest then
		SettingsRemote:Fire({ Action = "SeenNews", Id = newest.Id })
		local dot = self:_hudDot()
		if dot then
			dot.Visible = false
		end
	end
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local panel = self._frame.Panel
	Juice.Stagger({ panel.LatestShadow, panel.Latest }, 0.03)
	self:_animateEarlier()
	return FrameTransition.Open(self._frame):andThen(function()
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
