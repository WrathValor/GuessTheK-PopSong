--| removepass
-- Takes a game pass's perks away again.

return {
	Name = "removepass",
	Aliases = {},
	Description = "Takes a game pass's perks away again.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "shopPass", Name = "pass", Description = "Pass id" }
	},
}
