--| News
-- The update log shown on the News screen. Newest first: Entries[1] is the big card, the
-- rest are listed under "Earlier" (3 per page). Adding an entry at the top lights the red
-- dot on the HUD's News button until each player opens it (Settings.NewsSeen).
--
-- Each entry:
--   Id       unique, never reused ("2026-10-28" works)          required
--   Title    "Duel packs are here!"                              required
--   Body     a few sentences                                     required
--   Date     "28 Oct 2026"                                       required
--   Version  "v1.2" (big card chip)                              optional
--   Tag      "NEW" | "SHOP" | "FIX" | "EVENT" (Earlier list chip) optional, default "NEW"
--   Tags     { "Duel packs", "Items tab" } (big card chips)      optional
--   Colour   hex for the art / icon box                          optional
--   Glyph    one character for the Earlier list icon             optional
--   Image    rbxassetid for the big card art (else photocards)   optional
-- The entries below are placeholders: rewrite them before release.

return table.freeze({
	TAG_COLOURS = table.freeze({ NEW = "FFE07A", SHOP = "A7E9B8", FIX = "9ED8F5", EVENT = "FF9EC4" }),

	Entries = table.freeze({
		{
			Id = "2026-10-28",
			Version = "v1.2",
			Date = "28 Oct 2026",
			Title = "Duel packs are here!",
			Body = "Pick one of your song packs in Inventory and it mixes into duels when your rival has one on too. Plus: stages and mic stands sold on their own, group packs, and a smoother stake roll.",
			Tags = { "Duel packs", "Items tab", "Group packs" },
			Tag = "NEW",
			Colour = "B9A6FF",
			Glyph = "♪",
		},
		{
			Id = "2026-10-24",
			Date = "24 Oct",
			Title = "Background music",
			Body = "A lobby playlist that pauses during rounds and picks up where it left off.",
			Tag = "NEW",
			Colour = "B9A6FF",
			Glyph = "♪",
		},
		{
			Id = "2026-10-20",
			Date = "20 Oct",
			Title = "The shop opens",
			Body = "Stage sets every 2 hours, song packs and coins.",
			Tag = "SHOP",
			Colour = "A7E9B8",
			Glyph = "★",
		},
		{
			Id = "2026-10-15",
			Date = "15 Oct",
			Title = "Smoother rounds",
			Body = "Clips load before the clock starts, so nobody loses time to a slow download.",
			Tag = "FIX",
			Colour = "9ED8F5",
			Glyph = "✓",
		},
	}),
})
