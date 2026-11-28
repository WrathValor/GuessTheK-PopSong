--| BannersController
-- The style picker (Interface.Frames.Banners, built by SeasonController/Build), opened from the
-- Profile's STYLE button. Five tabs:
--   SETS        a banner and its matching photocard, equipped together
--   BANNERS     banners on their own
--   PHOTOCARDS  photocards on their own
--   STAGES      your duel stage (board 66: moved here from the old Inventory screen)
--   MICS        your mic stand
-- Stages and mics show only what you own (Classic always), read from PlayerData (Inventory.Stages
-- / .Mics / .EquippedStage / .EquippedMic); their preview is the real 3D duel spot, the picked
-- stage with your mic (or your stage with the picked mic), drawn by Modules/UI/CosmeticView in
-- Preview.Spot. The tiles show each item's 3D model too (CosmeticView, like the old Inventory
-- cards), but only the open page's: a tile off the page, or on another tab, has its viewport
-- cleared, CosmeticView skips one that already shows its item, and closing Style clears them all.
-- Tiles are cloned once per item and reused. Equip asks ShopRemote EquipItem.
-- Each grid holds one hidden "Template" tile (made by SeasonController/Build). A tile is cloned
-- from it only for what you own, the first time a page needs it (a Shop buy refills the picker,
-- so it gets its tile then), so a new banner only needs its line in SeasonConstants, no rebuild.
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
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)

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
	FRIENDS = C("A7E9B8"), -- Invite friends rewards (the Squad set)
	VIP = INK, -- the VIP Pass's VIP Gold set (gold text)
}
local TABS = { "Sets", "Banners", "Cards", "Stages", "Mics" }
local GRID = { Sets = "Sets", Banners = "Grid", Cards = "Cards", Stages = "Stages", Mics = "Mics" } -- the grid frame each tab shows
local TAB_TITLE = { Sets = "Sets", Banners = "Banners", Cards = "Photocards", Stages = "Stages", Mics = "Mics" } -- the grid page's heading
local NOUN = { Sets = { "set", "sets" }, Banners = { "banner", "banners" }, Cards = { "photocard", "photocards" }, Stages = { "stage", "stages" }, Mics = { "mic", "mics" } }
-- the stage / mic tabs: ShopCatalog kind, the PlayerData sets of what you own / wear
local PIECE = {
	Stages = { Kind = "Stage", Owned = "Stages", Worn = "EquippedStage", Line = "Stage + platform", Shows = "your duel stage" },
	Mics = { Kind = "Mic", Owned = "Mics", Worn = "EquippedMic", Line = "Mic stand", Shows = "the front of your duel spot" },
}
local RARITY_DOT = { Common = C("EDE4D4"), Uncommon = C("A7E9B8"), Rare = C("9ED8F5"), Epic = C("B9A6FF"), Legendary = C("FFE07A") }

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

-- [[ Stages + mics ]]

local function worn(tab: string): string
	local id = PlayerData.Inventory[PIECE[tab].Worn].Get()
	return if type(id) == "string" and id ~= "" then id else "Default"
end

