--| Albums.spec
-- K-POPPED! photocards (Modules/Library/Albums): rarities and odds, card ids, levels, bias,
-- pulls, gen and free packs, and the binder's earnings clock, against AlbumConstants.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local AlbumConstants = require(ReplicatedStorage.Constants.AlbumConstants)

-- a made-up album so the pull and odds tests don't depend on which groups are live
local FAKE = {
	Id = "test-album",
	Name = "Test",
	Artist = "TESTGROUP",
	Company = "Test",
	Members = {
		{ Key = "a", Name = "A", Art = "" },
		{ Key = "b", Name = "B", Art = "" },
		{ Key = "c", Name = "C", Art = "" },
		{ Key = "d", Name = "D", Art = "" },
	},
	Songs = {},
}

local function sum(list)
	local total = 0
	for _, entry in list do
		total += entry.Odds
	end
	return total
end

describe("Rarities", function()
	it("have odds that add up to 1", function()
		local total = 0
		for _, rarity in AlbumConstants.RARITIES do
			total += rarity.Odds
		end
		expect(math.abs(total - 1) < 1e-9).toBe(true)
	end)

	it("move a closed One of One's share to Signed Polaroid", function()
		local odds = Albums.RarityOdds({ oneofone = true })
		expect(math.abs(sum(odds) - 1) < 1e-9).toBe(true)
		for _, entry in odds do
			expect(entry.Rarity.Key).never.toBe("oneofone")
			if entry.Rarity.Key == AlbumConstants.FALLBACK_RARITY then
				expect(math.abs(entry.Odds - 0.0055) < 1e-9).toBe(true)
			end
		end
	end)

	it("can close a rarity for one album", function()
		local odds = Albums.RarityOdds({ fansign = true })
		expect(math.abs(sum(odds) - 1) < 1e-9).toBe(true)
		for _, entry in odds do
			expect(entry.Rarity.Key).never.toBe("fansign")
		end
	end)

	it("earn more and sell for more the rarer they are", function()
		local last = AlbumConstants.RARITIES[1]
		for i = 2, #AlbumConstants.RARITIES do
			local rarity = AlbumConstants.RARITIES[i]
			expect(rarity.Earn).toBeGreaterThan(last.Earn)
			expect(rarity.Odds).toBeLessThan(last.Odds)
			if rarity.Sell and last.Sell then
				expect(rarity.Sell).toBeGreaterThan(last.Sell)
			end
			last = rarity
		end
	end)

	it("earn 1 a minute for a Standard up to 100 for a One of One", function()
		expect(Albums.Rarity("standard").Earn).toBe(1)
		expect(Albums.Rarity("oneofone").Earn).toBe(100)
	end)
end)

