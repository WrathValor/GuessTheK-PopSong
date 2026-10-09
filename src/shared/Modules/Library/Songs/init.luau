--| Songs

local Songs = {};

--| Require

for _, Song in script:GetChildren() do
    if Song:IsA("ModuleScript") then
        Songs[Song.Name] = require(Song)
    end
end

--| Functions

function Songs.GetAllSongs()
    local AllSongs = {}
    for _, Song in pairs(Songs) do
        table.insert(AllSongs, Song)
    end
    return AllSongs
end

function Songs.GetRandomSong()
    local AllSongs = Songs.GetAllSongs()
    return AllSongs[math.random(1, #AllSongs)]
end

function Songs.GetSongsByDifficulty(Difficulty: "Easy" | "Medium" | "Hard")
    local FilteredSongs = {}
    for _, Song in pairs(Songs) do
        if Song.Difficulty == Difficulty then
            table.insert(FilteredSongs, Song)
        end
    end
    return FilteredSongs
end

function Songs.GetSongsByGeneration(Generation: string)
    local FilteredSongs = {}
    for _, Song in pairs(Songs) do
        if Song.Generation == Generation then
            table.insert(FilteredSongs, Song)
        end
    end
    return FilteredSongs
end

function Songs.GetSongsByStatus(Status: "Active" | "Disbanded")
    local FilteredSongs = {}
    for _, Song in pairs(Songs) do
        if Song.Status == Status then
            table.insert(FilteredSongs, Song)
        end
    end
    return FilteredSongs
end

function Songs.GetSongsByCompany(Company: string)
    local FilteredSongs = {}
    for _, Song in pairs(Songs) do
        if Song.Company == Company then
            table.insert(FilteredSongs, Song)
        end
    end
    return FilteredSongs
end

function Songs.GetSongsByGroupType(GroupType: "Boy" | "Girl" | "Mixed")
    local FilteredSongs = {}
    for _, Song in pairs(Songs) do
        if Song.GroupType == GroupType then
            table.insert(FilteredSongs, Song)
        end
    end
    return FilteredSongs
end

function Songs.GetSongsByArtist(Artist: string)
    local FilteredSongs = {}
    for _, Song in pairs(Songs) do
        if Song.Artist == Artist then
            table.insert(FilteredSongs, Song)
        end
    end
    return FilteredSongs
end

function Songs.GetSongByName(Name: string)
    for _, Song in pairs(Songs) do
        if Song.Name == Name then
            return Song
        end
    end
    return nil
end

--| Return
return Songs