--| setdailystreak
-- Sets how many days in a row have been claimed (0-7).

return {
	Name = "setdailystreak",
	Aliases = {},
	Description = "Sets how many days in a row have been claimed (0-7).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "days", Description = "Days" }
	},
}
