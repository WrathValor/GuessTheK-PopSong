--| GhostRecorder.spec
-- What gets recorded for a future ghost opponent (Engine/GhostRecorder): the level bands, the
-- key a recording is saved under, and which games are kept. Nothing here touches a DataStore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local GhostRecorder = require(ServerScriptService.Engine.GhostRecorder)

local ROUNDS = DuelConstants.ROUNDS
local ME = { UserId = 123456 }
local RIVAL = { UserId = 987 }

-- a full duel: ME answers `answered` rounds (right on tier 2 at 3 s), RIVAL answers them all wrong
local function duel(answered: number, extra: { [string]: any }?)
	local rounds = {}
	for i = 1, ROUNDS do
		local did = i <= answered
		rounds[i] = {
			Song = { Id = `Song {i} - Group` },
			Picks = {
				[ME] = { Picked = if did then `Song {i} - Group` else nil, Correct = did, Tier = 2, Time = if did then 3.14159 else nil },
				[RIVAL] = { Picked = "Other - Group", Correct = false, Tier = 4, Time = 9 },
			},
		}
	end
	local result = { Rounds = rounds, Scores = { [ME] = 20, [RIVAL] = 0 }, Winner = ME, Draw = false, Forfeit = false, Solo = false }
	for k, v in extra or {} do
		result[k] = v
	end
	return result
end

describe("level bands", function()
	it("start at each BANDS level", function()
		expect(GhostRecorder.Band(1)).toBe(1)
		for i, start in GhostRecorder.BANDS do
			expect(GhostRecorder.Band(start - 1)).toBe(i)
			expect(GhostRecorder.Band(start)).toBe(i + 1)
		end
		expect(GhostRecorder.Band(100)).toBe(#GhostRecorder.BANDS + 1)
	end)

	it("give one key per player per band", function()
		expect(GhostRecorder.Key(2, 123456)).toBe("B2/56/123456")
		expect(GhostRecorder.Key(1, 7)).toBe("B1/07/7")
	end)
end)

describe("recording", function()
	it("keeps each side of a full duel", function()
		local mine = GhostRecorder.Build(duel(ROUNDS), ME, 12, 340)
		expect(mine.U).toBe(ME.UserId)
		expect(mine.L).toBe(12)
		expect(mine.SP).toBe(340)
		expect(mine.W).toBe("Win")
		expect(#mine.R).toBe(ROUNDS)
		expect(mine.R[1]).toEqual({ Id = "Song 1 - Group", Tier = 2, Ok = true, Time = 3.14 })

		local theirs = GhostRecorder.Build(duel(ROUNDS), RIVAL, 3, 0)
		expect(theirs.W).toBe("Lose")
		expect(theirs.R[1].Pick).toBe("Other - Group") -- the wrong song they picked
	end)

	it("keeps an unanswered round as no time and no pick", function()
		local mine = GhostRecorder.Build(duel(ROUNDS - 1), ME, 1, 0)
		expect(mine.R[ROUNDS]).toEqual({ Id = `Song {ROUNDS} - Group`, Tier = 2, Ok = false })
	end)

	it("skips games that aren't a full, played 1v1", function()
		for _, flag in { "Solo", "Tutorial", "Party", "Forfeit" } do
			expect(GhostRecorder.Build(duel(ROUNDS, { [flag] = true }), ME, 1, 0)).toBe(nil)
		end
		expect(GhostRecorder.Build(duel(DuelConstants.GHOST_MIN_ANSWERS - 1), ME, 1, 0)).toBe(nil)
		local short = duel(ROUNDS)
		table.remove(short.Rounds)
		expect(GhostRecorder.Build(short, ME, 1, 0)).toBe(nil)
	end)

	it("skips a game the suspect check flags", function()
		local result = duel(ROUNDS)
		for _, round in result.Rounds do
			round.Picks[ME].Tier = 1
			round.Picks[ME].Time = DuelConstants.SUSPECT_INSTANT / 2
		end
		expect(GhostRecorder.Build(result, ME, 1, 0)).toBe(nil)
	end)
end)
