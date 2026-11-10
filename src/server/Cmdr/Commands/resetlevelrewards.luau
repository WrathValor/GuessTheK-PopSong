--| resetlevelrewards
-- Unclaims every level reward, so the Rewards screen offers them again (titles stay owned).

return {
	Name = "resetlevelrewards",
	Aliases = {},
	Description = "Unclaims every level reward so they can be claimed again (titles stay owned).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
	},
}
