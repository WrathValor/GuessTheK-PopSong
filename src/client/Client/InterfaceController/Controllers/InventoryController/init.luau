--| InventoryController
-- The inventory (Interface.Frames.Inventory, built by ./Build from the "Inventory" board):
-- category rail on the left, the loadout strip on top, 8 item cards per page with a pager.
--   • Stages / Mic stands – Classic (always yours) + owned pieces (bought, or from a set);
--                            mix and match freely
--   • Titles              – the default title + unlocked titles; shown under your name
--   • Song packs          – My Pack + every company/group pack you own a song of; one can be
--                            your duel pack ("Use in duels"); "Get more" opens the shop
-- The loadout strip shows what's equipped; its toggle turns the duel pack on/off.
-- Equipping is a request to the server (ShopService); the cards redraw from PlayerData.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
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
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local GREY = C("EDE4D4")
local PAPER = C("F3EBDD")

local CATEGORIES = Build.CATEGORIES
local PER_PAGE = Build.PER_PAGE
local RARITY_ORDER = { Legendary = 1, Epic = 2, Rare = 3, Uncommon = 4, Common = 5, Title = 6 }
local RARITY_COLOURS = table.clone(ShopCatalog.RARITY_COLOURS)
RARITY_COLOURS.Common = "EDE4D4"
RARITY_COLOURS.Title = "FFFFFF"

