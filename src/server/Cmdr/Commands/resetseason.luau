--| resetseason
-- Starts the Season Track over: Stars, milestones claimed, the season's duels / wins and
-- today's Star limits back to 0. Tickets, upgrades and anything already claimed stay.

return {
	Name = "resetseason",
	Aliases = {},
	Description = "Starts the Season Track over (Stars, claims, season duels / wins, daily limits). Rewards already claimed stay.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
