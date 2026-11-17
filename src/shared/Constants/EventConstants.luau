--| EventConstants
-- The Christmas event (Winter '26) and its Roblox experience event, for the sign-up. Read by
-- the HUD's Christmas card (HUDController) and the "Notify me" prompts (Client/EventSignup).
--   Before STARTS: "Notify me" opens Roblox's own sign-up prompt; afterwards "✓ Going".
--   STARTS to ENDS: the card reads LIVE_NAME and opens the Winter screen; the prompts hide.
--   After ENDS: the card hides.
-- Times are os.time, UTC.

return table.freeze({
	-- Creator Hub > the experience > Events: "First Snow in Seoul"
	EVENT_ID = "8935175166617584403",
	NAME = "Christmas",
	LIVE_NAME = "Winter '26",
	STARTS = 1796083200, -- 2026-12-01 00:00 UTC
	ENDS = 1799280000, -- 2027-01-07 00:00 UTC (the end of Jan 6)
	-- CollectionService tag for the world's "Notify me" ProximityPrompts (on the server tree)
	PROMPT_TAG = "EventSignup",
})
