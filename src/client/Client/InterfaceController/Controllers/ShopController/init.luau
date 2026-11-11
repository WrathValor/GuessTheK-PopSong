--| ShopController
-- The shop (Interface.Frames.Shop, built in Studio from the "Shop v3" board): one scrolling
-- page under the usual header. Top to bottom: the featured set, the Headliner (the featured
-- bundle), "Bundles": the one-time Debut Pack then the other bundles (ShopCatalog.Bundles:
-- tickets + upgrades + coins), the
-- four stage sets in the rotation, the stages + mic stands in the rotation, the banners +
-- photocards in the rotation (a set, or either half), roll tickets + card upgrades (Robux
-- bundles, the "Rolls" section), the coin bundles, the passes and the code box. Fills everything from ShopCatalog + the player's data;
-- purchases are only requests, the server (ShopService, RewardsService for codes) checks and
-- applies them. The song roll and the group's UGC are their own screens (RollController,
-- UGCController). Open with Interface:Open("Shop", "Coins") to land on the coin bundles.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)
local FitPanel = require(ReplicatedStorage.Modules.UI.FitPanel)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local Prices = require(ReplicatedStorage.Modules.Prices)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")
local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local PINK = C("FF9EC4")
local RED = C("FF5A4E")

local Currencies = require(ReplicatedStorage.Constants.Currencies)
local COIN = Currencies.Coins.Icon
local ROBUX = "rbxassetid://83637405007021"

local SCROLL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ITEM_OWNED = { Stage = "Stages", Mic = "Mics" }
local ITEM_EQUIPPED = { Stage = "EquippedStage", Mic = "EquippedMic" }
local PASS_CARDS = { VIP = "VIP", DoubleCoins = "DoubleCoins" } -- card name → ShopCatalog pass id
local ROLL_CARDS = { "Tickets", "Upgrades" } -- the Rolls section's cards, by Currencies id

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
	return (self :: any) :: UITypes.Controller
end

-- --------------------------------- Helpers -------------------------------- --

local function owns(path, id: string): boolean
	local ok, has = pcall(path.Has, id)
	return ok and has == true
end

-- Sets an action button (built with Icon + Label children): label, icon (Coin / Robux / none),
-- colour, and whether it can be pressed. Its <name>Shadow hides while it can't be pressed.
local function setButton(button: GuiButton, label: string, opts: { Icon: string?, Colour: Color3?, Enabled: boolean? })
	local lbl = button:FindFirstChild("Label") :: TextLabel
	local icon = button:FindFirstChild("Icon") :: ImageLabel
	lbl.Text = label
	icon.Visible = opts.Icon ~= nil
	if opts.Icon then
		icon.Image = opts.Icon
	end
	button.BackgroundColor3 = opts.Colour or MINT
	local enabled = opts.Enabled ~= false
	button.Active = enabled
	button.AutoButtonColor = false
	local shadow = button.Parent and button.Parent:FindFirstChild(button.Name .. "Shadow")
	if shadow then
		shadow.Visible = enabled
	end
end

-- a Robux button: the live price (Modules/Prices), "…" while it loads, "Soon" when off sale
-- or before the product exists (id 0)
local function setRobuxButton(button: GuiButton, kind: string, id: number?)
	if (id or 0) <= 0 then
		setButton(button, "Soon", { Colour = GREY, Enabled = false })
		return
	end
	local price, forSale = Prices.Get(kind, id)
	if price then
		setButton(button, fmt(price), { Icon = ROBUX })
	elseif forSale == nil then
		setButton(button, "…", { Enabled = false })
	else
		setButton(button, "Soon", { Colour = GREY, Enabled = false })
	end
end

-- A set counts as equipped while you wear both of its pieces.
local function setEquipped(set): boolean
	local stage, mic = ShopCatalog.SetPieces(set)
	return PlayerData.Inventory.EquippedStage.Get() == stage.Id and PlayerData.Inventory.EquippedMic.Get() == mic.Id
end

-- Buy / Equip / Equipped on a set's button
local function setSetButton(button: GuiButton, set)
	local owned = owns(PlayerData.Inventory.Sets, set.Id)
	if owned and setEquipped(set) then
		setButton(button, "Equipped", { Colour = GREY, Enabled = false })
	elseif owned then
		setButton(button, "Equip", { Colour = WHITE })
	else
		setButton(button, fmt(set.Price), { Icon = COIN })
	end
end

