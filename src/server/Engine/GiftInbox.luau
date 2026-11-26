--| GiftInbox
-- The Gifts inbox (design board "56 · Gifts inbox + send to anyone"): every gift waits in the
-- recipient's Inventory.Gifts until they claim it, wherever it came from: a coin item bought for
-- them in the shop (Engine/GiftService), from any server and while they're offline, or a gift from
-- the developer (the "gift" Cmdr command).
--   • A gift to someone in this server goes straight into their data; anyone else gets it through
--     Scribe's durable messages (PlayerData.SendMessage → PlayerData.OnMessage), which arrive in
--     whichever server they're in, or when they next join. Messages can repeat, so each gift has an
--     Id and arriving twice does nothing (Inventory.GiftsSeen remembers claimed Ids).
--   • Claiming pays it out (a cosmetic they already have turns into its price in coins) and plays
--     the "GIFT RECEIVED!" reveal (GiftRemote "Received").
--   • Up to MAX wait at once; one EXPIRE_DAYS old goes when they next join or claim.
-- A gift (stored as JSON in Inventory.Gifts[Id]):
--   { Id, At, From, FromId, Dev?, Kind, ItemId?, Amount?, Name, Note?, Price? }
--   Kind = "Coins" | "Tickets" | "Set" | "Stage" | "Mic" | "StyleSet" | "Banner" | "Photocard" | "Pass"
-- GiftRemote, client → server:
--   { Action = "Claim", Id = id }  /  { Action = "ClaimAll" }
-- GiftRemote, server → client:
--   { Message = "Claimed", Ok, Id?, Text? }  (then the usual "Received" for the reveal)
--   GiftInbox.Send(toUserId, gift) -> boolean      (gift without Id / At: they're added)
--   GiftInbox.Claim(player, id) / GiftInbox.Start()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local Analytics = require(script.Parent.Analytics)

local GiftRemote = Bridgenet.ReferenceBridge("GiftRemote")

local GiftInbox = {}

GiftInbox.MAX = 30 -- gifts that can wait at once (the data allows a few more, for gifts in flight)
GiftInbox.EXPIRE_DAYS = 30
GiftInbox.SEEN_DAYS = 90 -- how long a claimed gift's Id is remembered (repeat messages)

local DAY = 86400

-- [[ Helpers ]]

local function has(set, id: string): boolean
	local ok, yes = pcall(set.Has, id)
	return ok and yes == true
end

local function decode(json: string?): { [string]: any }?
	if type(json) ~= "string" then
		return nil
	end
	local ok, gift = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and type(gift) == "table" then gift else nil
end

-- every waiting gift, oldest first
function GiftInbox.List(data): { { [string]: any } }
	local out = {}
	for id, json in data.Inventory.Gifts.Get() or {} do
		local gift = decode(json)
		if gift then
			gift.Id = id
			table.insert(out, gift)
		end
	end
	table.sort(out, function(a, b)
		return (a.At or 0) < (b.At or 0)
	end)
	return out
end

local function count(data): number
	local n = 0
	for _ in data.Inventory.Gifts.Get() or {} do
		n += 1
	end
	return n
end

-- drops expired gifts and forgets old claimed Ids (call inside a Batch)
local function tidy(data)
	local now = os.time()
	for id, json in data.Inventory.Gifts.Get() or {} do
		local gift = decode(json)
		if not gift or now - (gift.At or 0) > GiftInbox.EXPIRE_DAYS * DAY then
			data.Inventory.Gifts.Remove(id)
		end
	end
	for id, at in data.Inventory.GiftsSeen.Get() or {} do
		if now - (tonumber(at) or 0) > GiftInbox.SEEN_DAYS * DAY then
			data.Inventory.GiftsSeen.Remove(id)
		end
	end
end

-- puts a gift into a loaded player's inbox; false when it's already there / claimed / full
local function add(player: Player, data, gift): boolean
	local id = gift.Id
	if type(id) ~= "string" or #id > 40 then
		return false
	end
	local waiting = data.Inventory.Gifts[id].Get()
	if (waiting and waiting ~= "") or (tonumber(data.Inventory.GiftsSeen[id].Get()) or 0) > 0 then
		return false -- (a repeat delivery)
	end
	if count(data) >= GiftInbox.MAX + 10 then
		warn(`[GiftInbox] {player.Name}'s inbox is full: gift {id} ({gift.Name}) from {gift.From} dropped`)
		return false
	end
	local stored = table.clone(gift)
	stored.Id = nil
	PlayerData.Batch(player, function()
		data.Inventory.Gifts[id].Set(HttpService:JSONEncode(stored))
	end)
	GiftRemote:Fire(player, { Message = "Inbox", From = gift.From, Name = gift.Name })
	return true
end

-- [[ Sending ]]

function GiftInbox.Send(toUserId: number, gift: { [string]: any }): boolean
	gift.Id = gift.Id or string.sub(HttpService:GenerateGUID(false), 1, 18)
	gift.At = gift.At or os.time()
	if type(gift.Note) == "string" then
		gift.Note = string.sub(gift.Note, 1, 80)
	end
	local to = Players:GetPlayerByUserId(toUserId)
	local data = to and PlayerData.Get(to)
	if to and data then
		return add(to, data, gift)
	end
	return PlayerData.SendMessage(toUserId, { Gift = gift }) == true
end

-- [[ Claiming ]]

local STYLE = {
	Banner = { Owned = "Banners", Free = SeasonConstants.FREE_BANNERS },
	Photocard = { Owned = "Photocards", Free = SeasonConstants.FREE_PHOTOCARDS },
}
local function ownsStyle(data, half: string, id: string): boolean
	return STYLE[half].Free[id] == true or has(data.Inventory[STYLE[half].Owned], id)
end

-- pays one gift out (inside a Batch). Returns the coins it turned into when they already had it
local function grant(data, gift): number
	local kind, id, amount = gift.Kind, gift.ItemId, math.max(0, math.floor(tonumber(gift.Amount) or 0))
	local refund = 0
	local function addTo(set, key: string): boolean
		if has(set, key) then
			return false
		end
		set.Add(key)
		return true
	end
	if kind == "Coins" then
		Currencies.Data(data, "Coins").Increment(amount)
	elseif kind == "Tickets" then
		Currencies.Data(data, "Tickets").Increment(amount)
	elseif kind == "Set" and type(id) == "string" then
		local set = ShopCatalog.GetSet(id)
		if set and addTo(data.Inventory.Sets, id) then
			local stage, mic = ShopCatalog.SetPieces(set)
			addTo(data.Inventory.Stages, stage.Id)
			addTo(data.Inventory.Mics, mic.Id)
		else
			refund = gift.Price or 0
		end
	elseif (kind == "Stage" or kind == "Mic") and type(id) == "string" then
		local owned = if kind == "Stage" then data.Inventory.Stages else data.Inventory.Mics
		if not addTo(owned, id) then
			refund = gift.Price or 0
		end
	elseif (kind == "StyleSet" or kind == "Banner" or kind == "Photocard") and type(id) == "string" then
		local got = false
		for _, half in { "Banner", "Photocard" } do
			if (kind == "StyleSet" or kind == half) and not ownsStyle(data, half, id) then
				data.Inventory[STYLE[half].Owned].Add(id)
				got = true
			end
		end
		if not got then
			refund = gift.Price or 0
		end
	elseif kind == "Pass" and type(id) == "string" then
		if not addTo(data.GamePasses, id) then
			refund = gift.Price or 0
		end
	end
	if refund > 0 then
		Currencies.Data(data, "Coins").Increment(refund)
	end
	return refund
end

-- the reveal's packet ("GIFT RECEIVED!", PurchasedController)
local function reveal(player: Player, gift, refund: number)
	local packet = {
		Message = "Received",
		From = gift.From,
		FromUserId = gift.FromId,
		Item = gift.Name,
		Kind = gift.Kind,
		Id = gift.ItemId,
		Amount = gift.Amount,
	}
	if gift.Kind == "Pass" then
		-- (the reveal draws passes from their gift product)
		for _, g in ShopCatalog.PassGifts do
			if g.Pass == gift.ItemId then
				packet.Product = g.Id
			end
		end
	end
	GiftRemote:Fire(player, packet)
	if refund > 0 then
		GiftRemote:Fire(player, { Message = "Claimed", Ok = true, Text = `You already had it: +{ShopCatalog.Format(refund)} coins instead` })
	end
end

function GiftInbox.Claim(player: Player, id: any, quiet: boolean?): boolean
	local data = PlayerData.Get(player)
	if not data or type(id) ~= "string" then
		return false
	end
	local gift = decode(data.Inventory.Gifts[id].Get())
	if not gift then
		if not quiet then
			GiftRemote:Fire(player, { Message = "Claimed", Ok = false, Id = id, Text = "That gift has gone" })
		end
		return false
	end
	local refund = 0
	PlayerData.Batch(player, function()
		data.Inventory.Gifts.Remove(id)
		data.Inventory.GiftsSeen[id].Set(os.time())
		refund = grant(data, gift)
	end)
	Analytics.Event(player, "GiftClaimed", 1, gift.Kind or "?", if gift.Dev then "Dev" else "Player")
	GiftRemote:Fire(player, { Message = "Claimed", Ok = true, Id = id })
	reveal(player, gift, refund)
	return true
end

-- [[ Start ]]

function GiftInbox.Start()
	-- a gift from another server, or one that waited for them to join (Scribe, durable)
	PlayerData.OnMessage:Connect(function(player: Player, message)
		if type(message) ~= "table" or type(message.Gift) ~= "table" then
			return
		end
		local data = PlayerData.Get(player)
		if data then
			add(player, data, message.Gift)
		end
	end)

	local function joined(player: Player)
		local ok, data = pcall(PlayerData.WaitForData, player)
		if ok and data and player.Parent then
			PlayerData.Batch(player, function()
				tidy(data)
			end)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(joined, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(joined, player)
	end
end

return GiftInbox
