--| givestars
-- Gives (or takes, if negative) Season Track Stars. Skips the daily limits.

return {
	Name = "givestars",
	Aliases = {},
	Description = "Gives (or takes, if negative) Season Track Stars. Skips the daily limits.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "Stars (negative removes)" }
	},
}
