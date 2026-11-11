--| ShopService
-- Server side of the shop. Every coin purchase is checked here (price, balance, rotation,
-- ownership) before anything changes; the client only asks. Robux coin bundles are granted
-- by Scribe's receipt handling (see PlayerData Products); game passes are checked on join
-- and after a purchase prompt.
--
-- ShopRemote requests: { Action = "BuySet" | "EquipSet", Id = setId }
--                      { Action = "BuyItem" | "EquipItem", Kind = "Stage" | "Mic", Id = itemId }
--                      { Action = "EquipTitle", Id = title ("" = default) }
--                      { Action = "BuyStyle", Kind = "Set" | "Banner" | "Photocard", Id = bannerId }
--                      { Action = "EquipStyle", Banner = id?, Photocard = id? }
-- Reply to the player:  { Message = "Result", Ok = bool, Text = string, Action, Id, Kind }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Levels = require(ReplicatedStorage.Modules.Levels)
local Analytics = require(script.Parent.Analytics)
local Collection = require(script.Parent.Collection)

local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")

local ShopService = {}

-- [[ Song sets (company + group, see Modules/Library/Packs). Songs aren't sold here any more:
-- they come from the song roll (Engine/RollService). ]]

-- After buying songs: finish any set they complete and give its title (Engine/Collection).
local function checkPacksComplete(data, songs: { any })
	Collection.Check(data, songs)
end

-- [[ Helpers ]]

local busy: { [Player]: boolean } = {}

-- VIP Pass: the next rotation is buyable early (ShopCatalog.VIP_EARLY_SECONDS)
local function vip(data): boolean
	return data.GamePasses.Has("VIP") == true
end

local function reply(player: Player, packet, ok: boolean, text: string)
	ShopRemote:Fire(player, {
		Message = "Result",
		Ok = ok,
		Text = text,
		Action = packet.Action,
		Id = packet.Id,
		Kind = packet.Kind, -- BuyItem / EquipItem: "Stage" | "Mic" (the purchase reveal needs it)
		Price = packet.Charged, -- BuyStyle: what it actually cost (finishing a set costs one half)
	})
end

-- [[ Analytics ]]

