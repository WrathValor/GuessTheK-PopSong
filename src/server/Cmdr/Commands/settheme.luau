--| settheme
-- Sets the solo theme the queue card opens on.

return {
	Name = "settheme",
	Aliases = {},
	Description = "Sets the solo theme the queue card opens on.",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "soloTheme", Name = "theme", Description = "Theme id" }
	},
}
