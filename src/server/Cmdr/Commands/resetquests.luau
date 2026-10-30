--| resetquests
-- Zeroes today's quest progress and unclaims every quest and the bonus.

return {
	Name = "resetquests",
	Aliases = {},
	Description = "Zeroes today's quest progress and unclaims every quest and the bonus.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
