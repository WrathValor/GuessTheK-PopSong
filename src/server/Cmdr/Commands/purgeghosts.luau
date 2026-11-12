--| purgeghosts
-- Deletes a player's ghost recordings (Engine/GhostRecorder), e.g. for a data-deletion request.

return {
	Name = "purgeghosts",
	Aliases = {},
	Description = "Deletes a player's ghost recordings (by user id; they don't need to be online).",
	Group = "Testing",
	Args = {
		{ Type = "integer", Name = "userId", Description = "The player's user id" }
	},
}
