--| Ladders
-- Group badges (design board "48 · Group badges · cards + songs ladders"). Every group has two
-- ladders, five rungs each, and Legend for topping both:
--   rung      Cards (photocards, any album)        Songs (Modules/Library/Mastery stars)
--   Bronze    any CARDS_BRONZE different cards     SONGS_BRONZE songs guessed right
--   Silver    a card of every member               every song ★
--   Gold      every member Store Benefit or better every song ★★
--   Platinum  every member Lucky Draw or better    half the songs ★★★ (rounded up)
--   Diamond   every member Fansign or better       every song ★★★
--   Legend    Diamond cards and Diamond songs
-- "Every member" counts each member's best card. Only groups with photocards AND at least
-- SONGS_MIN songs have ladders at all (Ladders.Eligible): a group missing either has no badges. Each rung pays COINS once (Engine/LadderService), and a rung once
-- reached is kept for good (Inventory.Ladders: the highest rung paid, by Key). One badge can be
-- worn in place of a title: Inventory.Title = TitleId(ladder, artist) (Engine/DataService turns
-- it into the "Title" / "TitleTier" / "TitleIcon" attributes; Modules/UI/TitleChip paints it).
--   Ladders.CardsRung(cards, artist) → rung, { Have, Need, Text } for the next one (nil at the top)
--   Ladders.SongsRung(mastery, artist) → same
--   Ladders.Key("Cards", artist) → "C:aespa"   Ladders.LEGEND_KEY(artist) → "L:aespa"
--   Ladders.Label(ladder, artist, rung) → "MY · GOLD" (the group's fandom name, Packs.FANDOMS)

local Albums = require(script.Parent.Albums)
local Packs = require(script.Parent.Packs)
local Mastery = require(script.Parent.Mastery)

local C = Color3.fromHex

local Ladders = {}

Ladders.RUNGS = table.freeze({ "Bronze", "Silver", "Gold", "Platinum", "Diamond" })
Ladders.TOP = #Ladders.RUNGS
Ladders.CARDS_BRONZE = 5
Ladders.SONGS_BRONZE = 5
Ladders.SONGS_MIN = 4
-- the least rarity every member needs, by rung (Silver = any card)
local CARD_RARITY = { [2] = "standard", [3] = "store", [4] = "luckydraw", [5] = "fansign" }
local RARITY_TEXT = { standard = "a card", store = "Store+", luckydraw = "Lucky Draw+", fansign = "Fansign+" }

-- coins for reaching each rung (assets/KPOPPED_Economy.xlsx, Badges tab)
Ladders.COINS = table.freeze({
	Cards = table.freeze({ 250, 500, 1000, 2000, 4000 }),
	Songs = table.freeze({ 50, 100, 200, 350, 600 }),
	Legend = 10000,
})

-- the chips' colours (board 48): Diamond is ice blue, Legend ink with gold text
Ladders.COLOURS = table.freeze({
	Bronze = C("E8B890"),
	Silver = C("DDE3EC"),
	Gold = C("FFE07A"),
	Platinum = C("C9D3E3"),
	Diamond = C("9ED8F5"),
	Legend = C("1E1B2E"),
})
Ladders.DIAMOND_SHEEN = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("7FCBF2")),
	ColorSequenceKeypoint.new(0.45, C("E8F8FF")),
	ColorSequenceKeypoint.new(0.6, C("9ED8F5")),
	ColorSequenceKeypoint.new(1, C("5BB8EA")),
})
Ladders.LEGEND_TEXT = C("FFE07A")

-- the two marks (board 48): a photocard for cards, a vinyl for songs
Ladders.ICONS = table.freeze({
	Cards = "rbxassetid://131856952611368", -- assets/UI/Badges/Photocard.png
	Songs = "rbxassetid://78116696469638", -- assets/UI/Badges/Vinyl.png
})

Ladders.TITLE_PREFIX = "Badge:"

-- [[ Keys ]]

local SHORT = { Cards = "C", Songs = "S" }
local LONG = { C = "Cards", S = "Songs", L = "Legend" }

function Ladders.Key(ladder: string, artist: string): string
	return `{SHORT[ladder]}:{artist}`
end

function Ladders.LegendKey(artist: string): string
	return `L:{artist}`
end

-- "C:aespa" → "Cards", "aespa"
function Ladders.ParseKey(key: string): (string?, string?)
	local short, artist = string.match(key, "^([CSL]):(.+)$")
	return short and LONG[short], artist
end

-- the Inventory.Title id for wearing a badge ("Badge:C:aespa")
function Ladders.TitleId(ladder: string, artist: string): string
	return Ladders.TITLE_PREFIX .. (if ladder == "Legend" then Ladders.LegendKey(artist) else Ladders.Key(ladder, artist))
end

