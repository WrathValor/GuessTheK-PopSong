--| EventService
-- The live in-game event (Constants/LiveEvents, design boards "79a–d · Events"): its missions,
-- its currency and its shop. Saved in data.Events (Modules/PlayerData), which belongs to one
-- event (Events.Id): when another event is live, or none, the old one is settled first: each
-- unspent unit of its currency pays Leftover coins, each unopened pack becomes a gen pack, and
-- the counters, claims and buys start over.
--
-- ReplicatedStorage attribute "LiveEvent" = the live event's Id ("" = none), checked every
-- minute, for the HUD button and the Events screen.
--
-- Progress: EventService.Record(player, { Wins = 1, Packs = 5, … }) (LiveEvents.STATS names)
-- moves today's counters and the event's. RewardsService passes on every duel's facts and the
-- photocard loops' stats; AlbumService adds SetCards (cards from the event's set). Outside any Batch.
--
-- EventRemote requests: { Action = "Claim", Id = mission id }
--                       { Action = "Buy", Id = shop item id }
-- Reply:                { Message = "Result", Ok, Text, Action, Id, Reward? = { Currency?, Packs? },
--                         Item? = the shop item bought }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local LiveEvents = require(ReplicatedStorage.Constants.LiveEvents)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Albums = require(ReplicatedStorage.Modules.Library.Albums)

local EventRemote = Bridgenet.ReferenceBridge("EventRemote")

local EventService = {}

local busy: { [Player]: boolean } = {}

local function reply(player: Player, action: string, ok: boolean, text: string, extra: { [string]: any }?)
	local packet = { Message = "Result", Ok = ok, Text = text, Action = action }
	for k, v in extra or {} do
		packet[k] = v
	end
	EventRemote:Fire(player, packet)
end

-- Brings a player's event save up to `now`: settles an old event, starts the live one's day.
-- Call inside PlayerData.Batch. Returns the live event (or nil).
local function settle(data, now: number)
	local live = LiveEvents.Current(now)
	local id = if live then live.Id else ""
	local ev = data.Events
	if ev.Id.Get() ~= id then
		local old = LiveEvents.Get(ev.Id.Get())
		local left = ev.Currency.Get()
		if left > 0 then
			data.Currencies.Won.Increment(left * (if old then old.Leftover else 0))
		end
		local packs = ev.Packs.Get()
		if packs > 0 then
			Currencies.Data(data, "GenPacks").Increment(packs)
		end
		ev.Currency.Set(0)
		ev.Packs.Set(0)
		ev.Daily.Clear()
		ev.Total.Clear()
		ev.DailyClaimed.Clear()
		ev.Claimed.Clear()
		ev.Bought.Clear()
		ev.BoughtToday.Clear()
		ev.Day.Set(LiveEvents.Day(now))
		ev.Id.Set(id)
	end
	if live and ev.Day.Get() ~= LiveEvents.Day(now) then
		ev.Day.Set(LiveEvents.Day(now))
		ev.Daily.Clear()
		ev.DailyClaimed.Clear()
		ev.BoughtToday.Clear()
	end
	return live
end

local function grantReward(data, reward)
	if (reward.Currency or 0) > 0 then
		data.Events.Currency.Increment(reward.Currency)
	end
	if (reward.Packs or 0) > 0 then
		data.Events.Packs.Increment(reward.Packs)
	end
end

local function claim(player: Player, data, id: any)
	if type(id) ~= "string" then
		return
	end
	local result
	PlayerData.Batch(player, function()
		local live = settle(data, os.time())
		if not live then
			result = { false, "The event is over" }
			return
		end
		local mission, daily = LiveEvents.Mission(live, id)
		if not mission then
			result = { false, "That mission isn't in this event" }
			return
		end
		local claimed = if daily then data.Events.DailyClaimed else data.Events.Claimed
		if claimed.Has(id) then
			result = { false, "Already claimed" }
			return
		end
		local counts = if daily then data.Events.Daily else data.Events.Total
		if (counts[mission.Stat].Get() or 0) < mission.Goal then
			result = { false, "Not done yet" }
			return
		end
		claimed.Add(id)
		grantReward(data, mission.Reward)
		result = { true, mission.Text, mission.Reward }
	end)
	reply(player, "Claim", result[1], result[2], { Id = id, Reward = result[3] })
end

