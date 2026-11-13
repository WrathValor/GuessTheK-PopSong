--| DailySongConstants
-- Tuning for the Daily Song (Engine/DailySongService): one song for every player each UTC
-- day, guessed by typing, in up to TRIES tries. Each miss or skip plays a longer clip (the
-- duel's Song tiers). Shared so the client can draw the ladder and the rewards; which song it
-- is never leaves the server until the player is done.

local DuelConstants = require(script.Parent.DuelConstants)

return table.freeze({
	-- the clip lengths, one per try (seconds); the same ladder as a Song duel
	TIERS = DuelConstants.TIERS.Song,
	TRIES = #DuelConstants.TIERS.Song,
	-- coins for solving it on try 1, 2, … (one per try)
	COINS = table.freeze({ 100, 75, 50, 30, 15 }),
	XP = 25, -- on top of the coins, for any solve
	-- the number shown as "#142": days since this one (a UTC day number, RewardsCatalog.Day)
	FIRST_DAY = 20769, -- 11 Nov 2026 is #1 (move it to the launch day)
	-- the "How everyone did" chart: MemoryStore counts per day, read back every STATS_REFRESH s
	STATS_REFRESH = 60,
	STATS_TTL = 3 * 86400, -- counts expire after 3 days
	SHARE_PER_DAY = 1, -- shares to chat a player can post a day
})
