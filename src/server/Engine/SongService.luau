--| SongService
-- Hands a song's audio (its clip assets: Songs.Clip) to a client that's allowed to hear it.
-- The library itself is server only (ServerScriptService.Songs), so this is the one way a
-- client gets a MusicId outside a round:
--   • the song has to be one they own (Inventory.Songs): Index previews, the roll reveal (the
--     pull is theirs before the reveal), their Rainbow card as background music
--   • never while they're in a match (the InDuel attribute, Duels:_setInDuel), so an owned
--     song coming up in a round can't be looked up then
-- Admins (CmdrService.IsAllowed) can ask for every song's clip, drafts too, for checkaudio.
--
-- SongRemote requests: { Action = "Clip", Id = songId }
--                      { Action = "All", Drafts = bool }            (admins: checkaudio)
-- Replies:             { Message = "Clip", Id, Clip? }               (no Clip = not allowed)
--                      { Message = "All", Songs = { { Label, File, Draft, Clip } } }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Library = require(ServerScriptService:WaitForChild("Songs"))
local CmdrService = require(script.Parent.CmdrService)

local SongRemote = Bridgenet.ReferenceBridge("SongRemote")

local MIN_GAP = 0.1 -- clip requests closer together than this are dropped

local SongService = {}

local last: { [Player]: number } = {}

-- [[ Private ]]

local function clipFor(player: Player, id: string)
	if player:GetAttribute("InDuel") then
		return nil
	end
	local song = Songs.GetById(id)
	if not song then
		return nil
	end
	-- (Get throws while the player's data is still loading: that's a no for now)
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data or not data.Inventory.Songs.Has(id) then
		return nil
	end
	return Songs.Clip(song)
end

-- [[ Public ]]

function SongService.Start()
	SongRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" then
			return
		end
		local now = os.clock()
		local tooSoon = now - (last[player] or 0) < MIN_GAP
		last[player] = now

		if packet.Action == "Clip" and type(packet.Id) == "string" and #packet.Id <= 80 then
			-- (too soon still gets an answer, just no clip, so the client never waits on one)
			local clip = if tooSoon then nil else clipFor(player, packet.Id)
			SongRemote:Fire(player, { Message = "Clip", Id = packet.Id, Clip = clip })
		elseif packet.Action == "All" and not tooSoon and CmdrService.IsAllowed(player) then
			SongRemote:Fire(player, { Message = "All", Songs = Library.Raw(packet.Drafts == true) })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
end

return SongService
