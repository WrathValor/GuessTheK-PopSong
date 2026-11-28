--| Songs (server only)
-- The song library, one module per group, in a folder per company:
--   Songs/<Company>/<Group>.luau   e.g. Songs/HYBE/BTS.luau, Songs/YG/BLACKPINK.luau
-- It lives in ServerScriptService so clients never get the audio ids: with every MusicId
-- on the client, an exploit could match a round's clip to its answer instantly. Everything
-- else requires ReplicatedStorage.Modules.Library.Songs, which gets its songs from here on
-- the server and a public catalog (no clip assets) on clients. Clients get a song's audio
-- through Engine/SongService, and only for songs they own.
-- The folder name is the song's Company. A group module returns:
--   Group       "BTS"                        shown as the artist on answers and cards
--   GroupType   "Boy" | "Girl" | "Co-ed" | "Solo"
--   Generation  "2nd" | "3rd" | "4th" | "5th"  wrong answers come from the same generation
--   Status      "Active" | "Hiatus" | "Disbanded"
--   Colour      "FF9EC4"  pastel hex: the group's card art + glow on the roll reveal
--   Gradient    ColorSequence of the group's real colours (official where they have one);
--               use it on a UIGradient. Optional: groups without one just have Colour
--   PackArt     optional "rbxassetid://…": a group photo for the group pack's sleeve (design
--               board "22 · Packs"). Square, faces in the top two thirds. Without it the sleeve
--               is the group's Colour with stripes
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
--   Albums      optional, K-POPPED! photocard albums (Modules/Library/Albums). One era each:
--     Id       "bts-love-yourself"  saved in card ids, so never rename it once it's live
--     Name     "Love Yourself"
--     Year     2018
--     Colour   "FF9EC4"  the era's pastel (default: the group's Colour)
--     Songs    { "FAKE LOVE", … }  names of this group's songs from the era; owning a card
--              from the album makes them "yours" in duels. A song can be in no album.
--     Members  { "RM", "Jin", … }  one photocard per member (card key = the name, lowercased,
--              letters and digits only), in the order the binder shows them
--     Art      optional { ["RM"] = "rbxassetid://…" } member photo for this era
--     Versions optional, soloists: photocards per era (e.g. 5). Members = { "IU" } then gives
--              "IU" (key "iu"), "IU 2" ("iu2") … each needing its own Art entry ["IU 2"]; a
--              version only goes live once it has art. Cards read "IU · Ver. 2" when there's >1
--     Keys     optional { ["HONGJOONG"] = "hoongjoong" }: a member's card key when it isn't their
--              name's (a typo fixed after the album went live; the key is in saved card ids)
--     Cover    optional "rbxassetid://…" the album's own cover, shown on its binder page (without
--              one the page shows the group's PackArt). The card bot sets it: /packart … album:
--     Draft = true    keeps an album out of the game (art not ready yet)
--     Event    optional "winter26": the album is in that event's set (Constants/LiveEvents), not its
--              group's: only the event's pack rolls it, and the binder shows it under Events
--              (Modules/Library/Albums "Event sets"). A group can be in the game with only these.
-- New group: add a module to its company folder (make the folder for a new company).
-- Song Tuner (plugins/SongTuner) edits PlaybackSpeed/TimePosition/ChorusPosition/Volume in
-- these modules for you.
--
-- Every song is flattened into one pool with the group fields copied onto it, plus
-- Artist (= Group), Company and Id ("Name - Artist", unique; saved in player data, so
-- don't rename songs or groups once players own them).
--
-- Songs.Load()            every live song (drafts left out), full entries, sorted by Id
-- Songs.Raw(withDrafts)   { Label, Name, File, Draft, Clip } per song, for checkaudio + tools
-- Songs.Clip(song)        the clip assets a client needs to play a song (rounds, previews)

local Songs = {}

local All = {}
local ById = {}
local AllAlbums = {}

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
	for _, album in if type(group.Albums) == "table" then group.Albums else {} do
		if not album.Draft then
			local entry = table.clone(album)
			entry.Artist = artist
			entry.Company = company
			entry.Colour = album.Colour or group.Colour
			entry.Generation = group.Generation
			entry.GroupType = group.GroupType
			entry.PackArt = group.PackArt
			table.insert(AllAlbums, entry)
		end
	end
end

local function groupModules(): { { Module: ModuleScript, Company: string } }
	local out = {}
	for _, folder in script:GetChildren() do
		if folder:IsA("Folder") then
			for _, module in folder:GetChildren() do
				if module:IsA("ModuleScript") then
					table.insert(out, { Module = module, Company = folder.Name })
				end
			end
		end
	end
	return out
end

for _, entry in groupModules() do
	load(entry.Module, entry.Company)
end

table.sort(All, function(a, b)
	return a.Id < b.Id
end)

--| Functions

function Songs.Load()
	return All
end

-- every live album (drafts left out), with Artist, Company, Colour, Generation and PackArt filled in. Albums hold
-- no audio, so all of this is public (Library/Songs publishes it to clients).
function Songs.Albums()
	return AllAlbums
end

-- What a client needs to play a song: the round's clip, an Index preview, the roll reveal,
-- your Rainbow card as background music. Never send this for a song the player shouldn't hear.
function Songs.Clip(song)
	return {
		MusicId = song.MusicId,
		AnimationId = song.AnimationId,
		-- playbackSpeed is the new field; Pitch is the old name for the same thing
		PlaybackSpeed = song.playbackSpeed or song.PlaybackSpeed or song.Pitch or 1,
		Volume = song.Volume or 1,
		Start = song.Start or 0,
		-- where the snippet starts on the sound's own timeline (what Studio's TimePosition shows)
		TimePosition = song.TimePosition,
		-- where the reveal plays the song from (sound timeline seconds)
		ChorusPosition = song.ChorusPosition,
	}
end

-- Every song straight from the group modules, drafts too when asked (checkaudio).
function Songs.Raw(withDrafts: boolean?)
	local out = {}
	for _, entry in groupModules() do
		local ok, group = pcall(require, entry.Module)
		if ok and type(group) == "table" and type(group.Songs) == "table" then
			for _, song in group.Songs do
				if withDrafts or not song.Draft then
					table.insert(out, {
						Label = `{song.Name} - {group.Group or entry.Module.Name}`,
						Name = song.Name,
						File = `{entry.Company}/{entry.Module.Name}`,
						Draft = song.Draft == true,
						Clip = Songs.Clip(song),
					})
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Label < b.Label
	end)
	return out
end

return Songs