local SUBS = {
	["Stages"] = "%d owned · platform + stage skin for your spot",
	["Mic stands"] = "%d owned · stands at the front of your spot",
	["Titles"] = "%d unlocked · shown under your name",
	["Song packs"] = "Pick one to mix into duels · only plays if your rival has one on too",
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
	return (self :: any) :: UITypes.Controller
end

local function owns(path, id: string): boolean
	local ok, has = pcall(path.Has, id)
	return ok and has == true
end

-- ----------------------------- Item lists --------------------------------- --
-- Each item: { Key, Name, Rarity, Kind = "Stage"|"Mic"|"Title"|"Pack"|"GetMore", Equipped, ... }

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

function Inventory:_titles()
	local current = PlayerData.Inventory.Title.Get()
	local list = { { Key = "", Kind = "Title", Name = HUDConstants.DEFAULT_TITLE, Rarity = "Title", Equipped = current == "" } }
	local ok, titles = pcall(PlayerData.Inventory.Titles.Get)
	if ok and type(titles) == "table" then
		for key, value in titles do
			local title = if type(key) == "string" then key else value
			if type(title) == "string" and title ~= "" then
				table.insert(list, { Key = title, Kind = "Title", Name = title, Rarity = "Title", Equipped = current == title })
			end
		end
	end
	return list
end

local function hasSong(id: string): boolean
	return owns(PlayerData.Inventory.Songs, id)
end

-- My Pack first, then every company + group pack you own a song of, then a "Get more" card.
function Inventory:_packs()
	local current = PlayerData.Inventory.DuelPack.Get()
	local list = {}
	local function add(id: string, colour: string, colour2: string)
		local pack = Packs.Get(id)
		local owned = #Packs.SongsFor(id, hasSong)
		if not pack or (owned == 0 and pack.Kind ~= "My") then
			return
		end
		local total = #pack.Songs
		local sub = if pack.Kind == "My" then `{owned} bought song{if owned == 1 then "" else "s"}`
			elseif owned >= total then `{total} songs · complete`
			else `{owned} / {total} songs`
		table.insert(list, {
			Key = pack.Id,
			Kind = "Pack",
			Name = Packs.DisplayName(pack.Id),
			Sub = sub,
			Rarity = if pack.Kind == "My" then "Yours" else pack.Kind,
			Colour = colour,
			Colour2 = colour2,
			Owned = owned,
			Equipped = current == pack.Id,
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
	table.insert(list, { Key = "GetMore", Kind = "GetMore", Name = "Get more", Sub = "Buy songs in the shop", Rarity = "Shop", Colour = "FBF7F0", Colour2 = "F3EBDD" })
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

function Inventory:_fillCard(holder: Frame, item)
	holder.Visible = item ~= nil
	holder:SetAttribute("Key", item and item.Key or nil)
	holder:SetAttribute("Kind", item and item.Kind or nil)
	if not item then
		return
	end
	local face = holder.Face
	local art = face.Art
	local isPack = item.Kind == "Pack" or item.Kind == "GetMore"
	art.Stage.Visible = item.Kind == "Stage"
	art.Platform.Visible = item.Kind == "Stage"
	art.MicArt.Visible = item.Kind == "Mic"
	art.Covers.Visible = isPack
	art.Big.Visible = item.Kind == "Title"
	art.Icon.Visible = false
	if item.Kind == "Stage" then
		art.BackgroundColor3 = C(item.Item.Bg)
		art.Stage.BackgroundColor3 = C(item.Item.Stage)
		art.Platform.BackgroundColor3 = C(item.Item.Platform)
	elseif item.Kind == "Mic" then
		art.BackgroundColor3 = C(item.Item.Bg)
		art.MicArt.Mic.BackgroundColor3 = C(item.Item.Mic)
	elseif item.Kind == "Title" then
		art.BackgroundColor3 = YELLOW
		art.Big.Text = item.Name
	else
		art.BackgroundColor3 = C(if item.Kind == "GetMore" then "FBF7F0" else "EFEAFF")
		art.Covers.Card1.BackgroundColor3 = C(item.Colour)
		art.Covers.Card2.BackgroundColor3 = C(item.Colour2)
	end
	-- packs: the rarity chip reads "IN DUELS" on the active one
	if item.Kind == "Pack" and item.Equipped then
		art.Rarity.Text = "IN DUELS"
		art.Rarity.BackgroundColor3 = YELLOW
	else
		art.Rarity.Text = item.Rarity
		art.Rarity.BackgroundColor3 = C(RARITY_COLOURS[item.Rarity] or "FFFFFF")
	end
	face.ItemName.Text = item.Name
	face.ItemSub.Visible = item.Sub ~= nil
	face.ItemSub.Text = item.Sub or ""

	local action = face.Action
	if item.Kind == "GetMore" then
		action.Text = "Open shop"
		action.BackgroundColor3 = YELLOW
		action.Active = true
		holder.Shadow.BackgroundColor3 = INK
	elseif item.Kind == "Pack" then
		action.Text = if item.Equipped then "In duels" else "Use in duels"
		action.BackgroundColor3 = if item.Equipped then GREY else MINT
		action.Active = true -- pressing "In duels" turns it off
		holder.Shadow.BackgroundColor3 = if item.Equipped then RED else INK
	else
		action.Text = if item.Equipped then "Equipped" else "Equip"
		action.BackgroundColor3 = if item.Equipped then GREY else MINT
		action.Active = not item.Equipped
		holder.Shadow.BackgroundColor3 = if item.Equipped then RED else INK
	end
end

-- The strip on top: equipped stage, mic and duel pack (with its on/off toggle).
function Inventory:_fillLoadout()
	local strip = self._frame.Panel.Content:FindFirstChild("Loadout")
	if not strip then
		return
	end
	for _, kind in { "Stage", "Mic" } do
		local id = PlayerData.Inventory[ITEM_EQUIPPED[kind]].Get()
		local item = ShopCatalog.GetItem(kind, if id == "" then "Default" else id) or ShopCatalog.GetItem(kind, "Default")
		local slot = strip[kind .. "Slot"]
		slot.SlotName.Text = item.Name
		slot.Swatch.BackgroundColor3 = C(if kind == "Stage" then item.Stage else item.Mic)
	end
	local slot = strip.PackSlot
	local packId = PlayerData.Inventory.DuelPack.Get()
	local on = packId ~= "" and Packs.Get(packId) ~= nil
	if on then
		local count = #Packs.SongsFor(packId, hasSong)
		slot.SlotName.Text = `{Packs.DisplayName(packId)} · {count}`
		self._lastPack = packId
	else
		slot.SlotName.Text = "Off"
	end
	slot.Swatch.BackgroundColor3 = if on then C("B9A6FF") else GREY
	slot.Toggle.BackgroundColor3 = if on then MINT else GREY
	slot.Toggle.Knob.Position = if on then UDim2.new(1, -12, 0.5, 0) else UDim2.new(0, 12, 0.5, 0)
end

-- Toggle: off → turn off; on → last pack used, else My Pack, else go pick one.
function Inventory:_togglePack()
	if PlayerData.Inventory.DuelPack.Get() ~= "" then
		ShopRemote:Fire({ Action = "SetDuelPack", Id = "" })
		return
	end
	for _, id in { self._lastPack, Packs.MY } do
		if id and #Packs.SongsFor(id, hasSong) > 0 then
			ShopRemote:Fire({ Action = "SetDuelPack", Id = id })
			return
		end
	end
	self:ShowCategory("Song packs")
	self:_toast("Buy a song first to make a duel pack")
	Sounds.Play("Wrong")
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
		local n = #self:_items(name)
		b.Count.Text = tostring(if name == "Song packs" then n - 1 else n) -- not counting "Get more"
	end

	local content = panel.Content
	self:_fillLoadout()
	local items = self:_items(self._category)
	local pages = math.max(1, math.ceil(#items / PER_PAGE))
	self._page = math.clamp(self._page, 1, pages)
	content.Heading.Text = self._category
	content.Sub.Text = string.format(SUBS[self._category] or "%d", #items)
	content.Page.Text = `{self._page} / {pages}`
	content.Prev.Visible = pages > 1
	content.Next.Visible = pages > 1
	content.Page.Visible = pages > 1
	content.Sort.Visible = self._category ~= "Song packs"
	content.Sort.Text = `Sort: {self._sort}`
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
	self:_animateGrid()
end

-- cards pop in one after another
function Inventory:_animateGrid()
	local list = {}
	local grid = self._frame.Panel.Content.Grid
	for i = 1, PER_PAGE do
		table.insert(list, grid["Item" .. i])
	end
	Juice.Stagger(list, 0.03)
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
		self._sort = if self._sort == "Rarity" then "A–Z" else "Rarity"
		self:_refresh()
		self:_animateGrid()
	end))
	j:Add(content.Prev.Activated:Connect(function()
		self._page -= 1
		self:_refresh()
		self:_animateGrid()
	end))
	j:Add(content.Next.Activated:Connect(function()
		self._page += 1
		self:_refresh()
		self:_animateGrid()
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
				local on = PlayerData.Inventory.DuelPack.Get() == key
				ShopRemote:Fire({ Action = "SetDuelPack", Id = if on then "" else key })
				Sounds.Play("Click")
			elseif kind == "GetMore" then
				self._interface:Open("Shop", "Packs")
			end
		end))
	end

	-- loadout strip: slots jump to their category, the toggle turns the duel pack on/off
	local strip = content.Loadout
	j:Add(strip.StageSlot.Activated:Connect(function()
		self:ShowCategory("Stages")
	end))
	j:Add(strip.MicSlot.Activated:Connect(function()
		self:ShowCategory("Mic stands")
	end))
	j:Add(strip.PackSlot.Activated:Connect(function()
		self:ShowCategory("Song packs")
	end))
	j:Add(strip.PackSlot.Toggle.Activated:Connect(function()
		self:_togglePack()
	end))

	j:Add(ShopRemote:Connect(function(packet)
		if self.State == "Active" and type(packet) == "table" and packet.Message == "Result" then
			if packet.Action == "EquipItem" or packet.Action == "EquipTitle" or packet.Action == "SetDuelPack" then
				if not packet.Ok then
					self:_toast(packet.Text or "")
					Sounds.Play("Wrong")
				elseif packet.Action == "SetDuelPack" then
					self:_toast(packet.Text or "")
				end
			end
		end
	end))

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
	for _, path in { PlayerData.Inventory.EquippedStage, PlayerData.Inventory.EquippedMic, PlayerData.Inventory.DuelPack } do
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
		PlayerData.Inventory.DuelPack,
		PlayerData.Inventory.Titles,
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
		self:_animateGrid()
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
