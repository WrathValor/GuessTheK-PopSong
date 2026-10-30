--| givestage
-- Gives a stage (or all of them).

return {
	Name = "givestage",
	Aliases = {},
	Description = "Gives a stage (or all of them).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "shopStage", Name = "stage", Description = "Stage id, or all" }
	},
}