-- does the player already own a stage / mic (a set's pieces count) of this rarity?
local function ownsRarity(data, rarity: string): boolean
	for _, kind in { "Stage", "Mic" } do
		for _, id in data.Inventory[if kind == "Stage" then "Stages" else "Mics"].Get() or {} do
			local item = ShopCatalog.GetItem(kind, id)
			if item and item.Rarity == rarity then
				return true
			end
		end
	end
	return false
end

-- a coin purchase went through: ItemBought (value = level), plus FirstOfRarity when `first`
local function logBought(player: Player, data, kind: string, rarity: string, id: string, first: boolean?)
	local level = (Levels.FromXP(data.Player.XP.Get()))
	Analytics.Event(player, "ItemBought", level, kind, rarity, id)
	if first then
		Analytics.Event(player, "FirstOfRarity", level, rarity, kind)
	end
end

-- Takes `price` coins and runs `grant` in one batch. False (and nothing changes) if they can't afford it.
-- transaction + sku go to the Economy dashboard (Constants/AnalyticsEvents.Transactions).
local function spend(player: Player, data, price: number, grant: () -> (), transaction: string, sku: string): boolean
	local coins = Currencies.Data(data, "Coins")
	if coins.Get() < price then
		return false
	end
	PlayerData.Batch(player, function()
		coins.Increment(-price)
		grant()
	end)
	Analytics.Economy(player, "Sink", "Coins", price, coins.Get(), transaction, sku)
	return true
end

-- [[ Actions ]]

local function buySet(player: Player, data, packet)
	local set = type(packet.Id) == "string" and ShopCatalog.GetSet(packet.Id)
	if not set then
		return reply(player, packet, false, "That set doesn't exist")
	end
	if data.Inventory.Sets.Has(set.Id) then
		return reply(player, packet, false, "You already own it")
	end
	if not (ShopCatalog.IsForSale(set.Id) or (vip(data) and ShopCatalog.IsForSale(set.Id, ShopCatalog.ShopTime(true)))) then
		return reply(player, packet, false, "That set has left the shop")
	end
	local stage, mic = ShopCatalog.SetPieces(set)
	local first = not ownsRarity(data, set.Rarity)
	local ok = spend(player, data, set.Price, function()
		data.Inventory.Sets.Add(set.Id)
		-- a set unlocks its own stage + mic; wear both straight away
		if not data.Inventory.Stages.Has(stage.Id) then
			data.Inventory.Stages.Add(stage.Id)
		end
		if not data.Inventory.Mics.Has(mic.Id) then
			data.Inventory.Mics.Add(mic.Id)
		end
		data.Inventory.EquippedSet.Set(set.Id)
		data.Inventory.EquippedStage.Set(stage.Id)
		data.Inventory.EquippedMic.Set(mic.Id)
	end, "ShopSet", set.Rarity)
	if ok then
		logBought(player, data, "Set", set.Rarity, set.Id, first)
	end
	reply(player, packet, ok, if ok then `{set.Name} unlocked!` else "Not enough coins")
end

local function equipSet(player: Player, data, packet)
	local id = packet.Id
	if id ~= "Default" and not (type(id) == "string" and data.Inventory.Sets.Has(id)) then
		return reply(player, packet, false, "You don't own that set")
	end
	data.Inventory.EquippedSet.Set(id)
	if id == "Default" then
		data.Inventory.EquippedStage.Set("Default")
		data.Inventory.EquippedMic.Set("Default")
	else
		local stage, mic = ShopCatalog.SetPieces(ShopCatalog.GetSet(id))
		data.Inventory.EquippedStage.Set(stage.Id)
		data.Inventory.EquippedMic.Set(mic.Id)
	end
	Analytics.Event(player, "Equip", 1, "Set", id)
	reply(player, packet, true, "Equipped")
end

-- [[ Stages + mic stands ]]

local ITEM_PATHS = {
	Stage = { Owned = "Stages", Equipped = "EquippedStage" },
	Mic = { Owned = "Mics", Equipped = "EquippedMic" },
}

local function buyItem(player: Player, data, packet)
	local paths = ITEM_PATHS[packet.Kind]
	local item = paths and type(packet.Id) == "string" and ShopCatalog.GetItem(packet.Kind, packet.Id)
	if not item or item.Id == "Default" then
		return reply(player, packet, false, "That item doesn't exist")
	end
	if item.Set or not item.Price then
		return reply(player, packet, false, "That piece only comes with its set")
	end
	if data.Inventory[paths.Owned].Has(item.Id) then
		return reply(player, packet, false, "You already own it")
	end
	if not (ShopCatalog.ItemForSale(packet.Kind, item.Id) or (vip(data) and ShopCatalog.ItemForSale(packet.Kind, item.Id, ShopCatalog.ShopTime(true)))) then
		return reply(player, packet, false, "That item has left the shop")
	end
	local first = not ownsRarity(data, item.Rarity)
	local ok = spend(player, data, item.Price, function()
		data.Inventory[paths.Owned].Add(item.Id)
		data.Inventory[paths.Equipped].Set(item.Id)
	end, `Shop{packet.Kind}`, item.Rarity)
	if ok then
		logBought(player, data, packet.Kind, item.Rarity, item.Id, first)
	end
	reply(player, packet, ok, if ok then `{item.Name} unlocked!` else "Not enough coins")
end

local function equipItem(player: Player, data, packet)
	local paths = ITEM_PATHS[packet.Kind]
	local id = packet.Id
	if not paths or type(id) ~= "string" then
		return reply(player, packet, false, "That item doesn't exist")
	end
	if id ~= "Default" and not data.Inventory[paths.Owned].Has(id) then
		return reply(player, packet, false, "You don't own that")
	end
	data.Inventory[paths.Equipped].Set(id)
	Analytics.Event(player, "Equip", 1, packet.Kind, id)
	reply(player, packet, true, "Equipped")
end

local function equipTitle(player: Player, data, packet)
	local title = packet.Id
	if title ~= "" and not (type(title) == "string" and data.Inventory.Titles.Has(title)) then
		return reply(player, packet, false, "You haven't unlocked that title")
	end
	data.Inventory.Title.Set(title)
	Analytics.Event(player, "Equip", 1, "Title", if title == "" then "Default" else title)
	reply(player, packet, true, "Title equipped")
end

-- [[ Banners + photocards ]] (ShopCatalog.StyleRotation; the free three are everyone's)

local STYLE = {
	Banner = { Owned = "Banners", Worn = "Banner", Free = SeasonConstants.FREE_BANNERS },
	Photocard = { Owned = "Photocards", Worn = "Photocard", Free = SeasonConstants.FREE_PHOTOCARDS },
}

local function ownsStyle(data, kind: string, id: string): boolean
	local s = STYLE[kind]
	return s.Free[id] == true or data.Inventory[s.Owned].Has(id)
end

-- Set = both halves, or just the one you're missing (at that half's price)
local function buyStyle(player: Player, data, packet)
	local id, kind = packet.Id, packet.Kind
	local spec = type(id) == "string" and ShopCatalog.GetStyle(id)
	if not spec or not (kind == "Set" or STYLE[kind]) then
		return reply(player, packet, false, "That isn't in the shop")
	end
	if not (ShopCatalog.StyleForSale(id) or (vip(data) and ShopCatalog.StyleForSale(id, ShopCatalog.ShopTime(true)))) then
		return reply(player, packet, false, "That has left the shop")
	end
	local want = {}
	for _, half in { "Banner", "Photocard" } do
		if (kind == "Set" or kind == half) and not ownsStyle(data, half, id) then
			table.insert(want, half)
		end
	end
	if #want == 0 then
		return reply(player, packet, false, "You already own it")
	end
	local price = if #want == 2 then ShopCatalog.StylePrice(id, "Set") else ShopCatalog.StylePrice(id, want[1])
	local ok = spend(player, data, price :: number, function()
		for _, half in want do
			data.Inventory[STYLE[half].Owned].Add(id)
			data.Inventory[STYLE[half].Worn].Set(id) -- wear what you just bought
		end
	end, `ShopStyle{kind}`, if spec.Animated then "Animated" else "Regular")
	if ok then
		logBought(player, data, if kind == "Set" then "StyleSet" else kind, if spec.Animated then "Animated" else "Regular", id)
	end
	local what = if #want == 2 then "set" elseif want[1] == "Banner" then "banner" else "photocard"
	packet = table.clone(packet)
	packet.Charged = if ok then price else nil
	reply(player, packet, ok, if ok then `{spec.Name} {what} unlocked!` else "Not enough coins")
end

-- either or both; Studio owns everything while SeasonConstants.STUDIO_OWN_ALL is on
local function equipStyle(player: Player, data, packet)
	local studio = RunService:IsStudio() and SeasonConstants.STUDIO_OWN_ALL
	for _, kind in { "Banner", "Photocard" } do
		local id = packet[kind]
		if id ~= nil then
			if type(id) ~= "string" or not (studio or ownsStyle(data, kind, id)) then
				return reply(player, packet, false, "You don't own that")
			end
		end
	end
	for _, kind in { "Banner", "Photocard" } do
		local id = packet[kind]
		if id then
			data.Inventory[STYLE[kind].Worn].Set(id)
			Analytics.Event(player, "Equip", 1, kind, id)
		end
	end
	reply(player, packet, true, "Equipped")
end

local ACTIONS = {
	BuyStyle = buyStyle,
	EquipStyle = equipStyle,
	BuySet = buySet,
	EquipSet = equipSet,
	BuyItem = buyItem,
	EquipItem = equipItem,
	EquipTitle = equipTitle,
}

-- [[ Game passes ]]

local function grantPass(player: Player, passId: string)
	local data = PlayerData.Get(player)
	if data and not data.GamePasses.Has(passId) then
		data.GamePasses.Add(passId)
	end
end

local function checkPasses(player: Player)
	for _, pass in ShopCatalog.Passes do
		if (pass.GamePassId or 0) > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.GamePassId)
			if ok and owns then
				grantPass(player, pass.Id)
			end
		end
	end
