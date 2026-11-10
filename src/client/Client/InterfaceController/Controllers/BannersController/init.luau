--| BannersController
-- The style picker (Interface.Frames.Banners, built by SeasonController/Build), opened from the
-- Profile's STYLE button. Three tabs:
--   SETS        a banner and its matching photocard, equipped together
--   BANNERS     banners on their own
--   PHOTOCARDS  photocards on their own
-- Only what you own is shown, BANNERS_PER_PAGE a page (the header's ‹ › page them). The left
-- side previews your inspect card with what's picked, and Equip puts it on.
-- Owned = the free ones plus the player's "Banners" / "Photocards" attributes (comma lists the
-- server mirrors from PlayerData Inventory; a set shows once you own both halves). Equip asks
-- the server (ShopRemote EquipStyle), which sets Inventory.Banner / Photocard and so the
-- "Banner" / "Photocard" attributes everyone's cards read. Bought in the Shop.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local FitPanel = require(ReplicatedStorage.Modules.UI.FitPanel)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- --------------------------------- Tables --------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")
local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local YELLOW = C("FFE07A")
local CREAM = C("FBF7F0")
local TAG_COLOUR = {
	FREE = C("FFFFFF"), SEASON = C("FF9EC4"), INDEX = C("DCD3FF"), SHOP = C("FFE07A"),
	TIER = C("FFE07A"), ANIMATED = C("FF9EC4"), HOLO = C("1E1B2E"), SOON = C("EDE4D4"),
}
local TABS = { "Sets", "Banners", "Cards" }
local GRID = { Sets = "Sets", Banners = "Grid", Cards = "Cards" } -- the grid frame each tab shows
local NOUN = { Sets = { "set", "sets" }, Banners = { "banner", "banners" }, Cards = { "photocard", "photocards" } }

-- ---------------------------------- Class --------------------------------- --
local BannersController = {}
BannersController.__index = BannersController

function BannersController.new()
	local self = setmetatable({}, BannersController)
	self.Name = "Banners"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._tab = "Sets"
	self._picked = {} :: { [string]: string } -- tab → picked id
	self._page = {} :: { [string]: number } -- tab → page (unset = open on the equipped one)
	return (self :: any) :: UITypes.Controller
end

local function csv(attribute: string, into: { [string]: boolean })
	local list = LOCAL_PLAYER:GetAttribute(attribute)
	if type(list) == "string" then
		for id in list:gmatch("[^,]+") do
			into[id] = true
		end
	end
end

-- what you own, per tab
local function owned(): { [string]: { [string]: boolean } }
	local all = RunService:IsStudio() and SeasonConstants.STUDIO_OWN_ALL
	local banners = table.clone(SeasonConstants.FREE_BANNERS)
	local cards = table.clone(SeasonConstants.FREE_PHOTOCARDS)
	local sets = {}
	csv("Banners", banners)
	csv("Photocards", cards)
	for _, spec in SeasonConstants.BANNERS do
		local id = spec.Id
		local hasCard = SeasonConstants.Photocard(id) ~= nil
		if all then
			banners[id] = true
			cards[id] = hasCard or nil
		end
		-- a set shows once you have both halves, however you got them
		sets[id] = (hasCard and banners[id] and cards[id]) or nil
	end
	return { Banners = banners, Cards = cards, Sets = sets }
end

local function equipped(): (string, string)
	return LOCAL_PLAYER:GetAttribute("Banner") or SeasonConstants.DEFAULT_BANNER,
		LOCAL_PLAYER:GetAttribute("Photocard") or SeasonConstants.DEFAULT_PHOTOCARD
end

-- is `id` what's on for this tab?
local function isOn(tab: string, id: string): boolean
	local banner, card = equipped()
	if tab == "Banners" then
		return id == banner
	elseif tab == "Cards" then
		return id == card
	end
	return id == banner and id == card
end

