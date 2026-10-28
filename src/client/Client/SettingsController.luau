--| SettingsController
-- Applies the saved settings on this client: Settings.MusicVolume, SfxVolume and ClipVolume
-- (0–1) drive the music, sound-effect and song-clip volumes. The Settings screen
-- (InterfaceController/Controllers/SettingsMenuController) changes them through
-- SettingsRemote (server: Engine/SettingsService); the client copy of PlayerData is read-only.
--
-- Preview(key, value) applies a volume straight away while a slider is dragged, before the
-- server has saved it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Sounds = require(ReplicatedStorage.Modules.Sounds)

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
