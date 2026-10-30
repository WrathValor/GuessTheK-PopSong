--| givepass
-- Gives a game pass's perks without buying it.

return {
	Name = "givepass",
	Aliases = {},
	Description = "Gives a game pass's perks without buying it.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "shopPass", Name = "pass", Description = "Pass id" }
	},
}