describe("Pins", function()
	local album = Albums.All()[1]
	local function id(i: number, rarity: string): string
		return Albums.CardId(album.Id, album.Members[((i - 1) % #album.Members) + 1].Key, rarity)
	end

	it("parse without blanks or repeats, at most PIN_SLOTS_MAX", function()
		expect(#Albums.Pins("")).toBe(0)
		expect(#Albums.Pins("a||b|a")).toBe(2)
		expect(#Albums.Pins("a|b|c|d|e|f|g")).toBe(AlbumConstants.PIN_SLOTS_MAX)
	end)

	it("only pinned cards you still own earn", function()
		local a, b = id(1, "standard"), id(2, "selca")
		local cards = { [a] = 1, [b] = 1 }
		expect(Albums.Rate(cards, nil, "")).toBe(0)
		expect(Albums.Rate(cards, nil, a)).toBe(Albums.EarnPerMinute(a, 1, nil))
		expect(Albums.Rate({ [b] = 1 }, nil, a .. "|" .. b)).toBe(Albums.EarnPerMinute(b, 1, nil))
	end)

	it("only the unlocked slots count", function()
		local cards, list = {}, {}
		for i = 1, AlbumConstants.PIN_SLOTS + 1 do
			local cid = id(i, if i <= #album.Members then "standard" else "selca")
			cards[cid] = 1
			table.insert(list, cid)
		end
		local expected = 0
		for i = 1, AlbumConstants.PIN_SLOTS do
			expected += Albums.EarnPerMinute(list[i], 1, nil)
		end
		expect(Albums.Rate(cards, nil, Albums.PinValue(list))).toBe(expected)
	end)

	it("set bonus is per member", function()
		expect(Albums.SetBonus(album)).toBe(#album.Members * AlbumConstants.SET_BONUS_PER_MEMBER)
		expect(#Albums.SetKey(album) <= 40).toBe(true)
	end)
end)

describe("Card ids", function()
	it("round-trip", function()
		local id = Albums.CardId("bts-love-yourself", "jungkook", "luckydraw")
		expect(id).toBe("bts-love-yourself:jungkook:luckydraw")
		local a, m, r = Albums.Parse(id)
		expect(a).toBe("bts-love-yourself")
		expect(m).toBe("jungkook")
		expect(r).toBe("luckydraw")
	end)

	it("reject the wrong shape", function()
		expect((Albums.Parse("a:b"))).toBeNil()
		expect((Albums.Parse("a:b:c:d"))).toBeNil()
		expect(Albums.Card("nope:nope:standard")).toBeNil()
	end)

	it("turn member names into keys", function()
		expect(Albums.MemberKey("Jung Kook")).toBe("jungkook")
		expect(Albums.MemberKey("j-hope")).toBe("jhope")
		expect(Albums.MemberKey("I.N")).toBe("in")
		expect(Albums.MemberKey("ROSÉ")).toBe("rose")
	end)
end)

describe("Levels", function()
	it("follow the copy counts", function()
		expect(Albums.Level(0)).toBeNil()
		expect(Albums.Level(1)).toBe("Normal")
		expect(Albums.Level(AlbumConstants.GOLD_COPIES)).toBe("Gold")
		expect(Albums.Level(AlbumConstants.RAINBOW_COPIES)).toBe("Rainbow")
	end)
end)

describe("Bias", function()
	it("round-trips, spaces and all", function()
		local value = Albums.BiasValue("LE SSERAFIM", "chaewon")
		local artist, key = Albums.BiasParts(value)
		expect(artist).toBe("LE SSERAFIM")
		expect(key).toBe("chaewon")
		expect((Albums.BiasParts(""))).toBeNil()
	end)

	it("only counts in the bias's own group", function()
		expect(Albums.IsBias(FAKE, "a", "TESTGROUP|a")).toBe(true)
		expect(Albums.IsBias(FAKE, "b", "TESTGROUP|a")).toBe(false)
		expect(Albums.IsBias(FAKE, "a", "OTHER|a")).toBe(false)
	end)

	it("doubles the bias's share of the album's odds", function()
		local odds = Albums.Odds(FAKE, "TESTGROUP|a")
		local total, a, b = 0, 0, 0
		for key, row in odds do
			for _, p in row do
				total += p
				if key == "a" then
					a += p
				elseif key == "b" then
					b += p
				end
			end
		end
		expect(math.abs(total - 1) < 1e-9).toBe(true)
		expect(math.abs(a / b - AlbumConstants.BIAS_PULL_WEIGHT) < 1e-9).toBe(true)
	end)
end)

describe("Roll", function()
	it("only gives live rarities and real members", function()
		local rng = Random.new(1)
		for _ = 1, 2000 do
			local member, rarity = Albums.Roll(FAKE, nil, rng)
			expect(Albums.Member(FAKE, member)).never.toBeNil()
			expect(Albums.Rarity(rarity).Live).toBe(true)
		end
	end)

	it("roughly follows the odds", function()
		local rng = Random.new(7)
		local n, standard = 20000, 0
		for _ = 1, n do
			local _, rarity = Albums.Roll(FAKE, nil, rng)
			standard += if rarity == "standard" then 1 else 0
		end
		expect(math.abs(standard / n - 0.55) < 0.02).toBe(true)
	end)

	it("picks a card you don't own under pity, when there is one", function()
		local rng = Random.new(3)
		for _ = 1, 500 do
			local member = Albums.Roll(FAKE, nil, rng, nil, function(id)
				return (Albums.Parse(id)) ~= nil and select(2, Albums.Parse(id)) == "c"
			end)
			expect(member).toBe("c")
		end
	end)
end)

describe("Binder clock", function()
	it("earns the rate a minute", function()
		local coins = Albums.Waiting(0, 0, 10, 60)
		expect(coins).toBe(10)
	end)

	it("stops at the cap", function()
		local cap = AlbumConstants.BINDER_CAP_SECONDS
		local coins = Albums.Waiting(0, 0, 10, cap * 3)
		expect(coins).toBe(10 * cap / 60)
	end)

	it("adds the bank, in hundredths, but never past the cap", function()
		expect((Albums.Waiting(250, 100, 10, 100))).toBe(19) -- 2.5 banked + 10 × 100 s / 60 = 19.2
		local cap = AlbumConstants.BINDER_CAP_SECONDS
		expect((Albums.Waiting(10 ^ 9, 0, 10, 60))).toBe(10 * cap / 60)
	end)

	it("never goes negative when the clock is ahead", function()
		expect((Albums.Waiting(0, 1000, 10, 0))).toBe(0)
	end)
end)

describe("Group pulls", function()
	it("have odds that add up to 1 for every group", function()
		for _, artist in Albums.Artists() do
			local total = 0
			for _, album in Albums.GroupOdds(artist, nil) do
				for _, row in album do
					for _, p in row do
						total += p
					end
				end
			end
			expect(math.abs(total - 1) < 1e-9).toBe(true)
		end
	end)

	it("only give cards from the group's own albums", function()
		local rng = Random.new(11)
		for _, artist in Albums.Artists() do
			for _ = 1, 50 do
				local album, member, rarity = Albums.RollGroup(artist, nil, rng)
				expect(album.Artist).toBe(artist)
				expect(Albums.Card(Albums.CardId(album.Id, member, rarity))).never.toBeNil()
			end
		end
	end)
end)

describe("Gen packs", function()
	it("every live group has a generation from the list", function()
		for _, artist in Albums.Artists() do
			expect(table.find(AlbumConstants.GENERATIONS, Albums.Generation(artist))).never.toBeNil()
		end
	end)

	it("only give cards from groups of that gen", function()
		local rng = Random.new(5)
		for _, gen in AlbumConstants.GENERATIONS do
			if #Albums.ArtistsInGen(gen) > 0 then
				for _ = 1, 40 do
					local album = Albums.RollGen(gen, rng)
					expect(album).never.toBeNil()
					expect(Albums.Generation(album.Artist)).toBe(gen)
				end
			end
		end
	end)

	it("with no gen, can come from any group", function()
		expect(#Albums.ArtistsInGen(nil)).toBe(#Albums.Artists())
	end)
end)

describe("Last card odds", function()
	it("add up to 1 and favour rarer cards", function()
		local last = Albums.LastOdds(AlbumConstants.PACK_SIZE)
		local total = 0
		for _, p in last do
			total += p
		end
		expect(math.abs(total - 1) < 1e-9).toBe(true)
		local each = Albums.LastOdds(1)
		expect(last.standard < each.standard).toBe(true)
		expect(last.polaroid > each.polaroid).toBe(true)
	end)
end)

describe("Premium packs", function()
	it("never roll below their floor", function()
		local rng = Random.new(3)
		for _, pack in AlbumConstants.PREMIUM_PACKS do
			for _ = 1, 60 do
				local _, _, rarity = Albums.RollGen(nil, rng, nil, nil, pack.LastMin)
				expect(Albums.RarityRank(rarity) >= Albums.RarityRank(pack.LastMin)).toBe(true)
			end
		end
	end)

	it("have last-card odds that add up to 1 and start at LastMin", function()
		for _, pack in AlbumConstants.PREMIUM_PACKS do
			local last = Albums.LastOdds(AlbumConstants.PACK_SIZE, nil, pack.CardMin, pack.LastMin)
			local total = 0
			for key, p in last do
				total += p
				if Albums.RarityRank(key) < Albums.RarityRank(pack.LastMin) then
					expect(p).toBe(0)
				end
			end
			expect(math.abs(total - 1) < 1e-9).toBe(true)
		end
	end)
end)

describe("Mixes", function()
	it("girl and boy groups only hold their type, and All is everyone", function()
		for _, artist in Albums.ArtistsIn("Girl") do
			expect(Albums.GroupType(artist)).toBe("Girl")
		end
		for _, artist in Albums.ArtistsIn("Boy") do
			expect(Albums.GroupType(artist)).toBe("Boy")
		end
		expect(#Albums.ArtistsIn("All")).toBe(#Albums.Artists())
		expect(#Albums.ArtistsIn("Girl")).toBeGreaterThan(0)
	end)
end)

describe("Group pack rotation", function()
	it("has ROTATION_SIZE different live groups", function()
		local list = Albums.Rotation(1795000000)
		expect(#list).toBe(math.min(AlbumConstants.ROTATION_SIZE, #Albums.Artists()))
		local seen = {}
		for _, artist in list do
			expect(seen[artist]).toBeNil()
			seen[artist] = true
			expect(#Albums.ForArtist(artist)).toBeGreaterThan(0)
		end
	end)

	it("is the same all through a rotation, and ends on the boundary", function()
		local period = AlbumConstants.ROTATION_SECONDS
		local start = 20000 * period
		local a, endsA = Albums.Rotation(start + 5)
		local b, endsB = Albums.Rotation(start + period - 1)
		expect(table.concat(a, "|")).toBe(table.concat(b, "|"))
		expect(endsA).toBe(start + period)
		expect(endsB).toBe(start + period)
	end)

	it("always includes your bias's group", function()
		local artist = Albums.Artists()[1]
		expect(Albums.InRotation(artist, Albums.BiasValue(artist, "x"), 0)).toBe(true)
	end)
end)

describe("Free pack clock", function()
	local period, cap = AlbumConstants.FREE_PACK_SECONDS, AlbumConstants.FREE_PACK_CAP

	it("refills one per period", function()
		local packs, at, wait = Albums.FreePacks(1, 1000, 1000 + period * 2 + 30)
		expect(packs).toBe(3)
		expect(at).toBe(1000 + period * 2)
		expect(wait).toBe(period - 30)
	end)

	it("stops at the cap, and the clock waits while full", function()
		local packs, at, wait = Albums.FreePacks(cap - 1, 0, period * 50)
		expect(packs).toBe(cap)
		expect(at).toBe(period * 50)
		expect(wait).toBeNil()
	end)

	it("gives nothing before a period has passed", function()
		local packs, at = Albums.FreePacks(0, 500, 500 + period - 1)
		expect(packs).toBe(0)
		expect(at).toBe(500)
	end)
end)

describe("Live albums", function()
	it("have members, and every card resolves", function()
		for _, album in Albums.All() do
			expect(#album.Members).toBeGreaterThan(0)
			for _, member in album.Members do
				for _, rarity in AlbumConstants.RARITIES do
					local id = Albums.CardId(album.Id, member.Key, rarity.Key)
					expect(Albums.Card(id)).never.toBeNil()
					expect(#id <= 80).toBe(true) -- Inventory.Cards' MaxKeyLength
				end
			end
		end
	end)
end)

describe("Serial numbers", function()
	local album = Albums.All()[1]
	local member = album.Members[1].Key

	it("only numbered rarities carry them, One of One included", function()
		expect(Albums.Numbered(Albums.CardId(album.Id, member, "standard"))).toBe(false)
		expect(Albums.Numbered(Albums.CardId(album.Id, member, "luckydraw"))).toBe(false)
		expect(Albums.Numbered(Albums.CardId(album.Id, member, "fansign"))).toBe(true)
		expect(Albums.Numbered(Albums.CardId(album.Id, member, "oneofone"))).toBe(true)
	end)

	it("keeps a sorted list, and selling drops the highest", function()
		local value = Albums.AddSerial("", 17)
		value = Albums.AddSerial(value, 3)
		value = Albums.AddSerial(value, 9)
		expect(value).toBe("3,9,17")
		local left, removed = Albums.DropSerial(value)
		expect(left).toBe("3,9")
		expect(removed).toBe(17)
		expect(#Albums.Serials("x,0,4,-2,2.5")).toBe(1)
	end)

	it("reads as #n, or 1 OF 1", function()
		expect(Albums.SerialText(Albums.CardId(album.Id, member, "polaroid"), 12)).toBe("#12")
		expect(Albums.SerialText(Albums.CardId(album.Id, member, "oneofone"), 1)).toBe("1 OF 1")
		expect(Albums.SerialText(Albums.CardId(album.Id, member, "selca"), 4)).toBeNil()
	end)
end)

describe("Renamed albums", function()
	it("every old id points at an album in the game, and isn't one itself", function()
		for old, new in AlbumConstants.RENAMED_ALBUMS do
			expect(Albums.Get(new)).never.toBeNil()
			expect(Albums.Get(old)).toBeNil()
		end
	end)

	it("moves saved cards to the new id, and keeps counters under the old one", function()
		local old = "itzy-crazy-in-love:yeji:fansign"
		expect(Albums.Current(old)).toBe("itzy-gold:yeji:fansign")
		expect(Albums.Card(Albums.Current(old))).never.toBeNil()
		expect(Albums.StoreKey("itzy-gold:yeji:fansign")).toBe(old)
		expect(Albums.Current("itzy-gold:yeji:fansign")).toBe("itzy-gold:yeji:fansign")
		expect(Albums.StoreKey("bts-love-yourself:jungkook:fansign")).toBe("bts-love-yourself:jungkook:fansign")
	end)
end)
