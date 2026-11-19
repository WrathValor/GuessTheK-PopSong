--| setdailystreak
-- Sets how many days in a row have been claimed (0-14: 8-14 is the second week of the daily login).

return {
	Name = "setdailystreak",
	Aliases = {},
	Description = "Sets how many days in a row have been claimed (0-14: 8-14 is the second week of the daily login).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "days", Description = "Days" }
	},
}
