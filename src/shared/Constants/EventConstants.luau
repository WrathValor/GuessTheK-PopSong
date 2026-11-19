--| EventConstants
-- The HUD event button and the world's "Notify me" prompts. Which event they point at is set
-- live, without a publish: Creator Hub > the experience > Configs, key CONFIG_KEY (a string),
-- value = the Roblox event ID (Creator Hub > Events). An empty string hides the button.
-- Server/EventConfigService reads it and puts it on ReplicatedStorage (attribute ATTRIBUTE);
-- Modules/EventRsvp asks Roblox for that event's title, times and the player's RSVP.
--   Before it starts: the button reads the title + "in 14d"; a tap opens Roblox's sign-up.
--   Signed up ("Going"): the button hides.
--   Live: hidden, unless EVENTS[id].Live says what to open. Over: hidden.
-- The button's icon is ICON (the calendar) unless EVENTS[id].Icon gives one.
-- EVENTS is optional, per event ID: Name (a shorter HUD title than the event's), Icon, Live
-- ({ Name, Opens = a screen }) and Starts / Ends (os.time, UTC; only used when Roblox can't
-- return the event, e.g. in Studio).

return table.freeze({
	CONFIG_KEY = "HudEventId",
	ATTRIBUTE = "HudEventId",
	-- when Configs can't load or has no CONFIG_KEY yet
	DEFAULT_EVENT_ID = "8935175166617584403",
	-- CollectionService tag for the world's "Notify me" ProximityPrompts (on the server tree)
	PROMPT_TAG = "EventSignup",
	-- the universal event icon (assets/ui/EventIcon.png)
	ICON = "rbxassetid://100605564771296",

	EVENTS = {
		-- "First Snow in Seoul"
		["8935175166617584403"] = {
			Name = "Christmas",
			Icon = "rbxassetid://139354612591708", -- the tree
			Live = { Name = "Winter '26", Opens = "Winter" },
			Starts = 1796083200, -- 2026-12-01 00:00 UTC
			Ends = 1799280000, -- 2027-01-07 00:00 UTC
		},
	},
})
