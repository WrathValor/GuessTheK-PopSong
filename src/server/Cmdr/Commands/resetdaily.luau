--| resetdaily
-- Makes the daily reward claimable again (keeps the day streak).

return {
	Name = "resetdaily",
	Aliases = {},
	Description = "Makes the daily reward claimable again (keeps the day streak).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
