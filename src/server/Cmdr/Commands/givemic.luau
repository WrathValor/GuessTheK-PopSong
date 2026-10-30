--| givemic
-- Gives a mic (or all of them).

return {
	Name = "givemic",
	Aliases = {},
	Description = "Gives a mic (or all of them).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "shopMic", Name = "mic", Description = "Mic id, or all" }
	},
}
