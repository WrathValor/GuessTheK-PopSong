--| DataMigrations
-- One-off fixes to saved player data (Modules/PlayerData passes this as Scribe's Migrations).
-- Scribe runs each step once per profile, in order, when the profile loads, then stamps the
-- profile's version, so a step never runs twice for the same player. Fail closed: a step that
-- errors keeps the old data untouched and the player can't join (nothing half-fixed is saved).
--
-- A step gets the RAW saved table, after Scribe has filled in any missing fields:
--   • a Scribe.SetOf is a plain array of ids (kept sorted)
--   • a Scribe.MapOf is a plain { [key] = value } table
--   • nothing here goes through Scribe's checks, so keep every value the declared type
--
-- Adding one: write the next number ([3] …). Never edit, reorder or remove a step that has
-- shipped; profiles already past it won't run it again. Tested in tests/DataMigrations.spec.
--
-- Rolling out: a server running OLD code kicks a player whose profile is a newer version
-- (Scribe's default), so publish with "Migrate to latest update" / restart servers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)

-- [[ Raw SetOf helpers ]]

local function has(list: { string }, id: string): boolean
	return table.find(list, id) ~= nil
end

local function add(list: { string }, id: string)
	if not table.find(list, id) then
		table.insert(list, id)
		table.sort(list)
	end
end

local function remove(list: { string }, id: string)
	local i = table.find(list, id)
	if i then
		table.remove(list, i)
	end
end

-- [[ Steps ]]

local Migrations = {}

-- [2] (was run on every join in Engine/DataService)
--   • sets bought before stages + mics were split: own each owned set's stage + mic piece
--   • the pre-season's banners, photocards and title were called S1 before they became S0:
--     move anything saved under the old names (owned, worn, and the title's tier)
Migrations[2] = function(data)
	local inv = data.Inventory

	for _, set in ShopCatalog.Sets do
		if has(inv.Sets, set.Id) then
			local stage, mic = ShopCatalog.SetPieces(set)
			add(inv.Stages, stage.Id)
			add(inv.Mics, mic.Id)
		end
	end

	for _, kind in { "Comeback", "Glow", "Star", "Icon", "Legend" } do
		local old, new = "S1" .. kind, "S0" .. kind
		for _, list in { inv.Banners, inv.Photocards } do
			if has(list, old) then
				remove(list, old)
				add(list, new)
			end
		end
		if inv.Banner == old then
			inv.Banner = new
		end
		if inv.Photocard == old then
			inv.Photocard = new
		end
	end

	local oldTitle, newTitle = "S1 Comeback", "S0 Comeback"
	if has(inv.Titles, oldTitle) then
		remove(inv.Titles, oldTitle)
		add(inv.Titles, newTitle)
		local tier = inv.TitleTiers[oldTitle] or 0
		if tier > (inv.TitleTiers[newTitle] or 0) then
			inv.TitleTiers[newTitle] = tier
		end
		inv.TitleTiers[oldTitle] = nil
		if inv.Title == oldTitle then
			inv.Title = newTitle
		end
	end
end

return Migrations
