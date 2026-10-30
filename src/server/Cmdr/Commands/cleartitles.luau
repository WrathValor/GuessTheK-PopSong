--| cleartitles
-- Removes every unlocked title (level titles return on the next XP change).

return {
	Name = "cleartitles",
	Aliases = {},
	Description = "Removes every unlocked title (level titles return on the next XP change).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
