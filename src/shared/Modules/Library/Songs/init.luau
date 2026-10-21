--| Songs
-- Every song from the Easy/Medium/Hard lists, flattened into one pool.
-- Each song gets an `Id` ("Name - Artist", unique) and its `Difficulty`.

local Songs = {}

local All = {}
local ById = {}

for _, list in script:GetChildren() do
	if list:IsA("ModuleScript") then
		for _, song in require(list) do
			local entry = table.clone(song)
			entry.Difficulty = list.Name
			entry.Id = `{song.Name} - {song.Artist}`
			if not ById[entry.Id] then
				ById[entry.Id] = entry
				table.insert(All, entry)
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

function Songs.GetSongsByDifficulty(difficulty: string)
	return filter("Difficulty", difficulty)
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
	return { Id = song.Id, Name = song.Name, Artist = song.Artist, Generation = song.Generation }
end

return Songs
