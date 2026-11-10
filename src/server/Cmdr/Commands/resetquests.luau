--| resetquests
-- Zeroes quest progress and unclaims every quest and the bonus: today's daily quests (and
-- today's swap), this week's weekly quests, or both.

return {
	Name = "resetquests",
	Aliases = {},
	Description = "Zeroes quest progress and unclaims every quest and the bonus (daily, weekly or all; default daily). Daily also gives back today's swap.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "string", Name = "scope", Description = "daily | weekly | all (default daily)", Optional = true },
	},
}
