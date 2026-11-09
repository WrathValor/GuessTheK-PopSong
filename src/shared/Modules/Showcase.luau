--| Showcase
-- The 5 song cards on a player's profile (design boards "Profile 1 · your card" and "Profile 3
-- · showcase: tap a slot, pick its card in the Index"). Players fill the slots one at a time
-- (PlayerData Profile.Showcase.S1–S5, saved by Engine/ProfileService); a slot they empty stays
-- empty. Only while nothing is pinned at all (a new player) do the slots show their best 5
-- cards, so a showcase is never blank. Only songs they own count.
-- Other players' clients read it from the "Showcase" player attribute: 5 lines, one per slot,
-- "<songId>|<Level>" (Level = Normal / Gold / Rainbow, Modules/Library/Cards) or "-" if empty.
--   Showcase.Resolve(pins, owns, copies) → { [slot]: { Id, Level }? }   (slots 1–5, may have gaps)
--   Showcase.Ids(cards) → { string }   (5 ids, "" for empty: what ProfileRemote SetShowcase takes)
--   Showcase.Encode(cards) / Showcase.Decode(text)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local Cards = require(ReplicatedStorage.Modules.Library.Cards)

local Showcase = {}

Showcase.SLOTS = 5
Showcase.KEYS = { "S1", "S2", "S3", "S4", "S5" }

export type Card = { Id: string, Level: string }

local function card(id: string, copies: { [string]: number }?): Card
	return { Id = id, Level = Cards.Level(Cards.Copies(copies, true, id)) or "Normal" }
end

-- pins: song ids by slot ("" = empty). owns(id) → whether the player owns it.
-- copies: the Inventory.Copies map.
function Showcase.Resolve(pins: { string }, owns: (string) -> boolean, copies: { [string]: number }?): { [number]: Card }
	local out: { [number]: Card } = {}
	local used: { [string]: boolean } = {}
	local any = false
	for i = 1, Showcase.SLOTS do
		local id = pins[i]
		if type(id) == "string" and id ~= "" then
			any = true
			if not used[id] and Songs.GetById(id) and owns(id) then
				out[i] = card(id, copies)
				used[id] = true
			end
		end
	end
	if any then
		return out
	end
	-- nothing pinned yet: the best cards, most copies first (Rainbow, Gold, Normal)
	local rest = {}
	for _, song in Songs.GetAllSongs() do
		if owns(song.Id) then
			table.insert(rest, { Id = song.Id, Copies = Cards.Copies(copies, true, song.Id), Name = song.Name })
		end
	end
	table.sort(rest, function(a, b)
		if a.Copies ~= b.Copies then
			return a.Copies > b.Copies
		end
		return a.Name < b.Name
	end)
	for i = 1, math.min(Showcase.SLOTS, #rest) do
		out[i] = card(rest[i].Id, copies)
	end
	return out
end

function Showcase.Ids(cards: { [number]: Card }): { string }
	local ids = {}
	for i = 1, Showcase.SLOTS do
		ids[i] = if cards[i] then cards[i].Id else ""
	end
	return ids
end

function Showcase.Count(cards: { [number]: Card }): number
	local n = 0
	for i = 1, Showcase.SLOTS do
		n += if cards[i] then 1 else 0
	end
	return n
end

function Showcase.Encode(cards: { [number]: Card }): string
	local lines = {}
	for i = 1, Showcase.SLOTS do
		local c = cards[i]
		lines[i] = if c then `{c.Id}|{c.Level}` else "-"
	end
	return table.concat(lines, "\n")
end

function Showcase.Decode(text: string?): { [number]: Card }
	local out: { [number]: Card } = {}
	if type(text) ~= "string" then
		return out
	end
	local i = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		i += 1
		if i > Showcase.SLOTS then
			break
		end
		local id, level = string.match(line, "^(.*)|(%a+)$")
		if id and Songs.GetById(id) then
			out[i] = { Id = id, Level = if Cards.RANK[level] then level else "Normal" }
		end
	end
	return out
end

return Showcase
