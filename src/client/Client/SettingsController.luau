--| SettingsController
-- Applies the saved settings on this client: Settings.MusicVolume, SfxVolume and ClipVolume
-- (0–1) drive the music, sound-effect and song-clip volumes. The Settings screen
-- (InterfaceController/Controllers/SettingsMenuController) changes them through
-- SettingsRemote (server: Engine/SettingsService); the client copy of PlayerData is read-only.
--
-- Preview(key, value) applies a volume straight away while a slider is dragged, before the
-- server has saved it.
--
-- Also sends your Roblox block list to the server (SettingsRemote "Blocked") at join and
-- whenever you block / unblock someone, so blocked players can't invite you (duels, parties).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Sounds = require(ReplicatedStorage.Modules.Sounds)

local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")
local BLOCK_TRIES = 30 -- the core scripts can take a while to answer GetCore at join

-- true once the block list was read (and sent)
local function sendBlocked(): boolean
	local ok, ids = pcall(StarterGui.GetCore, StarterGui, "GetBlockedUserIds")
	if ok and type(ids) == "table" then
		SettingsRemote:Fire({ Action = "Blocked", Ids = ids })
		return true
	end
	return false
end

local SettingsController = {}

function SettingsController.Start()
	PlayerData.Settings.SfxVolume.Observe(function(volume: number)
		Sounds.SetVolume(volume)
	end)
	PlayerData.Settings.MusicVolume.Observe(function(volume: number)
		Sounds.SetMusicVolume(volume)
	end)
	PlayerData.Settings.ClipVolume.Observe(function(volume: number)
		Sounds.SetClipVolume(volume)
	end)
	task.spawn(function()
		for _ = 1, BLOCK_TRIES do
			if sendBlocked() then
				break
			end
			task.wait(2)
		end
		for _, name in { "PlayerBlockedEvent", "PlayerUnblockedEvent" } do
			local ok, event = pcall(StarterGui.GetCore, StarterGui, name)
			if ok and typeof(event) == "Instance" and event:IsA("BindableEvent") then
				event.Event:Connect(sendBlocked)
			end
		end
	end)
end

local APPLY = {
	MusicVolume = function(v)
		Sounds.SetMusicVolume(v)
	end,
	SfxVolume = function(v)
		Sounds.SetVolume(v)
	end,
	ClipVolume = function(v)
		Sounds.SetClipVolume(v)
	end,
}

function SettingsController.Preview(key: string, value: number)
	local apply = APPLY[key]
	if apply then
		apply(value)
	end
end

return SettingsController
