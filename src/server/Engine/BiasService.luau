--| BiasService
-- Your bias (design board "2 · Pick your bias"): a group with albums, then one of its members.
-- Picked at the end of the tutorial / on the K-POPPED! welcome, before the free first album
-- (Engine/AlbumService). Saved as Inventory.Bias ("<Artist>|<member key>", Modules/Library/Albums).
-- Their cards are AlbumConstants.BIAS_PULL_WEIGHT× as likely in their group's albums and earn
-- BIAS_EARN more in the binder. The first pick is free; after that it can change once every
-- BIAS_CHANGE_SECONDS. Shown on your nametag and profile through the "Bias" player attribute
-- (the same "<Artist>|<member key>" value; "" = none).
--
-- BiasRemote request: { Action = "Set", Group = artist, Member = member key }
-- Reply:              { Message = "Bias", Ok, Text?, Bias?, NextChange? (os.time) }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)
local Analytics = require(script.Parent.Analytics)
local BinderService = require(script.Parent.BinderService)

local BiasRemote = Bridgenet.ReferenceBridge("BiasRemote")

local BiasService = {}

-- does `artist` have a pullable album (one with card art) with member `key`?
local function exists(artist: string, key: string): boolean
	for _, album in Albums.PullAlbums(artist) do
		if Albums.Member(album, key) then
			return true
		end
	end
	return false
end

-- when this player can next change their bias (0 = now)
function BiasService.NextChange(data): number
	if data.Inventory.Bias.Get() == "" then
		return 0
	end
	return data.Inventory.BiasAt.Get() + AlbumConstants.BIAS_CHANGE_SECONDS
end

local function set(player: Player, group: any, member: any)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local function reply(ok: boolean, text: string?)
		BiasRemote:Fire(player, {
			Message = "Bias",
			Ok = ok,
			Text = text,
			Bias = data.Inventory.Bias.Get(),
			NextChange = BiasService.NextChange(data),
		})
	end
	if type(group) ~= "string" or type(member) ~= "string" or not exists(group, member) then
		return reply(false, "Pick a member from the list")
	end
	local value = Albums.BiasValue(group, member)
	local old = data.Inventory.Bias.Get()
	if value == old then
		return reply(true)
	end
	local now = os.time()
	if now < BiasService.NextChange(data) then
		return reply(false, "You can change your bias once a week")
	end
	PlayerData.Batch(player, function()
		BinderService.Bank(data, now) -- the old bias keeps what it already earned
		data.Inventory.Bias.Set(value)
		data.Inventory.BiasAt.Set(now)
	end)
	Analytics.Event(player, "BiasPicked", 1, group, if old == "" then "First" else "Change")
	reply(true)
end

local function onPlayerAdded(player: Player)
	local data = PlayerData.WaitForData(player)
	if not data or not player.Parent then
		return
	end
	data.Inventory.Bias.Observe(function(value: string)
		if player.Parent then
			player:SetAttribute("Bias", value)
		end
	end)
end

function BiasService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	BiasRemote:Connect(function(player: Player, packet)
		if type(packet) == "table" and packet.Action == "Set" then
			local ok, err = pcall(set, player, packet.Group, packet.Member)
			if not ok then
				warn(`[BiasService] set failed for {player.Name}: {err}`)
			end
		end
	end)
end

return BiasService
