--| Songs
-- The song library, one module per group, in a folder per company:
--   Songs/<Company>/<Group>.luau   e.g. Songs/HYBE/BTS.luau, Songs/YG/BLACKPINK.luau
-- The folder name is the song's Company. A group module returns:
--   Group       "BTS"                        shown as the artist on answers and cards
--   GroupType   "Boy" | "Girl" | "Co-ed" | "Solo"
--   Generation  "2nd" | "3rd" | "4th" | "5th"  wrong answers come from the same generation
--   Status      "Active" | "Hiatus" | "Disbanded"
--   Colour      "FF9EC4"  pastel hex: the group's card art + glow on the roll reveal
--   Gradient    ColorSequence of the group's real colours (official where they have one);
--               use it on a UIGradient. Optional: groups without one just have Colour
--   Songs       list of songs:
--     Name            "Dynamite"
--     Year            2020 (release year)
--     MusicId         audio asset (the snippet + reveal)
--     AnimationId     dance animation (Choreography mode)
--     PlaybackSpeed   playback speed the audio needs to sound right (default 1)
--     TimePosition    where the snippet starts, in the audio's own seconds (default: halfway)
--     ChorusPosition  where the reveal plays from (default: TimePosition)
--     Volume          only when it isn't 1
--     Draft = true    keeps a song out of the game (audio not checked yet)
-- New group: add a module to its company folder (make the folder for a new company).
-- Song Tuner (plugins/SongTuner) edits PlaybackSpeed/TimePosition/ChorusPosition/Volume in
-- these modules for you.
--
-- Every song is flattened into one pool with the group fields copied onto it, plus
-- Artist (= Group), Company and Id ("Name - Artist", unique; saved in player data, so
-- don't rename songs or groups once players own them).

local Songs = {}

local All = {}
local ById = {}
local ByGeneration = {}

local function load(module: ModuleScript, company: string)
	local ok, group = pcall(require, module)
	if not ok or type(group) ~= "table" or type(group.Songs) ~= "table" then
		warn(`[Songs] {module:GetFullName()} isn't a group module: {group}`)
		return
	end
	local artist = group.Group or module.Name
	for _, song in group.Songs do
		if not song.Draft then
			local entry = table.clone(song)
			entry.Artist = artist
			entry.Company = company
			entry.GroupType = group.GroupType
			entry.Generation = group.Generation
			entry.Status = group.Status
			entry.Colour = group.Colour
			entry.Gradient = group.Gradient
			entry.Id = `{song.Name} - {artist}`
			if ById[entry.Id] then
				warn(`[Songs] duplicate song {entry.Id} in {module:GetFullName()}`)
			else
				ById[entry.Id] = entry
				table.insert(All, entry)
			end
		end
	end
end

for _, folder in script:GetChildren() do
	if folder:IsA("Folder") then
		for _, module in folder:GetChildren() do
			if module:IsA("ModuleScript") then
				load(module, folder.Name)
			end
		end
	end
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