-- "Badge:C:aespa" → "Cards", "aespa" (nil if it isn't a badge)
function Ladders.FromTitle(title: string?): (string?, string?)
	if type(title) ~= "string" or string.sub(title, 1, #Ladders.TITLE_PREFIX) ~= Ladders.TITLE_PREFIX then
		return nil, nil
	end
	return Ladders.ParseKey(string.sub(title, #Ladders.TITLE_PREFIX + 1))
end

-- the rung's name ("Gold"); Legend for the Legend badge; nil below Bronze
function Ladders.RungName(ladder: string, rung: number): string?
	if ladder == "Legend" then
		return if rung > 0 then "Legend" else nil
	end
	return Ladders.RUNGS[rung]
end

-- the group's fandom name ("MY" for aespa), else the group's own name
function Ladders.Fandom(artist: string): string
	return Packs.FANDOMS[artist] or artist
end

-- "MY · GOLD" / "MY · LEGEND": a badge is its fandom's name and the rung
function Ladders.Label(ladder: string, artist: string, rung: number): string
	return `{Ladders.Fandom(artist)} · {string.upper(Ladders.RungName(ladder, rung) or "")}`
end

-- [[ Cards ]]

-- every group's members with photocards: artist → { member key }
local membersCache: { [string]: { string } }? = nil
local function members(): { [string]: { string } }
	if membersCache then
		return membersCache
	end
	local out, seen = {}, {}
	for _, artist in Albums.Artists() do
		for _, album in Albums.ForArtist(artist) do
			if Albums.HasArt(album) then
				out[artist] = out[artist] or {}
				seen[artist] = seen[artist] or {}
				for _, member in album.Members do
					if not seen[artist][member.Key] then
						seen[artist][member.Key] = true
						table.insert(out[artist], member.Key)
					end
				end
			end
		end
	end
	membersCache = out
	return out
end

-- each member's best card rank and how many different cards, for one group
local function cardStats(cards: { [string]: number }, artist: string): ({ [string]: number }, number)
	local best, count = {}, 0
	for id, copies in cards do
		if type(copies) == "number" and copies > 0 then
			local info = Albums.Card(id)
			if info and info.Album.Artist == artist then
				count += 1
				local rank = Albums.RarityRank(info.Rarity.Key)
				best[info.Member.Key] = math.max(best[info.Member.Key] or 0, rank)
			end
		end
	end
	return best, count
end

-- the cards rung (0–5) and what the next one needs
function Ladders.CardsRung(cards: { [string]: number }, artist: string)
	local list = members()[artist]
	if not list or #list == 0 or not Ladders.HasSongs(artist) then
		return 0, nil
	end
	local best, count = cardStats(cards, artist)
	local function covered(rarityKey: string): number
		local need, n = Albums.RarityRank(rarityKey), 0
		for _, key in list do
			if (best[key] or 0) >= need then
				n += 1
			end
		end
		return n
	end
	local rung = 0
	if count >= Ladders.CARDS_BRONZE then
		rung = 1
		for r = 2, Ladders.TOP do
			if covered(CARD_RARITY[r]) >= #list then
				rung = r
			else
				break
			end
		end
	end
	if rung >= Ladders.TOP then
		return rung, nil
	end
	local nextRung = rung + 1
	if nextRung == 1 then
		return rung, { Have = count, Need = Ladders.CARDS_BRONZE, Text = `{Ladders.CARDS_BRONZE} different cards` }
	end
	local key = CARD_RARITY[nextRung]
	local text = if key == "standard" then "a card of every member" else `every member {RARITY_TEXT[key]}`
	return rung, { Have = covered(key), Need = #list, Text = text }
end

-- [[ Songs ]]

-- the songs rung (0–5) and what the next one needs (nil: top, or too few songs)
function Ladders.SongsRung(mastery: { [string]: string }, artist: string)
	local ids = Mastery.GroupSongs(artist)
	if #ids < Ladders.SONGS_MIN then
		return 0, nil
	end
	local one, two, three = 0, 0, 0
	local missing: { [number]: { string } } = { {}, {}, {} } -- songs short of 1 / 2 / 3 stars
	for _, id in ids do
		local stars = Mastery.Stars(mastery[id])
		if stars >= 1 then
			one += 1
		end
		if stars >= 2 then
			two += 1
		end
		if stars >= 3 then
			three += 1
		end
		for s = stars + 1, 3 do
			table.insert(missing[s], id)
		end
	end
	local n = #ids
	local half = math.ceil(n / 2)
	local checks = {
		{ Have = one, Need = math.min(Ladders.SONGS_BRONZE, n), Text = `{math.min(Ladders.SONGS_BRONZE, n)} songs guessed right`, Stars = 1 },
		{ Have = one, Need = n, Text = "every song ★", Stars = 1 },
		{ Have = two, Need = n, Text = "every song ★★", Stars = 2 },
		{ Have = three, Need = half, Text = "half the songs ★★★", Stars = 3 },
		{ Have = three, Need = n, Text = "every song ★★★", Stars = 3 },
	}
	local rung = 0
	for r, check in checks do
		if check.Have >= check.Need then
			rung = r
		else
			break
		end
	end
	local nextCheck = checks[rung + 1]
	if not nextCheck then
		return rung, nil
	end
	return rung, { Have = nextCheck.Have, Need = nextCheck.Need, Text = nextCheck.Text, Missing = missing[nextCheck.Stars] }
end

-- does this group have a songs ladder?
function Ladders.HasSongs(artist: string): boolean
	return #Mastery.GroupSongs(artist) >= Ladders.SONGS_MIN
end

-- can this group's ladders be climbed? (photocards and at least SONGS_MIN songs)
function Ladders.Eligible(artist: string): boolean
	local list = members()[artist]
	return list ~= nil and #list > 0 and Ladders.HasSongs(artist)
end

-- every group with ladders (Eligible), A–Z
function Ladders.Groups(): { string }
	local out = {}
	for artist in members() do
		if Ladders.Eligible(artist) then
			table.insert(out, artist)
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

-- the coins for rungs from+1 … to on one ladder
function Ladders.CoinsBetween(ladder: string, from: number, to: number): number
	local list, total = Ladders.COINS[ladder], 0
	for r = from + 1, to do
		total += list[r] or 0
	end
	return total
end

return Ladders
