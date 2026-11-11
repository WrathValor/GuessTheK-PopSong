--| FavoritePrompt
-- The one-time "favourite this game?" prompt (Roblox's own favourite dialog). ResultsController
-- calls Try() when the results screen closes after a real duel (not solo practice or the
-- tutorial, and not when they pressed Rematch). It shows once per player, ever: the server
-- saves Settings.FavoritePrompted (SettingsService "FavoritePrompted"). Players who have
-- already favourited the game are marked done without being asked. In Studio it asks after
-- every duel and saves nothing, for testing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")
local RunService = game:GetService("RunService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client

local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

local DELAY = 1.5 -- seconds after the results screen closes, so the lobby is back first

local FavoritePrompt = {}

local asked = false -- this session (the saved flag can take a moment to come back)

local function alreadyPrompted(): boolean
	local ok, v = pcall(PlayerData.Settings.FavoritePrompted.Get)
	return not ok or v == true -- data not ready: don't ask
end

function FavoritePrompt.Try()
	-- Studio: ask after every duel and save nothing, so it can be tested again and again
	local studio = RunService:IsStudio()
	if not studio and (asked or alreadyPrompted()) then
		return
	end
	asked = true
	task.delay(DELAY, function()
		if not studio then
			SettingsRemote:Fire({ Action = "FavoritePrompted" })
		end
		local okFav, favourited = pcall(AvatarEditorService.GetFavoriteAsync, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset)
		if okFav and favourited then
			return
		end
		pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
end

return FavoritePrompt
