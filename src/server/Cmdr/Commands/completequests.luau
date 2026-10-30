--| completequests
-- Fills today's quest progress so every quest is ready to claim.

return {
	Name = "completequests",
	Aliases = {},
	Description = "Fills today's quest progress so every quest is ready to claim.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
