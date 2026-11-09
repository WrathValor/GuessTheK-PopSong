--| cycletitles
-- Equips each unlocked fandom title in turn (ARMY, BLINK, ONCE…), one every few seconds, for
-- recording the name tag. "<Group> Stan" and "<Company> Expert" titles are skipped. Run it again
-- to stop; the title you had before goes back on.

return {
	Name = "cycletitles",
	Aliases = {},
	Description = "Toggles cycling through your unlocked fandom titles (run again to stop).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" },
		{ Type = "number", Name = "seconds", Description = "Seconds per title (default 1)", Optional = true },
	},
}
