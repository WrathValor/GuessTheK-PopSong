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
-- Launch posts (release: Fri 20 Nov 2026). Change the top entry's Id/Date if launch moves.

return table.freeze({
	TAG_COLOURS = table.freeze({ NEW = "FFE07A", SHOP = "A7E9B8", FIX = "9ED8F5", EVENT = "FF9EC4" }),

	Entries = table.freeze({
		{
			Id = "2026-11-20",
			Version = "v1.0",
			Date = "20 Nov 2026",
			Title = "Welcome to Guess the K-Pop Song!",
			Body = "Step onto a stage, hear a tiny clip and name the song before your rival does. The less you need to hear, the more you score. Win duels for coins and XP, keep your streak alive and roll for 300+ songs from 2nd to 5th gen to fill your Index.",
			Tags = { "1v1 duels", "300+ songs", "Gen 2-5" },
			Tag = "NEW",
			Colour = "FF9EC4",
			Glyph = "♪",
		},
		{
			Id = "2026-11-20-invites",
			Date = "20 Nov",
			Title = "Duel your friends",
			Body = "Waiting on a stage? Tap Invite on the queue card to challenge anyone in the server.",
			Tag = "NEW",
			Colour = "9ED8F5",
			Glyph = "♪",
		},
		{
			Id = "2026-11-20-group",
			Date = "20 Nov",
			Title = "Free group rewards",
			Body = "Join Wrath's UGC for a free stage, a group tag and bonus coins. Claim them at the sign on the street.",
			Tag = "EVENT",
			Colour = "FF9EC4",
			Glyph = "★",
		},
		{
			Id = "2026-11-20-boards",
			Date = "20 Nov",
			Title = "Climb the leaderboards",
			Body = "Most Wins, Most Answers, Top Streaks: every board is all time now. Find them on the street.",
			Tag = "NEW",
			Colour = "FFE07A",
			Glyph = "★",
		},
		{
			Id = "2026-11-20-shop",
			Date = "20 Nov",
			Title = "The shop is open",
			Body = "Stage sets and items rotate every 6 hours. Grab song packs for your faves and group UGC.",
			Tag = "SHOP",
			Colour = "A7E9B8",
			Glyph = "★",
		},
		{
			Id = "2026-11-20-yoursongs",
			Date = "20 Nov",
			Title = "Your songs play in duels",
			Body = "Roll for songs in the shop. Every song you own comes up more often in your duels, duplicates level its card up to Gold and Rainbow, and owning a whole group gets you its fandom title.",
			Tag = "NEW",
			Colour = "FF9EC4",
			Glyph = "♪",
		},
		{
			Id = "2026-11-20-practice",
			Date = "20 Nov",
			Title = "Practise solo",
			Body = "Warm up on any era or generation with Play Solo. Every round is practice for your duels.",
			Tag = "NEW",
			Colour = "B9A6FF",
			Glyph = "✓",
		},
	}),
})
