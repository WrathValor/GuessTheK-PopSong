--| Songs
-- The song library as everything outside ServerScriptService sees it. Same API on both sides
-- (All, GetById, GetAllSongs, Pick, GetWrongOptions, Public, …), so nothing that requires it
-- has to care where it runs:
--   • server: every song, clip assets included, from ServerScriptService.Songs (the group
--     modules live there now: edit songs in src/server/Songs/<Company>/<Group>.luau).
--     Songs.Clip(song) gives the assets a client needs to play one.
--   • client: the public catalog only (Id, Name, Year, Artist, Company, GroupType,
--     Generation, Status, Colour, Gradient). No MusicId / AnimationId / tuning, so an exploit
--     can't match a round's clip to its answer. The server publishes it once, as the
--     "Catalog" StringValue under this module; a song's audio comes from Modules/SongClips.

--| Services

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

--| Variables

local CATALOG = "Catalog" -- the StringValue under this module the server writes
local CATALOG_WAIT = 30

local Songs = {}

--| Catalog
-- JSON, one entry per group: { C = company, A = artist, T = group type, G = generation,
-- S = status, K = colour, R = gradient { { time, hex }, … }, L = { { name, year }, … } }

local function encodeGradient(gradient: ColorSequence?)
	if typeof(gradient) ~= "ColorSequence" then
		return nil
	end
	local keys = {}
	for _, k in gradient.Keypoints do
		table.insert(keys, { k.Time, k.Value:ToHex() })
	end
	return keys
end

local function decodeGradient(keys): ColorSequence?
	if type(keys) ~= "table" or #keys < 2 then
		return nil
	end
	local points = {}
	for _, k in keys do
		table.insert(points, ColorSequenceKeypoint.new(k[1], Color3.fromHex(k[2])))
	end
	return ColorSequence.new(points)
end

local function publish(entries)
	local groups, order = {}, {}
	for _, song in entries do
		local key = `{song.Company}/{song.Artist}`
		local group = groups[key]
		if not group then
			group = {
				C = song.Company,
				A = song.Artist,
				T = song.GroupType,
				G = song.Generation,
				S = song.Status,
				K = song.Colour,
				R = encodeGradient(song.Gradient),
				L = {},
			}
			groups[key] = group
			table.insert(order, group)
		end
		table.insert(group.L, { song.Name, song.Year })
	end
	local value = script:FindFirstChild(CATALOG) or Instance.new("StringValue")
	value.Name = CATALOG
	value.Value = HttpService:JSONEncode(order)
	value.Parent = script
end

local function readCatalog()
	local value = script:WaitForChild(CATALOG, CATALOG_WAIT) :: StringValue?
	if not value then
		warn("[Songs] no song catalog from the server")
		return {}
	end
	local ok, order = pcall(HttpService.JSONDecode, HttpService, value.Value)
	if not ok or type(order) ~= "table" then
		warn("[Songs] couldn't read the song catalog:", order)
		return {}
	end
	local entries = {}
	for _, group in order do
		local gradient = decodeGradient(group.R)
		for _, pair in group.L do
			table.insert(entries, {
				Id = `{pair[1]} - {group.A}`,
				Name = pair[1],
				Year = pair[2],
				Artist = group.A,
				Company = group.C,
				GroupType = group.T,
				Generation = group.G,
				Status = group.S,
				Colour = group.K,
				Gradient = gradient,
			})
		end
	end
	return entries
end

--| Library

local All = {}
local ById = {}
local ByGeneration = {}

