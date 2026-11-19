--| GiftService
-- Gifting ("Gifting 1–4" boards): a player picks someone in this server, the shop switches to
-- gift mode, and whatever they buy goes to that player.
--   • Robux items are gifted with their own products through Scribe (PlayerData.PromptGift):
--     the recipient's data gets the Grant, even if they leave mid-purchase. Passes use their
--     gift products (ShopCatalog.PassGifts), which put the pass in data.GamePasses.
--   • Coin items (sets, stages, mics, banners, photocards) are paid from the giver's coins here.
-- Nothing already owned can be gifted, and no one can gift themselves.
--
-- GiftRemote, client → server:
--   { Action = "Owned", To = userId }                     → what they own, for the gift-mode buttons
--   { Action = "Robux", Product = name, To = userId }      → Scribe gift prompt (name: a PlayerData
--                                                            Products key, e.g. "Coins2500", "GiftVIP")
--   { Action = "Coins", Kind = "Set" | "Stage" | "Mic" | "StyleSet" | "Banner" | "Photocard",
--     Id = id, To = userId }                               → paid in coins, given now
--   { Action = "Thanks", To = userId }                     → the giver gets a toast
-- GiftRemote, server → client:
--   { Message = "Owned", To, Passes, Sets, Stages, Mics, Banners, Photocards, Debut, Bundles }
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

local GiftRemote = Bridgenet.ReferenceBridge("GiftRemote")

local GiftService = {}

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

-- the recipient: someone else in this server whose data is loaded
local function recipientOf(player: Player, userId: any): (Player?, any)
	local to = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not to or to == player then
		return nil, nil
	end
	return to, PlayerData.Get(to)
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

local function giftRobux(player: Player, packet)
	local to, data = recipientOf(player, packet.To)
	local name = packet.Product
	if not to or not data or type(name) ~= "string" then
		return result(player, false, "They're not in this server")
	end
	local ok, why = canGiftProduct(name, data)
	if not ok then
		return result(player, false, why or "That can't be gifted")
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
	local to, data = recipientOf(player, packet.To)
	local mine = PlayerData.Get(player)
	if not to or not data or not mine then
		return result(player, false, "They're not in this server")
	end
	local kind, id = packet.Kind, packet.Id
	if type(id) ~= "string" then
		return result(player, false, "That isn't in the shop")
	end
	local price: number?, name: string?, grant: (() -> ())?
	if kind == "Set" then
		local set = ShopCatalog.GetSet(id)
		if not set or not forSale(mine, function(t) return ShopCatalog.IsForSale(id, t) end) then
			return result(player, false, "That set has left the shop")
		end
		if has(data.Inventory.Sets, id) then
			return result(player, false, "They already have it")
		end
		local stage, mic = ShopCatalog.SetPieces(set)
		price, name = set.Price, set.Name
		grant = function()
			data.Inventory.Sets.Add(id)
			if not has(data.Inventory.Stages, stage.Id) then
				data.Inventory.Stages.Add(stage.Id)
			end
			if not has(data.Inventory.Mics, mic.Id) then
				data.Inventory.Mics.Add(mic.Id)
			end
		end
	elseif kind == "Stage" or kind == "Mic" then
		local item = ShopCatalog.GetItem(kind, id)
		local owned = if kind == "Stage" then data.Inventory.Stages else data.Inventory.Mics
		if not item or item.Set or not item.Price or not forSale(mine, function(t) return ShopCatalog.ItemForSale(kind, id, t) end) then
			return result(player, false, "That has left the shop")
		end
		if has(owned, id) then
			return result(player, false, "They already have it")
		end
		price, name = item.Price, item.Name
		grant = function()
			owned.Add(id)
		end
	elseif kind == "StyleSet" or kind == "Banner" or kind == "Photocard" then
		local spec = ShopCatalog.GetStyle(id)
		if not spec or not forSale(mine, function(t) return ShopCatalog.StyleForSale(id, t) end) then
			return result(player, false, "That has left the shop")
		end
		local want = {}
		for _, half in { "Banner", "Photocard" } do
			if (kind == "StyleSet" or kind == half) and not ownsStyle(data, half, id) then
				table.insert(want, half)
			end
		end
		if #want == 0 then
			return result(player, false, "They already have it")
		end
		price = if #want == 2 then ShopCatalog.StylePrice(id, "Set") else ShopCatalog.StylePrice(id, want[1])
		name = `{spec.Name} {if #want == 2 then "set" elseif want[1] == "Banner" then "banner" else "photocard"}`
		grant = function()
			for _, half in want do
				data.Inventory[STYLE[half].Owned].Add(id)
			end
		end
	else
		return result(player, false, "That can't be gifted")
	end

	local coins = Currencies.Data(mine, "Coins")
	if not price or coins.Get() < price then
		return result(player, false, "Not enough coins")
	end
	PlayerData.Batch(player, function()
		coins.Increment(-(price :: number))
	end)
	PlayerData.Batch(to, grant :: () -> ())
	Analytics.Economy(player, "Sink", "Coins", price :: number, coins.Get(), AnalyticsEvents.Transactions.Gift, kind)
	Analytics.Event(player, "GiftSent", price :: number, "Coins", kind)
	delivered(player, player.DisplayName, to, name :: string, { Kind = kind, Id = id })
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
	local to, data = recipientOf(player, packet.To)
	if not to or not data then
		return result(player, false, "They're not in this server")
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

local ACTIONS = { Owned = owned, Robux = giftRobux, Coins = giftCoins, Thanks = thanks }

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
	end)
end

return GiftService
