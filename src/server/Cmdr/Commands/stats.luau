--| stats
-- Shows a player's saved progress.

return {
	Name = "stats",
	Aliases = {},
	Description = "Shows a player's saved progress.",
	Group = "Testing",
	Args = {
		{ Type = "player", Name = "player", Description = "Who" }
	},
}