local entries
-- (Edit mode counts as a client to RunService, but the command bar, plugins and the UI
-- builders can read ServerScriptService there, so they get the full library too)
if RunService:IsServer() or not RunService:IsRunning() then
	local library = require(game:GetService("ServerScriptService"):WaitForChild("Songs"))
	entries = library.Load()
	Songs.Clip = library.Clip
	-- (not in Edit: the command bar / Song Tuner mustn't leave a Catalog in the place)
	if RunService:IsRunning() then
		publish(entries)
	end
else
	entries = readCatalog()
end

for _, song in entries do
	ById[song.Id] = song
	table.insert(All, song)
end

table.sort(All, function(a, b)
	return a.Id < b.Id
end)

-- The library is static after module load, so keep generation pools ready for duel answers.
for _, song in All do
	if song.Generation then
		local pool = ByGeneration[song.Generation]
		if not pool then
			pool = {}
			ByGeneration[song.Generation] = pool
		end
		table.insert(pool, song)
	end
end

Songs.All = All

--| Functions

function Songs.GetAllSongs()
	return All
end

function Songs.GetById(id: string)
	return ById[id]
end

-- A random song from `pool`. `weight(song)` (optional) makes some songs likelier: a song
-- with weight 3 is three times as likely as one with weight 1 (duels use it for owned songs).
function Songs.Pick(pool: { any }, weight: ((any) -> number)?)
	if #pool == 0 then
		return nil
	end
	if not weight then
		return pool[math.random(1, #pool)]
	end
	local total = 0
	local weights = table.create(#pool)
	for i, song in pool do
		weights[i] = math.max(0, weight(song))
		total += weights[i]
	end
	local roll = math.random() * total
	for i, w in weights do
		roll -= w
		if roll < 0 then
			return pool[i]
		end
	end
	return pool[#pool]
end

function Songs.GetRandomSong(exclude: { [string]: boolean }?, weight: ((any) -> number)?)
	local pool = {}
	for _, song in All do
		if not (exclude and exclude[song.Id]) then
			table.insert(pool, song)
		end
	end
	return Songs.Pick(pool, weight)
end

-- A random song of one generation ("2nd".."5th"), else from the whole library.
function Songs.GetRandomSongOfGeneration(generation: string?, exclude: { [string]: boolean }?, weight: ((any) -> number)?)
	if generation then
		local pool = {}
		for _, song in All do
			if song.Generation == generation and not (exclude and exclude[song.Id]) then
				table.insert(pool, song)
			end
		end
		if #pool > 0 then
			return Songs.Pick(pool, weight)
		end
	end
	return Songs.GetRandomSong(exclude, weight)
end

-- Every generation in the library, sorted ("2nd", "3rd", "4th", "5th").
function Songs.Generations(): { string }
	local seen, out = {}, {}
	for _, song in All do
		if song.Generation and not seen[song.Generation] then
			seen[song.Generation] = true
			table.insert(out, song.Generation)
		end
	end
	table.sort(out)
	return out
end

local function filter(key: string, value: any)
	local out = {}
	for _, song in All do
		if song[key] == value then
			table.insert(out, song)
		end
	end
	return out
end

function Songs.GetSongsByGeneration(generation: string)
	return table.clone(ByGeneration[generation] or {})
end
function Songs.GetSongsByStatus(status: string)
	return filter("Status", status)
end
function Songs.GetSongsByCompany(company: string)
	return filter("Company", company)
end
function Songs.GetSongsByGroupType(groupType: string)
	return filter("GroupType", groupType)
end
function Songs.GetSongsByArtist(artist: string)
	return filter("Artist", artist)
end
function Songs.GetSongsByYear(year: number)
	return filter("Year", year)
end
function Songs.GetSongByName(name: string)
	for _, song in All do
		if song.Name == name then
			return song
		end
	end
	return nil
end

-- `count` wrong options for `answer`, drawn from across the generations (the answer's own
-- generation is only slightly favoured, so a round can mix 2nd, 3rd and 4th gen) and never
-- two from the same artist (nor the answer's artist) while the pool has enough artists.
-- `within` (a solo theme's songs, a party's custom pool) is used first, so a themed game's
-- options all come from the theme; a one-group theme falls back to repeating the artist.
local SAME_GEN_WEIGHT = 1.5 -- vs 1 for any other generation

function Songs.GetWrongOptions(answer, count: number, within: { any }?)
	local picked = {}
	local usedIds = { [answer.Id] = true }
	local usedArtists = { [answer.Artist] = true }
	-- one weighted pick at a time from `pool` (a new artist only, when `newArtist`)
	local function fill(pool, newArtist: boolean)
		while #picked < count do
			local total, candidates, weights = 0, {}, {}
			for _, song in pool do
				if not usedIds[song.Id] and not (newArtist and usedArtists[song.Artist]) then
					local w = if song.Generation == answer.Generation then SAME_GEN_WEIGHT else 1
					total += w
					table.insert(candidates, song)
					table.insert(weights, w)
				end
			end
			if #candidates == 0 then
				return
			end
			local roll = math.random() * total
			local chosen = candidates[#candidates]
			for i, song in candidates do
				roll -= weights[i]
				if roll <= 0 then
					chosen = song
					break
				end
			end
			usedIds[chosen.Id] = true
			usedArtists[chosen.Artist] = true
			table.insert(picked, chosen)
		end
	end
	if within then
		fill(within, true)
		fill(within, false)
	end
	fill(All, true)
	fill(All, false)
	return picked
end

-- What the client needs to show an option. Never includes clip assets.
function Songs.Public(song)
	return { Id = song.Id, Name = song.Name, Artist = song.Artist, Generation = song.Generation, Year = song.Year, Colour = song.Colour }
end

return Songs
