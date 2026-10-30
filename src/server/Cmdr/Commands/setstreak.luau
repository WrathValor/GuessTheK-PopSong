--| setstreak
-- Sets the win streak (and clears any streak to save).

return {
	Name = "setstreak",
	Aliases = {},
	Description = "Sets the win streak (and clears any streak to save).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "streak", Description = "Wins in a row" }
	},
}
