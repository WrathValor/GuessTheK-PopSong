--| resetgroupreward
-- Makes the group reward claimable again (removes Supporter).

return {
	Name = "resetgroupreward",
	Aliases = {},
	Description = "Makes the group reward claimable again (removes Supporter).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
