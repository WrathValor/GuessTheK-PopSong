--| PartyConstants
-- Party Stages: private stages a host runs (Engine/PartyService). Separate from public
-- matchmaking. The host picks Normal Duel (2 players) or Free-for-all (3–6, everyone their own
-- score), the song pool and who can join; guests ready up and the host starts. Values are
-- starting points to tune from playtests.
return table.freeze({
	-- spots on the stage (the platforms + mics are laid out round the circle for this many)
	MIN_SPOTS = 3, -- FFA
	MAX_SPOTS = 6,
	DEFAULT_SPOTS = 6,
	DUEL_SPOTS = 2,
	MIN_FFA_PLAYERS = 3,
	DEFAULT_MODE = "FFA", -- "FFA" | "Duel"
	DEFAULT_FRIENDS_ONLY = true,
	DEFAULT_SPECTATORS = true,
	DEFAULT_BOOST = false, -- "Owned songs count": off = every eligible song has the same chance

	COUNTDOWN = 5, -- seconds after the host presses START (anyone un-readying stops it)
	INVITE_TIME = 20, -- an invite / a join request lasts this long
	REQUEST_COOLDOWN = 20, -- a declined asker waits this long before asking the same host again
	ACTION_GAP = 0.2, -- spam guard on PartyRemote

	-- coins: a stake roll (like a duel's, weighted to the low end) sets the pot, times the match
	-- multiplier below; the reel shows the multiplied amounts. The pot is paid by placement.
	-- These average about 70 (the old flat pot) before the multiplier.
	STAKES = table.freeze({ 40, 60, 70, 90, 110, 140 }),
	STAKE_WEIGHTS = table.freeze({ 30, 25, 18, 12, 10, 5 }),
	PAYOUT = table.freeze({ 1, 0.7, 0.5, 0.3, 0.3, 0.3 }), -- 1st … 6th (a 1v1 pays 1st and 2nd)
	DUEL_PAYOUT = table.freeze({ 1, 0.3 }),
	-- FFA multiplier by how many started the match; Normal Duel is 1.0
	FFA_MULTIPLIER = table.freeze({ [3] = 1.2, [4] = 1.3, [5] = 1.4, [6] = 1.5 }),
	CUSTOM_POOL_MULTIPLIER = 0.8, -- the host picked the songs
	-- a custom pool needs this many songs before coins + XP pay out at all (stops hosts
	-- farming a handful of easy songs) …
	MIN_POOL_REWARDS = 20,
	-- … and this many to be saved at all (7 rounds + enough left over for wrong answers)
	MIN_POOL = 10,

	-- the stage's neon strip + sign
	STATUS_COLOURS = table.freeze({ Empty = "F4F0FA", Waiting = "B9A6FF", Live = "FF9EC4" }),
	PROMPT_DISTANCE = 12,
})
