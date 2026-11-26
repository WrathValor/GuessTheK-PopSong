--| setcopies
-- Sets how many copies of a song (or every song) a player has pulled from the song roll, so
-- card levels can be tested: 1 Normal, 3 Gold, 5 Rainbow. 0 takes the song away.

return {
	Name = "setcopies",
	Aliases = {},
	Description = "Sets song roll copies of a song, or every song (1 Normal, 3 Gold, 5 Rainbow, 0 removes).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "song", Name = "song", Description = "Song key, or all" },
		{ Type = "integer", Name = "copies", Description = "0-20" },
	},
}
