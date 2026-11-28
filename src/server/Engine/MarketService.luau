--| MarketService
-- The Market (design boards "60 · Market · Browse", "60b · Sell a card", "60c · Card detail +
-- buy"): players buy and sell their photocards (any rarity) with each other, for coins
-- only. Every server sees every listing. The rules live in Constants/MarketConstants.
--   • Listings live in a MemoryStore SortedMap (MarketConstants.MAP, sorted by price) that
--     drops each one when its time is up. Each server keeps a copy of the whole map (read every
--     REFRESH seconds) and does the filtering, sorting and paging for its players itself.
--   • Listing a card takes the copy out of the binder (escrow: its highest serial goes with it,
--     like selling) and records it in Inventory.Listings, which is what My listings shows.
--   • Who gets a listing is settled in a DataStore (CLAIM_STORE, a key a listing): the first
--     write wins, a buyer's or the seller's (Cancel, or the time running out). So a card can't
--     be sold twice, or sold and handed back too.
--   • The seller hears through Scribe's durable messages (PlayerData.SendMessage), so a sale made
--     while they're offline or in another server still reaches them; on joining, their open
--     listings are checked against the claims as well. A sold listing waits as "Sold!" in My
--     listings until they Collect it (the price minus the FEE).
--   • Guardrails: a price cap per rarity (MarketConstants.CAPS) and SELL_LEVEL to list, so alts
--     can't pass coins around through overpriced junk cards.
--   • Each card id's last SALES_KEPT sale prices are kept in SALES_STORE (the detail's chart and
--     the Sell form's pricing help). A numbered copy's owners go into its history
--     (SerialService.Transfer); a One of One's owner record moves to the buyer.
-- In Inventory.Listings (id → JSON): { C = card id, R = serial (0 = none), P = price,
--   A = listed at, E = ends at, S = "On" | "Sold", B = buyer's name?, T = sold at?,
--   W = sold before they joined (the away pop-up's "while you were away")? }
-- Every sale, listing, ending, cancel and collect is also logged in Inventory.MarketLog (the
-- last 30, My listings' ACTIVITY and the "While you were away" pop-up), with all-time totals in
-- MarketEarned / MarketSold (design boards "67 · Market · My listings details", "67b").
-- In the map (and Browse items): { Id, C, R, P, A, E, U = seller's UserId, N = seller's name }
-- MarketRemote, client → server:
--   { Action = "Browse", Page, Search?, Rarities? = { key }, Group?, Sort?, NotOwned?, Bias?, Card? }
--   { Action = "Detail", Id }   { Action = "Buy", Id, Price }
--   { Action = "Help", Card }   { Action = "List", Card, Price, Hours, Confirm? }
--   { Action = "Cancel", Id }   { Action = "Collect", Id }   { Action = "CollectAll" }
--   { Action = "Seen" } (My listings / the away pop-up looked at)   { Action = "Ranks" }
-- MarketRemote, server → client: { Message = <the Action>, Ok, Text?, … }:
--   Browse { Items, Page, Pages, Total }   Detail { Listing, Sales, History?, Others }
--   Buy { Card?, Serial?, Next? (cheapest other copy's id, when it was just sold) , Coins? (short) }
--   Help { Card, Lowest?, Sales }   List { Card, Confirm? }   Cancel / Collect { Id, Coins? }
--   CollectAll { Coins, Count }   Ranks { Ranks = { [id] = { Rank, Lowest, Count } } } (where
--   each of your open listings' price sits among that card's copies on sale)
-- and { Message = "Sold", Id, Card, Price } when one of your listings sells while you're here,
-- { Message = "Ended", Id, Card, Price } when one runs out unsold while you're here.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local Levels = require(ReplicatedStorage.Modules.Levels)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local MarketConstants = require(ReplicatedStorage.Constants.MarketConstants)
local Analytics = require(script.Parent.Analytics)
local SerialService = require(script.Parent.SerialService)
local BinderService = require(script.Parent.BinderService)

local MarketRemote = Bridgenet.ReferenceBridge("MarketRemote")

local MarketService = {}

local PAGE = 200 -- map entries a read
local MAX_PAGES = 15
local GONE_SECONDS = 90 -- a listing bought / cancelled here stays out of the copy this long
local SALES_TTL = 60

local listings: { [string]: { [string]: any } } = {} -- this server's copy of the map, by id
local gone: { [string]: number } = {} -- ids taken off here lately (os.clock)
local sales: { [string]: { List: { any }, At: number } } = {}
local busy: { [Player]: boolean } = {}
local joinedAt: { [Player]: number } = {}

-- [[ Helpers ]]

local function reply(player: Player, message: string, ok: boolean, text: string?, extra: { [string]: any }?)
	local packet = { Message = message, Ok = ok, Text = text }
	for k, v in extra or {} do
		packet[k] = v
	end
	MarketRemote:Fire(player, packet)
end

local function map(): MemoryStoreSortedMap?
	local ok, m = pcall(MemoryStoreService.GetSortedMap, MemoryStoreService, MarketConstants.MAP)
	return if ok then m else nil
end

local function store(name: string): DataStore?
	local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	return if ok then s else nil
end

local function coins(data): number
	return Currencies.Data(data, "Coins").Get() or 0
end

local function mine(data): { [string]: { [string]: any } }
	local out = {}
	for id, json in data.Inventory.Listings.Get() or {} do
		local l = MarketConstants.Decode(json)
		if l then
			out[id] = l
		end
	end
	return out
end

local function save(data, id: string, l: { [string]: any })
	data.Inventory.Listings[id].Set(HttpService:JSONEncode(l))
end

-- adds an event to My listings' ACTIVITY (call inside a PlayerData.Batch)
local function log(data, kind: string, fields: { [string]: any })
	local e = table.clone(fields)
	e.K = kind
	e.T = os.time()
	data.Inventory.MarketLog.Insert(HttpService:JSONEncode(e))
end

local function limit(data): number
	return if data.GamePasses.Has("VIP") then MarketConstants.LIMIT_VIP else MarketConstants.LIMIT
end

-- takes one copy out of the binder (no yield): the serial that goes with it (0 = none)
local function takeCopy(data, cardId: string): number
	local copies = data.Inventory.Cards[cardId].Get() or 0
	BinderService.Bank(data)
	if copies <= 1 then
		data.Inventory.Cards.Remove(cardId)
		local pins = Albums.Pins(data.Inventory.Pins.Get())
		local at = table.find(pins, cardId)
		if at then
			table.remove(pins, at)
			data.Inventory.Pins.Set(Albums.PinValue(pins))
		end
	else
		data.Inventory.Cards[cardId].Set(copies - 1)
	end
	if not Albums.Numbered(cardId) then
		return 0
	end
	local left, serial = Albums.DropSerial(data.Inventory.Serials[cardId].Get())
	if left == "" or copies <= 1 then
		data.Inventory.Serials.Remove(cardId)
	else
		data.Inventory.Serials[cardId].Set(left)
	end
	return serial or 0
end

-- puts a copy into the binder (no yield)
local function addCopy(data, cardId: string, serial: number?)
	BinderService.Bank(data)
	local copies = data.Inventory.Cards[cardId].Get() or 0
	data.Inventory.Cards[cardId].Set(math.min(copies + 1, AlbumConstants.RAINBOW_COPIES))
	if serial and serial > 0 then
		data.Inventory.Serials[cardId].Set(Albums.AddSerial(data.Inventory.Serials[cardId].Get(), serial))
	end
	if (data.Inventory.CardDates[cardId].Get() or 0) == 0 then
		data.Inventory.CardDates[cardId].Set(os.time())
	end
end

-- The claim: the first write for a listing wins. Returns (reached the store, won, what's stored)
local function claim(id: string, record: { [string]: any }): (boolean, boolean, any)
	local s = store(MarketConstants.CLAIM_STORE)
	if not s then
		return false, false, nil
	end
	for try = 1, 3 do
		local existing = nil
		local ok, err = pcall(s.UpdateAsync, s, id, function(old)
			existing = old
			if old ~= nil then
				return nil
			end
			return record
		end)
		if ok then
			if existing ~= nil then
				return true, false, existing
			end
			return true, true, record
		end
		warn(`[MarketService] couldn't claim listing {id} (try {try}): {err}`)
		task.wait(try)
	end
	return false, false, nil
end

local function unlist(id: string)
	listings[id] = nil
	gone[id] = os.clock()
	task.spawn(function()
		local m = map()
		if m then
			pcall(m.RemoveAsync, m, id)
		end
	end)
end

-- [[ The copy of the map ]]

local function refresh()
	local m = map()
	if not m then
		return
	end
	local fresh = {}
	local bound = nil
	for _ = 1, MAX_PAGES do
		local ok, items = pcall(m.GetRangeAsync, m, Enum.SortDirection.Ascending, PAGE, bound)
		if not ok then
			warn(`[MarketService] couldn't read the market: {items}`)
			return
		end
		for _, item in items do
			local v = item.value
			if type(v) == "table" and type(v.C) == "string" then
				v.Id = item.key
				fresh[item.key] = v
			end
		end
		if #items < PAGE then
			break
		end
		local last = items[#items]
		bound = { key = last.key, sortKey = last.sortKey }
	end
	local t = os.clock()
	for id, at in gone do
		if t - at > GONE_SECONDS then
			gone[id] = nil
		else
			fresh[id] = nil
		end
	end
	listings = fresh
end

local function live(l): boolean
	return l ~= nil and (l.E or 0) > os.time() + 5 and Albums.Card(l.C) ~= nil
end

-- [[ Sale prices ]]

local function salesOf(cardId: string): { any }
	local cached = sales[cardId]
	if cached and os.clock() - cached.At < SALES_TTL then
		return cached.List
	end
	local s = store(MarketConstants.SALES_STORE)
	local list = {}
	if s then
		local ok, v = pcall(s.GetAsync, s, Albums.StoreKey(cardId))
		if ok and type(v) == "table" then
			list = v
		elseif not ok and cached then
			return cached.List
		end
	end
	sales[cardId] = { List = list, At = os.clock() }
	return list
end

local function recordSale(cardId: string, price: number)
	local s = store(MarketConstants.SALES_STORE)
	if not s then
		return
	end
	local ok, list = pcall(s.UpdateAsync, s, Albums.StoreKey(cardId), function(old)
		local l = if type(old) == "table" then old else {}
		table.insert(l, 1, { P = price, T = os.time() })
		while #l > MarketConstants.SALES_KEPT do
			table.remove(l)
		end
		return l
	end)
	if ok and type(list) == "table" then
		sales[cardId] = { List = list, At = os.clock() }
	end
end

-- [[ Browse ]]

local function matches(l, q): boolean
	local card = Albums.Card(l.C)
	if not card then
		return false
	end
	if q.Card and l.C ~= q.Card then
		return false
	end
	if q.Rarities and not q.Rarities[card.Rarity.Key] then
		return false
	end
	if q.Group and card.Album.Artist ~= q.Group then
		return false
	end
	if q.Search then
		local hay = string.lower(`{card.Member.Name} {card.Album.Artist} {card.Album.Name}`)
		if not string.find(hay, q.Search, 1, true) then
			return false
		end
	end
	if q.Owned and (q.Owned[l.C] or 0) > 0 then
		return false
	end
	if q.BiasArtist and card.Album.Artist ~= q.BiasArtist then
		return false
	end
	return true
end

local function sorter(sort: string)
	local function rank(l)
		local card = Albums.Card(l.C)
		return if card then Albums.RarityRank(card.Rarity.Key) else 0
	end
	if sort == "Newest" then
		return function(a, b)
			return if a.A ~= b.A then a.A > b.A else a.Id < b.Id
		end
	elseif sort == "Rarest" then
		return function(a, b)
			local ra, rb = rank(a), rank(b)
			if ra ~= rb then
				return ra > rb
			end
			return if a.P ~= b.P then a.P < b.P else a.Id < b.Id
		end
	elseif sort == "Serial" then
		return function(a, b)
			local sa = if (a.R or 0) > 0 then a.R else math.huge
			local sb = if (b.R or 0) > 0 then b.R else math.huge
			if sa ~= sb then
				return sa < sb
			end
			return if a.P ~= b.P then a.P < b.P else a.Id < b.Id
		end
	end
	return function(a, b)
		return if a.P ~= b.P then a.P < b.P else a.Id < b.Id
	end
end

local function browse(player: Player, data, packet)
	local q = {}
	if type(packet.Search) == "string" and packet.Search ~= "" then
		q.Search = string.lower(string.sub(packet.Search, 1, 40))
	end
	if type(packet.Rarities) == "table" and #packet.Rarities > 0 then
		q.Rarities = {}
		for _, key in packet.Rarities do
			if type(key) == "string" then
				q.Rarities[key] = true
			end
		end
	end
	if type(packet.Group) == "string" and packet.Group ~= "" then
		q.Group = packet.Group
	end
	if type(packet.Card) == "string" then
		q.Card = packet.Card
	end
	if packet.NotOwned == true then
		q.Owned = data.Inventory.Cards.Get() or {}
	end
	if packet.Bias == true then
		q.BiasArtist = Albums.BiasParts(data.Inventory.Bias.Get()) or "-"
	end
	local list = {}
	for _, l in listings do
		if l.U ~= player.UserId and live(l) and matches(l, q) then
			table.insert(list, l)
		end
	end
	table.sort(list, sorter(if type(packet.Sort) == "string" then packet.Sort else "Price"))
	local per = MarketConstants.PER_PAGE
	local pages = math.max(1, math.ceil(#list / per))
	local page = math.clamp(math.floor(tonumber(packet.Page) or 1), 1, pages)
	local items = {}
	for i = (page - 1) * per + 1, math.min(page * per, #list) do
		table.insert(items, list[i])
	end
	reply(player, "Browse", true, nil, { Items = items, Page = page, Pages = pages, Total = #list })
end

-- the cheapest other live copy of a card on sale (not yours, not `except`): (listing, count)
local function others(player: Player, cardId: string, except: string?)
	local best, n = nil, 0
	for id, l in listings do
		if id ~= except and l.C == cardId and l.U ~= player.UserId and live(l) then
			n += 1
			if not best or l.P < best.P then
				best = l
			end
		end
	end
	return best, n
end

local function detail(player: Player, id: any)
	local l = type(id) == "string" and listings[id]
	if not live(l) then
		return reply(player, "Detail", false, "That card isn't on sale any more", { Id = id })
	end
	local history = nil
	if (l.R or 0) > 0 then
		history = SerialService.History(l.C, l.R)
	end
	local best, n = others(player, l.C, id)
	reply(player, "Detail", true, nil, {
		Id = id,
		Listing = l,
		Sales = salesOf(l.C),
		History = history,
		Others = { Count = n, Min = best and best.P, Id = best and best.Id },
	})
end

local function help(player: Player, cardId: any)
	if type(cardId) ~= "string" or not MarketConstants.Tradeable(cardId) then
		return
	end
	local best = others(player, cardId)
	reply(player, "Help", true, nil, { Card = cardId, Lowest = best and best.P, Sales = salesOf(cardId) })
end

-- [[ Selling ]]

local function sold(player: Player, data, id: string, buyer: string?, at: number?)
	local l = mine(data)[id]
	if not l or l.S ~= "On" then
		return
	end
	l.S = "Sold"
	l.B = if type(buyer) == "string" then string.sub(buyer, 1, 20) else nil
	l.T = if type(at) == "number" then math.floor(at) else os.time()
	l.W = if l.T < (joinedAt[player] or 0) then true else nil
	PlayerData.Batch(player, function()
		save(data, id, l)
		log(data, "Sold", { C = l.C, P = l.P, B = l.B })
		data.Inventory.MarketSold.Increment(1)
	end)
	reply(player, "Sold", true, nil, { Id = id, Card = l.C, Price = l.P })
end

local function list(player: Player, data, packet)
	local cardId, price, hours = packet.Card, tonumber(packet.Price), tonumber(packet.Hours)
	if type(cardId) ~= "string" or not MarketConstants.Tradeable(cardId) then
		return reply(player, "List", false, "That card can't go on the Market")
	end
	local card = Albums.Card(cardId) :: any
	local copies = data.Inventory.Cards[cardId].Get() or 0
	if copies < 1 then
		return reply(player, "List", false, "You don't have that card", { Card = cardId })
	end
	if not price or price ~= math.floor(price) or price < MarketConstants.Floor(cardId) then
		return reply(player, "List", false, `The price has to be at least {MarketConstants.Floor(cardId)}`, { Card = cardId })
	end
	if price > MarketConstants.Cap(cardId) then
		return reply(player, "List", false, `{card.Rarity.Name} cards can be listed for {MarketConstants.Cap(cardId)} at most`, { Card = cardId })
	end
	if Levels.FromXP(data.Player.XP.Get() or 0) < MarketConstants.SELL_LEVEL then
		return reply(player, "List", false, `You can sell on the Market from level {MarketConstants.SELL_LEVEL}`, { Card = cardId })
	end
	if not hours or not table.find(MarketConstants.HOURS, hours) then
		hours = MarketConstants.DEFAULT_HOURS
	end
	local open = 0
	for _, l in mine(data) do
		if l.S == "On" then
			open += 1
		end
	end
	if open >= limit(data) then
		return reply(player, "List", false, `You can have {limit(data)} cards on sale at once`, { Card = cardId })
	end
	if Albums.Numbered(cardId) and #Albums.Serials(data.Inventory.Serials[cardId].Get()) == 0 then
		return reply(player, "List", false, "That card is still getting its serial number, try again in a minute", { Card = cardId })
	end
	if copies == 1 and packet.Confirm ~= true and Albums.IsBias(card.Album, card.Member.Key, data.Inventory.Bias.Get()) then
		return reply(player, "List", false, nil, { Card = cardId, Confirm = true })
	end

	local id = HttpService:GenerateGUID(false)
	local now = os.time()
	local serial = 0
	local entry
	PlayerData.Batch(player, function()
		serial = takeCopy(data, cardId)
		entry = { C = cardId, R = serial, P = price, A = now, E = now + hours * 3600, S = "On" }
		save(data, id, entry)
		log(data, "Listed", { C = cardId, P = price })
	end)
	local value = { C = cardId, R = serial, P = price, A = now, E = entry.E, U = player.UserId, N = player.Name }
	local m = map()
	local ok, err = false, "no map"
	if m then
		ok, err = pcall(m.SetAsync, m, id, value, hours * 3600, price)
	end
	if not ok then
		warn(`[MarketService] couldn't list {cardId}: {err}`)
		PlayerData.Batch(player, function()
			data.Inventory.Listings.Remove(id)
			addCopy(data, cardId, serial)
		end)
		return reply(player, "List", false, "The Market's busy, try again in a moment", { Card = cardId })
	end
	value.Id = id
	listings[id] = value
	reply(player, "List", true, nil, { Card = cardId, Id = id })
end

-- takes a listing back (Cancel, or its time ran out: why = "Cancelled" | "Ended"): the card
-- comes home, unless it sold first
local function takeBack(player: Player, data, id: string, why: string): (boolean, string?)
	local l = mine(data)[id]
	if not l or l.S ~= "On" then
		return false, "That listing's gone"
	end
	local reached, won, record = claim(id, { X = true, T = os.time() })
	if not reached then
		return false, "The Market's busy, try again in a moment"
	end
	if not won then
		if type(record) == "table" and record.B then
			sold(player, data, id, record.N, record.T)
			return false, "It just sold!"
		end
		-- (already taken back, by another server: tidy up)
	end
	PlayerData.Batch(player, function()
		data.Inventory.Listings.Remove(id)
		if won then
			addCopy(data, l.C, l.R)
			log(data, why, { C = l.C, P = l.P })
		end
	end)
	unlist(id)
	return true, nil
end

local function cancel(player: Player, data, id: any)
	if type(id) ~= "string" then
		return
	end
	local ok, text = takeBack(player, data, id, "Cancelled")
	reply(player, "Cancel", ok, text, { Id = id })
end

local function collect(player: Player, data, id: any)
	local l = type(id) == "string" and mine(data)[id]
	if not l or l.S ~= "Sold" then
		return reply(player, "Collect", false, nil, { Id = id })
	end
	local pay = MarketConstants.Payout(l.P)
	PlayerData.Batch(player, function()
		data.Inventory.Listings.Remove(id)
		Currencies.Data(data, "Coins").Increment(pay)
		data.Inventory.MarketEarned.Increment(pay)
		log(data, "Paid", { P = pay, N = 1 })
	end)
	Analytics.Economy(player, "Source", "Coins", pay, coins(data), AnalyticsEvents.Transactions.MarketSale, Albums.Card(l.C) and (Albums.Card(l.C) :: any).Rarity.Key)
	reply(player, "Collect", true, nil, { Id = id, Coins = pay })
end

-- every sold listing at once (COLLECT ALL)
local function collectAll(player: Player, data)
	local ids, pay = {}, 0
	for id, l in mine(data) do
		if l.S == "Sold" then
			table.insert(ids, id)
			pay += MarketConstants.Payout(l.P)
		end
	end
	if #ids == 0 then
		return reply(player, "CollectAll", false, nil, { Coins = 0, Count = 0 })
	end
	PlayerData.Batch(player, function()
		for _, id in ids do
			data.Inventory.Listings.Remove(id)
		end
		Currencies.Data(data, "Coins").Increment(pay)
		data.Inventory.MarketEarned.Increment(pay)
		log(data, "Paid", { P = pay, N = #ids })
	end)
	Analytics.Economy(player, "Source", "Coins", pay, coins(data), AnalyticsEvents.Transactions.MarketSale, "all")
	reply(player, "CollectAll", true, nil, { Coins = pay, Count = #ids })
end

-- where each open listing's price sits among that card's copies on sale (this server's copy)
local function ranks(player: Player, data)
	local out = {}
	for id, l in mine(data) do
		if l.S ~= "On" then
			continue
		end
		local rank, lowest, count = 1, l.P, 1
		for otherId, o in listings do
			if otherId ~= id and o.C == l.C and live(o) then
				count += 1
				lowest = math.min(lowest, o.P)
				if o.P < l.P then
					rank += 1
				end
			end
		end
		out[id] = { Rank = rank, Lowest = lowest, Count = count }
	end
	reply(player, "Ranks", true, nil, { Ranks = out })
end

-- [[ Buying ]]

local function tellSeller(l, buyerName: string)
	local seller = Players:GetPlayerByUserId(l.U)
	local data = seller and PlayerData.Get(seller)
	if seller and data then
		sold(seller, data, l.Id, buyerName, os.time())
		return
	end
	local ok, err = pcall(PlayerData.SendMessage, l.U, { Market = { Id = l.Id, B = buyerName, T = os.time() } })
	if not ok then
		warn(`[MarketService] couldn't tell {l.U} their listing sold: {err}`)
	end
end

local function buy(player: Player, data, id: any, price: any)
	local l = type(id) == "string" and listings[id]
	if not live(l) then
		local best = l and others(player, l.C, id)
		return reply(player, "Buy", false, "Just sold!", { Id = id, Next = best and best.Id })
	end
	if l.U == player.UserId then
		return reply(player, "Buy", false, "That's your own listing", { Id = id })
	end
	if tonumber(price) ~= l.P then
		return reply(player, "Buy", false, "The price changed, take another look", { Id = id })
	end
	if (data.Inventory.Cards[l.C].Get() or 0) >= AlbumConstants.RAINBOW_COPIES then
		return reply(player, "Buy", false, "You've already got this card at Rainbow", { Id = id })
	end
	if coins(data) < l.P then
		return reply(player, "Buy", false, "Not enough coins", { Id = id, Coins = l.P - coins(data) })
	end

	PlayerData.Batch(player, function()
		Currencies.Data(data, "Coins").Increment(-l.P)
	end)
	local reached, won = claim(id, { B = player.UserId, N = player.Name, P = l.P, T = os.time() })
	if not won then
		PlayerData.Batch(player, function()
			Currencies.Data(data, "Coins").Increment(l.P)
		end)
		if not reached then
			return reply(player, "Buy", false, "The Market's busy, try again in a moment", { Id = id })
		end
		listings[id] = nil
		gone[id] = os.clock()
		local best = others(player, l.C, id)
		return reply(player, "Buy", false, "Just sold!", { Id = id, Next = best and best.Id })
	end

	PlayerData.Batch(player, function()
		addCopy(data, l.C, l.R)
	end)
	unlist(id)
	local card = Albums.Card(l.C) :: any
	Analytics.Economy(player, "Sink", "Coins", l.P, coins(data), AnalyticsEvents.Transactions.MarketBuy, card.Rarity.Key)
	reply(player, "Buy", true, nil, { Id = id, Card = l.C, Serial = l.R })
	task.spawn(tellSeller, l, player.Name)
	task.spawn(recordSale, l.C, l.P)
	if (l.R or 0) > 0 then
		task.spawn(SerialService.Transfer, l.C, l.R, player)
	end
	if card.Rarity.Key == "oneofone" then
		task.spawn(SerialService.SetOwner, l.C, player)
	end
end

-- [[ Lifecycle ]]

-- open listings whose time is up come home; on joining, ones that sold while away are marked
local function check(player: Player, data, joining: boolean)
	local now = os.time()
	local claims = if joining then store(MarketConstants.CLAIM_STORE) else nil
	for id, l in mine(data) do
		if not player.Parent then
			return
		end
		if l.S ~= "On" then
			continue
		end
		if (l.E or 0) <= now then
			-- (on joining, the away pop-up tells them instead of a notification)
			if takeBack(player, data, id, "Ended") and not joining then
				reply(player, "Ended", true, nil, { Id = id, Card = l.C, Price = l.P })
			end
		elseif claims then
			local ok, record = pcall(claims.GetAsync, claims, id)
			if ok and type(record) == "table" and record.B then
				sold(player, data, id, record.N, record.T)
			end
		end
	end
end

function MarketService.Start()
	-- a sale from another server, or one that waited for them to join (Scribe, durable)
	PlayerData.OnMessage:Connect(function(player: Player, message)
		local m = type(message) == "table" and message.Market
		if type(m) ~= "table" or type(m.Id) ~= "string" then
			return
		end
		local data = PlayerData.Get(player)
		if data then
			sold(player, data, m.Id, m.B, m.T)
		end
	end)

	local function joined(player: Player)
		local ok, data = pcall(PlayerData.WaitForData, player)
		if ok and data and player.Parent then
			check(player, data, true)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		joinedAt[player] = os.time()
		task.spawn(joined, player)
	end)
	for _, player in Players:GetPlayers() do
		joinedAt[player] = joinedAt[player] or os.time()
		task.spawn(joined, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		joinedAt[player] = nil
	end)

	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(MarketConstants.REFRESH)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.Get(player)
				if data and not busy[player] then
					busy[player] = true
					pcall(check, player, data, false)
					busy[player] = nil
				end
			end
		end
	end)

	MarketRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or type(packet.Action) ~= "string" then
			return
		end
		local data = PlayerData.Get(player)
		if not data then
			return
		end
		local action = packet.Action
		local guarded = action == "Buy" or action == "List" or action == "Cancel" or action == "Collect" or action == "CollectAll"
		if guarded then
			if busy[player] then
				return
			end
			busy[player] = true
		end
		local ok, err = pcall(function()
			if action == "Browse" then
				browse(player, data, packet)
			elseif action == "Detail" then
				detail(player, packet.Id)
			elseif action == "Help" then
				help(player, packet.Card)
			elseif action == "Buy" then
				buy(player, data, packet.Id, packet.Price)
			elseif action == "List" then
				list(player, data, packet)
			elseif action == "Cancel" then
				cancel(player, data, packet.Id)
			elseif action == "Collect" then
				collect(player, data, packet.Id)
			elseif action == "CollectAll" then
				collectAll(player, data)
			elseif action == "Ranks" then
				ranks(player, data)
			elseif action == "Seen" then
				PlayerData.Batch(player, function()
					data.Inventory.MarketSeen.Set(os.time())
				end)
			end
		end)
		if guarded then
			busy[player] = nil
		end
		if not ok then
			warn(`[MarketService] {action} failed for {player.Name}: {err}`)
			reply(player, action, false, "Something went wrong, try again")
		end
	end)
end

return MarketService
