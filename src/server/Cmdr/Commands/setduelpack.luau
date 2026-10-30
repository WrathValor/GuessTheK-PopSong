--| setduelpack
-- Sets the duel pack (My, a pack key, or off). Doesn't check ownership.

return {
	Name = "setduelpack",
	Aliases = {},
	Description = "Sets the duel pack (My, a pack key, or off). Doesn't check ownership.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "duelPack", Name = "pack", Description = "Pack key, My, or off" }
	},
}
