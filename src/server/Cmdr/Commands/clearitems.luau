--| clearitems
-- Removes every set, stage and mic and puts the defaults back on.

return {
	Name = "clearitems",
	Aliases = {},
	Description = "Removes every set, stage and mic and puts the defaults back on.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
