-- Duel tuning. Values follow the design doc (Rounds and Scoring / Stakes, Streaks and Progression)
-- and are starting points to tune from playtests.
return table.freeze({
	-- queue / pre-duel
	START_TIME = 5, -- queue intermission before the pre-duel screen (either player can Cancel during it)
	STAKE_SPIN = 2.5, -- stake reel spin on the pre-duel screen
	-- mode vote (Song / Choreography). Off until Choreography ships: every duel is Song and
	-- the pre-duel screen is just the stake roll (+ duel pack info), held for PRE_DUEL_HOLD.
	MODE_VOTE = false,
	DEFAULT_MODE = "Song",
	PRE_DUEL_HOLD = 3, -- with no vote: seconds the rolled stake stays up before round 1
	VOTE_TIME = 5, -- mode vote window
	MODE_REVEAL = 1.5, -- pause on the chosen mode before round 1

	-- rounds
	ROUNDS = 7,
	ROUND_CAP = 20, -- a round never lasts longer than this
	SOLO_CAP = 180, -- solo practice has no clock: this only ends a round someone walked away from
	LOAD_TIMEOUT = 8, -- longest the round clock waits for players' clips to load
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

	-- stake roll: 30-130 coins, weighted to the low end (averages ~52)
	STAKES = table.freeze({ 30, 40, 50, 70, 90, 130 }),
	STAKE_WEIGHTS = table.freeze({ 30, 25, 18, 12, 10, 5 }),
	-- solo practice's stake (paid as XP, a seventh per right answer): about two thirds of a
	-- duel's (averages ~34), so duels stay the better way to level. Same weights.
	SOLO_STAKES = table.freeze({ 20, 25, 35, 45, 60, 90 }),

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

	-- owned songs: every song a player owns (Inventory.Songs) comes up more often, nothing to
	-- equip. Each owner adds (weight - 1) to the song's chance, by its card level, so a song
	-- nobody owns is 1 and a Normal card both players own is 3. Once OWNED_ROUNDS_MAX rounds
	-- have played an owned song, the rest of the game goes back to plain odds.
	OWNED_WEIGHT = table.freeze({ Normal = 2, Gold = 3, Rainbow = 5 }),
	OWNED_ROUNDS_MAX = 3,
	OWNED_XP = 5, -- bonus XP for guessing a song you own (duels only)

	-- rematch series: two players who keep pressing Rematch play a running series (shown on
	-- the pre-duel + results screens). Winning a rematch right after losing to that same rival
	-- is a Revenge win and pays this on top (before the 2× Coins pass).
	REVENGE_COINS = 15,
	REVENGE_XP = 25,
	-- (Revenge pays once per rematch series, so trading wins back and forth can't farm it)

	-- same-rival guard (stops two friends / an alt farming coins off each other): after this
	-- many duels against the same rival in a UTC day, coins from them are halved
	-- (SAME_RIVAL_COIN_SCALE) and a win no longer grows the win streak
	SAME_RIVAL_GAMES = 3,
	SAME_RIVAL_COIN_SCALE = 0.5,

	-- Save Streak developer product. 0 = not set up yet (button is disabled).
	SAVE_STREAK_PRODUCT_ID = 3726066704,

	-- first-join tutorial (client/Client/Tutorial): a short solo practice game on songs most
	-- people know, no time pressure, then a one-time welcome gift
	TUTORIAL_ROUNDS = 3,
	TUTORIAL_CAP = 90, -- seconds a tutorial round may last (the tips need reading time)
	TUTORIAL_REVEAL_EXTRA = 4, -- round 1's reveal stays up longer for its tip
	TUTORIAL_COINS = 100,
	TUTORIAL_SONGS = table.freeze({
		"Dynamite - BTS",
		"DDU-DU DDU-DU - BLACKPINK",
		"Gee - Girls' Generation",
		"Super Shy - NewJeans",
		"Fancy - TWICE",
		"Next Level - aespa",
		"How You Like That - BLACKPINK",
		"Hype Boy - NewJeans",
		"FANTASTIC BABY - BIGBANG",
	}),
})
