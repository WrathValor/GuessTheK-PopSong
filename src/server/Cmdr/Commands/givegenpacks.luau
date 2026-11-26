--| givegenpacks
-- Gives (or takes, if negative) gen packs: the Robux ones that open a whole gen pack each.

return {
	Name = "givegenpacks",
	Aliases = {},
	Description = "Gives (or takes, if negative) gen packs (each opens a 5-card gen pack).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "amount", Description = "Gen packs (negative removes)" }
	},
}
