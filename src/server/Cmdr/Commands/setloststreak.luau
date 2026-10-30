--| setloststreak
-- Sets the streak Save Streak would restore (to test the offer).

return {
	Name = "setloststreak",
	Aliases = {},
	Description = "Sets the streak Save Streak would restore (to test the offer).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "streak", Description = "Lost streak" }
	},
}
