--| checkaudio
-- Tests every song's audio on YOUR client (audio permissions are per experience, so run it
-- in a published server, or in Studio Play for a first pass). Loads each MusicId, then checks
-- it loaded, has a length, and that TimePosition / ChorusPosition fall inside it. Results go to
-- the Output (F9 in a live server): one line per problem, then a summary.
--   checkaudio            – the songs in the game
--   checkaudio true       – drafts too (to see which drafted songs work again)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local LOAD_TIMEOUT = 10 -- seconds per song
local PARALLEL = 6

-- every song from the library modules (Songs/<Company>/<Group>), drafts included when asked
local function allSongs(withDrafts: boolean)
	local out = {}
	local root = ReplicatedStorage.Modules.Library.Songs
	for _, folder in root:GetChildren() do
		if folder:IsA("Folder") then
			for _, module in folder:GetChildren() do
				if module:IsA("ModuleScript") then
					local ok, group = pcall(require, module)
					if ok and type(group) == "table" and type(group.Songs) == "table" then
						for _, song in group.Songs do
							if withDrafts or not song.Draft then
								table.insert(out, {
									Label = `{song.Name} - {group.Group or module.Name}`,
									File = `{folder.Name}/{module.Name}`,
									Song = song,
								})
							end
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Label < b.Label
	end)
	return out
end

local function check(entry): (string?, string?)
	local song = entry.Song
	local id = song.MusicId
	if type(id) ~= "string" or id == "" then
		return "FAIL", "no MusicId"
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0
	sound.Parent = SoundService
	local status
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { sound }, function(_, s)
			status = s
		end)
	end)
	local deadline = os.clock() + LOAD_TIMEOUT
	while not sound.IsLoaded and os.clock() < deadline and status ~= Enum.AssetFetchStatus.Failure do
		task.wait(0.1)
	end
	local loaded, length = sound.IsLoaded, sound.TimeLength
	sound:Destroy()
	if status == Enum.AssetFetchStatus.Failure then
		return "FAIL", "asset failed to load (deleted, moderated, or no permission for this experience)"
	end
	if not loaded then
		return "FAIL", `didn't load within {LOAD_TIMEOUT}s`
	end
	if length <= 0 then
		return "FAIL", "loaded but has no length"
	end
	local tp = song.TimePosition
	if type(tp) == "number" and tp >= length then
		return "FAIL", `TimePosition {tp} is past the end ({string.format("%.1f", length)}s)`
	end
	local chorus = song.ChorusPosition
	if type(chorus) == "number" and chorus >= length then
		return "WARN", `ChorusPosition {chorus} is past the end ({string.format("%.1f", length)}s)`
	end
	if tp == 0 and (chorus == 0 or chorus == nil) then
		return "TUNE", "starts at 0:00 (not tuned yet)"
	end
	return nil
end

local function run(context, withDrafts: boolean)
	local songs = allSongs(withDrafts)
	local results = { FAIL = {}, WARN = {}, TUNE = {} }
	local done, nextIndex = 0, 1
	local started = os.clock()
	print(`[checkaudio] checking {#songs} songs{if withDrafts then " (drafts included)" else ""}…`)

	local function worker()
		while nextIndex <= #songs do
			local entry = songs[nextIndex]
			nextIndex += 1
			local ok, kind, why = pcall(check, entry)
			if not ok then
				kind, why = "FAIL", `check errored: {kind}`
			end
			if kind then
				local draft = if entry.Song.Draft then " [draft]" else ""
				table.insert(results[kind], `{kind}  {entry.Label}{draft}  ({entry.File})  {why}  {entry.Song.MusicId or ""}`)
			end
			done += 1
		end
	end
	local threads = {}
	for _ = 1, PARALLEL do
		table.insert(threads, task.spawn(worker))
	end
	while done < #songs do
		task.wait(0.25)
	end

	for _, kind in { "FAIL", "WARN", "TUNE" } do
		table.sort(results[kind])
		for _, line in results[kind] do
			if kind == "FAIL" then
				warn(line)
			else
				print(line)
			end
		end
	end
	local summary = `[checkaudio] {#songs} songs in {math.floor(os.clock() - started)}s · {#results.FAIL} failed · {#results.WARN} warnings · {#results.TUNE} still at 0:00 · {#songs - #results.FAIL - #results.WARN - #results.TUNE} fine`
	print(summary)
	pcall(context.Reply, context, summary .. " (details in the Output, F9)")
end

return {
	Name = "checkaudio",
	Aliases = { "audiocheck" },
	Description = "Tests every song's audio on your client and lists the ones that fail (Output / F9).",
	Group = "Testing",
	Args = {
		{ Type = "boolean", Name = "drafts", Description = "Also test draft songs", Optional = true },
	},
	ClientRun = function(context, withDrafts: boolean?)
		task.spawn(run, context, withDrafts == true)
		return "Checking every song's audio… the results print to the Output (F9) when it's done."
	end,
}
