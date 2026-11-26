--| Collection
-- Fandom titles come from photocards: owning a card of every member of a group (any album,
-- any rarity) completes the group's binder and unlocks its title (Packs.FANDOMS, "CARAT";
-- Inventory.Packs records "Group:<artist>"). Completing every group from a company unlocks
-- "<Company> Expert". Nothing is equipped for this; the player picks which title to show
-- (Inventory.Title).
-- The title levels up with the cards: each member's best card counts, and the lowest of those
-- sets the tier (every member Gold → Gold title, every member Rainbow → Rainbow title;
-- Inventory.TitleTiers, only goes up). Only groups with photocards (Albums.HasArt) can be
-- completed. DataService checks whenever Inventory.Cards changes and on join. A title (and
-- its tier) stays when an update adds new members or albums.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packs = require(ReplicatedStorage.Modules.Library.Packs)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)
local Albums = require(ReplicatedStorage.Modules.Library.Albums)

local Collection = {}

-- every group's members with photocards: artist → { [member key] = true }
local membersCache: { [string]: { [string]: boolean } }? = nil
local function groupMembers(): { [string]: { [string]: boolean } }
	if membersCache then
		return membersCache
	end
	local out = {}
	for _, artist in Albums.Artists() do
		for _, album in Albums.ForArtist(artist) do
			if Albums.HasArt(album) then
				out[artist] = out[artist] or {}
				for _, member in album.Members do
					out[artist][member.Key] = true
				end
			end
		end
	end
	membersCache = out
	return out
end

-- each group's binder level from the cards owned: artist → rank (1 Normal, 2 Gold, 3 Rainbow),
-- or no entry while a member is still missing
function Collection.GroupRanks(cards: { [string]: number }): { [string]: number }
	local best: { [string]: { [string]: number } } = {}
	for id, copies in cards do
		local info = copies > 0 and Albums.Card(id)
		local level = info and Albums.Level(copies)
		if info and level then
			local artist = info.Album.Artist
			best[artist] = best[artist] or {}
			best[artist][info.Member.Key] = math.max(best[artist][info.Member.Key] or 0, Cards.RANK[level])
		end
	end
	local ranks = {}
	for artist, members in groupMembers() do
		local low = math.huge
		for key in members do
			low = math.min(low, (best[artist] and best[artist][key]) or 0)
		end
		if low >= 1 and low < math.huge then
			ranks[artist] = low
		end
	end
	return ranks
end

-- Gives the titles of finished groups and companies. Returns what changed:
-- { { Title, Tier = "Normal" | "Gold" | "Rainbow", New = true when just unlocked } }
-- (the second argument is kept for older callers and ignored)
function Collection.Check(data, _songs: any?): { { Title: string, Tier: string, New: boolean } }
	local changes = {}
	local ranks = Collection.GroupRanks(data.Inventory.Cards.Get() or {})
	local tiers = data.Inventory.TitleTiers.Get() or {}
	local function give(packId: string, title: string?, rank: number)
		if not data.Inventory.Packs.Has(packId) then
			data.Inventory.Packs.Add(packId)
		end
		if not title then
			return
		end
		local new = not data.Inventory.Titles.Has(title)
		if new then
			data.Inventory.Titles.Add(title)
		end
		local upgraded = rank > 1 and rank > (tiers[title] or 1)
		if upgraded then
			data.Inventory.TitleTiers[title].Set(rank)
			tiers[title] = rank
		end
		if new or upgraded then
			table.insert(changes, { Title = title, Tier = Cards.LEVELS[tiers[title] or 1], New = new })
		end
	end
	-- groups, and each company's lowest group (only groups with photocards count)
	local companies: { [string]: { done: boolean, low: number, any: boolean } } = {}
	for _, pack in Packs.Groups() do
		local artist = pack.Name
		if groupMembers()[artist] then
			local company = (pack.Songs[1] and pack.Songs[1].Company) or "Other"
			local c = companies[company] or { done = true, low = math.huge, any = false }
			companies[company] = c
			c.any = true
			local rank = ranks[artist]
			if rank then
				c.low = math.min(c.low, rank)
				give(pack.Id, pack.Title, rank)
			else
				c.done = false
			end
		end
	end
	for _, pack in Packs.Companies() do
		local c = companies[pack.Name]
		if c and c.any and c.done then
			give(pack.Id, pack.Title, c.low)
		end
	end
	return changes
end

return Collection
