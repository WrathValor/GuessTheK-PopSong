--| Songs
-- The song library, one module per group, in a folder per company:
--   Songs/<Company>/<Group>.luau   e.g. Songs/HYBE/BTS.luau, Songs/YG/BLACKPINK.luau
-- The folder name is the song's Company. A group module returns:
--   Group       "BTS"                        shown as the artist on answers and cards
--   GroupType   "Boy" | "Girl" | "Co-ed" | "Solo"
--   Generation  "2nd" | "3rd" | "4th" | "5th"  wrong answers come from the same generation
--   Status      "Active" | "Hiatus" | "Disbanded"
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

Songs.All = All

--| Functions

function Songs.GetAllSongs()
	return All
end

function Songs.GetById(id: string)
	return ById[id]
end

function Songs.GetRandomSong(exclude: { [string]: boolean }?)
	local pool = {}
	for _, song in All do
		if not (exclude and exclude[song.Id]) then
			table.insert(pool, song)
		end
	end
	return pool[math.random(1, #pool)]
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
	return filter("Generation", generation)
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

-- `count` wrong options for `answer`. Same generation first so the options are fair,
-- then anything else to fill up. Never the same artist+name twice.
function Songs.GetWrongOptions(answer, count: number)
	local picked, used = {}, { [answer.Id] = true }
	local function take(pool)
		local copy = table.clone(pool)
		while #picked < count and #copy > 0 do
			local song = table.remove(copy, math.random(1, #copy))
			if not used[song.Id] then
				used[song.Id] = true
				table.insert(picked, song)
			end
		end
	end
	take(Songs.GetSongsByGeneration(answer.Generation))
	take(All)
	return picked
end

-- What the client needs to show an option. Never includes clip assets.
function Songs.Public(song)
	return { Id = song.Id, Name = song.Name, Artist = song.Artist, Generation = song.Generation, Year = song.Year }
end

return Songs
