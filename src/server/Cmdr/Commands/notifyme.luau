--| notifyme
-- Sends you the daily login's streak reminder now (an experience notification), to check it
-- arrives. Live game only, needs the Open Cloud package; Roblox's one-a-day limit still applies.

return {
	Name = "notifyme",
	Aliases = {},
	Description = "Sends you the streak reminder notification now (Streak, BigDay or DayTwo). Live game only.",
	Group = "Testing",
	Args = {
		{ Type = "string", Name = "kind", Description = "Streak, BigDay or DayTwo", Optional = true }
	},
}
