--| InventoryController
-- The inventory (Interface.Frames.Inventory, built by ./Build from the "Inventory redesign"):
-- category rail on the left, a heading + description with Sort ⌄ and the pager, 8 cards a page.
--   • Stages / Mic stands – Classic (always yours) + owned pieces (bought, or from a set);
--                            Equip (green "✓ Equipped" on the worn one)
--   • Titles              – the default title + titles you own (never ones you don't): your
--                            name with the chip in its tier colour (Gold shines, Rainbow scrolls)
--   • Song packs          – My Pack ("Roll for more") + every company/group pack you own a song
--                            of, with a progress bar or "Complete ✓". Nothing to equip.
-- Equipping is a request to the server (ShopService); the cards redraw from PlayerData.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local GroupArt = require(ReplicatedStorage.Modules.UI.GroupArt)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local HUDConstants = require(ReplicatedStorage.Constants.HUDConstants)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local NIGHT = C("2B2346")
local LINE = C("DCD3C4") -- an Equip button's outline
local GREEN = C("6FD08C")
local EQUIP_GREEN = C("1E8A4A")

local CATEGORIES = Build.CATEGORIES
local PER_PAGE = Build.PER_PAGE
local RARITY_ORDER = { Legendary = 1, Epic = 2, Rare = 3, Uncommon = 4, Common = 5, Title = 6 }
local RARITY_COLOURS = table.clone(ShopCatalog.RARITY_COLOURS)
RARITY_COLOURS.Common = "EDE4D4"
RARITY_COLOURS.Title = "FFFFFF"
RARITY_COLOURS.Yours = "FFFFFF"
RARITY_COLOURS.Company = "FFFFFF"
RARITY_COLOURS.Group = "FFFFFF"
-- a set title's tier chip (same colours as the title chip)
RARITY_COLOURS.Normal = "B9A6FF"
RARITY_COLOURS.Gold = "F2C94C"
RARITY_COLOURS.Rainbow = "B5DDFF"

local SUBS = {
	["Stages"] = "%d owned · the platform and stage skin for your spot",
	["Mic stands"] = "%d owned · the stand at the front of your spot",
	["Titles"] = "%d unlocked · shown under your name",
	["Song packs"] = "%d packs · your songs grouped by company and group",
}
local KIND_OF = { Stages = "Stage", ["Mic stands"] = "Mic" }
local ITEM_OWNED = { Stage = "Stages", Mic = "Mics" }
local ITEM_EQUIPPED = { Stage = "EquippedStage", Mic = "EquippedMic" }

-- ---------------------------------- Class --------------------------------- --
local Inventory = {}
Inventory.__index = Inventory

function Inventory.new()
	local self = setmetatable({}, Inventory)
	self.Name = "Inventory"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._category = CATEGORIES[1]
	self._page = 1
	self._sort = "Rarity" :: "Rarity" | "A–Z"
	self._packSort = "Company" :: "Company" | "Progress"
	return (self :: any) :: UITypes.Controller
end

local function owns(path, id: string): boolean
	local ok, has = pcall(path.Has, id)
	return ok and has == true
end

-- ----------------------------- Item lists --------------------------------- --
-- Each item: { Key, Name, Rarity, Kind = "Stage"|"Mic"|"Title"|"Pack", Equipped, ... }

function Inventory:_pieces(kind: string)
	local equipped = PlayerData.Inventory[ITEM_EQUIPPED[kind]].Get()
	local default = ShopCatalog.GetItem(kind, "Default")
	local list = { { Key = "Default", Kind = kind, Name = default.Name, Rarity = "Common", Item = default, Equipped = equipped == "Default" or equipped == "" } }
	for _, item in (if kind == "Stage" then ShopCatalog.Stages else ShopCatalog.Mics) do
		if owns(PlayerData.Inventory[ITEM_OWNED[kind]], item.Id) then
			table.insert(list, { Key = item.Id, Kind = kind, Name = item.Name, Rarity = item.Rarity, Item = item, Equipped = equipped == item.Id })
		end
	end
	return list
end

local function hasSong(id: string): boolean
	return owns(PlayerData.Inventory.Songs, id)
end

function Inventory:_titles()
	local current = PlayerData.Inventory.Title.Get()
	local list = { { Key = "", Kind = "Title", Name = HUDConstants.DEFAULT_TITLE, Rarity = "Common", Equipped = current == "" } }
	-- set titles level up with the set: show the tier, and how far the next one is
	local setOf = {}
	for _, group in { Packs.Groups(), Packs.Companies() } do
		for _, pack in group do
			if pack.Title then
				setOf[pack.Title] = pack
			end
		end
	end
	local tiers = {}
	pcall(function()
		tiers = PlayerData.Inventory.TitleTiers.Get() or {}
	end)
	local ok, titles = pcall(PlayerData.Inventory.Titles.Get)
	if ok and type(titles) == "table" then
		for key, value in titles do
			local title = if type(key) == "string" then key else value
			if type(title) == "string" and title ~= "" then
				local item = { Key = title, Kind = "Title", Name = title, Rarity = "Common", Equipped = current == title }
				local pack = setOf[title]
				if pack then
					local tier = Cards.LEVELS[tiers[title] or 1] or "Normal"
					item.Tier = tier
					item.Rarity = tier -- the chip reads Normal / Gold / Rainbow (the Index shows the next step)
				end
				table.insert(list, item)
			end
		end
	end
	return list
end

-- My Pack first, then every company + group pack you own a song of, then a "Get more" card.
function Inventory:_packs()
	local list = {}
	local function add(id: string, colour: string, colour2: string)
		local pack = Packs.Get(id)
		local owned = #Packs.SongsFor(id, hasSong)
		if not pack or (owned == 0 and pack.Kind ~= "My") then
			return
		end
		local total = #pack.Songs
		table.insert(list, {
			Key = pack.Id,
			Kind = "Pack",
			Name = Packs.DisplayName(pack.Id),
			Total = total,
			Rarity = if pack.Kind == "My" then "Yours" else pack.Kind,
			Colour = colour,
			Colour2 = colour2,
			Owned = owned,
			Complete = pack.Kind ~= "My" and owned >= total,
		})
	end
	add(Packs.MY, "B9A6FF", "FF9EC4")
	local colours = ShopCatalog.PACK_COLOURS
	for i, pack in Packs.Companies() do
		add(pack.Id, colours[(i - 1) % #colours + 1], "FFFFFF")
	end
	for i, pack in Packs.Groups() do
		add(pack.Id, colours[(i + 1) % #colours + 1], "FFE07A")
	end
	if self._packSort == "Progress" then
		-- My Pack first, then the closest to complete
		table.sort(list, function(a, b)
			if (a.Key == Packs.MY) ~= (b.Key == Packs.MY) then
				return a.Key == Packs.MY
			end
			local pa, pb = a.Owned / math.max(a.Total, 1), b.Owned / math.max(b.Total, 1)
			if pa ~= pb then
				return pa > pb
			end
			return a.Name < b.Name
		end)
	end
	return list
end

function Inventory:_items(category: string)
	local list = if KIND_OF[category] then self:_pieces(KIND_OF[category]) elseif category == "Titles" then self:_titles() else self:_packs()
	if category ~= "Song packs" then
		table.sort(list, function(a, b)
			if a.Key == "Default" or a.Key == "" then
				return true -- the default always comes first
			elseif b.Key == "Default" or b.Key == "" then
				return false
			end
			if self._sort == "Rarity" then
				local ra, rb = RARITY_ORDER[a.Rarity] or 9, RARITY_ORDER[b.Rarity] or 9
				if ra ~= rb then
					return ra < rb
				end
			end
			return a.Name < b.Name
		end)
	end
	return list
end

-- ------------------------------- Drawing ---------------------------------- --

-- pack initials for the front photocard: "HYBE Pack" → "HY", "My Pack" → "ME", "2NE1" → "2N"
local function packInitials(item): string
	if item.Key == Packs.MY then
		return "ME"
	end
	local name = string.gsub(item.Name, " Pack$", "")
	return string.upper(string.sub(string.gsub(name, "[^%w]", ""), 1, 2))
end

function Inventory:_fillCard(holder: Frame, item)
	holder.Visible = item ~= nil
	holder:SetAttribute("Key", item and item.Key or nil)
	holder:SetAttribute("Kind", item and item.Kind or nil)
	if not item then
		return
	end
	local face = holder.Face
	local art = face.Art
	local kind = item.Kind
	art.Stage.Visible = kind == "Stage"
	art.Platform.Visible = kind == "Stage"
	art.MicArt.Visible = kind == "Mic"
	art.Covers.Visible = kind == "Pack"
	art.TitleArt.Visible = kind == "Title"
	art.Rainbow.Enabled = false

	if kind == "Stage" then
		art.BackgroundColor3 = C(item.Item.Bg)
		art.Stage.BackgroundColor3 = C(item.Item.Stage)
		art.Platform.BackgroundColor3 = C(item.Item.Platform)
	elseif kind == "Mic" then
		art.BackgroundColor3 = C(item.Item.Bg)
		art.MicArt.Mic.BackgroundColor3 = C(item.Item.Mic)
	elseif kind == "Title" then
		-- your name with the title chip under it, on the dark panel
		art.BackgroundColor3 = NIGHT
		art.TitleArt.Player.Text = Players.LocalPlayer.DisplayName
		local chip = art.TitleArt.Chip
		chip.Text = item.Name
		TierShine.Apply(chip, chip.Rainbow, item.Tier, YELLOW) -- Gold shines, Rainbow scrolls
	else
		-- three stacked photocards in the pack's colours, its initials on the front one
		art.BackgroundColor3 = C("EFEAFF")
		local covers = art.Covers
		-- a group's pack wears the group's colours (Songs: Gradient); company packs keep theirs
		local group = string.match(item.Key, "^Group:(.+)$")
		for _, name in { "Card1", "Card2", "Front" } do
			local cover = covers[name]
			if group then
				GroupArt.Paint(cover, group, if name == "Front" then 135 else 45)
			else
				local g = cover:FindFirstChild("Group")
				if g then
					g.Enabled = false
				end
				cover.BackgroundColor3 = C(if name == "Front" then item.Colour2 else item.Colour)
			end
		end
		if not group then
			covers.Front.Initials.TextColor3 = INK
		end
		covers.Front.Initials.Text = packInitials(item)
	end
	-- stages + mics show their real model; packs and titles keep the drawn art
	if kind == "Stage" or kind == "Mic" then
		CosmeticView.Show(art, kind, item.Item.Id)
	else
		CosmeticView.Clear(art)
	end
	art.Rarity.Text = item.Rarity
	-- a Gold / Rainbow tag gets the tier's own finish (Gold shines, Rainbow scrolls)
	local tierTag = if item.Rarity == "Gold" or item.Rarity == "Rainbow" then item.Rarity else nil
	TierShine.Apply(art.Rarity, art.Rarity:FindFirstChild("Tier"), tierTag, C(RARITY_COLOURS[item.Rarity] or "FFFFFF"))
	face.ItemName.Text = item.Name

	-- the name sits just above the button and the art fills the rest;
	-- pack cards slot their progress bar in between, so their art is shorter
	local lift = if kind == "Pack" then 18 else 0
	face.ItemName.Position = UDim2.new(0, 10, 1, -60 - lift)
	art.Size = UDim2.new(1, -16, 1, -74 - lift)

	-- packs: progress bar + count (or Complete ✓); My Pack also gets "Roll for more"
	local prog = face.Progress
	prog.Visible = kind == "Pack"
	if kind == "Pack" then
		local done = item.Complete
		prog.Bar.Fill.Size = UDim2.fromScale(if item.Total > 0 then math.clamp(item.Owned / item.Total, 0, 1) else 0, 1)
		prog.Bar.Fill.Visible = item.Owned > 0
		prog.Bar.Fill.BackgroundColor3 = if done then EQUIP_GREEN else GREEN
		prog.Count.Text = if item.Key == Packs.MY then `{item.Owned} songs` elseif done then "Complete ✓" else `{item.Owned} / {item.Total}`
		prog.Count.TextColor3 = if done or item.Key == Packs.MY then EQUIP_GREEN else INK
	end

	local action = face.Action
	local line = action:FindFirstChildOfClass("UIStroke")
	local equipped = item.Equipped == true
	if kind == "Pack" then
		action.Visible = item.Key == Packs.MY
		action.Text = "Roll for more"
		action.BackgroundColor3 = YELLOW
		action.TextColor3 = INK
		line.Color = INK
		action.Active = true
	else
		action.Visible = true
		action.Text = if equipped then "✓ Equipped" else "Equip"
		action.BackgroundColor3 = if equipped then EQUIP_GREEN else WHITE
		action.TextColor3 = if equipped then WHITE else INK
		line.Color = if equipped then EQUIP_GREEN else LINE
		action.Active = not equipped
	end
	-- the worn card: green outline on a pale green card
	face.BackgroundColor3 = if equipped then C("EEF8EF") else WHITE
	face:FindFirstChildOfClass("UIStroke").Color = if equipped then EQUIP_GREEN else INK
	holder.Shadow.BackgroundColor3 = if equipped then EQUIP_GREEN else INK
end

function Inventory:_refresh()
	if not self._frame or not self._frame.Visible then
		return
	end
	local panel = self._frame.Panel
	-- rail
	for i, name in CATEGORIES do
		local b = panel.Rail["Category" .. i]
		local on = name == self._category
		b.BackgroundColor3 = if on then INK else WHITE
		b:FindFirstChildOfClass("UIStroke").Color = if on then INK else WHITE
		b.Label.TextColor3 = if on then YELLOW else INK
		b.Count.TextColor3 = if on then YELLOW else INK
		b.Count.Text = tostring(#self:_items(name))
	end

	local content = panel.Content
	local items = self:_items(self._category)
	local pages = math.max(1, math.ceil(#items / PER_PAGE))
	self._page = math.clamp(self._page, 1, pages)
	content.Heading.Text = self._category
	content.Sub.Text = string.format(SUBS[self._category] or "%d", #items)
	content.Page.Text = `{self._page} / {pages}`
	content.Prev.Visible = pages > 1
	content.Next.Visible = pages > 1
	content.Page.Visible = pages > 1
	content.Sort.Label.Text = `Sort: {if self._category == "Song packs" then self._packSort else self._sort}`
	content.Empty.Visible = #items == 0
	for i = 1, PER_PAGE do
		self:_fillCard(content.Grid["Item" .. i], items[(self._page - 1) * PER_PAGE + i])
	end
end

function Inventory:ShowCategory(name: string)
	if not table.find(CATEGORIES, name) then
		name = CATEGORIES[1]
	end
	self._category = name
	self._page = 1
	self:_refresh()
end

function Inventory:_toast(message: string)
	local toast = self._frame:FindFirstChild("Toast")
	if not toast then
		return
	end
	toast.Text = message
	toast.Visible = true
	Juice.SlideIn(toast, 24)
	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(2, function()
		if self._toastToken == token then
			toast.Visible = false
		end
	end)
end

-- -------------------------------- Lifecycle ------------------------------- --

function Inventory:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Inventory")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local j = self._janitor

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for i, name in CATEGORIES do
		j:Add(panel.Rail["Category" .. i].Activated:Connect(function()
			self:ShowCategory(name)
		end))
	end
	local content = panel.Content
	j:Add(content.Sort.Activated:Connect(function()
		if self._category == "Song packs" then
			self._packSort = if self._packSort == "Company" then "Progress" else "Company"
		else
			self._sort = if self._sort == "Rarity" then "A–Z" else "Rarity"
		end
		self._page = 1
		self:_refresh()
	end))
	j:Add(content.Prev.Activated:Connect(function()
		self._page -= 1
		self:_refresh()
	end))
	j:Add(content.Next.Activated:Connect(function()
		self._page += 1
		self:_refresh()
	end))
	for i = 1, PER_PAGE do
		local holder = content.Grid["Item" .. i]
		j:Add(holder.Face.Action.Activated:Connect(function()
			local key, kind = holder:GetAttribute("Key"), holder:GetAttribute("Kind")
			if key == nil then
				return
			end
			if kind == "Stage" or kind == "Mic" then
				ShopRemote:Fire({ Action = "EquipItem", Kind = kind, Id = key })
			elseif kind == "Title" then
				ShopRemote:Fire({ Action = "EquipTitle", Id = key })
			elseif kind == "Pack" then
				self._interface:Open("Shop", "Songs") -- My Pack's "Roll for more"
			end
		end))
	end

	j:Add(ShopRemote:Connect(function(packet)
		if self.State == "Active" and type(packet) == "table" and packet.Message == "Result" then
			if (packet.Action == "EquipItem" or packet.Action == "EquipTitle") and not packet.Ok then
				self:_toast(packet.Text or "")
				Sounds.Play("Wrong")
			end
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy

	-- the newly equipped card gets a punch
	local function popEquipped(key: string)
		if self.State ~= "Active" then
			return
		end
		for i = 1, PER_PAGE do
			local holder = content.Grid["Item" .. i]
			if holder.Visible and holder:GetAttribute("Key") == key then
				Juice.Pop(holder, 0.1)
			end
		end
	end
	for _, path in { PlayerData.Inventory.EquippedStage, PlayerData.Inventory.EquippedMic } do
		j:Add(path.Observe(function(id)
			task.defer(popEquipped, id)
		end))
	end
	j:Add(PlayerData.Inventory.Title.Observe(function(title)
		task.defer(popEquipped, title)
	end))

	for _, path in {
		PlayerData.Inventory.Stages,
		PlayerData.Inventory.Mics,
		PlayerData.Inventory.EquippedStage,
		PlayerData.Inventory.EquippedMic,
		PlayerData.Inventory.Titles,
		PlayerData.Inventory.TitleTiers,
		PlayerData.Inventory.Copies,
		PlayerData.Inventory.Title,
		PlayerData.Inventory.Songs,
	} do
		j:Add(path.Observe(function()
			self:_refresh()
		end))
	end
end

function Inventory:Activate(category: string?)
	self._frame.Visible = true
	if category then
		self:ShowCategory(category)
	else
		self:_refresh()
	end
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Inventory:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Inventory:Destroy()
	self._janitor:Destroy()
end

return Inventory
