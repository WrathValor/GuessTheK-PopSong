--| restartsim
-- Shows the server restart notice (lobby banner → in-duel pill → hand-over card) as if a
-- restart were scheduled in `seconds`, without closing the server. 0 clears it.

return {
	Name = "restartsim",
	Aliases = {},
	Description = "Pretends a server restart is coming in N seconds (0 clears). Kind Update or Maintenance; optional title / message.",
	Group = "Testing",
	Args = {
		{ Type = "number", Name = "seconds", Description = "Seconds until the restart (0 clears it)" },
		{ Type = "string", Name = "kind", Description = "Update or Maintenance", Optional = true },
		{ Type = "string", Name = "title", Description = "Banner title (like the restart's \"title\" attribute)", Optional = true },
		{ Type = "string", Name = "message", Description = "Banner line (like the restart's \"message\" attribute)", Optional = true },
	},
}
