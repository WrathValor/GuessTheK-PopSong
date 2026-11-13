--| resethints
-- Clears the one-time hints a player has seen (lobby nudges + first-open screen guides), so
-- they show again. Reopen the screen after.

return {
	Name = "resethints",
	Aliases = {},
	Description = "Shows the lobby nudges and screen guides again.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
