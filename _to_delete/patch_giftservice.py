import os
os.chdir(os.path.expanduser('~/mnt/GuessTheK-PopSong/src'))
exec(open('/tmp/p.py').read())
G = 'server/Engine/GiftService.luau'

patch(G, [
# header
("""--| GiftService
-- Gifting ("Gifting 1–4" boards): a player picks someone in this server, the shop switches to
-- gift mode, and whatever they buy goes to that player.
--   • Robux items are gifted with their own products through Scribe (PlayerData.PromptGift):
--     the recipient's data gets the Grant, even if they leave mid-purchase. Passes use their
--     gift products (ShopCatalog.PassGifts), which put the pass in data.GamePasses.
--   • Coin items (sets, stages, mics, banners, photocards) are paid from the giver's coins here.
-- Nothing already owned can be gifted, and no one can gift themselves.""",
"""--| GiftService
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
-- Nothing already owned can be gifted (when they're here to check), and no one can gift themselves."""),
("""--   { Action = "Coins", Kind = "Set" | "Stage" | "Mic" | "StyleSet" | "Banner" | "Photocard",
--     Id = id, To = userId }                               → paid in coins, given now
--   { Action = "Thanks", To = userId }                     → the giver gets a toast""",
"""--   { Action = "Coins", Kind = "Set" | "Stage" | "Mic" | "StyleSet" | "Banner" | "Photocard",
--     Id = id, To = userId, Note = text? }                 → paid in coins, into their Gifts inbox
--   { Action = "Thanks", To = userId }                     → the giver gets a toast
--   { Action = "Find", Name = username }                   → "Found" (who that is)
--   { Action = "Claim", Id = giftId } / { Action = "ClaimAll" } → Engine/GiftInbox"""),
("""--   { Message = "Owned", To, Passes, Sets, Stages, Mics, Banners, Photocards, Debut, Bundles }""",
"""--   { Message = "Owned", To, Passes, Sets, Stages, Mics, Banners, Photocards, Debut, Bundles,
--     Away? }                                              (Away: not in this server, nothing known)
--   { Message = "Found", Name, UserId? }                   (no UserId: no such player)"""),
# requires
("""local Analytics = require(script.Parent.Analytics)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)""",
"""local Analytics = require(script.Parent.Analytics)
local AnalyticsEvents = require(ReplicatedStorage.Constants.AnalyticsEvents)
local GiftInbox = require(script.Parent.GiftInbox)"""),
("""local GiftService = {}
""", """local GiftService = {}

GiftService.DAILY_COIN_GIFTS = 25000 -- coins' worth of coin-item gifts one player can send a day
"""),
# recipient anywhere
("""-- the recipient: someone else in this server whose data is loaded
local function recipientOf(player: Player, userId: any): (Player?, any)""",
"""-- anyone else, by UserId: (their UserId, them if they're in this server, their data if loaded)
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

-- the recipient: someone else in this server whose data is loaded
local function recipientOf(player: Player, userId: any): (Player?, any)"""),
# robux: away recipients get consumables only
("""local function giftRobux(player: Player, packet)
	local to, data = recipientOf(player, packet.To)
	local name = packet.Product
	if not to or not data or type(name) ~= "string" then
		return result(player, false, "They're not in this server")
	end
	local ok, why = canGiftProduct(name, data)
	if not ok then
		return result(player, false, why or "That can't be gifted")
	end""",
"""-- products anyone can be sent without checking what they own: coins, tickets, potions
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
	end"""),
# coin gifts → inbox
("""local function giftCoins(player: Player, packet)
	local to, data = recipientOf(player, packet.To)
	local mine = PlayerData.Get(player)
	if not to or not data or not mine then
		return result(player, false, "They're not in this server")
	end""",
"""local function giftCoins(player: Player, packet)
	local userId, to, data = anyone(player, packet.To)
	local mine = PlayerData.Get(player)
	if not userId or not mine then
		return result(player, false, "Pick who it's for first")
	end"""),
("""		if has(data.Inventory.Sets, id) then
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
		end""",
"""		if data and has(data.Inventory.Sets, id) then
			return result(player, false, "They already have it")
		end
		price, name = set.Price, set.Name"""),
("""		local item = ShopCatalog.GetItem(kind, id)
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
		end""",
"""		local item = ShopCatalog.GetItem(kind, id)
		if not item or item.Set or not item.Price or not forSale(mine, function(t) return ShopCatalog.ItemForSale(kind, id, t) end) then
			return result(player, false, "That has left the shop")
		end
		local owned = data and (if kind == "Stage" then data.Inventory.Stages else data.Inventory.Mics)
		if owned and has(owned, id) then
			return result(player, false, "They already have it")
		end
		price, name = item.Price, item.Name"""),
("""		local want = {}
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
		end""",
"""		local want = {}
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
		kind = if #want == 2 then "StyleSet" else want[1]"""),
("""	local price: number?, name: string?, grant: (() -> ())?""", """	local price: number?, name: string?"""),
("""	local coins = Currencies.Data(mine, "Coins")
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
end""",
"""	local coins = Currencies.Data(mine, "Coins")
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
end"""),
# owned: away recipients
("""local function owned(player: Player, packet)
	local to, data = recipientOf(player, packet.To)
	if not to or not data then
		return result(player, false, "They're not in this server")
	end""",
"""local function owned(player: Player, packet)
	local userId, to, data = anyone(player, packet.To)
	if not userId then
		return
	end
	if not to or not data then
		-- not here: nothing to check against (coin items they already have pay back their price)
		GiftRemote:Fire(player, { Message = "Owned", To = userId, Away = true, Bundles = {} })
		return
	end"""),
# find + actions
("""local ACTIONS = { Owned = owned, Robux = giftRobux, Coins = giftCoins, Thanks = thanks }""",
"""-- the Gifts screen's search: a username → who that is
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

local ACTIONS = { Owned = owned, Robux = giftRobux, Coins = giftCoins, Thanks = thanks, Find = find, Claim = claim, ClaimAll = claimAll }"""),
("""	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lastThanks[player] = nil
	end)""", """	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		lastThanks[player] = nil
		lastFind[player] = nil
	end)"""),
])