local function paintRarity(art: Instance, rarity: string)
	local chip = art:FindFirstChild("Rarity") :: TextLabel?
	if chip then
		chip.Text = rarity
		chip.BackgroundColor3 = C(ShopCatalog.RARITY_COLOURS[rarity] or "FFFFFF")
	end
end

local function promptPass(pass)
	if pass and (pass.GamePassId or 0) > 0 then
		MarketplaceService:PromptGamePassPurchase(LOCAL_PLAYER, pass.GamePassId)
	end
end

local function promptProduct(id: number?)
	if (id or 0) > 0 then
		MarketplaceService:PromptProductPurchase(LOCAL_PLAYER, id :: number)
	end
end

-- the coin bundles on sale (a Hidden bundle still grants if bought before, but isn't shown)
local function shownBundles(): { any }
	local out = {}
	for _, bundle in ShopCatalog.CoinBundles do
		if not bundle.Hidden then
			table.insert(out, bundle)
		end
	end
	return out
end

-- ----------------------------------- Toast ---------------------------------- --

function Shop:_toast(message: string)
	local toast = self._frame:FindFirstChild("Toast")
	if not toast or message == "" then
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

function Shop:_notEnoughCoins()
	self:_toast("Not enough coins")
	Sounds.Play("Wrong")
	Juice.Shake(self._frame.Panel.Header.Balance)
	self:ScrollTo("Coins")
end

-- --------------------------------- Scrolling -------------------------------- --

-- Scrolls the page so a section (Featured, Sets, Pieces, Coins, Passes, Codes) sits at the top.
function Shop:ScrollTo(section: string?, instant: boolean?)
	local scroll = self._scroll
	local target = section and scroll:FindFirstChild(section)
	local y = 0
	if target then
		-- CanvasPosition is in screen pixels, like AbsolutePosition; leave a small gap above
		y = target.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y - 12
	end
	local maxY = math.max(scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y, 0)
	local to = Vector2.new(0, math.clamp(y, 0, maxY))
	if instant then
		scroll.CanvasPosition = to
	else
		TweenService:Create(scroll, SCROLL_TWEEN, { CanvasPosition = to }):Play()
	end
end

-- ---------------------------------- Sections -------------------------------- --

function Shop:_fillFeatured()
	local face = self._scroll.Featured.Face
	local set, ends = ShopCatalog.Featured()
	self._scroll.Featured.Visible = set ~= nil
	face:SetAttribute("SetId", set and set.Id or nil)
	if not set then
		return
	end
	face.Timer.Text = `Leaves in {ShopCatalog.Countdown(ends - os.time())}`
	if self._featuredId ~= set.Id then
		self._featuredId = set.Id
		face.SetName.Text = set.Name
		face.Desc.Text = set.Blurb or `{set.Rarity} stage skin, spot platform and mic`
		face.Art.BackgroundColor3 = C(set.Bg)
		paintRarity(face.Art, set.Rarity)
		CosmeticView.Show(face.Art, "Set", set.Id)
	end
	setSetButton(face.Buy, set)
end

function Shop:_fillDebut()
	local section = self._scroll.Debut
	local pack = ShopCatalog.DebutPack
	-- shown once the product exists. Once bought it stays, with a "Bought" button: a pack
	-- that vanishes from the shop reads as "my data got wiped"
	local show = pack ~= nil and (pack.ProductId or 0) > 0
	section.Visible = show
	if not show then
		return
	end
	local bought = owns(PlayerData.Rewards.Claimed, pack.Id)
	local face = section.Face
	local items = face.Items
	if face:FindFirstChild("Count") then
		face.Count.Text = `{#pack.Items} ITEMS`
	end
	if face:FindFirstChild("Note") then
		face.Note.Text = if bought then "0/1 left" else "1/1 left"
	end
	for i = 1, 4 do
		-- (Item n is a tilted photocard slot: Shadow + Card; Plus n-1 sits before it)
		local slot = items:FindFirstChild("Item" .. i)
		local entry = pack.Items[i]
		slot.Visible = entry ~= nil
		local plus = items:FindFirstChild("Plus" .. (i - 1))
		if plus then
			plus.Visible = entry ~= nil
		end
		local tile = slot:FindFirstChild("Card") or slot
		if slot:FindFirstChild("Only") then
			slot.Only.Visible = entry ~= nil and entry.Only == true
		end
		if entry then
			tile.Label.Text = entry.Label
			if tile:FindFirstChild("Sub") then
				tile.Sub.Text = entry.Sub or ""
			end
			-- what's inside: a coin pile image, or the actual stage / mic model,
			-- each on its own pastel tile (not the night card the other model cards use)
			local art = tile.Art
			if entry.Kind then
				CosmeticView.Show(art, entry.Kind, entry.Id)
				local night = art:FindFirstChild("CardGradient")
				if night then
					night.Enabled = false
				end
				art.BackgroundColor3 = C(entry.Colour)
			else
				art.BackgroundColor3 = C(entry.Colour)
				art.Pic.Image = entry.Image or ""
				art.Pic.Visible = entry.Image ~= nil
				-- (the coin pile: a touch bigger than its box, nudged up onto the coins)
				art.Pic.AnchorPoint = Vector2.new(0.5, 0.56)
				art.Pic.Size = UDim2.fromScale(1.1, 1.1)
			end
		end
	end
	if bought then
		setButton(section.Face.Buy, "Bought", { Colour = GREY, Enabled = false })
	else
		setRobuxButton(section.Face.Buy, "Product", pack.ProductId)
	end
end

-- [[ Bundles ]] one banner from a ShopCatalog.Bundles entry (Build.AddBundles made them)
local BUNDLE_KIND = { Tickets = "Roll tickets", Upgrades = "Card upgrades", Coins = "Coins" }
local BUNDLE_ART = { Tickets = "DCD3FF", Upgrades = "9ED8F5", Coins = "FFE07A", Stage = "D8F6F2", Mic = "D8F6F2" } -- (the Spotlight set's teal)

-- the shop's coin pile that fits an amount
local function pileFor(amount: number): string
	local best = ShopCatalog.CoinBundles[1].Pile
	for _, b in ShopCatalog.CoinBundles do
		if b.Amount <= amount and not b.Hidden then
			best = b.Pile
		end
	end
	return best
end

-- times this player bought a bundle (Rewards.Bundles)
local function bundleBought(id: string): number
	local ok, all = pcall(PlayerData.Rewards.Bundles.Get)
	return if ok and type(all) == "table" then all[id] or 0 else 0
end

local function fillBundle(holder: Instance?, bundle)
	if not holder then
		return
	end
	holder.Visible = bundle ~= nil
	if not bundle then
		return
	end
	local face = holder.Face
	face:SetAttribute("BundleId", bundle.Id)
	face.Title.Text = bundle.Name
	face.Sub.Text = bundle.Sub or ""
	face.Tag.Visible = bundle.Tag ~= nil
	face.Tag.Text = bundle.Tag or ""
	face.Tag.BackgroundColor3 = C(bundle.TagColour or "FF9EC4")
	local g = bundle.Gradient or { "FFFFFF", "FFFFFF" }
	face.Tint.Color = ColorSequence.new(C(g[1]), C(g[2]))
	local contents = ShopCatalog.BundleContents(bundle)
	if face:FindFirstChild("Count") then
		face.Count.Text = `{#contents} ITEMS`
		-- big banner: the line + chip follow the title however many lines it takes (like the
		-- Debut Pack's), and the block stays centred in the banner
		local titleH = math.max(face.Title.TextBounds.Y, 30)
		local subH = math.max(face.Sub.TextBounds.Y, 16)
		local blockH = titleH + 6 + subH + 10 + face.Count.Size.Y.Offset
		local top = math.floor((face.Size.Y.Offset - blockH) / 2)
		face.Title.Position = UDim2.fromOffset(face.Title.Position.X.Offset, top)
		face.Sub.Position = UDim2.fromOffset(face.Sub.Position.X.Offset, top + titleH + 6)
		face.Count.Position = UDim2.fromOffset(face.Count.Position.X.Offset, top + titleH + 6 + subH + 10)
	end
	local ownsSet = true
	for i = 1, 5 do
		local slot = face.Items:FindFirstChild("Item" .. i)
		if not slot then
			break
		end
		local entry = contents[i]
		slot.Visible = entry ~= nil
		local plus = face.Items:FindFirstChild("Plus" .. (i - 1))
		if plus then
			plus.Visible = entry ~= nil
		end
		if entry then
			local tile = slot.Card
			local art = tile.Art
			art.BackgroundColor3 = C(BUNDLE_ART[entry.Kind] or "FFFFFF")
			local isItem = entry.Kind == "Stage" or entry.Kind == "Mic"
			slot.Only.Visible = isItem
			if isItem then
				local item = ShopCatalog.GetItem(entry.Kind, entry.Id)
				local mine = owns(PlayerData.Inventory[ITEM_OWNED[entry.Kind]], entry.Id)
				ownsSet = ownsSet and mine
				slot.Only.Text = if mine then "✓ OWNED" else "ONLY HERE"
				slot.Only.BackgroundColor3 = if mine then MINT else C("FFE07A")
				tile.Label.Text = entry.Kind -- "Stage" / "Mic"
				tile.Sub.Text = if item then item.Name else ""
				art.Pic.Visible = false
				if art:GetAttribute("Shown") ~= entry.Id then
					art:SetAttribute("Shown", entry.Id)
					CosmeticView.Show(art, entry.Kind, entry.Id) -- the real model
					local night = art:FindFirstChild("CardGradient")
					if night then
						night.Enabled = false
					end
				end
			else
				local coins = entry.Kind == "Coins"
				tile.Label.Text = if coins then fmt(entry.Amount) else `×{entry.Amount}`
				tile.Sub.Text = BUNDLE_KIND[entry.Kind]
				art.Pic.Visible = true
				art.Pic.Image = if coins then pileFor(entry.Amount) else Currencies.Get(entry.Kind).Icon
				-- the coin pile sits low in its square image: a touch bigger, nudged up onto the coins
				art.Pic.AnchorPoint = Vector2.new(0.5, if coins then 0.56 else 0.5)
				art.Pic.Size = UDim2.fromScale(if coins then 1.1 else 0.8, if coins then 1.1 else 0.8)
			end
		end
	end
	-- purchase limit: "2/2 left", then Bought / Sold out
	local limit = bundle.Limit or 1
	local left = math.max(0, limit - bundleBought(bundle.Id))
	face.Note.Text = `{left}/{limit} left`
	if left <= 0 then
		setButton(face.Buy, if limit == 1 then "Bought" else "Sold out", { Colour = GREY, Enabled = false })
	else
		setRobuxButton(face.Buy, "Product", bundle.ProductId)
	end
end

function Shop:_fillBundles()
	local scroll = self._scroll
	local big, small = nil, {}
	for _, b in ShopCatalog.Bundles do
		if b.Hidden then
			continue
		elseif b.Big and not big then
			big = b
		elseif not b.Big then
			table.insert(small, b)
		end
	end
	fillBundle(scroll:FindFirstChild("Headliner"), big)
	local list = scroll:FindFirstChild("Bundles")
	if list then
		for i = 1, 3 do
			fillBundle(list:FindFirstChild("Bundle" .. i), small[i])
		end
	end
end

-- the time the rotations are shown for, and the restock chip: a VIP's restocks come early
-- (ShopCatalog.ShopTime / VIP_EARLY_SECONDS)
local function shopTime(): (number, string)
	local vip = LOCAL_PLAYER:GetAttribute("VIP") == true
	local t = ShopCatalog.ShopTime(vip)
	local left = ShopCatalog.Countdown(select(2, ShopCatalog.RotationWindow(t)) - t)
	return t, if vip then `VIP · restocks in {left}` else `Restocks in {left}`
end

function Shop:_fillSets()
	local t, chip = shopTime()
	self._scroll.SetsTitle.Chip.Text = chip
	local rotation = ShopCatalog.Rotation(t)
	local sets = self._scroll.Sets
	for i = 1, 4 do
		local card = sets["Set" .. i]
		local set = rotation[i]
		card.Visible = set ~= nil
		sets["Set" .. i .. "Shadow"].Visible = set ~= nil
		card:SetAttribute("SetId", set and set.Id or nil)
		if set then
			if card:GetAttribute("Shown") ~= set.Id then
				card:SetAttribute("Shown", set.Id)
				card.SetName.Text = set.Name
				card.Art.BackgroundColor3 = C(set.Bg)
				paintRarity(card.Art, set.Rarity)
				CosmeticView.Show(card.Art, "Set", set.Id)
			end
			local new = card:FindFirstChild("New")
			if new then
				new.Visible = set.New == true
			end
			setSetButton(card.Action, set)
		end
	end
end

function Shop:_fillPieces()
	local pieces = self._scroll.Pieces
	for _, kind in { "Stage", "Mic" } do
		local rotation = ShopCatalog.ItemRotation(kind, (shopTime()))
		for i = 1, 4 do
			local card = pieces[kind .. i]
			local item = rotation[i]
			card.Visible = item ~= nil
			pieces[kind .. i .. "Shadow"].Visible = item ~= nil
			card:SetAttribute("ItemId", item and item.Id or nil)
			if item then
				if card:GetAttribute("Shown") ~= item.Id then
					card:SetAttribute("Shown", item.Id)
					card.ItemName.Text = item.Name
					card.Art.BackgroundColor3 = C(item.Bg)
					card.Rarity.Text = item.Rarity
					card.Rarity.BackgroundColor3 = C(ShopCatalog.RARITY_COLOURS[item.Rarity] or "FFFFFF")
					CosmeticView.Show(card.Art, kind, item.Id)
				end
				local equipped = PlayerData.Inventory[ITEM_EQUIPPED[kind]].Get() == item.Id
				if equipped then
					setButton(card.Action, "Equipped", { Colour = GREY, Enabled = false })
				elseif owns(PlayerData.Inventory[ITEM_OWNED[kind]], item.Id) then
					setButton(card.Action, "Equip", { Colour = WHITE })
				else
					setButton(card.Action, fmt(item.Price), { Icon = COIN })
				end
			end
		end
	end
end

-- [[ Banners + photocards ]]

local STYLE_OWNED = { Banner = "Banners", Photocard = "Photocards" }
local STYLE_WORN = { Banner = "Banner", Photocard = "Photocard" }
local STYLE_FREE = { Banner = SeasonConstants.FREE_BANNERS, Photocard = SeasonConstants.FREE_PHOTOCARDS }

local function ownsStyle(kind: string, id: string): boolean
	return STYLE_FREE[kind][id] == true or owns(PlayerData.Inventory[STYLE_OWNED[kind]], id)
end

local function wearing(kind: string, id: string): boolean
	local worn = PlayerData.Inventory[STYLE_WORN[kind]].Get()
	return worn == id or (worn == "" and id == SeasonConstants["DEFAULT_" .. string.upper(kind)])
end

-- what a style button would do: "Buy" (+ price), "Equip" or nil (nothing: already on)
local function styleAction(kind: string, id: string): (string?, number?)
	if kind == "Set" then
		local hasB, hasC = ownsStyle("Banner", id), ownsStyle("Photocard", id)
		if hasB and hasC then
			return if wearing("Banner", id) and wearing("Photocard", id) then nil else "Equip", nil
		elseif hasB then
			return "Buy", ShopCatalog.StylePrice(id, "Photocard")
		elseif hasC then
			return "Buy", ShopCatalog.StylePrice(id, "Banner")
		end
		return "Buy", ShopCatalog.StylePrice(id, "Set")
	end
	if ownsStyle(kind, id) then
		return if wearing(kind, id) then nil else "Equip", nil
	end
	return "Buy", ShopCatalog.StylePrice(id, kind)
end

-- the small half buttons: kind label over coin + price / Owned
local function setHalfButton(button: GuiButton, kind: string, id: string)
	local owned = ownsStyle(kind, id)
	button.BackgroundColor3 = if owned then GREY else WHITE
	button.Active = not owned
	button.Row.Icon.Visible = not owned
	button.Row.Label.Text = if owned then "Owned" else fmt(ShopCatalog.StylePrice(id, kind) or 0)
	local shadow = button.Parent:FindFirstChild(button.Name .. "Shadow")
	if shadow then
		shadow.Visible = not owned
	end
end

function Shop:_fillStyle()
	local title = self._scroll:FindFirstChild("StyleTitle")
	local section = self._scroll:FindFirstChild("Style")
	if not title or not section then
		return -- not built yet (SeasonController/Build.ShopStyle)
	end
	local t, chip = shopTime()
	title.Chip.Text = chip
	local rotation = ShopCatalog.StyleRotation(t)
	for i = 1, 4 do
		local card = section["Style" .. i]
		local spec = rotation[i]
		card.Visible = spec ~= nil
		section["Style" .. i .. "Shadow"].Visible = spec ~= nil
		card:SetAttribute("StyleId", spec and spec.Id or nil)
		if spec then
			local id = spec.Id
			if card:GetAttribute("Shown") ~= id then
				card:SetAttribute("Shown", id)
				card.SetName.Text = spec.Name
				local art = card.Art
				SeasonArt.PaintBanner(art.Banner, id)
				local avatar = art.Card.Photo:FindFirstChild("Avatar")
				if avatar then
					avatar.Image = `rbxthumb://type=AvatarBust&id={LOCAL_PLAYER.UserId}&w=150&h=150`
				end
				SeasonArt.PaintPhotocard(art.Card, id)
				art.BackgroundColor3 = spec.Fill
				art.Animated.Visible = spec.Animated == true
			end
			-- Set: buy both / finish the set / equip it
			local action, price = styleAction("Set", id)
			local full = ShopCatalog.StylePrice(id, "Set") or 0
			local halves = (ShopCatalog.StylePrice(id, "Banner") or 0) + (ShopCatalog.StylePrice(id, "Photocard") or 0)
			local finishing = action == "Buy" and price ~= full
			local pre = card.SetBuy:FindFirstChild("Pre")
			if pre then
				pre.Visible = action == "Buy"
				pre.Text = if finishing then "Finish set" else "Set"
			end
			if action == "Buy" then
				setButton(card.SetBuy, fmt(price :: number), { Icon = COIN })
			elseif action == "Equip" then
				setButton(card.SetBuy, "Equip set", { Colour = WHITE })
			else
				setButton(card.SetBuy, "Equipped", { Colour = GREY, Enabled = false })
			end
			card.Save.Visible = action == "Buy" and not finishing
			card.Save.Text = `SAVE {fmt(halves - full)}`
			setHalfButton(card.BannerBuy, "Banner", id)
			setHalfButton(card.PhotocardBuy, "Photocard", id)
		end
	end
end

function Shop:_fillCoins()
	local face = self._scroll.Coins.Face
	local bundles = shownBundles()
	for i = 1, 5 do
		local holder = face:FindFirstChild("Bundle" .. i)
		local bundle = bundles[i]
		holder.Visible = bundle ~= nil
		if bundle then
			holder.Amount.Text = `{fmt(bundle.Amount)} coins`
			local tag = holder:FindFirstChild("Tag") :: TextLabel?
			if bundle.Tag and not tag then
				-- a sticker on a bundle that wasn't given one in Studio: borrow the BEST VALUE one
				local source = face:FindFirstChild("Tag", true)
				if source then
					tag = source:Clone()
					tag.Parent = holder
				end
			end
			if tag then
				tag.Visible = bundle.Tag ~= nil
				tag.Text = bundle.Tag or ""
				tag.BackgroundColor3 = if bundle.Tag == "BEST VALUE" then RED else PINK
			end
			setRobuxButton(holder.Buy, "Product", bundle.ProductId)
		end
	end
end

-- Rolls + upgrades: how many you have, and each card's three Robux bundles
function Shop:_fillRolls()
	local section = self._scroll:FindFirstChild("Rolls")
	if not section then
		return
	end
	for _, id in ROLL_CARDS do
		local face = section:FindFirstChild(id)
		if face then
			face.Have.Text = `You have {fmt(Currencies.Count(LOCAL_PLAYER, id))}`
			local bundles = ShopCatalog.RollBundlesFor(id)
			for i = 1, 3 do
				local tile = face:FindFirstChild("Bundle" .. i)
				local bundle = bundles[i]
				if tile then
					tile.Visible = bundle ~= nil
					if bundle then
						tile.Count.Text = `×{bundle.Amount}`
						tile.Tag.Visible = bundle.Tag ~= nil
						tile.Tag.Text = bundle.Tag or ""
						tile.Tag.BackgroundColor3 = if bundle.Tag == "BEST VALUE" then RED else PINK
						setRobuxButton(tile.Buy, "Product", bundle.ProductId)
					end
				end
			end
		end
	end
end

function Shop:_fillPasses()
	local passes = self._scroll.Passes
	for card, id in PASS_CARDS do
		local face = passes:FindFirstChild(card)
		local pass = ShopCatalog.GetPass(id)
		if face and pass then
			face.PassName.Text = pass.Name
			face.Desc.Text = pass.Sub
			if owns(PlayerData.GamePasses, pass.Id) then
				setButton(face.Action, "Owned", { Colour = GREY, Enabled = false })
			else
				setRobuxButton(face.Action, "GamePass", pass.GamePassId)
			end
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
	self:_fillFeatured()
	self:_fillDebut()
	self:_fillBundles()
	self:_fillSets()
	self:_fillPieces()
	self:_fillStyle()
	self:_fillRolls()
	self:_fillCoins()
	self:_fillPasses()
end

-- --------------------------------- Actions ---------------------------------- --

-- Clicked a set's button: buy it, or equip it if it's already yours.
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
			self:_notEnoughCoins()
			return
		end
		ShopRemote:Fire({ Action = "BuySet", Id = setId })
	end
end

function Shop:_itemAction(kind: string, id: string?)
	if not id or PlayerData.Inventory[ITEM_EQUIPPED[kind]].Get() == id then
		return
	end
	if owns(PlayerData.Inventory[ITEM_OWNED[kind]], id) then
		ShopRemote:Fire({ Action = "EquipItem", Kind = kind, Id = id })
		return
	end
	local item = ShopCatalog.GetItem(kind, id)
	if item and PlayerData.Currencies.Won.Get() < (item.Price or 0) then
		self:_notEnoughCoins()
		return
	end
	ShopRemote:Fire({ Action = "BuyItem", Kind = kind, Id = id })
end

-- kind = "Set" | "Banner" | "Photocard"
function Shop:_styleAction(kind: string, id: string?)
	if not id then
		return
	end
	local action, price = styleAction(kind, id)
	if action == "Equip" then
		ShopRemote:Fire({
			Action = "EquipStyle",
			Banner = if kind ~= "Photocard" then id else nil,
			Photocard = if kind ~= "Banner" then id else nil,
		})
	elseif action == "Buy" then
		if PlayerData.Currencies.Won.Get() < (price or 0) then
			self:_notEnoughCoins()
			return
		end
		ShopRemote:Fire({ Action = "BuyStyle", Kind = kind, Id = id })
	end
end

function Shop:_redeem()
	local box = self._scroll.Codes.Face.CodeBox
	local code = string.upper((box.Text:gsub("%s", "")))
	if code == "" then
		Juice.Shake(box, 0.25)
		return
	end
	RewardsRemote:Fire({ Action = "RedeemCode", Code = code })
end

-- -------------------------------- Lifecycle ------------------------------- --

function Shop:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Shop")
	self._frame.Visible = false
	local panel = self._frame.Panel
	local scroll = panel.Scroll
	self._scroll = scroll
	FitPanel.Watch(self._frame, self._janitor)
	ButtonScale.ApplyToDescendants(panel)

	local j = self._janitor
	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(panel.Header.Balance.Plus.Activated:Connect(function()
		self:ScrollTo("Coins")
	end))

	-- featured + rotating sets
	j:Add(scroll.Featured.Face.Buy.Activated:Connect(function()
		self:_setAction(scroll.Featured.Face:GetAttribute("SetId"))
	end))
	for i = 1, 4 do
		local card = scroll.Sets["Set" .. i]
		j:Add(card.Action.Activated:Connect(function()
			self:_setAction(card:GetAttribute("SetId"))
		end))
	end

	-- stages + mic stands
	for _, kind in { "Stage", "Mic" } do
		for i = 1, 4 do
			local card = scroll.Pieces[kind .. i]
			j:Add(card.Action.Activated:Connect(function()
				self:_itemAction(kind, card:GetAttribute("ItemId"))
			end))
		end
	end

	-- banners + photocards (built by SeasonController/Build.ShopStyle)
	local style = scroll:FindFirstChild("Style")
	for i = 1, 4 do
		local card = style and style:FindFirstChild("Style" .. i)
		if card then
			for button, kind in { SetBuy = "Set", BannerBuy = "Banner", PhotocardBuy = "Photocard" } do
				j:Add(card[button].Activated:Connect(function()
					self:_styleAction(kind, card:GetAttribute("StyleId"))
				end))
			end
		end
	end

	-- Robux: debut pack, coin bundles, passes
	j:Add(scroll.Debut.Face.Buy.Activated:Connect(function()
		local pack = ShopCatalog.DebutPack
		if pack and owns(PlayerData.Rewards.Claimed, pack.Id) then
			return -- already theirs (the button reads "Bought")
		end
		promptProduct(pack and pack.ProductId)
	end))
	-- bundles: whichever bundle the banner shows (fillBundle sets BundleId)
	local bundleFaces = {}
	if scroll:FindFirstChild("Headliner") then
		table.insert(bundleFaces, scroll.Headliner.Face)
	end
	if scroll:FindFirstChild("Bundles") then
		for i = 1, 3 do
			local b = scroll.Bundles:FindFirstChild("Bundle" .. i)
			if b then
				table.insert(bundleFaces, b.Face)
			end
		end
	end
	for _, face in bundleFaces do
		j:Add(face.Buy.Activated:Connect(function()
			local bundle = ShopCatalog.GetBundle(face:GetAttribute("BundleId") or "")
			if bundle and bundleBought(bundle.Id) >= (bundle.Limit or 1) then
				return -- at its limit (the button reads Bought / Sold out)
			end
			promptProduct(bundle and bundle.ProductId)
		end))
	end
	for i = 1, 5 do
		j:Add(scroll.Coins.Face["Bundle" .. i].Buy.Activated:Connect(function()
			local bundle = shownBundles()[i]
			promptProduct(bundle and bundle.ProductId)
		end))
	end
	local rolls = scroll:FindFirstChild("Rolls")
	for _, id in ROLL_CARDS do
		local face = rolls and rolls:FindFirstChild(id)
		for i = 1, 3 do
			local tile = face and face:FindFirstChild("Bundle" .. i)
			if tile then
				j:Add(tile.Buy.Activated:Connect(function()
					local bundle = ShopCatalog.RollBundlesFor(id)[i]
					promptProduct(bundle and bundle.ProductId)
				end))
			end
		end
		-- "You have n" stays right
		j:Add(LOCAL_PLAYER:GetAttributeChangedSignal(Currencies.Get(id).Attribute):Connect(function()
			self:_refresh()
		end))
	end
	for card, id in PASS_CARDS do
		j:Add(scroll.Passes[card].Action.Activated:Connect(function()
			promptPass(ShopCatalog.GetPass(id))
		end))
	end

	-- codes
	local codes = scroll.Codes.Face
	j:Add(codes.Redeem.Activated:Connect(function()
		self:_redeem()
	end))
	j:Add(codes.CodeBox.FocusLost:Connect(function(enter: boolean)
		if enter then
			self:_redeem()
		end
	end))

	-- server replies
	j:Add(ShopRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Result" then
			-- a successful buy gets the full purchase reveal (PurchasedController) instead of a toast
			local bought = packet.Ok and (packet.Action == "BuySet" or packet.Action == "BuyItem" or packet.Action == "BuyStyle")
			if not bought then
				self:_toast(packet.Text or "")
			end
			if packet.Ok and packet.Action ~= "EquipSet" and packet.Action ~= "EquipItem" and packet.Action ~= "EquipStyle" then
				Sounds.Play("Success")
			elseif not packet.Ok then
				Sounds.Play("Wrong")
			end
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy
	j:Add(RewardsRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "Result" and packet.Action == "RedeemCode" then
			-- (RewardsController plays the success / wrong sound for every RewardsRemote reply)
			-- a code that worked gets the purchase reveal (PurchasedController) instead of a toast
			if packet.Ok then
				codes.CodeBox.Text = ""
			else
				self:_toast(packet.Text or "")
				Juice.Shake(codes.CodeBox, 0.25)
			end
		end
	end), "Disconnect")

	-- live data → redraw
	for _, path in {
		PlayerData.Currencies.Won,
		PlayerData.Inventory.Sets,
		PlayerData.Inventory.Stages,
		PlayerData.Inventory.Mics,
		PlayerData.Inventory.EquippedStage,
		PlayerData.Inventory.EquippedMic,
		PlayerData.Inventory.Banners,
		PlayerData.Inventory.Photocards,
		PlayerData.Inventory.Banner,
		PlayerData.Inventory.Photocard,
		PlayerData.Rewards.Claimed,
		PlayerData.Rewards.Bundles,
		PlayerData.GamePasses,
	} do
		j:Add(path.Observe(function()
			self:_refresh()
		end))
	end

	-- live Robux prices arrive in the background
	j:Add(Prices.Changed:Connect(function()
		self:_refresh()
	end))

	-- countdowns + rotation changes while open
	j:Add(task.spawn(function()
		while true do
			task.wait(1)
			if self.State == "Active" then
				self:_refresh()
			end
		end
	end), true)
end

-- section: "Coins" (or any section name) to land on it; nil starts at the top
function Shop:Activate(section: string?)
	self._frame.Visible = true
	self:_refresh()
	-- old tab names other screens may still open with
	if section == "Featured" or section == "Sets" then
		section = nil
	elseif section == "Items" then
		section = "PiecesTitle"
	end
	self:ScrollTo(section, true)
	if section then
		-- the canvas size settles a frame after the first fill
		task.defer(function()
			self:ScrollTo(section, true)
		end)
	end
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
