--| giveboost
-- Adds minutes to a boost potion clock (Coins, XP or Luck), like drinking one. 0 clears it.

return {
	Name = "giveboost",
	Aliases = {},
	Description = "Adds minutes to a boost potion clock (Coins / XP / Luck). 0 clears it.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "string", Name = "kind", Description = "Coins, XP or Luck" },
		{ Type = "integer", Name = "minutes", Description = "Minutes to add (0 clears)" },
	},
}
