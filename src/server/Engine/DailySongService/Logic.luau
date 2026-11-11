--| Logic
-- The Daily Song's rules, with no players, data or remotes, so it can be tested on its own
-- (tests/DailySong.spec). Server-only: it picks the day's answer, which a client must never be
-- able to work out.
--   • which song a day plays (PickSong)
--   • what a guess or a skip does to today's play (Apply)
--   • the coins a solve pays, and the streak after a finished day

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailySongConstants = require(ReplicatedStorage.Constants.DailySongConstants)

local Logic = {}

-- [[ The day's song ]]

-- FNV-1a, 32 bit: the same number for the same text on every server
function Logic.Hash(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		-- h * 16777619 mod 2^32, split into 16-bit halves so every product stays exact
		local lo = h % 65536
		local hi = (h - lo) / 65536
		h = (lo * 16777619 + ((hi * 16777619) % 65536) * 65536) % 4294967296
	end
	return h
end

-- The song for UTC day `day`: of every song, the one whose hash with the day is lowest
-- ("rendezvous hashing"). Every server agrees without talking, and adding or removing a song
-- only changes a day whose pick it was or now beats, so an update mid-day can't swap the
-- answer for everyone. `skip[id]` leaves songs out (audio this server couldn't load).
function Logic.PickSong(songs: { any }, day: number, skip: { [string]: boolean }?): any?
	local best, bestHash = nil, math.huge
	for _, song in songs do
		if not (skip and skip[song.Id]) then
			local h = Logic.Hash(`{day}:{song.Id}`)
			if h < bestHash or (h == bestHash and best and song.Id < best.Id) then
				best, bestHash = song, h
			end
		end
	end
	return best
end

-- "#1" on FIRST_DAY
function Logic.Number(day: number): number
	return day - DailySongConstants.FIRST_DAY + 1
end

-- [[ Playing ]]

export type Play = {
	Guesses: { string }, -- song Ids guessed, "" for a skip, in order
	Solved: boolean,
	Done: boolean, -- solved, or out of tries
}

function Logic.NewPlay(): Play
	return { Guesses = {}, Solved = false, Done = false }
end

-- the clip tier the next try plays (1 = shortest)
function Logic.Tier(play: Play): number
	return math.min(#play.Guesses + 1, DailySongConstants.TRIES)
end

-- One guess (a song Id) or a skip (nil) on `play`, for the day whose answer is `answerId`.
-- Returns the new play and what happened: "Right", "Wrong", "Skip", "Missed" (the last try
-- went), or nil when the move isn't allowed (already done, or a guess repeated).
function Logic.Apply(play: Play, answerId: string, guess: string?): (Play, string?)
	if play.Done then
		return play, nil
	end
	if guess ~= nil then
		if guess == "" or table.find(play.Guesses, guess) then
			return play, nil
		end
	end
	local nextPlay: Play = { Guesses = table.clone(play.Guesses), Solved = false, Done = false }
	table.insert(nextPlay.Guesses, guess or "")
	if guess == answerId then
		nextPlay.Solved = true
		nextPlay.Done = true
		return nextPlay, "Right"
	end
	if #nextPlay.Guesses >= DailySongConstants.TRIES then
		nextPlay.Done = true
		return nextPlay, "Missed"
	end
	return nextPlay, if guess == nil then "Skip" else "Wrong"
end

-- coins for solving on try `tries` (0 when it isn't a solve)
function Logic.Coins(tries: number): number
	return DailySongConstants.COINS[tries] or 0
end

-- [[ Streaks ]]

-- The streak after finishing `day`. `lastSolved` = the last day solved before it (0 = never).
-- Solving the day after your last solve adds one; any gap, or a miss, starts again.
function Logic.Streak(streak: number, lastSolved: number, day: number, solved: boolean): number
	if not solved then
		return 0
	end
	if lastSolved == day - 1 then
		return streak + 1
	end
	return 1
end

-- The streak to show on `today`: a streak only lasts while yesterday (or today) was solved.
function Logic.LiveStreak(streak: number, lastSolved: number, today: number): number
	return if lastSolved >= today - 1 then streak else 0
end

return table.freeze(Logic)
