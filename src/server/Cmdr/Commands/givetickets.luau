--| givetickets
-- Gives (or takes, if negative) roll tickets.

return {
	Name = "givetickets",
	Aliases = {},
	Description = "Gives (or takes, if negative) roll tickets.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "Tickets (negative removes)" }
	},
}
