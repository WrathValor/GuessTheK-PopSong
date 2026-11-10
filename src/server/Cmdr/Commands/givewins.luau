--| givewins
-- Gives (or takes, if negative) season wins (the Ranks tab's Season Wins board follows).

return {
	Name = "givewins",
	Aliases = {},
	Description = "Gives (or takes, if negative) season wins. The Season Wins board follows.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "Wins (negative removes)" }
	},
}
