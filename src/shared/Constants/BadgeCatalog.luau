--| BadgeCatalog
-- The game's badges (Engine/Badges awards them). Make each one on the Creator Dashboard
-- (Experience → Engagement → Badges), then paste its id here: Id = 0 is skipped quietly, so a
-- badge goes live as soon as it has an id. Each is checked against the player's saved stats
-- (Badges.luau), so players who already did the thing get it the next time they join.
--   Key          used in code + analytics, never shown
--   Name / Blurb what to type on the Creator Dashboard
--   Id           the badge's asset id (0 = not made yet)

return table.freeze({
	{ Key = "Welcome", Name = "Debut", Blurb = "Joined Guess the K-Pop Song.", Id = 1535597703864158 },
	{ Key = "FirstWin", Name = "First Win", Blurb = "Won your first 1v1 duel.", Id = 1409403542596021 },
	{ Key = "Streak5", Name = "On Fire", Blurb = "Won 5 duels in a row.", Id = 926599218820009 },
	{ Key = "Streak10", Name = "Unstoppable", Blurb = "Won 10 duels in a row.", Id = 4495318588631128 },
	{ Key = "Perfect", Name = "Perfect Pitch", Blurb = "Won a duel 7–0, every answer by 2 seconds.", Id = 941060556765844 },
	{ Key = "Level10", Name = "Rising Star", Blurb = "Reached level 10.", Id = 3193683765226119 },
	{ Key = "FirstCard", Name = "First Card", Blurb = "Got your first song card.", Id = 3033124749386374 },
	{ Key = "Collector", Name = "Collector", Blurb = "Own 50 song cards.", Id = 3140539305652468 },
})