local function avatar(card: Instance?)
	local photo = card and card:FindFirstChild("Photo")
	local a = photo and photo:FindFirstChild("Avatar")
	if a then
		a.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=150&h=150`
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function BannersController:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Banners")
	self._frame.Visible = false
	local panel = self._frame.Panel
	FitPanel.Watch(self._frame, self._janitor)
	ButtonScale.ApplyToDescendants(panel)

	local j = self._janitor
	j:Add(panel.Header.Close.Activated:Connect(function()
		-- back to the profile it was opened from
		self._interface:Open("Profile")
	end))
	local tabs = panel.Header:FindFirstChild("Tabs")
	for _, tab in TABS do
		local t = tabs and tabs:FindFirstChild(tab)
		if t then
			j:Add(t.Activated:Connect(function()
				if self._tab ~= tab then
					Sounds.Play("Click")
					self._tab = tab
					self:_fill()
				end
			end))
		end
		local grid = panel:FindFirstChild(GRID[tab])
		if grid then
			for _, b in grid:GetChildren() do
				if b:IsA("GuiButton") then
					j:Add(b.Activated:Connect(function()
						Sounds.Play("Click")
						self._picked[tab] = b.Name
						Juice.Pop(b, 0.08)
						self:_fill()
					end))
				end
			end
		end
	end
	local pager = panel.Header:FindFirstChild("Pager")
	if pager then
		for name, step in { Prev = -1, Next = 1 } do
			j:Add(pager[name].Activated:Connect(function()
				Sounds.Play("Click")
				self._page[self._tab] = (self._page[self._tab] or 1) + step
				self:_fill()
			end))
		end
	end
	j:Add(panel.Preview.Equip.Activated:Connect(function()
		local tab = self._tab
		local id = self._picked[tab]
		if id and owned()[tab][id] and not isOn(tab, id) then
			Sounds.Play("Success")
			ShopRemote:Fire({
				Action = "EquipStyle",
				Banner = if tab ~= "Cards" then id else nil,
				Photocard = if tab ~= "Banners" then id else nil,
			})
			Juice.Pop(panel.Preview.Card, 0.12)
		end
	end))
	-- the server's answer (and anything bought in the Shop) comes back as attributes
	for _, attribute in { "Banner", "Photocard", "Banners", "Photocards" } do
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal(attribute):Connect(function()
			if self._frame.Visible then
				self:_fill()
			end
		end))
	end
end

function BannersController:Activate()
	self._frame.Visible = true
	local banner, card = equipped()
	self._picked = { Sets = if banner == card then banner else nil, Banners = banner, Cards = card }
	self._page = {} -- each tab opens on the page with what's on
	self:_fill()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function BannersController:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function BannersController:Destroy()
	self._janitor:Destroy()
end

-- [[ Fill ]]

local function paintTag(tag: TextLabel?, spec)
	if tag then
		tag.Text = spec.Tag
		tag.BackgroundColor3 = TAG_COLOUR[spec.Tag] or WHITE
		tag.TextColor3 = if spec.Tag == "HOLO" then YELLOW else INK
	end
end

-- one tile in the current tab's grid
function BannersController:_paintTile(tab: string, b: GuiButton, spec, have: boolean, picked: boolean)
	local id = spec.Id
	local on = isOn(tab, id)
	if tab == "Banners" then
		SeasonArt.PaintBanner(b.Banner, id)
		b.Banner.Lock.Visible = not have
		b.Banner.Equipped.Visible = on
		paintTag(b.Banner:FindFirstChild("Tag"), spec)
	elseif tab == "Cards" then
		avatar(b.Card)
		SeasonArt.PaintPhotocard(b.Card, id)
		b.Equipped.Visible = on
		paintTag(b:FindFirstChild("Tag"), spec)
	else
		SeasonArt.PaintBanner(b.Banner, id)
		avatar(b.Card)
		SeasonArt.PaintPhotocard(b.Card, id)
		b.Banner.Equipped.Visible = on
		paintTag(b.Banner:FindFirstChild("Tag"), spec)
	end
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Thickness = if picked then 5 else 3
	end
end

function BannersController:_fill()
	local panel = self._frame.Panel
	local tab = self._tab
	local have = owned()[tab]
	local banner, card = equipped()

	-- tabs: the open one is solid
	local tabs = panel.Header:FindFirstChild("Tabs")
	for _, name in TABS do
		local t = tabs and tabs:FindFirstChild(name)
		if t then
			t.BackgroundTransparency = if name == tab then 0 else 0.55
			t.BackgroundColor3 = if name == tab then YELLOW else CREAM
		end
		local g = panel:FindFirstChild(GRID[name])
		if g then
			g.Visible = name == tab
		end
	end

	-- only what you own, in list order, BANNERS_PER_PAGE a page
	local list = {}
	local onAt = 1
	for _, spec in SeasonConstants.BANNERS do
		if have[spec.Id] then
			table.insert(list, spec)
			if isOn(tab, spec.Id) then
				onAt = #list
			end
		end
	end
	local picked = self._picked[tab]
	if not picked or not have[picked] then
		picked = if list[onAt] then list[onAt].Id else nil
		self._picked[tab] = picked
	end
	local perPage = SeasonConstants.BANNERS_PER_PAGE
	local maxPage = math.max(1, math.ceil(#list / perPage))
	local page = math.clamp(self._page[tab] or math.ceil(onAt / perPage), 1, maxPage)
	self._page[tab] = page

	local grid = panel[GRID[tab]]
	local shown = {}
	for i, spec in list do
		if math.ceil(i / perPage) == page then
			shown[spec.Id] = i
		end
	end
	for _, b in grid:GetChildren() do
		if b:IsA("GuiButton") then
			local i = shown[b.Name]
			b.Visible = i ~= nil
			if i then
				local slot = (i - 1) % perPage
				local cw, ch = b.Size.X.Offset, b.Size.Y.Offset
				-- Juice.Pop re-anchors a tile to its centre, so place by its anchor, not its corner
				local x, y = (slot % 4) * (cw + 12), math.floor(slot / 4) * (ch + 18)
				b.Position = UDim2.fromOffset(x + b.AnchorPoint.X * cw, y + b.AnchorPoint.Y * ch)
				self:_paintTile(tab, b, SeasonConstants.Banner(b.Name), true, b.Name == picked)
			end
		end
	end
	local noun = NOUN[tab]
	panel.Header.Tabs.Owned.Text = if #list == 1 then `1 {noun[1]}` else `{#list} {noun[2]}`
	local pager = panel.Header:FindFirstChild("Pager")
	if pager then
		pager.Visible = maxPage > 1
		pager.Page.Text = `{page} / {maxPage}`
		for name, on in { Prev = page > 1, Next = page < maxPage } do
			pager[name].Visible = on
			local shadow = pager:FindFirstChild(name .. "Shadow")
			if shadow then
				shadow.Visible = on
			end
		end
	end

	-- preview: your inspect card with the picked banner / photocard (the other half as worn)
	local previewBanner = if tab == "Cards" then banner else picked or banner
	local previewCard = if tab == "Banners" then card else picked or card
	local cardFrame = panel.Preview.Card
	local _, tierInfo = SeasonArt.Of(LOCAL_PLAYER)
	SeasonArt.PaintBanner(cardFrame.Banner, previewBanner)
	cardFrame.PlayerName.Text = LOCAL_PLAYER.DisplayName
	avatar(cardFrame.Photo)
	SeasonArt.PaintPhotocard(cardFrame.Photo, previewCard)
	SeasonArt.PaintChip(cardFrame.Tier, tierInfo)

	local spec = SeasonConstants.Banner(picked or previewBanner)
	local what = if tab == "Sets" then "Banner + photocard" elseif tab == "Cards" then "Photocard" else "Banner"
	panel.Preview.Info.BannerName.Text = spec.Name
	panel.Preview.Info.Source.Text = `{what} · {spec.Source}. Shows on your profile and inspect card.`

	local equip = panel.Preview.Equip
	local mine = picked ~= nil and have[picked] == true
	local on = picked ~= nil and isOn(tab, picked)
	equip.Text = if on then "EQUIPPED" elseif mine then "EQUIP" else "LOCKED"
	equip.BackgroundColor3 = if on or not mine then GREY else MINT
	equip.Active = mine and not on
end

return BannersController
