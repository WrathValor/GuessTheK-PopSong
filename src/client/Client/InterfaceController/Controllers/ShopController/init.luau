--| ShopController
-- The shop (Interface.Frames.Shop, built by ./Build from the Shop A boards): tabs in the header,
-- five pages that never scroll (Featured, Sets, Items, Packs, Coins). Items sells stages and
-- mic stands one by one; Packs switches between company and group packs. Fills everything from
-- ShopCatalog + the player's data; purchases are only requests, the server (ShopService)
-- checks and applies them. Open with Interface:Open("Shop", "Coins") to land on a tab.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local PAPER = C("F3EBDD")
local LINE = C("CFC5B3")
local GREY = C("EDE4D4")

local TABS = { "Featured", "Sets", "Items", "Packs", "Coins" }
local PACK_SLOTS = 5
local COIN_LAYOUTS = {
	[1] = { { 33, 32 } },
	[3] = { { 33, 20 }, { 18, 44 }, { 48, 44 } },
	[6] = { { 33, 8 }, { 20, 30 }, { 46, 30 }, { 8, 52 }, { 33, 52 }, { 58, 52 } },
}

local fmt = ShopCatalog.Format

-- ---------------------------------- Class --------------------------------- --
local Shop = {}
Shop.__index = Shop

function Shop.new()
	local self = setmetatable({}, Shop)
	self.Name = "Shop"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._tab = "Featured"
	self._packIndex = 1 -- which of the visible pack slots is selected
	self._packKind = "Company" :: "Company" | "Group"
	self._packOffset = 0 -- paging through more than PACK_SLOTS packs
	self._packs = {} :: { any }
	return (self :: any) :: UITypes.Controller
end

-- --------------------------------- Helpers -------------------------------- --

local function owns(path, id: string): boolean
	local ok, has = pcall(path.Has, id)
	return ok and has == true
end

-- Sets an Action-style button: label text, icon on/off, colour, and whether it can be pressed.
local function setButton(button: GuiButton, label: string, opts: { Icon: boolean?, Colour: Color3?, Enabled: boolean?, Old: string? })
	local lbl = button:FindFirstChild("Label") :: TextLabel
	local icon = button:FindFirstChild("Icon") :: ImageLabel
	local old = button:FindFirstChild("Old") :: TextLabel?
	lbl.Text = label
	icon.Visible = opts.Icon ~= false
	button.BackgroundColor3 = opts.Colour or MINT
	button.Active = opts.Enabled ~= false
	if old then
		old.Visible = opts.Old ~= nil
		old.RichText = true
		old.Text = if opts.Old then `<s>{opts.Old}</s>` else ""
	end
end

-- A set counts as equipped while you wear both of its pieces.
local function setEquipped(set): boolean
	local stage, mic = ShopCatalog.SetPieces(set)
	return PlayerData.Inventory.EquippedStage.Get() == stage.Id and PlayerData.Inventory.EquippedMic.Get() == mic.Id
end

-- Paints the art + name + action of a set card.
function Shop:_fillSetCard(holder: Frame, set)
	holder:SetAttribute("SetId", set and set.Id or nil)
	holder.Visible = set ~= nil
	local shadow = holder.Parent:FindFirstChild(holder.Name .. "Shadow")
	if shadow then
		shadow.Visible = set ~= nil
	end
	if not set then
		return
	end
	local face = holder:FindFirstChild("Face") or holder
	local art = face:FindFirstChild("Art")
	if art then
		art.BackgroundColor3 = C(set.Bg)
		if art:FindFirstChild("Stage") then
			art.Stage.BackgroundColor3 = C(set.Stage)
		end
		if art:FindFirstChild("Platform") then
			art.Platform.BackgroundColor3 = C(set.Platform)
		end
		if art:FindFirstChild("Mic") then
			art.Mic.BackgroundColor3 = C(set.Mic)
		end
		local rarity = art:FindFirstChild("Rarity")
		if rarity then
			rarity.Text = set.Rarity
			rarity.BackgroundColor3 = C(ShopCatalog.RARITY_COLOURS[set.Rarity] or "FFFFFF")
		end
	end
	face.SetName.Text = set.Name

	local owned = owns(PlayerData.Inventory.Sets, set.Id)
	local equipped = owned and setEquipped(set)
	local action = face.Action
	if equipped then
		setButton(action, "Equipped", { Icon = false, Colour = GREY, Enabled = false })
	elseif owned then
		setButton(action, "Equip", { Icon = false, Colour = WHITE })
	else
		setButton(action, fmt(set.Price), { Colour = MINT })
	end
