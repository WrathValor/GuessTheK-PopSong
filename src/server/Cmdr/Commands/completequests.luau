--| completequests
-- Fills quest progress so every quest is ready to claim: today's daily quests, this week's
-- weekly quests, or both.

return {
	Name = "completequests",
	Aliases = {},
	Description = "Fills quest progress so every quest is ready to claim (daily, weekly or all; default daily).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "string", Name = "scope", Description = "daily | weekly | all (default daily)", Optional = true },
	},
}
