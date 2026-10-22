-- Duel tuning. Values follow the design doc (Rounds and Scoring / Stakes, Streaks and Progression)
-- and are starting points to tune from playtests.
return table.freeze({
	-- queue / pre-duel
	START_TIME = 10, -- queue intermission before the pre-duel screen
	STAKE_SPIN = 2.5, -- stake reel spin on the pre-duel screen
	VOTE_TIME = 5, -- mode vote window
	MODE_REVEAL = 1.5, -- pause on the chosen mode before round 1

	-- rounds
	ROUNDS = 7,
	ROUND_CAP = 20, -- a round never lasts longer than this
	ANSWER_WINDOW = 10, -- after the first guess, everyone else has this long
	REVEAL_TIME = 5, -- seconds the answer + song play between rounds
	FIRST_CORRECT_BONUS = 1,

	-- snippet ladders (seconds of clip unlocked per tier), one per mode
	TIERS = table.freeze({
		Song = table.freeze({ 0.1, 0.5, 2, 8, 15 }),
		Choreography = table.freeze({ 0.5, 1, 3, 8, 15 }),
	}),
	TIER_POINTS = table.freeze({ 10, 7, 5, 2, 1 }),
	MODES = table.freeze({ "Song", "Choreography" }),

	-- stake roll: 20-100 coins, weighted to the low end
	STAKES = table.freeze({ 20, 30, 40, 50, 70, 100 }),
	STAKE_WEIGHTS = table.freeze({ 30, 25, 18, 12, 10, 5 }),

	-- rewards
	XP_CORRECT = 10,
	XP_WIN = 50,
	XP_LOSE = 20,
	LOSER_COINS = 10,
	PERFECT_XP = 100,
	PERFECT_COINS = 50,
	PERFECT_MAX_TIER = 3, -- "none past 2 s": every correct answer on tier 3 or better
	-- win streak -> stake multiplier
	STREAK_MULTIPLIERS = table.freeze({ { 10, 2 }, { 5, 1.5 }, { 3, 1.2 } }),

	-- Save Streak developer product. 0 = not set up yet (button is disabled).
	SAVE_STREAK_PRODUCT_ID = 0,
})
