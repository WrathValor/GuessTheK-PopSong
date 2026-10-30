--| setcoins
-- Sets coins to an exact amount.

return {
	Name = "setcoins",
	Aliases = {},
	Description = "Sets coins to an exact amount.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "Coins" }
	},
}
