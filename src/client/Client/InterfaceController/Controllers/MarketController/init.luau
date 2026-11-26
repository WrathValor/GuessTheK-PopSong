--| MarketController ("Market")
-- The Market screen (Interface.Frames.Market, built by ./Build from design boards "60 · Market ·
-- Browse", "60b · Sell a card" and "60c · Card detail + buy"). Three tabs top centre:
--   Browse   – every card other players have on sale, from every server, 8 a page, with the
--              filters on the left (search, rarity, group, sort, "only cards I don't have",
--              "my bias's group"). Nothing is bought from the grid: VIEW opens the card's detail
--              (the card big, its last 5 sales, this copy's story, other copies) and BUY FOR.
--   Sell     – your Lucky Draw-and-up cards; tap one, set the price (pricing help beside it)
--              and how long, LIST CARD.
--   Listings – ("My listings") your cards on sale with time left + Cancel, and sold ones to
--              COLLECT (the tab's red count, also pushed as a notification when one sells).
-- The server (Engine/MarketService) does the filtering and paging and every trade; the rules
-- live in Constants/MarketConstants. MarketRemote packets are described there.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local MarketConstants = require(ReplicatedStorage.Constants.MarketConstants)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local Photocard = require(ReplicatedStorage.Modules.UI.Photocard)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Notify = require(ReplicatedStorage.Modules.UI.Notify)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local MarketRemote = Bridgenet.ReferenceBridge("MarketRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local SAND = C("F3EEE0")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local TRACK = C("EDE4D4")

local function get(path, fallback)
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else fallback
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function span(seconds: number): string
	seconds = math.max(0, seconds)
	if seconds < 3600 then
		return `{math.max(1, math.floor(seconds / 60))} min`
	elseif seconds < 72 * 3600 then
		return `{math.floor(seconds / 3600)} h`
	elseif seconds < 14 * 86400 then
		return `{math.floor(seconds / 86400)} d`
	end
	return `{math.floor(seconds / 604800)} w`
end

local function ago(t: number?): string
	if not t then
		return ""
	end
	local s = os.time() - t
	return if s < 60 then "just now" else `{span(s)} ago`
end

local function rarityColour(key: string): Color3
	return C(MarketConstants.RARITY_COLOURS[key] or "FFFFFF")
end

local function copies(cardId: string): number
	return get(PlayerData.Inventory.Cards, {})[cardId] or 0
end

-- ---------------------------------- Class --------------------------------- --
local Market = {}
Market.__index = Market

function Market.new()
	local self = setmetatable({}, Market)
	self.Name = "Market"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._tab = "Browse"
	self._q = { Page = 1, Rarities = {}, Sort = "Price", NotOwned = false, Bias = false, Search = "", Group = nil, Card = nil }
	self._pages = 1
	self._detail = nil -- the listing the detail shows
	self._sel = nil -- Sell: the card picked
	self._price = 0
	self._hours = MarketConstants.DEFAULT_HOURS
	self._confirm = false
	self._items = {} -- Sell list buttons, by card id
	self._rows = {} -- My listings rows
	return (self :: any) :: UITypes.Controller
end

-- [[ Tabs ]]

function Market:_paintTabs()
	local tabs = self._frame.Header.Tabs
	for _, name in Build.TABS do
		local b = tabs[name]
		local on = name == self._tab
		b.BackgroundTransparency = if on then 0 else 1
		b:FindFirstChildOfClass("UIStroke").Enabled = on
		b.Label.TextColor3 = if on then INK else CREAM
	end
	local sold = 0
	for _, l in self:_mine() do
		if l.S == "Sold" then
			sold += 1
		end
	end
	tabs.Listings.Badge.Visible = sold > 0
	tabs.Listings.Badge.Text = tostring(sold)
end

function Market:SetTab(tab: string)
	if not table.find(Build.TABS, tab) then
		tab = "Browse"
	end
	self._tab = tab
	for _, name in Build.TABS do
		self._frame.Pages[name].Visible = name == tab
	end
	self:_paintTabs()
	if tab == "Browse" then
		self:_browse()
	elseif tab == "Sell" then
		self:_fillSell()
	else
		self:_fillListings()
	end
end

-- [[ Browse ]]

function Market:_browse()
	local q = self._q
	local rarities = {}
	for key, on in q.Rarities do
		if on then
			table.insert(rarities, key)
		end
	end
	MarketRemote:Fire({
		Action = "Browse",
		Page = q.Page,
		Search = q.Search,
		Rarities = rarities,
		Group = q.Group,
		Sort = q.Sort,
		NotOwned = q.NotOwned,
		Bias = q.Bias,
		Card = q.Card,
	})
end

function Market:_paintFilters()
	local f = self._frame.Pages.Browse.Filters
	local q = self._q
	for _, key in MarketConstants.RARITIES do
		f.Rarities[key].BackgroundColor3 = if q.Rarities[key] then rarityColour(key) else WHITE
	end
	for _, key in MarketConstants.SORTS do
		f.Sorts[key].BackgroundColor3 = if q.Sort == key then YELLOW else WHITE
	end
	for name, on in { NotOwned = q.NotOwned, Bias = q.Bias } do
		local track = f[name].Track
		track.BackgroundColor3 = if on then MINT else TRACK
		track.Knob.Position = if on then UDim2.new(1, -18, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
	end
	f.Group.Label.Text = q.Group or "All groups"
end

-- a filter changed: back to page 1 (and off a "See them" card)
function Market:_filtered()
	self._q.Page = 1
	self._q.Card = nil
	self:_paintFilters()
	self:_browse()
end

function Market:_onBrowse(packet)
	local g = self._frame.Pages.Browse.Grid
	local items = packet.Items or {}
	self._pages = packet.Pages or 1
	self._q.Page = packet.Page or 1
	g.PageText.Text = `{self._q.Page} / {self._pages}`
	g.Prev.BackgroundColor3 = if self._q.Page > 1 then WHITE else SAND
	g.Next.BackgroundColor3 = if self._q.Page < self._pages then WHITE else SAND
	local total = packet.Total or 0
	local info = `{commas(total)} {if total == 1 then "card" else "cards"}`
	if self._q.Card then
		local card = Albums.Card(self._q.Card)
		info ..= if card then ` · only {card.Member.Name} · {card.Rarity.Name}` else ""
	end
	g.TitleRow.Info.Text = info
	g.Empty.Visible = #items == 0
	g.Empty.Text = if self._q.Search ~= "" or self._q.Group or next(self._q.Rarities) or self._q.NotOwned or self._q.Bias then "Nothing on sale matches that" else "Nothing on sale yet: be the first to list a card!"
	local owned = get(PlayerData.Inventory.Cards, {})
	self._tiles = {}
	for i = 1, MarketConstants.PER_PAGE do
		local tile = g[`Tile{i}`]
		local l = items[i]
		local card = l and Albums.Card(l.C)
		tile.Visible = card ~= nil
		if card then
			self._tiles[i] = l
			local face = tile.Face
			Photocard.Paint(face.Card, l.C, 1, if (l.R or 0) > 0 then l.R else nil)
			face.NameRow.Title.Text = card.Member.Name
			face.NameRow.New.Visible = (owned[l.C] or 0) == 0
			face.Line.Text = `{card.Album.Artist} · {card.Album.Name} · by {l.N or "?"}`
			face.Price.Amount.Text = commas(l.P)
		end
	end
end

-- [[ Card detail ]]

function Market:_showDetail(on: boolean)
	local d = self._frame.Detail
	if on and not d.Visible then
		d.Visible = true
		FrameTransition.Open(d.Panel)
	elseif not on then
		d.Visible = false
		self._detail = nil
	end
end

function Market:_paintDetail(l, extra)
	local card = Albums.Card(l.C)
	if not card then
		return
	end
	self._detail = l
	local p = self._frame.Detail.Panel
	local serial = if (l.R or 0) > 0 then l.R else nil
	Photocard.Paint(p.Card, l.C, 1, serial)
	p.CardChips.Rarity.Text = card.Rarity.Name
	p.CardChips.Rarity.BackgroundColor3 = rarityColour(card.Rarity.Key)
	p.CardChips.Serial.Visible = serial ~= nil
	p.CardChips.Serial.Text = Albums.SerialText(l.C, serial) or ""
	p.Title.Text = card.Member.Name
	p.Line.Text = `{card.Album.Artist} · {card.Album.Name} · {card.Rarity.Name}`
	local have = copies(l.C)
	p.Tags.New.Visible = have == 0
	local bias = get(PlayerData.Inventory.Bias, "")
	p.Tags.Earns.Text = `Earns {commas(Albums.EarnPerHour(l.C, have + 1, bias))} an hour pinned`
	p.Tags.Seller.Text = `Seller: {l.N or "?"} · listed {ago(l.A)} · {span((l.E or 0) - os.time())} left`

	local coins = get(PlayerData.Currencies.Won, 0)
	p.Price.Amount.Text = commas(l.P)
	local short = coins < l.P
	p.After.Text = if short then `You need {commas(l.P - coins)} more` else `You'll have {commas(coins - l.P)} left`
	local inner = p.Buy.Inner
	inner.Label.Text = if short then "GET COINS" else "BUY FOR"
	inner.Amount.Visible = not short
	inner.Amount.Amount.Text = commas(l.P)
	p.Buy.BackgroundColor3 = if short then YELLOW else MINT

	-- what only the server knows: loading until it answers
	extra = extra or {}
	local sales = extra.Sales
	local bars = p.Sales.Bars
	p.Sales.Empty.Visible = sales ~= nil and #sales == 0
	p.Sales.Empty.Text = "No sales of this card yet"
	local top = 1
	for _, s in sales or {} do
		top = math.max(top, s.P or 0)
	end
	for i = 1, Build.BARS do
		local s = sales and sales[i]
		local bar = bars[`Bar{i}`]
		bar.Visible = s ~= nil
		if s then
			bar.Fill.Size = UDim2.fromOffset(52, math.floor(12 + 66 * (s.P / top)))
			bar.Price.Text = commas(s.P)
			bar.Ago.Text = ago(s.T)
		end
	end
	if not sales then
		p.Sales.Empty.Visible = true
		p.Sales.Empty.Text = "Loading…"
	end

	local rows = { { `{l.N or "?"} listed it`, ago(l.A) } }
	local history = extra.History
	if type(history) == "table" and type(history.Owners) == "table" then
		for i = #history.Owners, 1, -1 do
			local o = history.Owners[i]
			if type(o) == "table" then
				table.insert(rows, { `{o.Name or "?"} {if i == 1 then "pulled it" else "bought it"}`, ago(o.At) })
			end
		end
	elseif not serial then
		table.insert(rows, { "Lucky Draws aren't numbered, so there's no history", "" })
	end
	for i = 1, 3 do
		local r = p.Copy[`Row{i}`]
		r.Visible = rows[i] ~= nil
		if rows[i] then
			r.Left.Text = rows[i][1]
			r.Right.Text = rows[i][2]
		end
	end

	local others = extra.Others
	p.Others.Visible = others ~= nil and (others.Count or 0) > 0
	if p.Others.Visible then
		p.Others.Text.Label.Text = `{others.Count} other {if others.Count == 1 then "copy" else "copies"} on sale, from`
		p.Others.Text.Min.Amount.Text = commas(others.Min or 0)
	end
end

function Market:_openDetail(l)
	self:_paintDetail(l)
	self:_showDetail(true)
	MarketRemote:Fire({ Action = "Detail", Id = l.Id })
end

function Market:_onDetail(packet)
	if not packet.Ok then
		if self._detail and self._detail.Id == packet.Id then
			self:_showDetail(false)
			Notify.Toast(packet.Text or "That card isn't on sale any more", { Kind = "Error" })
			self:_browse()
		end
		return
	end
	if not self._frame.Detail.Visible or not packet.Listing then
		return
	end
	local l = packet.Listing
	l.Id = packet.Id
	self:_paintDetail(l, packet)
end

function Market:_buy()
	local l = self._detail
	if not l then
		return
	end
	if get(PlayerData.Currencies.Won, 0) < l.P then
		self:_showDetail(false)
		self._interface:Open("Shop", "Coins")
		return
	end
	Sounds.Play("Click")
	MarketRemote:Fire({ Action = "Buy", Id = l.Id, Price = l.P })
end

function Market:_onBuy(packet)
	if packet.Ok then
		local card = Albums.Card(packet.Card or "")
		self:_showDetail(false)
		Sounds.Play("Success")
		if card then
			local serial = Albums.SerialText(packet.Card, if (packet.Serial or 0) > 0 then packet.Serial else nil)
			Notify.Show("Success", `You got {card.Member.Name}!`, `{card.Rarity.Name}{if serial then " " .. serial else ""} is in your binder`, { Silent = true })
		end
		self:_browse()
		return
	end
	if packet.Text == "Not enough coins" then
		Notify.Toast("Not enough coins")
		return
	end
	Notify.Toast(packet.Text or "Couldn't buy that", { Kind = "Error" })
	if packet.Text == "Just sold!" then
		if packet.Next then
			MarketRemote:Fire({ Action = "Detail", Id = packet.Next })
			self._detail = { Id = packet.Next }
		else
			self:_showDetail(false)
		end
		self:_browse()
	end
end

-- [[ Sell ]]

function Market:_mine(): { { [string]: any } }
	local out = {}
	for id, json in get(PlayerData.Inventory.Listings, {}) do
		local l = MarketConstants.Decode(json)
		if l then
			l.Id = id
			table.insert(out, l)
		end
	end
	return out
end

function Market:_limit(): number
	local ok, vip = pcall(PlayerData.GamePasses.Has, "VIP")
	return if ok and vip then MarketConstants.LIMIT_VIP else MarketConstants.LIMIT
end

-- the serial that would go with a listed copy (the highest, like selling)
local function topSerial(cardId: string): number?
	local list = Albums.Serials(get(PlayerData.Inventory.Serials, {})[cardId])
	return list[#list]
end

function Market:_fillSell()
	local page = self._frame.Pages.Sell
	local scroll = page.Cards.List
	local template = scroll.Item
	local list = {}
	for id, n in get(PlayerData.Inventory.Cards, {}) do
		if n > 0 and MarketConstants.Tradeable(id) then
			table.insert(list, id)
		end
	end
	table.sort(list, function(a, b)
		local ca, cb = Albums.Card(a) :: any, Albums.Card(b) :: any
		local ra, rb = Albums.RarityRank(ca.Rarity.Key), Albums.RarityRank(cb.Rarity.Key)
		if ra ~= rb then
			return ra > rb
		end
		return ca.Member.Name < cb.Member.Name
	end)
	local keep = {}
	for i, id in list do
		keep[id] = true
		local item = self._items[id]
		if not item then
			item = template:Clone()
			item.Name = id
			item.Parent = scroll
			ButtonScale.Apply(item)
			self._items[id] = item
			self._janitor:Add(item.Activated:Connect(function()
				Sounds.Play("Click")
				self:_select(id)
			end))
		end
		local n = copies(id)
		local card = Albums.Card(id) :: any
		Photocard.Paint(item.Card, id, n, topSerial(id))
		item.LayoutOrder = i
		item.Visible = true
		item.Title.Text = card.Member.Name
		local serial = Albums.SerialText(id, topSerial(id))
		item.Line.Text = card.Rarity.Name .. (if n > 1 then ` · ×{n}` elseif serial then ` · {serial}` else "")
		item.Ring.Visible = id == self._sel
	end
	for id, item in self._items do
		if not keep[id] then
			item:Destroy()
			self._items[id] = nil
		end
	end
	page.Cards.Empty.Visible = #list == 0
	if self._sel and not keep[self._sel] then
		self._sel = nil
	end
	self:_paintForm()
end

function Market:_select(id: string)
	self._sel = id
	self._confirm = false
	self._help = nil
	self._price = MarketConstants.Floor(id)
	for cid, item in self._items do
		item.Ring.Visible = cid == id
	end
	MarketRemote:Fire({ Action = "Help", Card = id })
	self:_paintForm()
end

function Market:_paintForm()
	local form = self._frame.Pages.Sell.Form
	local id = self._sel
	local card = id and Albums.Card(id)
	form.Pick.Visible = card == nil
	form.Body.Visible = card ~= nil
	if not card then
		return
	end
	local b = form.Body
	local n = copies(id)
	local serial = topSerial(id)
	Photocard.Paint(b.Card, id, 1, serial)
	b.Title.Text = card.Member.Name
	b.Line.Text = `{card.Album.Artist} · {card.Album.Name} · {card.Rarity.Name}`
	b.Chips.Rarity.Text = card.Rarity.Name
	b.Chips.Rarity.BackgroundColor3 = rarityColour(card.Rarity.Key)
	local serialText = Albums.SerialText(id, serial)
	b.Chips.Serial.Visible = serialText ~= nil
	b.Chips.Serial.Text = serialText or ""
	b.Chips.Copies.Text = if n <= 1 then "Your only copy" else `You have {n}`

	local help = self._help
	b.Help.Lowest.Value.Text = if help == nil then "…" elseif help.Lowest then commas(help.Lowest) else "None on sale"
	local sales = help and help.Sales or {}
	if help == nil then
		b.Help.Sales.Value.Text = "…"
	elseif #sales == 0 then
		b.Help.Sales.Value.Text = "No sales yet"
	else
		local lo, hi = math.huge, 0
		for _, s in sales do
			lo, hi = math.min(lo, s.P), math.max(hi, s.P)
		end
		b.Help.Sales.Value.Text = if lo == hi then commas(lo) else `{commas(lo)} – {commas(hi)}`
	end
	local gamePrice = Albums.SellPrice(id)
	b.Help.Game.Value.Text = if gamePrice then commas(gamePrice) else "Can't be sold"

	b.Price.Input.Text = commas(self._price)
	b.YouGet.Amount.Amount.Text = commas(MarketConstants.Payout(self._price))
	for _, h in MarketConstants.HOURS do
		b.Hours[tostring(h)].BackgroundColor3 = if h == self._hours then YELLOW else WHITE
	end
	local open = 0
	for _, l in self:_mine() do
		if l.S == "On" then
			open += 1
		end
	end
	local full = open >= self:_limit()
	local level = LOCAL_PLAYER:GetAttribute("Level") or 0
	local locked = level < MarketConstants.SELL_LEVEL
	b.List.Text = if locked then `SELLING UNLOCKS AT LEVEL {MarketConstants.SELL_LEVEL}` elseif full then "YOUR LISTINGS ARE FULL" elseif self._confirm then "TAP AGAIN TO LIST" else "LIST CARD"
	b.List.BackgroundColor3 = if full or locked then SAND else MINT
	b.Fee.Text = `Market fee {math.floor(MarketConstants.FEE * 100 + 0.5)}% · up to {commas(MarketConstants.Cap(id))}`
end

function Market:_onHelp(packet)
	if packet.Card ~= self._sel then
		return
	end
	self._help = packet
	-- a starting price: the cheapest on sale, else the last sales' middle, else 3× the floor
	local floor = MarketConstants.Floor(packet.Card)
	local start = packet.Lowest
	if not start and packet.Sales and #packet.Sales > 0 then
		local sum = 0
		for _, s in packet.Sales do
			sum += s.P
		end
		start = sum / #packet.Sales
	end
	start = start or floor * 3
	self._price = math.clamp(math.floor(start / MarketConstants.STEP + 0.5) * MarketConstants.STEP, floor, MarketConstants.Cap(packet.Card))
	self:_paintForm()
end

function Market:_setPrice(p: number)
	if not self._sel then
		return
	end
	self._price = math.clamp(math.floor(p), MarketConstants.Floor(self._sel), MarketConstants.Cap(self._sel))
	self._confirm = false
	self:_paintForm()
end

function Market:_list()
	local id = self._sel
	if not id then
		return
	end
	if (LOCAL_PLAYER:GetAttribute("Level") or 0) < MarketConstants.SELL_LEVEL then
		Sounds.Play("Wrong")
		Notify.Toast(`You can sell on the Market from level {MarketConstants.SELL_LEVEL}`, { Kind = "Error", Silent = true })
		return
	end
	Sounds.Play("Click")
	MarketRemote:Fire({ Action = "List", Card = id, Price = self._price, Hours = self._hours, Confirm = self._confirm or nil })
end

function Market:_onList(packet)
	if packet.Confirm then
		self._confirm = true
		self:_paintForm()
		Notify.Toast("That's your bias's last copy. Tap again to list it", { Kind = "Neutral" })
		return
	end
	self._confirm = false
	if not packet.Ok then
		Notify.Toast(packet.Text or "Couldn't list that", { Kind = "Error" })
		self:_paintForm()
		return
	end
	local card = Albums.Card(packet.Card or "")
	Sounds.Play("Success")
	if card then
		Notify.Show("Success", "Listed!", `{card.Member.Name} is on the Market for {commas(self._price)}`, { Silent = true })
	end
	self._sel = nil
	task.defer(function()
		if self._tab == "Sell" then
			self:_fillSell()
		end
	end)
end

-- [[ My listings ]]

function Market:_fillListings()
	local page = self._frame.Pages.Listings
	local panel = page.Panel
	local scroll = panel.List
	local list = self:_mine()
	table.sort(list, function(a, b)
		if (a.S == "Sold") ~= (b.S == "Sold") then
			return a.S == "Sold"
		end
		return (a.E or 0) < (b.E or 0)
	end)
	local open = 0
	for _, l in list do
		if l.S == "On" then
			open += 1
		end
	end
	panel.TitleRow.Info.Text = `{open} of {self:_limit()} on sale`
	panel.Empty.Visible = #list == 0
	for i = #self._rows + 1, #list do
		local r = scroll.Row:Clone()
		r.Name = `Listing{i}`
		r.Parent = scroll
		ButtonScale.ApplyToDescendants(r)
		self._rows[i] = r
		self._janitor:Add(r.Face.Action.Activated:Connect(function()
			local l = r:GetAttribute("Id")
			if not l then
				return
			end
			Sounds.Play("Click")
			MarketRemote:Fire({ Action = if r:GetAttribute("Sold") then "Collect" else "Cancel", Id = l })
		end))
	end
	for i, r in self._rows do
		local l = list[i]
		local card = l and Albums.Card(l.C)
		r.Visible = card ~= nil
		r.LayoutOrder = i
		if card then
			local f = r.Face
			local sold = l.S == "Sold"
			r:SetAttribute("Id", l.Id)
			r:SetAttribute("Sold", sold)
			Photocard.Paint(f.Card, l.C, 1, if (l.R or 0) > 0 then l.R else nil)
			f.Title.Text = card.Member.Name
			local serial = Albums.SerialText(l.C, if (l.R or 0) > 0 then l.R else nil)
			f.Line.Text = `{card.Album.Artist} · {card.Album.Name} · {card.Rarity.Name}{if serial then " · " .. serial else ""}`
			f.Status.Text = if sold then `Sold{if l.B then " to " .. l.B else ""}!` else `{span((l.E or 0) - os.time())} left`
			f.Status.BackgroundColor3 = if sold then MINT else SAND
			f.Price.Amount.Text = commas(l.P)
			f.Get.Text = `you get {commas(MarketConstants.Payout(l.P))}`
			f.Action.Text = if sold then "COLLECT" else "CANCEL"
			f.Action.BackgroundColor3 = if sold then MINT else CREAM
		end
	end
end

function Market:_onCancel(packet)
	if packet.Ok then
		Notify.Toast("It's back in your binder", { Kind = "Neutral" })
	else
		Notify.Toast(packet.Text or "Couldn't cancel that", { Kind = "Error" })
	end
end

function Market:_onCollect(packet)
	if packet.Ok and packet.Coins then
		Sounds.Play("Coins")
		Notify.Show("Success", `+{commas(packet.Coins)} coins`, "From your Market sale", { Silent = true })
	end
end

function Market:_onSold(packet)
	local card = Albums.Card(packet.Card or "")
	if not card then
		return
	end
	Notify.Show("Notify", `Your {card.Member.Name} sold!`, `Collect {commas(MarketConstants.Payout(packet.Price or 0))} coins in the Market`, {
		OnTap = function()
			if self.State == "Active" then
				self:SetTab("Listings")
			elseif self._interface.Mode == "Gameplay" then
				self._interface:Open("Market", "Listings")
			end
		end,
	})
end

-- [[ Refresh ]]

function Market:_refresh()
	if not self._frame.Visible then
		return
	end
	local coins = get(PlayerData.Currencies.Won, 0)
	local bal = self._frame.Header.Balance
	if self._shownCoins ~= coins then
		if self._shownCoins then
			Juice.CountUp(bal.Amount, self._shownCoins, coins, commas)
			Juice.Pop(bal, if coins > self._shownCoins then 0.18 else 0.1)
		else
			bal.Amount.Text = commas(coins)
		end
		self._shownCoins = coins
	end
	self:_paintTabs()
	if self._tab == "Sell" then
		self:_fillSell()
	elseif self._tab == "Listings" then
		self:_fillListings()
	end
	if self._detail and self._detail.C and self._frame.Detail.Visible then
		-- (coins changed: the buy button + "you'll have")
		local p = self._frame.Detail.Panel
		local l = self._detail
		local short = coins < l.P
		p.After.Text = if short then `You need {commas(l.P - coins)} more` else `You'll have {commas(coins - l.P)} left`
		p.Buy.Inner.Label.Text = if short then "GET COINS" else "BUY FOR"
		p.Buy.Inner.Amount.Visible = not short
		p.Buy.BackgroundColor3 = if short then YELLOW else MINT
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function Market:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Market")
	self._frame.Visible = false
	local frame = self._frame
	ButtonScale.ApplyToDescendants(frame)
	local j = self._janitor

	j:Add(frame.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for _, name in Build.TABS do
		j:Add(frame.Header.Tabs[name].Activated:Connect(function()
			if self._tab ~= name then
				Sounds.Play("Click")
				self:SetTab(name)
			end
		end))
	end

	-- Browse: filters
	local f = frame.Pages.Browse.Filters
	local searchToken = 0
	j:Add(f.Search.Input:GetPropertyChangedSignal("Text"):Connect(function()
		searchToken += 1
		local mine = searchToken
		task.delay(0.35, function()
			if mine == searchToken and self._q.Search ~= f.Search.Input.Text then
				self._q.Search = f.Search.Input.Text
				self:_filtered()
			end
		end)
	end))
	for _, key in MarketConstants.RARITIES do
		j:Add(f.Rarities[key].Activated:Connect(function()
			Sounds.Play("Click")
			self._q.Rarities[key] = if self._q.Rarities[key] then nil else true
			self:_filtered()
		end))
	end
	for _, key in MarketConstants.SORTS do
		j:Add(f.Sorts[key].Activated:Connect(function()
			Sounds.Play("Click")
			self._q.Sort = key
			self:_filtered()
		end))
	end
	for _, name in { "NotOwned", "Bias" } do
		j:Add(f[name].Activated:Connect(function()
			Sounds.Play("Click")
			self._q[name] = not self._q[name]
			self:_filtered()
		end))
	end
	-- the group dropdown
	local groupList = f.GroupList
	local scroll = groupList.List
	local groups = Albums.Artists()
	table.sort(groups, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	table.insert(groups, 1, "")
	for i, artist in groups do
		local item = scroll.Item:Clone()
		item.Name = `Group{i}`
		item.LayoutOrder = i
		item.Visible = true
		item.Label.Text = if artist == "" then "All groups" else artist
		item.Parent = scroll
		j:Add(item.Activated:Connect(function()
			Sounds.Play("Click")
			self._q.Group = if artist == "" then nil else artist
			groupList.Visible = false
			self:_filtered()
		end))
		j:Add(item.MouseEnter:Connect(function()
			item.BackgroundTransparency = 0
		end))
		j:Add(item.MouseLeave:Connect(function()
			item.BackgroundTransparency = 1
		end))
	end
	j:Add(f.Group.Activated:Connect(function()
		Sounds.Play("Click")
		groupList.Visible = not groupList.Visible
	end))

	-- Browse: grid
	local g = frame.Pages.Browse.Grid
	j:Add(g.Prev.Activated:Connect(function()
		if self._q.Page > 1 then
			Sounds.Play("Click")
			self._q.Page -= 1
			self:_browse()
		end
	end))
	j:Add(g.Next.Activated:Connect(function()
		if self._q.Page < self._pages then
			Sounds.Play("Click")
			self._q.Page += 1
			self:_browse()
		end
	end))
	self._tiles = {}
	for i = 1, MarketConstants.PER_PAGE do
		j:Add(g[`Tile{i}`].Face.View.Activated:Connect(function()
			local l = self._tiles[i]
			if l then
				Sounds.Play("Click")
				self:_openDetail(l)
			end
		end))
	end

	-- detail
	local d = frame.Detail
	j:Add(d.Panel.Close.Activated:Connect(function()
		self:_showDetail(false)
	end))
	j:Add(d.Dim.Activated:Connect(function()
		self:_showDetail(false)
	end))
	j:Add(d.Panel.Buy.Activated:Connect(function()
		self:_buy()
	end))
	j:Add(d.Panel.Others.See.Activated:Connect(function()
		local l = self._detail
		if not l or not l.C then
			return
		end
		Sounds.Play("Click")
		self:_showDetail(false)
		self._q.Card = l.C
		self._q.Page = 1
		self._q.Sort = "Price"
		self:_paintFilters()
		self:_browse()
	end))

	-- Sell form
	local b = frame.Pages.Sell.Form.Body
	j:Add(b.Minus.Activated:Connect(function()
		Sounds.Play("Click")
		self:_setPrice(self._price - MarketConstants.STEP)
	end))
	j:Add(b.Plus.Activated:Connect(function()
		Sounds.Play("Click")
		self:_setPrice(self._price + MarketConstants.STEP)
	end))
	j:Add(b.Price.Input.FocusLost:Connect(function()
		local digits = string.gsub(b.Price.Input.Text, "%D", "")
		self:_setPrice(tonumber(digits) or self._price)
	end))
	for _, h in MarketConstants.HOURS do
		j:Add(b.Hours[tostring(h)].Activated:Connect(function()
			Sounds.Play("Click")
			self._hours = h
			self:_paintForm()
		end))
	end
	j:Add(b.List.Activated:Connect(function()
		self:_list()
	end))

	-- server replies (and sales pushed while you're here, even with the screen shut)
	j:Add(MarketRemote:Connect(function(packet)
		if type(packet) ~= "table" then
			return
		end
		local m = packet.Message
		if m == "Browse" then
			self:_onBrowse(packet)
		elseif m == "Detail" then
			self:_onDetail(packet)
		elseif m == "Buy" then
			self:_onBuy(packet)
		elseif m == "Help" then
			self:_onHelp(packet)
		elseif m == "List" then
			self:_onList(packet)
		elseif m == "Cancel" then
			self:_onCancel(packet)
		elseif m == "Collect" then
			self:_onCollect(packet)
		elseif m == "Sold" then
			self:_onSold(packet)
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy

	for _, path in {
		PlayerData.Currencies.Won,
		PlayerData.Inventory.Cards,
		PlayerData.Inventory.Serials,
		PlayerData.Inventory.Listings,
		PlayerData.GamePasses,
	} do
		j:Add(path.Observe(function()
			self:_refresh()
		end))
	end

	-- time left ticks, and Browse picks up other servers' listings
	j:Add(task.spawn(function()
		local n = 0
		while true do
			task.wait(1)
			n += 1
			if self.State == "Active" then
				if self._tab == "Listings" and n % 15 == 0 then
					self:_fillListings()
				elseif self._tab == "Browse" and n % MarketConstants.REFRESH == 0 and not frame.Detail.Visible then
					self:_browse()
				end
			end
		end
	end), true)

	self:_paintFilters()
end

-- tab: "Browse" (default) | "Sell" | "Listings"
function Market:Activate(tab: string?)
	self._frame.Visible = true
	self._frame.Detail.Visible = false
	self._frame.Pages.Browse.Filters.GroupList.Visible = false
	self._shownCoins = nil
	self:SetTab(tab or self._tab or "Browse")
	self:_refresh()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Market:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self._detail = nil
		self.State = "Inactive"
	end)
end

function Market:Destroy()
	self._janitor:Destroy()
end

return Market