-- what you own of a piece tab, Classic first then ShopCatalog's order: { { Id, Name, Source, Item } }
local function pieces(tab: string): { any }
	local p = PIECE[tab]
	local list = {}
	local default = ShopCatalog.GetItem(p.Kind, "Default")
	table.insert(list, { Id = "Default", Name = default.Name, Source = "Classic · always yours", Item = default })
	local have = PlayerData.Inventory[p.Owned].Get() or {}
	local set = {}
	for k, v in have do
		set[if type(k) == "string" then k else v] = true -- (a set's map or an id list)
	end
	for _, item in (if p.Kind == "Stage" then ShopCatalog.Stages else ShopCatalog.Mics) do
		if set[item.Id] then
			table.insert(list, { Id = item.Id, Name = item.Name, Source = item.Rarity, Item = item })
		end
	end
	return list
end

-- a piece tile's drawing: its backdrop and its stage skin + platform, or its mic head
local function paintPiece(art: Instance, item)
	art.BackgroundColor3 = C(item.Bg or "2B2346")
	local skin, plat, head = art:FindFirstChild("Skin"), art:FindFirstChild("Platform"), art:FindFirstChild("Head")
	if skin then
		skin.BackgroundColor3 = C(item.Stage or "FFFFFF")
	end
	if plat then
		plat.BackgroundColor3 = C(item.Platform or "FFFFFF")
	end
	if head then
		head.BackgroundColor3 = C(item.Mic or "FFFFFF")
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function BannersController:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Banners")
	self._frame.Visible = false
	local panel = self._frame.Panel
	for _, gridName in GRID do
		local template = panel[gridName]:FindFirstChild("Template")
		if template then
			template.Visible = false
		else
			warn(`[Banners] {gridName} has no Template tile; re-run SeasonController/Build.Banners`)
		end
	end
	-- (full screen now, board 61: no FitPanel)
	ButtonScale.ApplyToDescendants(panel)

	local j = self._janitor
	j:Add(panel.Header.Close.Activated:Connect(function()
		-- back to the profile it was opened from
		self._interface:Open("Profile")
	end))
	-- MORE IN THE SHOP: the Shop's Profile style tab
	local shop = panel.Header:FindFirstChild("Shop")
	if shop then
		j:Add(shop.Activated:Connect(function()
			Sounds.Play("Click")
			self._interface:Open("Shop", if PIECE[self._tab] then "Stage" else "Profile")
		end))
	end
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
		if PIECE[tab] then
			if id and id ~= worn(tab) then
				Sounds.Play("Success")
				ShopRemote:Fire({ Action = "EquipItem", Kind = PIECE[tab].Kind, Id = id })
				Juice.Pop(panel.Preview.Spot, 0.12)
			end
			return
		end
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
	-- stages / mics: what you own and wear (PlayerData)
	for _, path in { PlayerData.Inventory.Stages, PlayerData.Inventory.Mics, PlayerData.Inventory.EquippedStage, PlayerData.Inventory.EquippedMic } do
		j:Add(path.Observe(function()
			if self._frame.Visible and PIECE[self._tab] then
				self:_fill()
			end
		end))
	end
	local spot = panel.Preview:FindFirstChild("Spot")
	if spot then
		CosmeticView.EnableSpin(spot.Art)
	end
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
	self._picked = { Sets = if banner == card then banner else nil, Banners = banner, Cards = card, Stages = worn("Stages"), Mics = worn("Mics") }
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
		local panel = self._frame.Panel
		local spot = panel.Preview:FindFirstChild("Spot")
		if spot then
			CosmeticView.Clear(spot.Art) -- (no live viewport while Style is closed)
		end
		for name in PIECE do
			local g = panel:FindFirstChild(GRID[name])
			for _, t in if g then g:GetChildren() else {} do
				if t:IsA("GuiButton") and t.Name ~= "Template" then
					CosmeticView.Clear(t.Art)
				end
			end
		end
		self.State = "Inactive"
	end)
end

function BannersController:Destroy()
	self._janitor:Destroy()
end

-- [[ Fill ]]

-- `id`'s tile in `tab`'s grid, cloned from its Template the first time it's needed: name +
-- source written once, the rest painted per fill (_paintTile)
function BannersController:_tile(tab: string, grid: Instance, spec): GuiButton?
	local b = grid:FindFirstChild(spec.Id)
	if b then
		return b
	end
	local template = grid:FindFirstChild("Template")
	if not template then
		return nil
	end
	b = template:Clone()
	b.Name = spec.Id
	local name = b:FindFirstChild("BannerName") or b:FindFirstChild("CardName") or b:FindFirstChild("SetName") or b:FindFirstChild("ItemName")
	if name then
		name.Text = spec.Name
	end
	local source = b:FindFirstChild("Source")
	if source then
		source.Text = spec.Source
	end
	if spec.Item then -- a stage / mic: its drawing and rarity dot never change, so paint them once
		paintPiece(b.Art, spec.Item)
		local dot = b:FindFirstChild("Dot")
		if dot then
			dot.BackgroundColor3 = RARITY_DOT[spec.Item.Rarity or "Common"] or RARITY_DOT.Common
		end
	end
	self._janitor:Add(b.Activated:Connect(function()
		Sounds.Play("Click")
		self._picked[tab] = spec.Id
		Juice.Pop(b, 0.08)
		self:_fill()
	end))
	self._janitor:Add(b)
	b.Parent = grid
	return b
end

local function paintTag(tag: TextLabel?, spec)
	if tag then
		tag.Text = spec.Tag
		tag.BackgroundColor3 = TAG_COLOUR[spec.Tag] or WHITE
		tag.TextColor3 = if spec.Tag == "HOLO" or spec.Tag == "VIP" then YELLOW else INK
	end
end

