--| resetstarter
-- Makes a player new to the starter offer again: no Debut Pack, no offer clock, the card not
-- seen. Tells you what was there first. Rejoin after (the card shows once a session).

return {
	Name = "resetstarter",
	Aliases = {},
	Description = "Shows the starter offer again (takes away the Debut Pack claim).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
