--| giveboost
-- Adds minutes to a boost potion clock (Coins or XP), like drinking one. 0 clears it.

return {
	Name = "giveboost",
	Aliases = {},
	Description = "Adds minutes to a boost potion clock (Coins / XP). 0 clears it.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "string", Name = "kind", Description = "Coins or XP" },
		{ Type = "integer", Name = "minutes", Description = "Minutes to add (0 clears)" },
	},
}
