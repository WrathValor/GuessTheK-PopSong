--| giveevent
-- Gives (or takes, if negative) the live event's currency (Snowflakes) and unopened event packs.

return {
	Name = "giveevent",
	Aliases = {},
	Description = "Gives (or takes) the live event's currency and its packs (Snowflakes, Winter packs).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "integer", Name = "currency", Description = "Event currency (negative removes)" },
		{ Type = "integer", Name = "packs", Description = "Event packs (negative removes)", Optional = true },
	},
}
