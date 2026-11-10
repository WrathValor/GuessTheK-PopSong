--| SongClips
-- A song's audio on this client (client only). The song library on clients has no clip assets
-- (Modules/Library/Songs); the server (Engine/SongService) sends one song's clip at a time, and
-- only for a song you own, never mid-match. Rounds don't use this: their clip comes with the
-- round packet.
--   SongClips.Get(id) -> Promise<clip?>   { MusicId, PlaybackSpeed, Volume, TimePosition, … },
--       ready for GameController/Snippet.new(clip, "Song"); nil = not allowed / no answer
--   SongClips.All(withDrafts) -> Promise<{ { Label, File, Draft, Clip } }>   (admins, checkaudio)
-- Clips are cached for the session (a song's audio never changes mid-server).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Promise = require(ReplicatedStorage.Packages.promise)

local TIMEOUT = 6 -- seconds before a request gives up (resolves nil)
local ALL_TIMEOUT = 20

local SongClips = {}

local remote = nil
local cache: { [string]: any } = {}
local waiting: { [string]: { (any) -> () } } = {}
local waitingAll: { (any) -> () } = {}

local function answer(list: { (any) -> () }?, value)
	for _, resolve in list or {} do
		resolve(value)
	end
end

local function connect()
	if remote then
		return remote
	end
	remote = Bridgenet.ReferenceBridge("SongRemote")
	remote:Connect(function(packet)
		if type(packet) ~= "table" then
			return
		end
		if packet.Message == "Clip" and type(packet.Id) == "string" then
			if packet.Clip then
				cache[packet.Id] = packet.Clip
			end
			local list = waiting[packet.Id]
			waiting[packet.Id] = nil
			answer(list, packet.Clip)
		elseif packet.Message == "All" then
			local list = waitingAll
			waitingAll = {}
			answer(list, packet.Songs or {})
		end
	end)
	return remote
end

function SongClips.Get(id: string?)
	if type(id) ~= "string" or id == "" then
		return Promise.resolve(nil)
	end
	if cache[id] then
		return Promise.resolve(cache[id])
	end
	return Promise.new(function(resolve)
		local first = waiting[id] == nil
		waiting[id] = waiting[id] or {}
		table.insert(waiting[id], resolve)
		if first then
			connect():Fire({ Action = "Clip", Id = id })
		end
	end):timeout(TIMEOUT):catch(function()
		waiting[id] = nil
		return nil
	end)
end

function SongClips.All(withDrafts: boolean?)
	return Promise.new(function(resolve)
		table.insert(waitingAll, resolve)
		connect():Fire({ Action = "All", Drafts = withDrafts == true })
	end):timeout(ALL_TIMEOUT):catch(function()
		waitingAll = {}
		return {}
	end)
end

return SongClips
