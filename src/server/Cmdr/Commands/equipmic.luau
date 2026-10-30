--| equipmic
-- Equips a mic, giving it first (resetmic puts the Default back).

return {
	Name = "equipmic",
	Aliases = {},
	Description = "Equips a mic, giving it first (resetmic puts the Default back).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "shopMic", Name = "mic", Description = "Mic id" }
	},
}
