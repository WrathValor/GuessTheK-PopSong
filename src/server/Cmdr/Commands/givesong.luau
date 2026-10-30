--| givesong
-- Gives a bought song (My Pack), or every song.

return {
	Name = "givesong",
	Aliases = {},
	Description = "Gives a bought song (My Pack), or every song.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "song", Name = "song", Description = "Song key, or all" }
	},
}