end

-- Clicked a set card's button: buy it, or equip it if it's already yours.
function Shop:_setAction(setId: string?)
	if not setId then
		return
	end
	local set = ShopCatalog.GetSet(setId)
	if owns(PlayerData.Inventory.Sets, setId) then
		if set and setEquipped(set) then
			return
		end
		ShopRemote:Fire({ Action = "EquipSet", Id = setId })
	else
		if set and PlayerData.Currencies.Won.Get() < set.Price then
			self:_toast("Not enough coins")
			Sounds.Play("Wrong")
			Juice.Shake(self._frame.Panel.Header.Balance)
			self:ShowTab("Coins")
			return
		end
		ShopRemote:Fire({ Action = "BuySet", Id = setId })
	end
end

function Shop:_toast(message: string)
	local toast = self._frame:FindFirstChild("Toast")
	if not toast then
		return
	end
	toast.Text = message
	toast.Visible = true
	Juice.SlideIn(toast, 24)
	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(2.2, function()
		if self._toastToken == token then
			toast.Visible = false
		end
	end)
end

local function promptPass(pass)
	if (pass.GamePassId or 0) > 0 then
		MarketplaceService:PromptGamePassPurchase(LOCAL_PLAYER, pass.GamePassId)
	end
end

-- ---------------------------------- Pages --------------------------------- --

function Shop:_restockText(): string
	local _, ends = ShopCatalog.RotationWindow()
	return `Restocks in {ShopCatalog.Countdown(ends - os.time())}`
end

function Shop:_fillFeatured()
	local page = self._pages.Featured
	local set, ends = ShopCatalog.Featured()
	local card = page.FeaturedSet
	if set then
		card:SetAttribute("SetId", set.Id)
		card.Tag.Text = `FEATURED · LEAVES IN {string.upper(ShopCatalog.Countdown(ends - os.time()))}`
		card.SetName.Text = set.Name
		card.Blurb.Text = set.Blurb or `{set.Rarity} stage skin, platform + mic`
		card.Art.Stage.BackgroundColor3 = C(set.Stage)
		card.Art.Platform.BackgroundColor3 = C(set.Platform)
		local owned = owns(PlayerData.Inventory.Sets, set.Id)
		local equipped = owned and setEquipped(set)
		if equipped then
			setButton(card.Action, "Equipped", { Icon = false, Colour = GREY, Enabled = false })
		elseif owned then
			setButton(card.Action, "Equip", { Icon = false, Colour = WHITE })
		else
			setButton(card.Action, fmt(set.Price), {})
		end
	end

	local vip = ShopCatalog.GetPass("VIP")
	if vip then
		page.Vip.PassName.Text = vip.Name
		for i = 1, 3 do
			local perk = page.Vip.Perks:FindFirstChild("Perk" .. i)
			if perk then
				perk.Text = vip.Perks and vip.Perks[i] or ""
				perk.Visible = vip.Perks ~= nil and vip.Perks[i] ~= nil
			end
		end
		self:_fillPassButton(page.Vip.Action, vip)
	end

	page.TitleRow.Chip.Text = self:_restockText()
	local rotation = ShopCatalog.Rotation()
	for i = 1, 4 do
		self:_fillSetCard(page.Grid["Card" .. i], rotation[i])
	end
end

function Shop:_fillSets()
	local page = self._pages.Sets
	page.TitleRow.Chip.Text = self:_restockText()
	local rotation = ShopCatalog.Rotation()
	for i = 1, 4 do
		self:_fillSetCard(page.Grid["Card" .. i], rotation[i])
	end
