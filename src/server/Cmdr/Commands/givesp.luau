--| givesp
-- Gives (or takes, if negative) Season Points, as if duels had moved them: peak SP and the
-- Ranks board update too.

return {
	Name = "givesp",
	Aliases = {},
	Description = "Gives (or takes, if negative) Season Points. Peak SP and the Ranks board follow.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "SP (negative removes)" }
	},
}
