--| setlevel
-- Sets XP to the start of a level (1-100).

return {
	Name = "setlevel",
	Aliases = {},
	Description = "Sets XP to the start of a level (1-100).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "level", Description = "Level" }
	},
}
