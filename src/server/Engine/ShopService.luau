--| ShopService
-- Server side of the shop. Every coin purchase is checked here (price, balance, rotation,
-- ownership) before anything changes; the client only asks. Robux coin bundles are granted
-- by Scribe's receipt handling (see PlayerData Products); game passes are checked on join
-- and after a purchase prompt.
--
-- ShopRemote requests: { Action = "BuySet" | "EquipSet", Id = setId }
--                      { Action = "BuyItem" | "EquipItem", Kind = "Stage" | "Mic", Id = itemId }
--                      { Action = "EquipTitle", Id = title ("" = default) }
--                      { Action = "BuySong", Id = songId }
--                      { Action = "BuyPack", Id = packId ("Company:HYBE" / "Group:BTS") }
--                      { Action = "SetDuelPack", Id = packId ("" = off) }
-- Reply to the player:  { Message = "Result", Ok = bool, Text = string, Action, Id }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Packs = require(ReplicatedStorage.Modules.Library.Packs)

local ShopRemote = Bridgenet.ReferenceBridge("ShopRemote")

local ShopService = {}

-- [[ Song packs (company + group, see Modules/Library/Packs) ]]

-- After buying songs: mark every pack they belong to complete (and give its title) once all
-- its songs are owned.
local function checkPacksComplete(data, songs: { any })
	local seen = {}
	for _, song in songs do
		for _, pack in Packs.ForSong(song) do
			if not seen[pack.Id] then
				seen[pack.Id] = true
				local complete = #pack.Songs > 0
				for _, s in pack.Songs do
					if not data.Inventory.Songs.Has(s.Id) then
						complete = false
						break
					end
				end
				if complete then
					if not data.Inventory.Packs.Has(pack.Id) then
						data.Inventory.Packs.Add(pack.Id)
					end
					if pack.Title and not data.Inventory.Titles.Has(pack.Title) then
						data.Inventory.Titles.Add(pack.Title)
					end
				end
			end
		end
	end
end

-- [[ Helpers ]]

local busy: { [Player]: boolean } = {}

local function reply(player: Player, packet, ok: boolean, text: string)
	ShopRemote:Fire(player, {
		Message = "Result",
		Ok = ok,
		Text = text,
		Action = packet.Action,
		Id = packet.Id,
	})
end

-- Takes `price` coins and runs `grant` in one batch. False (and nothing changes) if they can't afford it.
local function spend(player: Player, data, price: number, grant: () -> ()): boolean
	if data.Currencies.Won.Get() < price then
		return false
	end
	PlayerData.Batch(player, function()
		data.Currencies.Won.Increment(-price)
		grant()
	end)
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
	if not ShopCatalog.IsForSale(set.Id) then
		return reply(player, packet, false, "That set has left the shop")
	end
	local stage, mic = ShopCatalog.SetPieces(set)
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
	end)
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
	if not ShopCatalog.ItemForSale(packet.Kind, item.Id) then
		return reply(player, packet, false, "That item has left the shop")
	end
	local ok = spend(player, data, item.Price, function()
		data.Inventory[paths.Owned].Add(item.Id)
		data.Inventory[paths.Equipped].Set(item.Id)
	end)
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
	reply(player, packet, true, "Equipped")
end

local function equipTitle(player: Player, data, packet)
	local title = packet.Id
	if title ~= "" and not (type(title) == "string" and data.Inventory.Titles.Has(title)) then
		return reply(player, packet, false, "You haven't unlocked that title")
	end
	data.Inventory.Title.Set(title)
	reply(player, packet, true, "Title equipped")
end

local function buySong(player: Player, data, packet)
	local song = type(packet.Id) == "string" and Songs.GetById(packet.Id)
	if not song then
		return reply(player, packet, false, "That song doesn't exist")
	end
	if data.Inventory.Songs.Has(song.Id) then
		return reply(player, packet, false, "You already own it")
	end
	if not Packs.SongForSale(song) then
		return reply(player, packet, false, "That pack has left the shop")
	end
	local ok = spend(player, data, ShopCatalog.SONG_PRICE, function()
		data.Inventory.Songs.Add(song.Id)
		checkPacksComplete(data, { song })
	end)
	reply(player, packet, ok, if ok then `{song.Name} added to My Pack` else "Not enough coins")
end

local function buyPack(player: Player, data, packet)
	local pack = type(packet.Id) == "string" and Packs.Get(packet.Id)
	if not pack or pack.Kind == "My" or #pack.Songs == 0 then
		return reply(player, packet, false, "That pack doesn't exist")
	end
	if not Packs.IsForSale(pack.Id) then
		return reply(player, packet, false, "That pack has left the shop")
	end
	local missing = {}
	for _, song in pack.Songs do
		if not data.Inventory.Songs.Has(song.Id) then
			table.insert(missing, song)
		end
	end
	if #missing == 0 then
		return reply(player, packet, false, "You own every song in it")
	end
	local price = ShopCatalog.PackPrice(#missing)
	local ok = spend(player, data, price, function()
		for _, song in missing do
			data.Inventory.Songs.Add(song.Id)
		end
		checkPacksComplete(data, missing)
	end)
	reply(player, packet, ok, if ok then `{Packs.DisplayName(pack.Id)} complete!` else "Not enough coins")
end

-- The pack mixed into duels. Any pack you own at least one song of.
local function setDuelPack(player: Player, data, packet)
	local id = packet.Id
	if id == "" then
		data.Inventory.DuelPack.Set("")
		return reply(player, packet, true, "Duel pack off")
	end
	if type(id) ~= "string" or not Packs.Get(id) then
		return reply(player, packet, false, "That pack doesn't exist")
	end
	local owned = Packs.SongsFor(id, function(songId)
		return data.Inventory.Songs.Has(songId)
	end)
	if #owned == 0 then
		return reply(player, packet, false, "Buy a song from it first")
	end
	data.Inventory.DuelPack.Set(Packs.Get(id).Id)
	reply(player, packet, true, `{Packs.DisplayName(id)} will mix into duels`)
end

local ACTIONS = {
	BuySet = buySet,
	EquipSet = equipSet,
	BuyItem = buyItem,
	EquipItem = equipItem,
	SetDuelPack = setDuelPack,
	EquipTitle = equipTitle,
	BuySong = buySong,
	BuyPack = buyPack,
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
		if not purchased then
			return
		end
		for _, pass in ShopCatalog.Passes do
			if pass.GamePassId == gamePassId then
				grantPass(player, pass.Id)
			end
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