end

-- Packs: company or group packs (Modules/Library/Packs), depending on the switch.
function Shop:_buildPacks()
	self._packs = Packs.Rotation(self._packKind)
	self._packWindow = Packs.RotationWindow()
	self._packOffset = math.clamp(self._packOffset, 0, math.max(0, #self._packs - PACK_SLOTS))
end

function Shop:_setPackKind(kind: string)
	if kind == self._packKind then
		return
	end
	self._packKind = kind
	self._packOffset = 0
	self._packIndex = 1
	self:_buildPacks()
	self:_refresh()
	self:_animatePage("Packs")
end

function Shop:_fillPacks()
	local page = self._pages.Packs
	local picker = page.Picker
	local visible = math.min(PACK_SLOTS, #self._packs - self._packOffset)
	self._packIndex = math.clamp(self._packIndex, 1, math.max(visible, 1))

	-- switch + pager
	local switch = page.Header:FindFirstChild("Kind")
	if switch then
		for _, kind in { "Company", "Group" } do
			local b = switch:FindFirstChild(if kind == "Company" then "Companies" else "Groups")
			local on = kind == self._packKind
			b.BackgroundColor3 = if on then INK else WHITE
			b.TextColor3 = if on then YELLOW else C("5C566B")
		end
	end
	local paged = #self._packs > PACK_SLOTS
	for _, n in { "PickerPrev", "PickerNext" } do
		local b = page:FindFirstChild(n)
		if b then
			b.Visible = paged
		end
	end
	local chip = page.Header:FindFirstChild("Chip")
	if chip then
		local _, ends = Packs.RotationWindow()
		chip.Text = `Restocks in {ShopCatalog.Countdown(ends - os.time())}`
	end
	if page:FindFirstChild("Note") then
		page.Note.Text = if self._packKind == "Group" then "Group songs also count toward their company pack." else "Songs you own go into My Pack."
	end

	for i = 1, PACK_SLOTS do
		local b = picker:FindFirstChild("Pack" .. i)
		local sh = picker:FindFirstChild("Pack" .. i .. "Shadow")
		local pack = self._packs[self._packOffset + i]
		b.Visible = pack ~= nil
		sh.Visible = pack ~= nil
		if pack then
			local have = 0
			for _, song in pack.Songs do
				if owns(PlayerData.Inventory.Songs, song.Id) then
					have += 1
				end
			end
			local done = have == #pack.Songs
			local selected = i == self._packIndex
			b.PackName.Text = pack.Name
			b.Sub.Text = if done then `All {#pack.Songs} owned` else `{have} / {#pack.Songs} owned`
			b.Chip.Visible = done
			b.BackgroundColor3 = if selected then INK else WHITE
			b.PackName.TextColor3 = if selected then YELLOW else INK
			b.Sub.TextColor3 = if selected then YELLOW else INK
			b.Cover.BackgroundColor3 = C(ShopCatalog.PACK_COLOURS[(self._packOffset + i - 1) % #ShopCatalog.PACK_COLOURS + 1])
			b.Cover:FindFirstChildOfClass("UIStroke").Color = if selected then YELLOW else INK
		end
	end

	local sel = page.Selected
	local pack = self._packs[self._packOffset + self._packIndex]
	sel.Visible = pack ~= nil
	if not pack then
		return
	end
	local missing = {}
	for _, song in pack.Songs do
		if not owns(PlayerData.Inventory.Songs, song.Id) then
			table.insert(missing, song)
		end
	end
	local count = #pack.Songs
	sel.Top.PackName.Text = pack.Name
	local company = if pack.Kind == "Group" and pack.Songs[1] then ` · {pack.Songs[1].Company}` else ""
	sel.Top.Count.Text = `{count} songs · you own {count - #missing}{company}`
	sel.Reward.Text = if #missing == 0 then `Title unlocked: {pack.Title}` else `Own all {count} → title: {pack.Title}`

	for i = 1, 12 do
		local row = sel.Songs:FindFirstChild("Song" .. i)
		local song = pack.Songs[i]
		row.Visible = song ~= nil
		if song then
			local owned = owns(PlayerData.Inventory.Songs, song.Id)
			row:SetAttribute("SongId", song.Id)
			row.SongTitle.Text = song.Name
			row.Artist.Text = song.Artist
			row.BackgroundColor3 = if owned then PAPER else WHITE
			row:FindFirstChildOfClass("UIStroke").Color = if owned then LINE else INK
			row.Owned.Visible = owned
			row.Buy.Visible = not owned
			setButton(row.Buy, fmt(ShopCatalog.SONG_PRICE), { Colour = YELLOW })
		end
	end

	local buyAll = sel.BuyAll
	local shadow = sel:FindFirstChild("BuyAllShadow")
	if #missing == 0 then
		sel.BuyAllTitle.Text = `You own the whole {pack.Name} pack`
		sel.BuyAllSub.Text = "Every song in it is in My Pack."
		buyAll.Visible = false
	else
		local full = #missing * ShopCatalog.SONG_PRICE
		sel.BuyAllTitle.Text = `Buy the {#missing} {pack.Name} songs you're missing`
		sel.BuyAllSub.Text = `You only pay for songs you don't own · {math.floor(ShopCatalog.PACK_DISCOUNT * 100)}% off`
		buyAll.Visible = true
		setButton(buyAll, fmt(ShopCatalog.PackPrice(#missing)), { Old = if #missing > 1 then fmt(full) else nil })
	end
	if shadow then
		shadow.Visible = buyAll.Visible
	end
end

-- [[ Items: stages + mic stands ]]

local ITEM_OWNED = { Stage = "Stages", Mic = "Mics" }
local ITEM_EQUIPPED = { Stage = "EquippedStage", Mic = "EquippedMic" }

function Shop:_fillItemCard(holder: Frame, kind: string, item)
	holder.Visible = item ~= nil
	holder:SetAttribute("ItemId", item and item.Id or nil)
	if not item then
		return
	end
	local face = holder.Face
	local art = face.Art
	art.BackgroundColor3 = C(item.Bg)
	if kind == "Stage" then
		art.Stage.BackgroundColor3 = C(item.Stage)
		art.Platform.BackgroundColor3 = C(item.Platform)
	else
		art.Mic.BackgroundColor3 = C(item.Mic)
	end
	art.Rarity.Text = item.Rarity
	art.Rarity.BackgroundColor3 = C(ShopCatalog.RARITY_COLOURS[item.Rarity] or "FFFFFF")
	face.ItemName.Text = item.Name
	local owned = owns(PlayerData.Inventory[ITEM_OWNED[kind]], item.Id)
	local equipped = PlayerData.Inventory[ITEM_EQUIPPED[kind]].Get() == item.Id
	if equipped then
		setButton(face.Action, "Equipped", { Icon = false, Colour = GREY, Enabled = false })
	elseif owned then
		setButton(face.Action, "Equip", { Icon = false, Colour = WHITE })
	else
		setButton(face.Action, fmt(item.Price), { Colour = MINT })
	end
end

function Shop:_fillItems()
	local page = self._pages.Items
	page.Chip.Text = self:_restockText()
	for _, kind in { "Stage", "Mic" } do
		local rotation = ShopCatalog.ItemRotation(kind)
		local grid = page[kind .. "Grid"]
		for i = 1, 4 do
			self:_fillItemCard(grid["Card" .. i], kind, rotation[i])
		end
	end
end

function Shop:_itemAction(kind: string, id: string?)
	if not id then
		return
	end
	if PlayerData.Inventory[ITEM_EQUIPPED[kind]].Get() == id then
		return
	end
	if owns(PlayerData.Inventory[ITEM_OWNED[kind]], id) then
		ShopRemote:Fire({ Action = "EquipItem", Kind = kind, Id = id })
		return
	end
	local item = ShopCatalog.GetItem(kind, id)
	if item and PlayerData.Currencies.Won.Get() < (item.Price or 0) then
		self:_toast("Not enough coins")
		Sounds.Play("Wrong")
		Juice.Shake(self._frame.Panel.Header.Balance)
		self:ShowTab("Coins")
		return
	end
	ShopRemote:Fire({ Action = "BuyItem", Kind = kind, Id = id })
end

function Shop:_fillPassButton(button: GuiButton, pass)
	if owns(PlayerData.GamePasses, pass.Id) then
		setButton(button, "Owned", { Icon = false, Colour = GREY, Enabled = false })
	elseif (pass.GamePassId or 0) > 0 then
		setButton(button, tostring(pass.Robux), {})
	else
		setButton(button, "Soon", { Icon = false, Colour = GREY, Enabled = false })
	end
end

function Shop:_fillCoins()
	local page = self._pages.Coins
	for i = 1, 3 do
		local holder = page.Bundles:FindFirstChild("Bundle" .. i)
		local bundle = ShopCatalog.CoinBundles[i]
		holder.Visible = bundle ~= nil
		if bundle then
			local face = holder.Face
			face.Amount.Text = `{fmt(bundle.Amount)} coins`
			face.Sub.Text = bundle.Sub
			face.Art.BackgroundColor3 = C(bundle.Bg)
			local layout = COIN_LAYOUTS[bundle.Coins] or COIN_LAYOUTS[1]
			for c = 1, 6 do
				local img = face.Art:FindFirstChild("Coin" .. c)
				local spot = layout[c]
				img.Visible = spot ~= nil
				if spot then
					img.Position = UDim2.fromScale(spot[1] / 100, spot[2] / 100)
					img.ZIndex = c
				end
			end
			holder.Best.Visible = bundle.Best == true
			if (bundle.ProductId or 0) > 0 then
				setButton(face.Action, tostring(bundle.Robux), {})
			else
				setButton(face.Action, "Soon", { Icon = false, Colour = GREY, Enabled = false })
			end
		end
	end
	for i = 1, 2 do
		local card = page:FindFirstChild("Pass" .. i)
		local pass = ShopCatalog.Passes[i]
		card.Visible = pass ~= nil
		if pass then
			card.BackgroundColor3 = C(pass.Bg)
			card.PassName.Text = pass.Name
			card.Sub.Text = pass.Sub
			local isCrown = pass.Icon == "Crown"
			card.IconCircle.IconText.Visible = not isCrown
			card.IconCircle.IconText.Text = if isCrown then "" else pass.Icon
			card.IconCircle.IconImage.Visible = isCrown
			self:_fillPassButton(card.Action, pass)
		end
	end
end

function Shop:_refresh()
	if not self._frame or not self._frame.Visible then
		return
	end
	local coins = PlayerData.Currencies.Won.Get()
	if self._shownCoins ~= coins then
		local balance = self._frame.Panel.Header.Balance
		if self._shownCoins then
			-- roll the number and punch the chip when it changes while you're looking
			Juice.CountUp(balance.Amount, self._shownCoins, coins, fmt)
			Juice.Pop(balance, if coins > self._shownCoins then 0.18 else 0.1)
		else
			balance.Amount.Text = fmt(coins)
		end
		self._shownCoins = coins
	end
	if self._tab == "Featured" then
		self:_fillFeatured()
	elseif self._tab == "Sets" then
		self:_fillSets()
	elseif self._tab == "Items" then
		self:_fillItems()
	elseif self._tab == "Packs" then
		self:_fillPacks()
	elseif self._tab == "Coins" then
		self:_fillCoins()
	end
end

function Shop:ShowTab(name: string, force: boolean?)
	if not table.find(TABS, name) then
		name = "Featured"
	end
	local changed = self._tab ~= name
	self._tab = name
	for _, tab in TABS do
		local holder = self._frame.Panel.Header.Tabs[tab]
		local on = tab == name
		holder.Button.BackgroundTransparency = if on then 0 else 0.65
		-- buttons are centre-anchored (CenterButtons); the active tab sits 1px higher
		local base = holder.Button:GetAttribute("BaseY")
		if base == nil then
			base = holder.Button.Position.Y.Offset
			holder.Button:SetAttribute("BaseY", base)
		end
		local p = holder.Button.Position
		holder.Button.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, base - (if on then 1 else 0))
		holder.Shadow.Visible = on
		self._pages[tab].Visible = on
		if on and changed then
			Juice.Pop(holder.Button, 0.12)
		end
	end
	self:_refresh()
	if changed or force then
		self:_animatePage(name)
	end
end

-- What pops in (in order) when a page appears.
function Shop:_animatePage(name: string)
	local page = self._pages[name]
	local list = {}
	local function add(parent: Instance?, ...)
		if not parent then
			return
		end
		for _, n in { ... } do
			local child = parent:FindFirstChild(n)
			if child then
				table.insert(list, child)
			end
		end
	end
	if name == "Featured" then
		add(page, "FeaturedSetShadow", "FeaturedSet", "FeaturedNew", "VipShadow", "Vip", "TitleRow")
		add(page:FindFirstChild("Grid"), "Card1", "Card2", "Card3", "Card4")
	elseif name == "Sets" then
		add(page, "TitleRow")
		add(page:FindFirstChild("Grid"), "Card1", "Card2", "Card3", "Card4")
		add(page, "FooterShadow", "Footer")
	elseif name == "Items" then
		add(page, "StageRow", "Chip")
		add(page:FindFirstChild("StageGrid"), "Card1", "Card2", "Card3", "Card4")
		add(page, "MicRow")
		add(page:FindFirstChild("MicGrid"), "Card1", "Card2", "Card3", "Card4")
		add(page, "Footnote")
	elseif name == "Packs" then
		for i = 1, 5 do
			add(page.Picker, "Pack" .. i .. "Shadow", "Pack" .. i)
		end
		add(page, "SelectedShadow", "Selected")
	elseif name == "Coins" then
		add(page, "TitleRow")
		add(page:FindFirstChild("Bundles"), "Bundle1", "Bundle2", "Bundle3")
		add(page, "Pass1Shadow", "Pass1", "Pass2Shadow", "Pass2")
	end
	Juice.Stagger(list, 0.04)
end

-- Song rows cascade in when you pick a pack.
function Shop:_animateSongs()
	local list = {}
	for i = 1, 12 do
		table.insert(list, self._pages.Packs.Selected.Songs["Song" .. i])
	end
	Juice.Stagger(list, 0.025, 0.7)
end

-- -------------------------------- Lifecycle ------------------------------- --

function Shop:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Shop")
	self._frame.Visible = false
	local panel = self._frame.Panel
	self._pages = panel.Pages
	self:_buildPacks()
	ButtonScale.ApplyToDescendants(panel)

	local j = self._janitor
	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for _, tab in TABS do
		j:Add(panel.Header.Tabs[tab].Button.Activated:Connect(function()
			self:ShowTab(tab)
		end))
	end

	-- set cards (Featured grid, Sets grid, featured set)
	for _, page in { self._pages.Featured, self._pages.Sets } do
		for i = 1, 4 do
			local holder = page.Grid["Card" .. i]
			j:Add(holder.Face.Action.Activated:Connect(function()
				self:_setAction(holder:GetAttribute("SetId"))
			end))
		end
	end
	j:Add(self._pages.Featured.FeaturedSet.Action.Activated:Connect(function()
		self:_setAction(self._pages.Featured.FeaturedSet:GetAttribute("SetId"))
	end))
	j:Add(self._pages.Featured.Vip.Action.Activated:Connect(function()
		local vip = ShopCatalog.GetPass("VIP")
		if vip then
			promptPass(vip)
		end
	end))

	-- items
	local itemsPage = self._pages.Items
	for _, kind in { "Stage", "Mic" } do
		for i = 1, 4 do
			local holder = itemsPage[kind .. "Grid"]["Card" .. i]
			j:Add(holder.Face.Action.Activated:Connect(function()
				self:_itemAction(kind, holder:GetAttribute("ItemId"))
			end))
		end
	end

	-- packs
	local packs = self._pages.Packs
	j:Add(packs.Header.Kind.Companies.Activated:Connect(function()
		self:_setPackKind("Company")
	end))
	j:Add(packs.Header.Kind.Groups.Activated:Connect(function()
		self:_setPackKind("Group")
	end))
	for step, n in { [-1] = "PickerPrev", [1] = "PickerNext" } do
		j:Add(packs[n].Activated:Connect(function()
			local max = math.max(0, #self._packs - PACK_SLOTS)
			local nextOffset = math.clamp(self._packOffset + step * PACK_SLOTS, 0, max)
			if nextOffset ~= self._packOffset then
				self._packOffset = nextOffset
				self._packIndex = 1
				self:_refresh()
				self:_animatePage("Packs")
			end
		end))
	end
	for i = 1, 5 do
		j:Add(packs.Picker["Pack" .. i].Activated:Connect(function()
			local changed = self._packIndex ~= i
			self._packIndex = i
			self:_refresh()
			if changed then
				Juice.Pop(packs.Picker["Pack" .. i], 0.08)
				self:_animateSongs()
			end
		end))
	end
	for i = 1, 12 do
		local row = packs.Selected.Songs["Song" .. i]
		j:Add(row.Buy.Activated:Connect(function()
			local id = row:GetAttribute("SongId")
			if not id then
				return
			end
			if PlayerData.Currencies.Won.Get() < ShopCatalog.SONG_PRICE then
				self:_toast("Not enough coins")
				Sounds.Play("Wrong")
				return
			end
			ShopRemote:Fire({ Action = "BuySong", Id = id })
		end))
	end
	j:Add(packs.Selected.BuyAll.Activated:Connect(function()
		local pack = self._packs[self._packOffset + self._packIndex]
		if pack then
			ShopRemote:Fire({ Action = "BuyPack", Id = pack.Id })
		end
	end))

	-- coins + passes (Robux)
	local coins = self._pages.Coins
	for i = 1, 3 do
		j:Add(coins.Bundles["Bundle" .. i].Face.Action.Activated:Connect(function()
			local bundle = ShopCatalog.CoinBundles[i]
			if bundle and (bundle.ProductId or 0) > 0 then
				MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, bundle.ProductId)
			end
		end))
	end
	for i = 1, 2 do
		j:Add(coins["Pass" .. i].Action.Activated:Connect(function()
			local pass = ShopCatalog.Passes[i]
			if pass then
				promptPass(pass)
			end
		end))
	end

	-- server replies
	j:Add(ShopRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Result" then
			self:_toast(packet.Text or "")
			if packet.Ok and packet.Action ~= "EquipSet" and packet.Action ~= "EquipItem" then
				Sounds.Play("Coins")
			elseif not packet.Ok then
				Sounds.Play("Wrong")
			end
		end
	end))

	-- live data → redraw
	for _, path in {
		PlayerData.Currencies.Won,
		PlayerData.Inventory.Sets,
		PlayerData.Inventory.Stages,
		PlayerData.Inventory.Mics,
		PlayerData.Inventory.EquippedStage,
		PlayerData.Inventory.EquippedMic,
		PlayerData.Inventory.Songs,
		PlayerData.GamePasses,
	} do
		j:Add(path.Observe(function()
			self:_refresh()
		end))
	end

	-- countdowns + rotation changes while open
	j:Add(task.spawn(function()
		while true do
			task.wait(1)
			if self.State == "Active" then
				local window = ShopCatalog.RotationWindow()
				if window ~= self._window then
					self._window = window
				end
				if Packs.RotationWindow() ~= self._packWindow then
					self:_buildPacks() -- new packs in the shop
				end
				self:_refresh()
			end
		end
	end), true)
end

function Shop:Activate(tab: string?)
	self._frame.Visible = true
	self:ShowTab(tab or self._tab or "Featured", true)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Shop:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Shop:Destroy()
	self._janitor:Destroy()
end

return Shop