end

-- [[ Lifecycle ]]

-- also used by the Cmdr testing commands (givesong / givepack)
ShopService.CheckPacksComplete = checkPacksComplete

-- [[ Robux analytics ]]
-- productId → { Key, Kind, Sku, Coins?, Tickets?, Upgrades? } for every Robux product
local robuxProducts: { [number]: any } = {}
for _, b in ShopCatalog.CoinBundles do
	robuxProducts[b.ProductId] = { Key = b.Id, Kind = "Coins", Sku = "CoinBundle", Coins = b.Amount }
end
for _, b in ShopCatalog.RollBundles do
	robuxProducts[b.ProductId] = { Key = b.Id, Kind = b.Currency, Sku = `{b.Currency}Bundle`, [b.Currency] = b.Amount }
end
if ShopCatalog.DebutPack then
	local d = ShopCatalog.DebutPack
	robuxProducts[d.ProductId] = { Key = d.Id, Kind = "Bundle", Sku = "DebutPack", Coins = d.Coins }
end
for _, b in ShopCatalog.Bundles do
	robuxProducts[b.ProductId] = { Key = b.Id, Kind = "Bundle", Sku = "Bundle", Coins = b.Coins, Tickets = b.Tickets, Upgrades = b.Upgrades }
end
if (DuelConstants.SAVE_STREAK_PRODUCT_ID or 0) > 0 then
	robuxProducts[DuelConstants.SAVE_STREAK_PRODUCT_ID] = { Key = "SaveStreak", Kind = "Streak", Sku = "SaveStreak" }
