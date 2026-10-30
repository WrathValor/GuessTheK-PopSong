--| giveset
-- Gives a set (and its stage + mic), or all sets.

return {
	Name = "giveset",
	Aliases = {},
	Description = "Gives a set (and its stage + mic), or all sets.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "shopSet", Name = "set", Description = "Set id, or all" }
	},
}
