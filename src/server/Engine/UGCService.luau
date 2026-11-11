--| UGCService
-- The group's avatar items (Constants/UGCCatalog), sold for Robux in the shop's UGC tab.
-- Reads the group's catalog live (and again every UGCCatalog.REFRESH seconds), loads each
-- item so the client can preview it on the player's own avatar, and tells the client when
-- a purchase went through. Robux purchases are Roblox's own prompt: nothing to grant here.
--
-- Loaded previews: ReplicatedStorage.Assets.UGC.<assetId>  (an Animation for a dance, the
-- Accessory for an accessory)
-- UGCRemote requests: { Action = "Get" }                    -> { Message = "Catalog", Items }
-- To the player:      { Message = "Bought", Id = assetId }  (after a successful purchase)
-- Item: { Id, Name, Artist, Kind = "Dance" | "Accessory", Price, Song = songId? }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")
local InsertService = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local UGCCatalog = require(ReplicatedStorage.Constants.UGCCatalog)
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Analytics = require(script.Parent.Analytics)

local UGCRemote = Bridgenet.ReferenceBridge("UGCRemote")

local UGCService = {}
UGCService.Items = {} :: { any }

local byId: { [number]: any } = {}

local function folder(): Folder
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = ReplicatedStorage
	end
	local ugc = assets:FindFirstChild("UGC")
	if not ugc then
		ugc = Instance.new("Folder")
		ugc.Name = "UGC"
		ugc.Parent = assets
	end
	return ugc :: Folder
end

-- no [tags], no emoji, single spaces
local function clean(name: string): string
	name = name:gsub("%b[]", "")
	local out = {}
	for _, code in utf8.codes(name) do
		-- drop emoji + their joiners / variation selectors; keep accents and Korean
		if not (code >= 0x2600 or code == 0x200D or (code >= 0xFE00 and code <= 0xFE0F)) or (code >= 0xAC00 and code <= 0xD7AF) then
			table.insert(out, utf8.char(code))
		end
	end
	return (table.concat(out):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

local function skipped(name: string): boolean
	for _, pattern in UGCCatalog.SKIP do
		if name:match(pattern) then
			return true
		end
	end
	return false
end

local function describe(entry): any?
	local kind = UGCCatalog.KINDS[entry.AssetType or ""]
	if entry.ItemType ~= "Asset" or not kind or skipped(entry.Name) or not entry.Price or UGCCatalog.EXCLUDE[entry.Id] then
		return nil
	end
	local item = { Id = entry.Id, Kind = kind, Price = entry.Price }
	local songId = UGCCatalog.SONGS[entry.Id]
	local song = songId and Songs.GetById(songId)
	local named = UGCCatalog.NAMES[entry.Id]
	if song then
		item.Name, item.Artist, item.Song = song.Name, song.Artist, song.Id
	elseif named then
		item.Name, item.Artist = named[1], named[2]
	elseif kind == "Dance" then
		local title, artist = clean(entry.Name):match("^(.-)%s+%-%s+(.+)$")
		item.Name = title or clean(entry.Name)
		item.Artist = artist or "Dance"
	else
		item.Name = clean(entry.Name)
		item.Artist = UGCCatalog.ACCESSORY_SUB[entry.AssetType] or "Accessory"
	end
	return item
end

-- loads the preview (Animation / Accessory) into Assets.UGC, once per item per server
local function loadPreview(item)
	local into = folder()
	if into:FindFirstChild(tostring(item.Id)) then
		return
	end
	local ok, model = pcall(InsertService.LoadAsset, InsertService, item.Id)
	if not ok or not model then
		warn(`[UGCService] couldn't load {item.Id} ({item.Name}): {model}`)
		return
	end
	local found = if item.Kind == "Dance" then model:FindFirstChildWhichIsA("Animation", true) else model:FindFirstChildWhichIsA("Accessory", true)
	if found then
		found.Name = tostring(item.Id)
		found.Parent = into
	end
	model:Destroy()
end

local function search(): { any }?
	local params = CatalogSearchParams.new()
	params.CreatorName = UGCCatalog.CREATOR
	params.Limit = 120
	local ok, pages = pcall(AvatarEditorService.SearchCatalog, AvatarEditorService, params)
	if not ok then
		warn("[UGCService] catalog search failed:", pages)
		return nil
	end
	local list = {}
	while true do
		for _, entry in pages:GetCurrentPage() do
			table.insert(list, entry)
		end
		if pages.IsFinished then
			break
		end
		local more = pcall(pages.AdvanceToNextPageAsync, pages)
		if not more then
			break
		end
	end
	return list
end

function UGCService.Refresh()
	local entries = search()
	if not entries then
		return
	end
	local items = {}
	for _, entry in entries do
		local item = describe(entry)
		if item then
			table.insert(items, item)
		end
	end
	-- dances from songs in the game first, then other dances, then accessories (catalog order inside)
	local rank = function(item)
		return if item.Song then 1 elseif item.Kind == "Dance" then 2 else 3
	end
	for i, item in items do
		item._order = i
	end
	table.sort(items, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a._order < b._order
	end)
	byId = {}
	for _, item in items do
		item._order = nil
		byId[item.Id] = item
	end
	UGCService.Items = items
	UGCRemote:Fire(Bridgenet.AllPlayers(), { Message = "Catalog", Items = items })
	for _, item in items do
		task.spawn(loadPreview, item)
	end
end

function UGCService.Start()
	folder()
	UGCRemote:Connect(function(player: Player, packet)
		if type(packet) == "table" and packet.Action == "Get" then
			UGCRemote:Fire(player, { Message = "Catalog", Items = UGCService.Items })
		end
	end)
	MarketplaceService.PromptPurchaseFinished:Connect(function(player: Player, assetId: number, purchased: boolean)
		local item = byId[assetId]
		if not item or not purchased then
			return
		end
		Analytics.Event(player, "UGCBought", item.Price, item.Name, item.Kind)
		UGCRemote:Fire(player, { Message = "Bought", Id = assetId })
	end)
	task.spawn(function()
		while true do
			UGCService.Refresh()
			task.wait(UGCCatalog.REFRESH)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		if #UGCService.Items > 0 then
			UGCRemote:Fire(player, { Message = "Catalog", Items = UGCService.Items })
		end
	end)
end

return UGCService