end
robuxProducts[0] = nil

-- a Robux prompt closed: the Robux funnel, RobuxPrompt, and (bought) the currencies it adds as
-- Economy sources. Balances are read a moment later, once Scribe has granted.
local function logRobuxPrompt(player: Player, key: string, kind: string, purchased: boolean, product)
	local session = Analytics.ShopSession(player)
	Analytics.Funnel(player, "Robux", session, "Prompted")
	Analytics.Event(player, "RobuxPrompt", 1, key, kind, if purchased then "Bought" else "Cancelled")
	if not purchased then
		return
	end
	Analytics.Funnel(player, "Robux", session, "Bought")
	if not product then
		return
	end
	task.delay(3, function()
		local ok, data = pcall(PlayerData.Get, player)
		if not ok or not data then
			return
		end
		for _, currency in { "Coins", "Tickets", "Upgrades" } do
			local amount = product[currency]
			if amount and amount > 0 then
				Analytics.Economy(player, "Source", currency, amount, Currencies.Data(data, currency).Get(), "RobuxBundle", product.Sku)
			end
		end
	end)
end

function ShopService.Start()
	ShopRemote:Connect(function(player: Player, packet)
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
			warn("[ShopService]", packet.Action, err)
			reply(player, packet, false, "Something went wrong")
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		for _, pass in ShopCatalog.Passes do
			if pass.GamePassId == gamePassId then
				logRobuxPrompt(player, pass.Id, "Pass", purchased, nil)
				if purchased then
					grantPass(player, pass.Id)
				end
			end
		end
	end)

	-- Robux products: analytics only. Granting is Scribe's receipt handling (PlayerData
	-- Products); this only hears that Roblox finished the prompt, so it can never get in the
	-- way of a purchase.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local player = Players:GetPlayerByUserId(userId)
		local product = robuxProducts[productId]
		if player and product then
			logRobuxPrompt(player, product.Key, product.Kind, purchased, product)
		end
	end)

	local function onJoin(player: Player)
		if PlayerData.WaitForData(player) then
			checkPasses(player)
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

return ShopService