-- the shop: what each Kind gives (inside a Batch)
local GRANTS = {
	Pack = function(data, _item)
		data.Events.Packs.Increment(1)
	end,
	Set = function(data, item)
		local set = ShopCatalog.GetSet(item.Set)
		if not set then
			return
		end
		local stage, mic = ShopCatalog.SetPieces(set)
		data.Inventory.Sets.Add(set.Id)
		if not data.Inventory.Stages.Has(stage.Id) then
			data.Inventory.Stages.Add(stage.Id)
		end
		if not data.Inventory.Mics.Has(mic.Id) then
			data.Inventory.Mics.Add(mic.Id)
		end
	end,
	Title = function(data, item)
		data.Inventory.Titles.Add(item.Title)
	end,
	Premium = function(data, item)
		data.Inventory.PremiumOwned[item.Pack].Increment(1)
	end,
	Luck = function(data, item)
		local clock = data.Boosts.Luck
		clock.Set(math.min(clock.Get() + item.Minutes * 60, ShopCatalog.BOOST_MAX_SECONDS))
	end,
	Coins = function(data, item)
		data.Currencies.Won.Increment(item.Amount)
	end,
}

-- an item you can't buy again (a set or title you already have, from anywhere)
local function owned(data, item): boolean
	if item.Kind == "Set" then
		return data.Inventory.Sets.Has(item.Set)
	elseif item.Kind == "Title" then
		return data.Inventory.Titles.Has(item.Title)
	end
	return false
end
EventService.Owned = owned

local function buy(player: Player, data, id: any)
	if type(id) ~= "string" then
		return
	end
	local result
	PlayerData.Batch(player, function()
		local live = settle(data, os.time())
		local item = live and LiveEvents.Item(live, id)
		if not (live and item and GRANTS[item.Kind]) then
			result = { false, "That isn't in the shop" }
			return
		end
		if owned(data, item) then
			result = { false, "You already have it" }
			return
		end
		if item.Limit and (data.Events.Bought[id].Get() or 0) >= item.Limit then
			result = { false, "Sold out" }
			return
		end
		if item.DailyLimit and (data.Events.BoughtToday[id].Get() or 0) >= item.DailyLimit then
			result = { false, "Sold out for today" }
			return
		end
		if data.Events.Currency.Get() < item.Price then
			result = { false, `Not enough {live.Currency.Plural}` }
			return
		end
		data.Events.Currency.Increment(-item.Price)
		data.Events.Bought[id].Set((data.Events.Bought[id].Get() or 0) + 1)
		data.Events.BoughtToday[id].Set((data.Events.BoughtToday[id].Get() or 0) + 1)
		GRANTS[item.Kind](data, item)
		result = { true, `Bought {item.Name}`, item }
	end)
	reply(player, "Buy", result[1], result[2], { Id = id, Item = result[3] })
end

local ACTIONS = {
	Claim = function(player, data, packet)
		claim(player, data, packet.Id)
	end,
	Buy = function(player, data, packet)
		buy(player, data, packet.Id)
	end,
}

-- [[ Progress ]]

-- stats = { Wins = 1, Packs = 5, … } (LiveEvents.STATS); unknown names and zeros are skipped.
-- Call it outside any other Batch.
function EventService.Record(player: Player, stats: { [string]: number })
	local data = PlayerData.Get(player)
	if not data or not LiveEvents.Current() then
		return
	end
	PlayerData.Batch(player, function()
		if not settle(data, os.time()) then
			return
		end
		for stat, n in stats do
			if type(n) == "number" and n > 0 and table.find(LiveEvents.STATS, stat) then
				local daily, total = data.Events.Daily[stat], data.Events.Total[stat]
				daily.Set((daily.Get() or 0) + n)
				total.Set((total.Get() or 0) + n)
			end
		end
	end)
end

-- the live event, for AlbumService's event pack (nil = none). Its set's last card falls back to
-- a normal one while the set has no card art yet.
function EventService.LiveSet()
	return LiveEvents.Current()
end

-- settle a player's save now (AlbumService calls it before opening an event pack)
function EventService.Settle(player: Player)
	local data = PlayerData.Get(player)
	if data then
		PlayerData.Batch(player, function()
			settle(data, os.time())
		end)
	end
end

-- [[ Lifecycle ]]

function EventService.Start()
	local function publish()
		local live = LiveEvents.Current()
		local id = if live then live.Id else ""
		if ReplicatedStorage:GetAttribute("LiveEvent") ~= id then
			ReplicatedStorage:SetAttribute("LiveEvent", id)
			-- an event started or ended while players are in: settle everyone now
			for _, player in Players:GetPlayers() do
				task.spawn(EventService.Settle, player)
			end
		end
	end
	publish()
	task.spawn(function()
		while true do
			task.wait(60)
			publish()
		end
	end)

	EventRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or busy[player] then
			return
		end
		local action = ACTIONS[packet.Action]
		local data = PlayerData.Get(player)
		if not action or not data then
			return
		end
		busy[player] = true
		local ok, err = pcall(action, player, data, packet)
		busy[player] = nil
		if not ok then
			warn("[EventService]", packet.Action, err)
			reply(player, packet.Action, false, "Something went wrong")
		end
	end)

	local function onJoin(player: Player)
		if PlayerData.WaitForData(player) then
			EventService.Settle(player)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

return EventService
