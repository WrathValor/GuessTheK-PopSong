--| DailySong.spec
-- The Daily Song's rules (Engine/DailySongService/Logic): the day's pick, guessing and
-- skipping, coins and streaks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local DailySongConstants = require(ReplicatedStorage.Constants.DailySongConstants)
local Logic = require(ServerScriptService.Engine.DailySongService.Logic)

local TRIES = DailySongConstants.TRIES
local DAY = 20768

local function songs(n: number)
	local list = {}
	for i = 1, n do
		list[i] = { Id = `Song {i} - Artist {i % 7}` }
	end
	return list
end

describe("Hash", function()
	it("is FNV-1a 32-bit (published test values)", function()
		expect(Logic.Hash("")).toBe(2166136261)
		expect(Logic.Hash("a")).toBe(3826002220)
		expect(Logic.Hash("foobar")).toBe(3214735720)
	end)
end)

describe("the day's song", function()
	local library = songs(400)

	it("is the same on every call (every server agrees)", function()
		expect(Logic.PickSong(library, DAY).Id).toBe(Logic.PickSong(library, DAY).Id)
	end)

	it("doesn't depend on the order songs load in", function()
		local reversed = {}
		for i = #library, 1, -1 do
			table.insert(reversed, library[i])
		end
		expect(Logic.PickSong(reversed, DAY).Id).toBe(Logic.PickSong(library, DAY).Id)
	end)

	it("survives a song being added, unless the new song wins", function()
		local pick = Logic.PickSong(library, DAY)
		local more = table.clone(library)
		local extra = { Id = "Brand New - Rookies" }
		table.insert(more, extra)
		local after = Logic.PickSong(more, DAY)
		expect(after == pick or after == extra).toBe(true)
	end)

	it("changes from day to day, and spreads across the library", function()
		local seen, changes, last = {}, 0, nil
		for day = DAY, DAY + 199 do
			local id = Logic.PickSong(library, day).Id
			seen[id] = true
			if id ~= last then
				changes += 1
			end
			last = id
		end
		local distinct = 0
		for _ in seen do
			distinct += 1
		end
		expect(changes).toBeGreaterThan(190)
		expect(distinct).toBeGreaterThan(120) -- 200 days over 400 songs: no favourites
	end)

	it("can leave songs out", function()
		local pick = Logic.PickSong(library, DAY)
		expect(Logic.PickSong(library, DAY, { [pick.Id] = true }).Id).never.toBe(pick.Id)
		expect(Logic.PickSong({}, DAY)).toBeNil()
	end)

	it("numbers days from FIRST_DAY", function()
		expect(Logic.Number(DailySongConstants.FIRST_DAY)).toBe(1)
		expect(Logic.Number(DailySongConstants.FIRST_DAY + 141)).toBe(142)
	end)
end)

describe("playing", function()
	local ANSWER = "Super Shy - NewJeans"

	it("starts on the shortest clip", function()
		local play = Logic.NewPlay()
		expect(Logic.Tier(play)).toBe(1)
		expect(play.Done).toBe(false)
	end)

	it("solves on the right guess", function()
		local play, result = Logic.Apply(Logic.NewPlay(), ANSWER, ANSWER)
		expect(result).toBe("Right")
		expect(play.Solved).toBe(true)
		expect(play.Done).toBe(true)
	end)

	it("plays a longer clip after each miss or skip", function()
		local play = Logic.NewPlay()
		local result
		play, result = Logic.Apply(play, ANSWER, "Hype Boy - NewJeans")
		expect(result).toBe("Wrong")
		expect(Logic.Tier(play)).toBe(2)
		play, result = Logic.Apply(play, ANSWER, nil)
		expect(result).toBe("Skip")
		expect(Logic.Tier(play)).toBe(3)
		expect(play.Guesses).toEqual({ "Hype Boy - NewJeans", "" })
	end)

	it("ends after the last try, unsolved", function()
		local play, result = Logic.NewPlay(), nil
		for _ = 1, TRIES do
			play, result = Logic.Apply(play, ANSWER, nil)
		end
		expect(result).toBe("Missed")
		expect(play.Done).toBe(true)
		expect(play.Solved).toBe(false)
		expect(Logic.Tier(play)).toBe(TRIES)
	end)

	it("can still be solved on the last try", function()
		local play = Logic.NewPlay()
		for _ = 1, TRIES - 1 do
			play = Logic.Apply(play, ANSWER, nil)
		end
		local final, result = Logic.Apply(play, ANSWER, ANSWER)
		expect(result).toBe("Right")
		expect(#final.Guesses).toBe(TRIES)
	end)

	it("refuses moves once done, a repeated guess, and an empty guess", function()
		local done = Logic.Apply(Logic.NewPlay(), ANSWER, ANSWER)
		local same, result = Logic.Apply(done, ANSWER, "Hype Boy - NewJeans")
		expect(result).toBeNil()
		expect(same).toBe(done)

		local once = Logic.Apply(Logic.NewPlay(), ANSWER, "Hype Boy - NewJeans")
		expect(select(2, Logic.Apply(once, ANSWER, "Hype Boy - NewJeans"))).toBeNil()
		expect(select(2, Logic.Apply(once, ANSWER, ""))).toBeNil()
	end)

	it("never changes the play it was given", function()
		local play = Logic.NewPlay()
		Logic.Apply(play, ANSWER, "Hype Boy - NewJeans")
		expect(#play.Guesses).toBe(0)
	end)
end)

describe("coins", function()
	it("has a reward for every try, paying less each try", function()
		expect(#DailySongConstants.COINS).toBe(TRIES)
		for i = 2, TRIES do
			expect(Logic.Coins(i)).toBeLessThan(Logic.Coins(i - 1))
		end
		expect(Logic.Coins(TRIES)).toBeGreaterThan(0)
	end)

	it("pays nothing outside the tries", function()
		expect(Logic.Coins(0)).toBe(0)
		expect(Logic.Coins(TRIES + 1)).toBe(0)
	end)
end)

describe("streaks", function()
	it("grows when solved the day after the last solve", function()
		expect(Logic.Streak(6, DAY - 1, DAY, true)).toBe(7)
	end)

	it("starts at 1 after a gap, or the first time", function()
		expect(Logic.Streak(6, DAY - 2, DAY, true)).toBe(1)
		expect(Logic.Streak(0, 0, DAY, true)).toBe(1)
	end)

	it("resets on a miss", function()
		expect(Logic.Streak(6, DAY - 1, DAY, false)).toBe(0)
	end)

	it("shows 0 once a day has gone unsolved", function()
		expect(Logic.LiveStreak(6, DAY - 1, DAY)).toBe(6) -- today not played yet
		expect(Logic.LiveStreak(7, DAY, DAY)).toBe(7) -- solved today
		expect(Logic.LiveStreak(6, DAY - 2, DAY)).toBe(0) -- missed yesterday
	end)
end)
