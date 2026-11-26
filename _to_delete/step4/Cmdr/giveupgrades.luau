--| giveupgrades
-- Gives (or takes, if negative) card upgrades.

return {
	Name = "giveupgrades",
	Aliases = {},
	Description = "Gives (or takes, if negative) card upgrades.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "Upgrades (negative removes)" }
	},
}