-- one tile in the current tab's grid
function BannersController:_paintTile(tab: string, b: GuiButton, spec, have: boolean, picked: boolean)
	local id = spec.Id
	local on = if PIECE[tab] then id == worn(tab) else isOn(tab, id)
	if PIECE[tab] then
		b.Equipped.Visible = on
	elseif tab == "Banners" then
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
	local piece = PIECE[tab]
	local banner, card = equipped()

	-- tabs: the open one is cream with an outline (the full-screen tabs, like Shop / Quests)
	local tabs = panel.Header:FindFirstChild("Tabs")
	for _, name in TABS do
		local t = tabs and tabs:FindFirstChild(name)
		if t then
			local on = name == tab
			t.BackgroundColor3 = CREAM
			t.BackgroundTransparency = if on then 0 else 1
			t.TextColor3 = if on then INK else CREAM
			local s = t:FindFirstChildOfClass("UIStroke")
			if s then
				s.Enabled = on
			end
		end
		local g = panel:FindFirstChild(GRID[name])
		if g then
			g.Visible = name == tab
		end
	end

	-- only what you own, in list order, BANNERS_PER_PAGE a page
	local list = {}
	local onAt = 1
	local have: { [string]: boolean } = {}
	if piece then
		list = pieces(tab)
		local on = worn(tab)
		for i, spec in list do
			have[spec.Id] = true
			if spec.Id == on then
				onAt = i
			end
		end
	else
		have = owned()[tab]
		for _, spec in SeasonConstants.BANNERS do
			if have[spec.Id] then
				table.insert(list, spec)
				if isOn(tab, spec.Id) then
					onAt = #list
				end
			end
		end
	end
	local byId = {}
	for _, spec in list do
		byId[spec.Id] = spec
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
			self:_tile(tab, grid, spec)
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
				self:_paintTile(tab, b, byId[b.Name], true, b.Name == picked)
				if piece then
					CosmeticView.Show(b.Art, piece.Kind, b.Name) -- (a no-op when it already shows it)
				end
			elseif piece and b.Name ~= "Template" then
				CosmeticView.Clear(b.Art) -- (off this page: no viewport left rendering)
			end
		end
	end
	-- the other piece tab's tiles: no viewports while it isn't open
	for name in PIECE do
		local g = if name ~= tab then panel:FindFirstChild(GRID[name]) else nil
		if g then
			for _, t in g:GetChildren() do
				if t:IsA("GuiButton") and t.Name ~= "Template" then
					CosmeticView.Clear(t.Art)
				end
			end
		end
	end
	local noun = NOUN[tab]
	local owned = panel:FindFirstChild("Owned", true)
	if owned then
		owned.Text = if #list == 1 then `1 {noun[1]}` else `{#list} {noun[2]}`
	end
	local head = panel:FindFirstChild("PageHead")
	if head then
		head.Title.Text = string.upper(TAB_TITLE[tab] or tab)
	end
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

	-- stages / mics: the 3D duel spot in place of the inspect card
	local preview = panel.Preview
	local spot = preview:FindFirstChild("Spot")
	local spotShadow = preview:FindFirstChild("SpotShadow")
	preview.Card.Visible = not piece
	preview.CardShadow.Visible = not piece
	if spot then
		spot.Visible = piece ~= nil
		spotShadow.Visible = piece ~= nil
	end
	local heading = preview:FindFirstChild("Heading")
	if heading then
		heading.Text = if piece then "PREVIEW · YOUR DUEL SPOT" else "PREVIEW · YOUR PROFILE CARD"
	end
	if piece then
		local stage = if tab == "Stages" then picked or worn("Stages") else worn("Stages")
		local mic = if tab == "Mics" then picked or worn("Mics") else worn("Mics")
		if spot then
			CosmeticView.Show(spot.Art, "Spot", `{stage}|{mic}`)
		end
		local spec = byId[picked or ""]
		local item = spec and spec.Item
		local other = ShopCatalog.GetItem(if tab == "Stages" then "Mic" else "Stage", if tab == "Stages" then mic else stage)
		preview.Info.BannerName.Text = item and item.Name or ""
		preview.Info.Source.Text = `{piece.Line} · {item and item.Rarity or "Common"}. Shown with your {if tab == "Stages" then "mic" else "stage"}: {other and other.Name or "Classic"}. On {piece.Shows}.`
		local equip = preview.Equip
		local on = picked ~= nil and picked == worn(tab)
		equip.Text = if on then "EQUIPPED" else "EQUIP"
		equip.BackgroundColor3 = if on then GREY else MINT
		equip.Active = not on
		return
	elseif spot then
		CosmeticView.Clear(spot.Art)
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
