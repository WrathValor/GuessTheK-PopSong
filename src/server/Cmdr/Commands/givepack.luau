--| givepack
-- Gives every song in a pack (completing it), or every pack.

return {
	Name = "givepack",
	Aliases = {},
	Description = "Gives every song in a pack (completing it), or every pack.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "pack", Name = "pack", Description = "Pack key, or all" }
	},
}
