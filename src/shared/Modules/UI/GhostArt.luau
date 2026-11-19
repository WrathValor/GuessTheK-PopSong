--| GhostArt
-- The ghost rival on screen (DuelService/Duels.GhostProfile). Its id (DuelConstants.GHOST_USER_ID)
-- never belongs to a real player, so wherever a rival's headshot loads it gets the ghost art
-- instead (assets/ui/GhostRival.png). It's always anonymous: no name, no avatar of the player
-- whose game it replays.
--   GhostArt.Is(userId) -> boolean
--   GhostArt.Thumbnail(userId, thumbType?, size?) -> string   -- yields for a real player ("" on failure)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)

local GhostArt = {}

GhostArt.IMAGE = "rbxassetid://96403288406111"

function GhostArt.Is(userId: any): boolean
	return tonumber(userId) == DuelConstants.GHOST_USER_ID
end

function GhostArt.Thumbnail(userId: number, thumbType: Enum.ThumbnailType?, size: Enum.ThumbnailSize?): string
	if GhostArt.Is(userId) then
		return GhostArt.IMAGE
	end
	local ok, img = pcall(Players.GetUserThumbnailAsync, Players, userId, thumbType or Enum.ThumbnailType.HeadShot, size or Enum.ThumbnailSize.Size150x150)
	return if ok and img then img else ""
end

return GhostArt
