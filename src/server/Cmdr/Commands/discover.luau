--| discover
-- Adds a song (or every song) to the Index.

return {
	Name = "discover",
	Aliases = {},
	Description = "Adds a song (or every song) to the Index.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "song", Name = "song", Description = "Song key, or all" }
	},
}
