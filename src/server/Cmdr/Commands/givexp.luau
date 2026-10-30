--| givexp
-- Gives XP (level titles unlock as usual).

return {
	Name = "givexp",
	Aliases = {},
	Description = "Gives XP (level titles unlock as usual).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "XP" }
	},
}
