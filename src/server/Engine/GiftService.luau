--| GiftService
-- Gifting ("Gifting 1–4" boards, "56 · Gifts inbox"): a player picks someone (in this server from
-- the shop's picker, or anyone by username / from their friends on the Gifts screen), the shop
-- switches to gift mode, and whatever they buy goes to that player.
--   • Robux items are gifted with their own products through Scribe (PlayerData.PromptGift):
--     the recipient's data gets the Grant, even if they leave mid-purchase. Passes use their
--     gift products (ShopCatalog.PassGifts), which put the pass in data.GamePasses. Someone who
--     isn't in this server can only be sent coins, tickets and potions (what they own can't be
--     checked from here).
--   • Coin items (sets, stages, mics, banners, photocards) are paid from the giver's coins here
--     and land in the recipient's Gifts inbox (Engine/GiftInbox), in any server or offline;
--     they claim it there. Up to DAILY_COIN_GIFTS coins of gifts a day each (no alt funnelling).
-- Nothing already owned can be gifted (when they're here to check), and no one can gift themselves.
--
-- GiftRemote, client → server:
--   { Action = "Owned", To = userId }                     → what they own, for the gift-mode buttons
--   { Action = "Robux", Product = name, To = userId }      → Scribe gift prompt (name: a PlayerData
--                                                            Products key, e.g. "Coins2500", "GiftVIP")
--   { Action = "Coins", Kind = "Set" | "Stage" | "Mic" | "StyleSet" | "Banner" | "Photocard",
--     Id = id, To = userId, Note = text? }                 → paid in coins, into their Gifts inbox
--   { Action = "Thanks", To = userId }                     → the giver gets a toast
--   { Action = "Find", Name = username }                   → "Found" (who that is)
--   { Action = "Claim", Id = giftId } / { Action = "ClaimAll" } → Engine/GiftInbox
-- GiftRemote, server → client:
--   { Message = "Owned", To, Passes, Sets, Stages, Mics, Banners, Photocards, Debut, Bundles,
--     Away? }                                              (Away: not in this server, nothing known)
--   { Message = "Found", Name, UserId? }                   (no UserId: no such player)
--   { Message = "Result", Ok, Text }                       → the giver: refused / coin gift done
--   { Message = "Received", From, FromUserId, Item, Kind, Id, Product } → the recipient's reveal
--   { Message = "Sent", To, Item, Kind, Id, Product }      → the giver's reveal, once it's delivered
--   { Message = "Thanks", From }                           → the giver
--   { Message = "Announce", From, To, Item }               → everyone: the chat line (Client/GiftChat)
--   GiftService.Start()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local Analytics = require(script.Parent.Analytics)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local GiftInbox = require(script.Parent.GiftInbox)

local GiftRemote = Bridgenet.ReferenceBridge("GiftRemote")

local GiftService = {}

GiftService.DAILY_COIN_GIFTS = 25000 -- coins' worth of coin-item gifts one player can send a day

local busy: { [Player]: boolean } = {}
local lastThanks: { [Player]: number } = {}

-- [[ Helpers ]]

local function result(player: Player, ok: boolean, text: string)
	GiftRemote:Fire(player, { Message = "Result", Ok = ok, Text = text })
end

local function has(set, id: string): boolean
	local ok, yes = pcall(set.Has, id)
	return ok and yes == true
end

local function vip(data): boolean
	return has(data.GamePasses, "VIP")
end

-- anyone else, by UserId: (their UserId, them if they're in this server, their data if loaded)
local function anyone(player: Player, userId: any): (number?, Player?, any)
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 or userId == player.UserId then
		return nil, nil, nil
	end
	local to = Players:GetPlayerByUserId(userId)
	return userId, to, to and PlayerData.Get(to)
end

local function nameOf(userId: number): string
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return if ok and type(name) == "string" then name else "them"
end

local STYLE = {
	Banner = { Owned = "Banners", Free = SeasonConstants.FREE_BANNERS },
	Photocard = { Owned = "Photocards", Free = SeasonConstants.FREE_PHOTOCARDS },
}
local function ownsStyle(data, half: string, id: string): boolean
	return STYLE[half].Free[id] == true or has(data.Inventory[STYLE[half].Owned], id)
end

-- tells both sides and the server once something has reached the recipient
local function delivered(from: Player?, fromName: string, to: Player, item: string, extra: { [string]: any }?)
	local packet = { Message = "Received", From = fromName, FromUserId = from and from.UserId, Item = item }
	for k, v in extra or {} do
		packet[k] = v
	end
	GiftRemote:Fire(to, packet)
	if from then
		-- the giver's "GIFT SENT!" reveal: the same item fields
		local sent = { Message = "Sent", To = to.DisplayName, Item = item }
		for k, v in extra or {} do
			sent[k] = v
		end
		GiftRemote:Fire(from, sent)
	end
	GiftRemote:Fire(Bridgenet.AllPlayers(), { Message = "Announce", From = fromName, To = to.DisplayName, Item = item })
end

-- [[ Robux gifts ]]

-- product name → (giftable to this recipient?, reason)
local function canGiftProduct(name: string, data): (boolean, string?)
	for _, g in ShopCatalog.PassGifts do
		if g.Id == name then
			if (g.ProductId or 0) <= 0 then
				return false, "Not ready yet"
			end
			return not has(data.GamePasses, g.Pass), "They already have it"
		end
	end
	local pack = ShopCatalog.DebutPack
	if pack and name == pack.Id then
		return not has(data.Rewards.Claimed, pack.Id), "They already have it"
	end
	for _, b in ShopCatalog.Bundles do
		if b.Id == name then
			if b.Hidden then
				return false, "That isn't in the shop"
			end
			-- (a bundle they've never bought reads nil, not 0)
			local bought = data.Rewards.Bundles[b.Id]
			local count = tonumber(bought and bought.Get()) or 0
			return count < (b.Limit or 1), "They've got as many as they can"
		end
	end
	for _, list in { ShopCatalog.CoinBundles, ShopCatalog.RollBundles, ShopCatalog.Boosts } do
		for _, b in list do
			if b.Id == name then
				return not b.Hidden and (b.ProductId or 0) > 0, "That isn't in the shop"
			end
		end
	end
	return false, "That can't be gifted"
end

-- products anyone can be sent without checking what they own: coins, tickets, potions
local function consumable(name: string): boolean
	for _, list in { ShopCatalog.CoinBundles, ShopCatalog.RollBundles, ShopCatalog.Boosts } do
		for _, b in list do
			if b.Id == name then
				return not b.Hidden and (b.ProductId or 0) > 0
			end
		end
	end
	return false
end

local function giftRobux(player: Player, packet)
	local userId, here, data = anyone(player, packet.To)
	local name = packet.Product
	if not userId or type(name) ~= "string" then
		return result(player, false, "Pick who it's for first")
	end
	local to = { UserId = userId, Name = if here then here.Name else nameOf(userId) }
	if here and data then
		local ok, why = canGiftProduct(name, data)
		if not ok then
			return result(player, false, why or "That can't be gifted")
		end
	elseif not consumable(name) then
		return result(player, false, "They need to be in your server for that one")
	end

	-- (its gift twin when it has one, so it can't collide with a normal purchase)
	name = ShopCatalog.GiftProduct(name)
	local prompted, err = PlayerData.PromptGift(player, name, to.UserId)
	-- Scribe's answer (its GiftReason when refused), every time, so a stuck gift says why
	local answer = if prompted then "prompt opened" else "refused: " .. tostring(err)
	print(`[GiftService] PromptGift {name} from {player.Name} to {to.Name} ({to.UserId}): {answer}`)
	if not prompted then
		result(player, false, if RunService:IsStudio() then `Couldn't open the gift: {err}` else "Couldn't open the gift")
	end
end

-- [[ Coin gifts ]] (the same rules as buying for yourself in Engine/ShopService; the giver's
-- VIP early restocks count, and nothing is equipped for the recipient)

local function forSale(buyerData, check: (number?) -> boolean): boolean
	return check(nil) or (vip(buyerData) and check(ShopCatalog.ShopTime(true)))
end

local function giftCoins(player: Player, packet)
	local userId, to, data = anyone(player, packet.To)
	local mine = PlayerData.Get(player)
	if not userId or not mine then
		return result(player, false, "Pick who it's for first")
	end
	local kind, id = packet.Kind, packet.Id
	if type(id) ~= "string" then
		return result(player, false, "That isn't in the shop")
	end
	local price: number?, name: string?
	if kind == "Set" then
		local set = ShopCatalog.GetSet(id)
		if not set or not forSale(mine, function(t) return ShopCatalog.IsForSale(id, t) end) then
			return result(player, false, "That set has left the shop")
		end
		if data and has(data.Inventory.Sets, id) then
			return result(player, false, "They already have it")
		end
		price, name = set.Price, set.Name
	elseif kind == "Stage" or kind == "Mic" then
		local item = ShopCatalog.GetItem(kind, id)
		if not item or item.Set or not item.Price or not forSale(mine, function(t) return ShopCatalog.ItemForSale(kind, id, t) end) then
			return result(player, false, "That has left the shop")
		end
		local owned = data and (if kind == "Stage" then data.Inventory.Stages else data.Inventory.Mics)
		if owned and has(owned, id) then
			return result(player, false, "They already have it")
		end
		price, name = item.Price, item.Name
	elseif kind == "StyleSet" or kind == "Banner" or kind == "Photocard" then
		local spec = ShopCatalog.GetStyle(id)
		if not spec or not forSale(mine, function(t) return ShopCatalog.StyleForSale(id, t) end) then
			return result(player, false, "That has left the shop")
		end
		local want = {}
		for _, half in { "Banner", "Photocard" } do
			if (kind == "StyleSet" or kind == half) and not (data and ownsStyle(data, half, id)) then
				table.insert(want, half)
			end
		end
		if #want == 0 then
			return result(player, false, "They already have it")
		end
		price = if #want == 2 then ShopCatalog.StylePrice(id, "Set") else ShopCatalog.StylePrice(id, want[1])
		name = `{spec.Name} {if #want == 2 then "set" elseif want[1] == "Banner" then "banner" else "photocard"}`
		-- (only the half they're missing, when we could tell)
		kind = if #want == 2 then "StyleSet" else want[1]
	else
		return result(player, false, "That can't be gifted")
	end

	local coins = Currencies.Data(mine, "Coins")
	if not price or coins.Get() < price then
		return result(player, false, "Not enough coins")
	end
	-- the daily cap (UTC days)
	local today = os.time() // 86400
	local sentToday = if mine.Rewards.GiftDay.Get() == today then mine.Rewards.GiftCoins.Get() else 0
	if sentToday + price > GiftService.DAILY_COIN_GIFTS then
		return result(player, false, `You can gift {ShopCatalog.Format(GiftService.DAILY_COIN_GIFTS)} coins of items a day`)
	end
	PlayerData.Batch(player, function()
		coins.Increment(-(price :: number))
		mine.Rewards.GiftDay.Set(today)
		mine.Rewards.GiftCoins.Set(sentToday + price)
	end)
	local note = if type(packet.Note) == "string" then string.sub(packet.Note, 1, 80) else nil
	local sent = GiftInbox.Send(userId, {
		From = player.DisplayName,
		FromId = player.UserId,
		Kind = kind,
		ItemId = id,
		Name = name,
		Price = price,
		Note = note,
	})
	if not sent then
		-- (their inbox couldn't take it: nothing was sent, so nothing is spent)
		PlayerData.Batch(player, function()
			coins.Increment(price :: number)
			mine.Rewards.GiftCoins.Set(sentToday)
		end)
		return result(player, false, "Couldn't send it: their gift inbox may be full")
	end
	Analytics.Economy(player, "Sink", "Coins", price :: number, coins.Get(), AnalyticsEvents.Transactions.Gift, kind)
	Analytics.Event(player, "GiftSent", price :: number, "Coins", kind)
	local toName = if to then to.DisplayName else nameOf(userId)
	GiftRemote:Fire(player, { Message = "Sent", To = toName, Item = name, Kind = kind, Id = id })
	if to then
		GiftRemote:Fire(Bridgenet.AllPlayers(), { Message = "Announce", From = player.DisplayName, To = to.DisplayName, Item = name })
	end
end

-- [[ What they own ]] (the gift-mode buttons say "Saa has it")

local function ownedList(set): { string }
	local ok, list = pcall(set.Get)
	local out = {}
	if ok and type(list) == "table" then
		for k, v in list do
			table.insert(out, if type(k) == "string" then k else v)
		end
	end
	return out
end

local function owned(player: Player, packet)
	local userId, to, data = anyone(player, packet.To)
	if not userId then
		return
	end
	if not to or not data then
		-- not here: nothing to check against (coin items they already have pay back their price)
		GiftRemote:Fire(player, { Message = "Owned", To = userId, Away = true, Bundles = {} })
		return
	end
	local bundles = {}
	for _, b in ShopCatalog.Bundles do
		local count = data.Rewards.Bundles[b.Id]
		bundles[b.Id] = tonumber(count and count.Get()) or 0
	end
	local pack = ShopCatalog.DebutPack
	GiftRemote:Fire(player, {
		Message = "Owned",
		To = to.UserId,
		Passes = ownedList(data.GamePasses),
		Sets = ownedList(data.Inventory.Sets),
		Stages = ownedList(data.Inventory.Stages),
		Mics = ownedList(data.Inventory.Mics),
		Banners = ownedList(data.Inventory.Banners),
		Photocards = ownedList(data.Inventory.Photocards),
		Debut = pack ~= nil and has(data.Rewards.Claimed, pack.Id),
		Bundles = bundles,
	})
end

local function thanks(player: Player, packet)
	local to = type(packet.To) == "number" and Players:GetPlayerByUserId(packet.To)
	if not to or to == player or os.clock() - (lastThanks[player] or 0) < 3 then
		return
	end
	lastThanks[player] = os.clock()
	GiftRemote:Fire(to, { Message = "Thanks", From = player.DisplayName })
end

-- the Gifts screen's search: a username → who that is
local lastFind: { [Player]: number } = {}
local function find(player: Player, packet)
	local name = packet.Name
	if type(name) ~= "string" or #name < 3 or #name > 20 or os.clock() - (lastFind[player] or 0) < 1 then
		return
	end
	lastFind[player] = os.clock()
	local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, name)
	local found = ok and type(userId) == "number" and userId ~= player.UserId
	GiftRemote:Fire(player, { Message = "Found", Name = if found then nameOf(userId) else name, UserId = if found then userId else nil })
end

local function claim(player: Player, packet)
	GiftInbox.Claim(player, packet.Id)
end

local function claimAll(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	for _, gift in GiftInbox.List(data) do
		GiftInbox.Claim(player, gift.Id, true)
	end
end

local ACTIONS = { Owned = owned, Robux = giftRobux, Coins = giftCoins, Thanks = thanks, Find = find, Claim = claim, ClaimAll = claimAll }

function GiftService.Start()
	GiftRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" or busy[player] then
			return
		end
		local action = ACTIONS[packet.Action]
		if not action then
			return
		end
		busy[player] = true
		local ok, err = pcall(action, player, packet)
		busy[player] = nil
		if not ok then
			warn("[GiftService]", packet.Action, err)
			-- (in Studio the toast says what broke)
			result(player, false, if RunService:IsStudio() then `Something went wrong: {err}` else "Something went wrong")
		end
	end)

	-- a Robux gift has landed in the recipient's data (Scribe); the giver may have left
	PlayerData.OnGiftReceived:Connect(function(to: Player, info)
		local from = Players:GetPlayerByUserId(info.FromUserId)
		local fromName = if from then from.DisplayName else "A fan"
		if not from then
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, info.FromUserId)
			if ok and name then
				fromName = name
			end
		end
		local product = ShopCatalog.GiftBase(info.Product) -- (the twin's name → the item)
		if from then
			Analytics.Event(from, "GiftSent", 1, "Robux", product)
		end
		delivered(from, fromName, to, ShopCatalog.GiftName(product) or "a gift", { Product = product })
	end)

	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lastThanks[player] = nil
		lastFind[player] = nil
	end)
end

return GiftService