# the robux branch above used `to.UserId` / `to.Name` further down: keep them working
s = open(G, encoding='utf-8').read()
assert s.count('local prompted, err = PlayerData.PromptGift(player, name, to.UserId)') == 1
open(G, 'w', encoding='utf-8', newline='').write(s)

# --- data ---
P = 'shared/Modules/PlayerData.luau'
patch(P, [
("""			Ladders = Scribe.MapOf("string", Count(), { MaxKeys = 400, MaxKeyLength = 64 }),""",
"""			Ladders = Scribe.MapOf("string", Count(), { MaxKeys = 400, MaxKeyLength = 64 }),
			-- the Gifts inbox (Engine/GiftInbox): gift Id → the gift as JSON, until it's claimed
			Gifts = Scribe.MapOf("string", Scribe.String("", { MaxLength = 600 }), { MaxKeys = 40, MaxKeyLength = 40 }),
			-- claimed gift Ids → when (os.time), so a repeated delivery isn't paid twice (kept 90 days)
			GiftsSeen = Scribe.MapOf("string", Count(), { MaxKeys = 600, MaxKeyLength = 40 }),"""),
("""			Bundles = Scribe.MapOf("string", Count(), { MaxKeys = 20, MaxKeyLength = 20 }), -- times each ShopCatalog.Bundles entry was bought""",
"""			Bundles = Scribe.MapOf("string", Count(), { MaxKeys = 20, MaxKeyLength = 20 }), -- times each ShopCatalog.Bundles entry was bought
			-- coin-item gifts sent today (Engine/GiftService.DAILY_COIN_GIFTS): the UTC day, the coins
			GiftDay = Count(),
			GiftCoins = Count(),"""),
])

A = 'shared/Constants/AnalyticsEvents.luau'
patch(A, [
("""	GiftSent = { Fields = { "Paid", "What" } }, -- value: coins spent (Coins) or 1 (Robux)""",
"""	GiftSent = { Fields = { "Paid", "What" } }, -- value: coins spent (Coins) or 1 (Robux)
	GiftClaimed = { Fields = { "Kind", "From" } }, -- a gift claimed from the inbox (Engine/GiftInbox); From = "Dev" | "Player\""""),
])
print('gift server patched')
