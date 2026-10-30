--| givetitle
-- Unlocks a title and equips it (quote titles with spaces).

return {
	Name = "givetitle",
	Aliases = {},
	Description = "Unlocks a title and equips it (quote titles with spaces).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "string", Name = "title", Description = "Title text" }
	},
}
