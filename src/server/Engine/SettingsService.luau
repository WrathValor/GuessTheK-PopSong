--| SettingsService
-- Saves the Settings screen's changes. The client copy of PlayerData is read-only, so the
-- screen asks here and everything is checked before it's written.
--
-- SettingsRemote requests: { Action = "SetVolume", Key = "MusicVolume" | "SfxVolume" | "ClipVolume", Value = 0–1 }
--                          { Action = "SetInvites", Value = bool }
--                          { Action = "Reset" }                 (volumes back to 1, invites on)
--                          { Action = "SeenNews", Id = newsId } (clears the News button dot)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local News = require(ReplicatedStorage.Constants.News)

local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

local VOLUMES = { MusicVolume = true, SfxVolume = true, ClipVolume = true }
local MIN_GAP = 0.1 -- requests closer together than this are dropped (slider spam)

local SettingsService = {}

local last: { [Player]: number } = {}

local function handle(player: Player, packet)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local settings = data.Settings
	local action = packet.Action
	if action == "SetVolume" then
		local value = tonumber(packet.Value)
		if VOLUMES[packet.Key] and value and value == value then
			settings[packet.Key].Set(math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1))
		end
	elseif action == "SetInvites" then
		if type(packet.Value) == "boolean" then
			settings.DuelInvites.Set(packet.Value)
		end
	elseif action == "Reset" then
		PlayerData.Batch(player, function()
			for key in VOLUMES do
				settings[key].Set(1)
			end
			settings.DuelInvites.Set(true)
		end)
	elseif action == "SeenNews" then
		local newest = News.Entries[1]
		if newest and packet.Id == newest.Id then
			settings.NewsSeen.Set(newest.Id)
		end
	end
end

-- For a future duel-invite system: may `target` be sent an invite?
function SettingsService.AcceptsInvites(target: Player): boolean
	local data = PlayerData.Get(target)
	return data ~= nil and data.Settings.DuelInvites.Get() == true
end

function SettingsService.Start()
	SettingsRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" then
			return
		end
		local now = os.clock()
		if packet.Action ~= "SetVolume" or now - (last[player] or 0) >= MIN_GAP then
			last[player] = now
			local ok, err = pcall(handle, player, packet)
			if not ok then
				warn("[SettingsService]", packet.Action, err)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
end

return SettingsService
