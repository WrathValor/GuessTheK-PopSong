--| StreetScreens
-- Tunables for the screens around the street: the jumbotron over the Duel Stages
-- (Map.Landmarks.BigScreen) and the walk-up machines (Map.StreetMachines). The server
-- (Engine/StreetScreens) gathers what they show; the client (Client/StreetScreens) draws it.

local StreetScreens = {}

-- seconds each jumbotron slide stays up (slides with nothing to show are skipped)
StreetScreens.SLIDE_SECONDS = 8

-- IN THE SHOP NOW: the slide flips through stage sets → photocards → mics → stages, this many
-- seconds a page (so it stays up 4 × this, not SLIDE_SECONDS)
StreetScreens.SHOP_PAGE_SECONDS = 5

-- "NEW THIS FRIDAY": Song Ids added in this week's drop, newest first, e.g.
-- { "Mirror Mirror - IVE", "FOCUS - Hearts2Hearts" }. Update it with each Friday drop.
-- Empty = the slide shows the newest releases in the library (by Year) instead.
StreetScreens.NEW_SONGS = {}
StreetScreens.NEW_SHOWN = 4 -- cards on the slide

-- the weekly drop: Fridays at 00:00 UTC (the countdown on the slide)
StreetScreens.DROP_WEEKDAY = 5 -- 0 = Sunday … 5 = Friday

-- SERVER HIGHLIGHTS
StreetScreens.HIGHLIGHTS = 3 -- rows on the slide (newest first)
StreetScreens.STREAK_EVERY = 5 -- a win streak makes the board at 5, 10, 15 …
StreetScreens.COMEBACK_MIN = 3 -- an ENCORE comeback counts if the winner was at least this far behind

-- card roll ticker on the gacha machine: the last few Gold / Rainbow pulls on the server
StreetScreens.PULLS = 6

-- the merch pop-up's featured UGC item changes this often
StreetScreens.MERCH_SECONDS = 7 * 24 * 60 * 60

return table.freeze(StreetScreens)
