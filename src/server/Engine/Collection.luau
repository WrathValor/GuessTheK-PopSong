--| Collection
-- Song sets: owning every song of a pack (bought in the shop or pulled from a song roll)
-- completes it (Inventory.Packs) and unlocks its title: group packs give the fandom name
-- (Packs.FANDOMS, "CARAT"), company packs "<Company> Expert". Nothing is equipped for this;
-- the player just picks which unlocked title to show (Inventory.Title).
-- The title levels up with the set (Cards.SetLevel, the lowest card in it): every card Gold →
-- Gold title, every card Rainbow → Rainbow title (Inventory.TitleTiers). DataService checks
-- every set whenever Inventory.Songs or Inventory.Copies changes, so any way of getting a song
-- or a copy counts. A title (and its tier) stays when an update adds new songs to its set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)

local Collection = {}

-- Marks finished sets and gives their titles. `songs` (optional) limits it to the sets those
-- songs belong to; leave it out to check every set. Returns what changed, for the roll reveal:
-- { { Title, Tier = "Normal" | "Gold" | "Rainbow", New = true when just unlocked } }
function Collection.Check(data, songs: { any }?): { { Title: string, Tier: string, New: boolean } }
	local changes = {}
	local packs = {}
	if songs then
		local seen = {}
		for _, song in songs do
			for _, pack in Packs.ForSong(song) do
				if not seen[pack.Id] then
					seen[pack.Id] = true
					table.insert(packs, pack)
				end
			end
		end
	else
		for _, list in { Packs.Groups(), Packs.Companies() } do
			for _, pack in list do
				table.insert(packs, pack)
			end
		end
	end
	local copies = data.Inventory.Copies.Get()
	local tiers = data.Inventory.TitleTiers.Get() or {}
	local function owns(id: string): boolean
		return data.Inventory.Songs.Has(id)
	end
	for _, pack in packs do
		local level = if pack.Kind ~= Packs.MY then Cards.SetLevel(pack.Songs, copies, owns) else nil
		if level then
			if not data.Inventory.Packs.Has(pack.Id) then
				data.Inventory.Packs.Add(pack.Id)
			end
			if pack.Title then
				local new = not data.Inventory.Titles.Has(pack.Title)
				if new then
					data.Inventory.Titles.Add(pack.Title)
				end
				-- Gold / Rainbow: only ever goes up
				local rank = Cards.RANK[level]
				local upgraded = rank > 1 and rank > (tiers[pack.Title] or 1)
				if upgraded then
					data.Inventory.TitleTiers[pack.Title].Set(rank)
					tiers[pack.Title] = rank
				end
				if new or upgraded then
					table.insert(changes, { Title = pack.Title, Tier = Cards.LEVELS[tiers[pack.Title] or 1], New = new })
				end
			end
		end
	end
	return changes
end

return Collection
