--| GhostPool.spec
-- Which recordings the ghost rival can replay (Engine/GhostPool.Usable) and the made-up ghost
-- used when nothing recorded fits (GhostPool.Synthetic). Nothing here touches a DataStore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local SongLibrary = require(ReplicatedStorage.Modules.Library.Songs)
local GhostPool = require(ServerScriptService.Engine.GhostPool)

local ROUNDS = DuelConstants.ROUNDS

-- a recording of a full game on real songs from the library
local function recording(): any
	local rounds = {}
	for i = 1, ROUNDS do
		rounds[i] = { Id = SongLibrary.All[i].Id, Tier = 2, Ok = true, Time = 3 }
	end
	return { V = 1, U = 42, T = 0, L = 8, SP = 0, S = 30, W = "Win", R = rounds }
end

describe("Usable", function()
	it("takes a full game on songs still in the library", function()
		expect(GhostPool.Usable(recording())).toBe(true)
	end)

	it("skips a game with a song that's gone", function()
		local r = recording()
		r.R[3].Id = "Not A Song - Nobody"
		expect(GhostPool.Usable(r)).toBe(false)
	end)

	it("skips a short game, another format or junk", function()
		local short = recording()
		table.remove(short.R)
		expect(GhostPool.Usable(short)).toBe(false)
		local v2 = recording()
		v2.V = 2
		expect(GhostPool.Usable(v2)).toBe(false)
		expect(GhostPool.Usable(nil)).toBe(false)
		expect(GhostPool.Usable("ghost")).toBe(false)
	end)
end)

describe("Synthetic", function()
	it("makes a usable full game at the asked level", function()
		for _, level in { 1, 7, 15, 30, 80 } do
			local r = GhostPool.Synthetic(level)
			expect(GhostPool.Usable(r)).toBe(true)
			expect(r.L).toBe(level)
			expect(r.Synthetic).toBe(true)
			expect(r.U).toBe(0) -- never anyone's own recording
		end
	end)

	it("answers on a real tier, after hearing it, with a different song when wrong", function()
		local tiers = DuelConstants.TIERS[DuelConstants.DEFAULT_MODE]
		for _ = 1, 20 do
			for _, round in GhostPool.Synthetic(10).R do
				expect(round.Tier >= 1 and round.Tier <= #tiers).toBe(true)
				if round.Time then
					expect(round.Time >= tiers[round.Tier]).toBe(true)
				end
				if not round.Ok and round.Pick then
					expect(round.Pick).never.toBe(round.Id)
				end
			end
		end
	end)
end)
