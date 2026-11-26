--| BinderService
-- The K-POPPED! binder's money side (design boards "6 · Binder page + Collect", "32 · Binder · pin
-- 3 cards to earn"). Your PINNED cards (Inventory.Pins, Albums.PinSlots of them) earn coins an
-- hour (Modules/Library/Albums.EarnPerHour: rarity × level × bias, ×2 with the 2× Coins pass,
-- Albums.Boost): the full rate while you're
-- online, AlbumConstants.OFFLINE_EARN of it while you're away, up to BINDER_CAP_SECONDS of
-- earnings. The rest of the binder earns nothing, so a
-- bigger binder isn't free money: owning every member of an album pays a one-time set bonus
-- instead (BinderService.ClaimSets, SET_BONUS_PER_MEMBER a member). The HUD's Binder card
-- shows what's waiting (Albums.Waiting on the client's mirror) and Collect pays it out.
--
-- The clock is two saved numbers (Rewards.BinderBank, Rewards.BinderAt): whenever the binder
-- changes, what the old rate earned is banked first (BinderService.Bank), so a new card never
-- pays for the hours before you had it and a sold one keeps what it already earned. Online
-- players are banked at full rate every ONLINE_BANK_SECONDS, so the time since the last bank
-- when someone joins is their time away: it's banked at OFFLINE_EARN as they join.
--
-- Selling: any card but a One of One, one copy at a time, for its rarity's Sell price. Selling
-- the last copy of a card of your bias needs Confirm = true (the client's second tap). Selling a
-- numbered card gives up its highest serial (Engine/SerialService).
--
-- Pinning: a card you own, into a free slot, or in place of a pinned one (Replace = its id);
-- selling your last copy of a pinned card unpins it.
--
-- BinderRemote request: { Action = "Collect" }
--                       { Action = "Pin", Card = card id, Replace = pinned card id? }
--                       { Action = "Unpin", Card = card id }
--                       { Action = "Sell", Card = card id, Where = "Reveal" | "Binder", Confirm? }
--                       { Action = "Owners", Album = album id }  (the binder page's One of One slots)
-- Reply:                { Message = "Binder", Action, Ok, Text?, Coins?, Card?, Copies?, Confirm? }
--                       Owners: { …, Album, Owners = { [member key] = owner's name } }
--                       Pin / Unpin: { …, Card, Pins = Inventory.Pins value, Full? = no free slot }
-- Pushed:               { Message = "Binder", Action = "SetBonus", Ok = true, Albums = { ids }, Coins }
--   Confirm = true on a Sell reply: it's the last copy of your bias's card, ask again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local Analytics = require(script.Parent.Analytics)
local SerialService = require(script.Parent.SerialService)

local BinderRemote = Bridgenet.ReferenceBridge("BinderRemote")

local BinderService = {}

local busy: { [Player]: boolean } = {}
local arrived: { [Player]: boolean } = {} -- the time away has been banked (at OFFLINE_EARN)

-- [[ The clock ]]

-- Coins waiting for this player now: (whole coins, exact). share: the part of the rate earned
-- since the last bank (1 online, the default; OFFLINE_EARN for time away).
function BinderService.Waiting(data, now: number?, share: number?): (number, number)
	local cards = data.Inventory.Cards.Get() or {}
	local rate = Albums.Rate(cards, data.Inventory.Bias.Get(), data.Inventory.Pins.Get(), Albums.Boost(data.GamePasses))
	return Albums.Waiting(data.Rewards.BinderBank.Get(), data.Rewards.BinderAt.Get(), rate, now or os.time(), share)
end

-- Banks what the binder has earned at its current rate and restarts the clock. Call it inside
-- the same PlayerData.Batch as any change to Inventory.Cards or Inventory.Bias, before the change.
-- (it doesn't yield)
function BinderService.Bank(data, now: number?, share: number?)
	now = now or os.time()
	local _, exact = BinderService.Waiting(data, now, share)
	data.Rewards.BinderBank.Set(math.floor(exact * 100))
	data.Rewards.BinderAt.Set(now)
end

-- [[ Requests ]]

local function reply(player: Player, action: string, ok: boolean, text: string?, extra: { [string]: any }?)
	local packet = { Message = "Binder", Action = action, Ok = ok, Text = text }
	for k, v in extra or {} do
		packet[k] = v
	end
	BinderRemote:Fire(player, packet)
end

local function collect(player: Player, data)
	local now = os.time()
	local coins, exact = BinderService.Waiting(data, now)
	if coins < 1 then
		return reply(player, "Collect", false, "Nothing to collect yet")
	end
	PlayerData.Batch(player, function()
		Currencies.Data(data, "Coins").Increment(coins)
		data.Rewards.BinderBank.Set(math.floor((exact - coins) * 100))
		data.Rewards.BinderAt.Set(now)
	end)
	local balance = Currencies.Data(data, "Coins").Get()
	Analytics.Event(player, "BinderCollected", coins)
	Analytics.Economy(player, "Source", "Coins", coins, balance, AnalyticsEvents.Transactions.Binder, "Collect")
	reply(player, "Collect", true, nil, { Coins = coins })
end

local function sell(player: Player, data, cardId: any, where: any, confirm: boolean)
	if type(cardId) ~= "string" then
		return
	end
	local card = Albums.Card(cardId)
	local copies = data.Inventory.Cards[cardId].Get() or 0
	if not card or copies < 1 then
		return reply(player, "Sell", false, "You don't have that card", { Card = cardId })
	end
	local price = Albums.SellPrice(cardId)
	if not price then
		return reply(player, "Sell", false, `{card.Rarity.Name} cards can't be sold`, { Card = cardId })
	end
	if copies == 1 and not confirm and Albums.IsBias(card.Album, card.Member.Key, data.Inventory.Bias.Get()) then
		return reply(player, "Sell", false, nil, { Card = cardId, Confirm = true })
	end
	PlayerData.Batch(player, function()
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
		-- a numbered card: a copy still waiting for its number goes first, else the highest
		-- serial (you keep your best number; Engine/SerialService)
		local waiting = data.Inventory.SerialsPending[cardId].Get() or 0
		if not Albums.Numbered(cardId) then
			-- (nothing to give up)
		elseif waiting > 0 then
			if waiting <= 1 then
				data.Inventory.SerialsPending.Remove(cardId)
			else
				data.Inventory.SerialsPending[cardId].Set(waiting - 1)
			end
		else
			local left = Albums.DropSerial(data.Inventory.Serials[cardId].Get())
			if left == "" or copies <= 1 then
				data.Inventory.Serials.Remove(cardId)
			else
				data.Inventory.Serials[cardId].Set(left)
			end
		end
		Currencies.Data(data, "Coins").Increment(price)
	end)
	local whereName = if where == "Reveal" then "Reveal" else "Binder"
	Analytics.Event(player, "CardSold", price, card.Rarity.Key, whereName)
	Analytics.Economy(player, "Source", "Coins", price, Currencies.Data(data, "Coins").Get(), AnalyticsEvents.Transactions.CardSell, card.Rarity.Key)
	reply(player, "Sell", true, nil, { Card = cardId, Coins = price, Copies = copies - 1 })
end

-- the One of One owners of an album's members, for the binder page
local function owners(player: Player, albumId: any)
	local album = type(albumId) == "string" and Albums.Get(albumId)
	if not album then
		return
	end
	local ids, byId = {}, {}
	for _, member in album.Members do
		local id = Albums.CardId(album.Id, member.Key, "oneofone")
		table.insert(ids, id)
		byId[id] = member.Key
	end
	local list = {}
	for id, name in SerialService.Owners(ids) do
		list[byId[id]] = name
	end
	reply(player, "Owners", true, nil, { Album = album.Id, Owners = list })
end

-- [[ History ]]

-- a card's numbered copies you own (up to 3, lowest first): who rolled each and its owners
local function history(player: Player, data, cardId: any)
	if type(cardId) ~= "string" or not Albums.Numbered(cardId) then
		return
	end
	local records = {}
	for i, serial in Albums.Serials(data.Inventory.Serials[cardId].Get()) do
		if i > 3 then
			break
		end
		local r = SerialService.History(cardId, serial)
		if type(r) == "table" then
			records[tostring(serial)] = r
		end
	end
	reply(player, "History", true, nil, { Card = cardId, Records = records })
end

-- [[ Pins ]]

local function pin(player: Player, data, cardId: any, replace: any)
	if type(cardId) ~= "string" or not Albums.Card(cardId) or (data.Inventory.Cards[cardId].Get() or 0) < 1 then
		return reply(player, "Pin", false, "You don't have that card", { Card = cardId })
	end
	local pins = Albums.Pins(data.Inventory.Pins.Get())
	if table.find(pins, cardId) then
		return reply(player, "Pin", true, nil, { Card = cardId, Pins = Albums.PinValue(pins) })
	end
	local slots = Albums.PinSlots()
	-- (pins past the unlocked slots, or of cards no longer owned, make room first)
	for i = #pins, 1, -1 do
		if i > slots or (data.Inventory.Cards[pins[i]].Get() or 0) < 1 then
			table.remove(pins, i)
		end
	end
	if type(replace) == "string" and table.find(pins, replace) then
		pins[table.find(pins, replace) :: number] = cardId
	elseif #pins < slots then
		table.insert(pins, cardId)
	else
		return reply(player, "Pin", false, "Your pins are full: swap one out", { Card = cardId, Full = true, Pins = Albums.PinValue(pins) })
	end
	PlayerData.Batch(player, function()
		BinderService.Bank(data)
		data.Inventory.Pins.Set(Albums.PinValue(pins))
	end)
	reply(player, "Pin", true, nil, { Card = cardId, Pins = Albums.PinValue(pins) })
end

local function unpin(player: Player, data, cardId: any)
	local pins = Albums.Pins(data.Inventory.Pins.Get())
	local at = type(cardId) == "string" and table.find(pins, cardId)
	if at then
		table.remove(pins, at)
		PlayerData.Batch(player, function()
			BinderService.Bank(data)
			data.Inventory.Pins.Set(Albums.PinValue(pins))
		end)
	end
	reply(player, "Unpin", true, nil, { Card = cardId, Pins = Albums.PinValue(pins) })
end

-- [[ Set bonuses ]]

-- Pays the set bonus for each complete album (every member owned, any rarity) not paid yet:
-- `albumIds` (just pulled) or every album. Returns the coins paid and the album ids. (no yield)
function BinderService.ClaimSets(player: Player, data, albumIds: { string }?): (number, { string })
	local cards = data.Inventory.Cards.Get() or {}
	local paid, coins = {}, 0
	local list = {}
	if albumIds then
		for _, id in albumIds do
			table.insert(list, Albums.Get(id))
		end
	else
		list = Albums.All()
	end
	for _, album in list do
		if album and not data.Rewards.Claimed.Has(Albums.SetKey(album)) and Albums.Complete(cards, album) then
			table.insert(paid, album.Id)
			coins += Albums.SetBonus(album)
		end
	end
	if #paid == 0 then
		return 0, paid
	end
	PlayerData.Batch(player, function()
		for _, id in paid do
			data.Rewards.Claimed.Add(Albums.SetKey(Albums.Get(id) :: any))
		end
		Currencies.Data(data, "Coins").Increment(coins)
	end)
	Analytics.Economy(player, "Source", "Coins", coins, Currencies.Data(data, "Coins").Get(), AnalyticsEvents.Transactions.Binder, "SetBonus")
	reply(player, "SetBonus", true, nil, { Albums = paid, Coins = coins })
	return coins, paid
end

-- [[ Lifecycle ]]

function BinderService.Start()
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		arrived[player] = nil
	end)
	-- joining: the time since the last bank was spent away, so it earns at OFFLINE_EARN
	local function joined(player: Player)
		local ok, data = pcall(PlayerData.WaitForData, player)
		if ok and data and player.Parent then
			BinderService.Bank(data, os.time(), AlbumConstants.OFFLINE_EARN)
			arrived[player] = true
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(joined, player)
	end
	Players.PlayerAdded:Connect(joined)
	-- online: bank everyone at the full rate now and then
	task.spawn(function()
		while true do
			task.wait(AlbumConstants.ONLINE_BANK_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = PlayerData.Get(player)
				if data and arrived[player] and not busy[player] then
					pcall(BinderService.Bank, data)
				end
			end
		end
	end)
	BinderRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or busy[player] then
			return
		end
		local data = PlayerData.Get(player)
		if not data then
			return
		end
		busy[player] = true
		local ok, err = pcall(function()
			if packet.Action == "Collect" then
				collect(player, data)
			elseif packet.Action == "Sell" then
				sell(player, data, packet.Card, packet.Where, packet.Confirm == true)
			elseif packet.Action == "Owners" then
				owners(player, packet.Album)
			elseif packet.Action == "History" then
				history(player, data, packet.Card)
			elseif packet.Action == "Pin" then
				pin(player, data, packet.Card, packet.Replace)
			elseif packet.Action == "Unpin" then
				unpin(player, data, packet.Card)
			end
		end)
		busy[player] = nil
		if not ok then
			warn(`[BinderService] {packet.Action} failed for {player.Name}: {err}`)
			reply(player, tostring(packet.Action), false, "Something went wrong, try again")
		end
	end)
end

return BinderService
