--| givecoins
-- Gives (or takes, if negative) coins.

return {
	Name = "givecoins",
	Aliases = {},
	Description = "Gives (or takes, if negative) coins.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "Coins (negative removes)" }
	},
}
