--| UGC
-- Client side of the group's avatar items (Engine/UGCService, Constants/UGCCatalog): the item
-- list, who owns what, buying (Roblox's own Robux prompt) and playing a dance you own.
--   UGC.Items                       – list from the server (dances from game songs first)
--   UGC.Get(id) / UGC.ForSong(songId)
--   UGC.Owned(id) -> true | false | nil (nil = not checked yet; checks in the background)
--   UGC.Buy(id, where)              – where: "Shop" | "Reveal" | "Results" (analytics)
--   UGC.Dance(id)                   – plays an owned dance on your character
--   UGC.Changed                     – Signal: the list or an ownership answer changed

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ContentProvider = game:GetService("ContentProvider")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Signal = require(ReplicatedStorage.Packages.signal)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)

local UGCRemote = Bridgenet.ReferenceBridge("UGCRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local UGC = {}
UGC.Items = {} :: { any }
UGC.Changed = Signal.new()

local byId: { [number]: any } = {}
local bySong: { [string]: any } = {}
local owned: { [number]: boolean } = {}
local checking: { [number]: boolean } = {}

function UGC.Get(id: number?)
	return id and byId[id]
end

function UGC.ForSong(songId: string?)
	return songId and bySong[songId]
end

function UGC.Owned(id: number): boolean?
	if owned[id] ~= nil then
		return owned[id]
	end
	if not checking[id] then
		checking[id] = true
		task.spawn(function()
			local ok, has = pcall(MarketplaceService.PlayerOwnsAsset, MarketplaceService, LOCAL_PLAYER, id)
			checking[id] = nil
			owned[id] = ok and has == true
			UGC.Changed:Fire()
		end)
	end
	return nil
end

function UGC.Buy(id: number, where: string)
	local item = byId[id]
	if not item or owned[id] then
		return
	end
	AnalyticsClient.Event("UGCPrompt", item.Price, item.Name, where)
	MarketplaceService:PromptPurchase(LOCAL_PLAYER, id)
end

-- [[ Dancing ]]

local playing: AnimationTrack? = nil
local stopConn: RBXScriptConnection? = nil

local function stopDance()
	if stopConn then
		stopConn:Disconnect()
		stopConn = nil
	end
	if playing then
		playing:Stop(0.2)
		playing = nil
	end
end

function UGC.Dance(id: number)
	local folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UGC")
	local animation = folder and folder:FindFirstChild(tostring(id))
	local character = LOCAL_PLAYER.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (animation and animation:IsA("Animation") and animator) then
		return
	end
	stopDance()
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok or not track then
		warn("[UGC] couldn't play dance", id, track)
		return
	end
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.2)
	playing = track
	-- walking or jumping ends it, like Roblox's own emotes
	stopConn = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		if humanoid.MoveDirection.Magnitude > 0.1 then
			stopDance()
		end
	end)
end

-- [[ Preloading ]]
-- Every item's dance / accessory (meshes, textures, animation keyframes) downloads in the
-- background as soon as the server has loaded it, so previews and dances start instantly.

local preloaded: { [Instance]: boolean } = {}
local function preload(asset: Instance)
	if preloaded[asset] then
		return
	end
	preloaded[asset] = true
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { asset })
	end)
end
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("Assets", 30)
	local folder = assets and assets:WaitForChild("UGC", 30)
	if not folder then
		return
	end
	for _, asset in folder:GetChildren() do
		preload(asset)
	end
	-- a preview that was waiting for its model can draw now (one redraw per burst)
	local pending = false
	folder.ChildAdded:Connect(function(asset)
		preload(asset)
		if not pending then
			pending = true
			task.delay(0.3, function()
				pending = false
				UGC.Changed:Fire()
			end)
		end
	end)
end)

-- [[ Server ]]

UGCRemote:Connect(function(packet)
	if type(packet) ~= "table" then
		return
	end
	if packet.Message == "Catalog" and type(packet.Items) == "table" then
		UGC.Items = packet.Items
		byId, bySong = {}, {}
		for _, item in packet.Items do
			byId[item.Id] = item
			if item.Song then
				bySong[item.Song] = item
			end
		end
		UGC.Changed:Fire()
	elseif packet.Message == "Bought" and type(packet.Id) == "number" then
		owned[packet.Id] = true
		UGC.Changed:Fire()
	end
end)
UGCRemote:Fire({ Action = "Get" })

return UGC
