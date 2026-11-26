--| resetonboard
-- Makes a player new to the K-POPPED! onboarding (TutorialController/Flow) again: no saved step,
-- the old tutorial not done (so the full version with the practice round), and the All set
-- rewards and the 500-coin Payout gift claimable again. Tells you what was there first.
-- Rejoin after (the onboarding starts on join).

return {
	Name = "resetonboard",
	Aliases = {},
	Description = "Starts the onboarding over as a new player (rejoin after).",
	Group = "Testing",
	Args = {
		{ Type = "players", Name = "players", Description = "Who" }
	},
}
