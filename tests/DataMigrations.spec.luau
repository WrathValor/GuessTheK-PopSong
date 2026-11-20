--| DataMigrations.spec
-- The one-off save fixes (Modules/DataMigrations), run on fake raw saves shaped the way Scribe
-- stores them (SetOf = sorted array, MapOf = plain table).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ServerStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local DataMigrations = require(ReplicatedStorage.Modules.DataMigrations)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)

-- a fresh raw save with only the fields the migrations touch
local function save(inventory)
	local inv = {
		Sets = {},
		Stages = {},
		Mics = {},
		Banners = {},
		Photocards = {},
		Banner = "",
		Photocard = "",
		Titles = {},
		Title = "",
		TitleTiers = {},
	}
	for k, v in inventory or {} do
		inv[k] = v
	end
	return { Inventory = inv }
end

local function isSorted(list)
	for i = 2, #list do
		if list[i] < list[i - 1] then
			return false
		end
	end
	return true
end

describe("the step list", function()
	it("has no gaps from 2 up (Scribe refuses a missing step)", function()
		local highest = 1
		for version in DataMigrations do
			expect(typeof(version)).toBe("number")
			highest = math.max(highest, version)
		end
		for version = 2, highest do
			expect(typeof(DataMigrations[version])).toBe("function")
		end
	end)
end)

describe("step 2", function()
	local migrate = DataMigrations[2]
	local set = ShopCatalog.Sets[1]
	local stage, mic = ShopCatalog.SetPieces(set)

	it("gives an old set's stage and mic pieces", function()
		local data = save({ Sets = { set.Id } })
		migrate(data)
		expect(table.find(data.Inventory.Stages, stage.Id)).never.toBeNil()
		expect(table.find(data.Inventory.Mics, mic.Id)).never.toBeNil()
	end)

	it("doesn't duplicate pieces already owned, and keeps lists sorted", function()
		local data = save({ Sets = { set.Id }, Stages = { "AAA", stage.Id, "zzz" }, Mics = { mic.Id } })
		table.sort(data.Inventory.Stages)
		migrate(data)
		local count = 0
		for _, id in data.Inventory.Stages do
			count += if id == stage.Id then 1 else 0
		end
		expect(count).toBe(1)
		expect(#data.Inventory.Mics).toBe(1)
		expect(isSorted(data.Inventory.Stages)).toBe(true)
	end)

	it("gives nothing to a player with no sets", function()
		local data = save()
		migrate(data)
		expect(#data.Inventory.Stages).toBe(0)
		expect(#data.Inventory.Mics).toBe(0)
	end)

	it("renames S1 banners and photocards to S0, owned and worn", function()
		local data = save({ Banners = { "S1Glow" }, Photocards = { "S0Star", "S1Star" }, Banner = "S1Glow", Photocard = "S1Star" })
		migrate(data)
		expect(data.Inventory.Banners).toEqual({ "S0Glow" })
		expect(data.Inventory.Photocards).toEqual({ "S0Star" })
		expect(data.Inventory.Banner).toBe("S0Glow")
		expect(data.Inventory.Photocard).toBe("S0Star")
	end)

	it("moves the S1 Comeback title, keeping the better tier and the equipped title", function()
		local data = save({ Titles = { "Fan", "S1 Comeback" }, Title = "S1 Comeback", TitleTiers = { ["S1 Comeback"] = 3 } })
		migrate(data)
		expect(table.find(data.Inventory.Titles, "S1 Comeback")).toBeNil()
		expect(table.find(data.Inventory.Titles, "S0 Comeback")).never.toBeNil()
		expect(data.Inventory.Title).toBe("S0 Comeback")
		expect(data.Inventory.TitleTiers["S0 Comeback"]).toBe(3)
		expect(data.Inventory.TitleTiers["S1 Comeback"]).toBeNil()
		expect(isSorted(data.Inventory.Titles)).toBe(true)
	end)

	it("never lowers a tier the S0 title already has", function()
		local data = save({ Titles = { "S0 Comeback", "S1 Comeback" }, TitleTiers = { ["S1 Comeback"] = 1, ["S0 Comeback"] = 2 } })
		migrate(data)
		expect(data.Inventory.TitleTiers["S0 Comeback"]).toBe(2)
		expect(#data.Inventory.Titles).toBe(1)
	end)

	it("leaves an up-to-date save exactly as it was", function()
		local data = save({ Banners = { "S0Glow" }, Titles = { "Fan" }, Title = "Fan", TitleTiers = { Fan = 1 } })
		local before = table.clone(data.Inventory)
		migrate(data)
		for k, v in before do
			expect(data.Inventory[k]).toEqual(v)
		end
	end)
end)

describe("step 3 (LNGSHOT - Masterpiece removed)", function()
	local migrate = DataMigrations[3]
	local ID = "Masterpiece - LNGSHOT"

	local function full(inventory, coins)
		local data = save(inventory)
		data.Inventory.Songs = data.Inventory.Songs or {}
		data.Inventory.Index = data.Inventory.Index or {}
		data.Inventory.Copies = data.Inventory.Copies or {}
		data.Currencies = { Won = coins or 0 }
		data.Profile = { Showcase = { S1 = "", S2 = "", S3 = "", S4 = "", S5 = "" }, BgMusic = "" }
		data.DailySong = { Guesses = {} }
		return data
	end

	it("takes the song away and refunds 150 coins once, whatever the copies", function()
		local data = full({ Songs = { ID, "Moonwalkin' - LNGSHOT" }, Copies = { [ID] = 4, ["Moonwalkin' - LNGSHOT"] = 2 }, Index = { ID } }, 100)
		data.Profile.Showcase.S2 = ID
		data.Profile.BgMusic = ID
		data.DailySong.Guesses = { ID, "Moonwalkin' - LNGSHOT" }
		migrate(data)
		expect(table.find(data.Inventory.Songs, ID)).toBeNil()
		expect(table.find(data.Inventory.Songs, "Moonwalkin' - LNGSHOT")).never.toBeNil()
		expect(data.Inventory.Copies[ID]).toBeNil()
		expect(data.Inventory.Copies["Moonwalkin' - LNGSHOT"]).toBe(2)
		expect(table.find(data.Inventory.Index, ID)).toBeNil()
		expect(data.Currencies.Won).toBe(250)
		expect(data.Profile.Showcase.S2).toBe("")
		expect(data.Profile.BgMusic).toBe("")
		expect(data.DailySong.Guesses[1]).toBe("")
		expect(data.DailySong.Guesses[2]).toBe("Moonwalkin' - LNGSHOT")
	end)

	it("refunds copies-only saves too, and leaves everyone else alone", function()
		local copiesOnly = full({ Copies = { [ID] = 1 } }, 0)
		migrate(copiesOnly)
		expect(copiesOnly.Currencies.Won).toBe(150)

		local never = full({ Songs = { "Moonwalkin' - LNGSHOT" } }, 500)
		migrate(never)
		expect(never.Currencies.Won).toBe(500)
		expect(#never.Inventory.Songs).toBe(1)
	end)
end)
