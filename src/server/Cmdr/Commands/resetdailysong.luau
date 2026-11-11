--| resetdailysong
-- Lets today's Daily Song be played again (keeps the streak). Reopen the screen after.

return {
	Name = "resetdailysong",
	Aliases = {},
	Description = "Lets today's Daily Song be played again (keeps the streak).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
