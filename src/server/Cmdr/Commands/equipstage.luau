--| equipstage
-- Equips a stage, giving it first (resetstage puts the Default back).

return {
	Name = "equipstage",
	Aliases = {},
	Description = "Equips a stage, giving it first (resetstage puts the Default back).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "shopStage", Name = "stage", Description = "Stage id" }
	},
}
