--| MeasureLoudness (Studio tool, Edit mode)
-- Measures how loud every live song's snippet is, so each song's Volume can be set to
-- make them all play at the same loudness. A loud master would otherwise make the
-- 0.1 s tier easier than a quiet one, which isn't fair in a duel.
--
-- How: each song plays silently into an AudioAnalyzer (no output wired, so you hear nothing)
-- from its snippet start for the full snippet (15 s, the last Song tier), at its
-- PlaybackSpeed. Frames quieter than GATE_DB are skipped (silence/breaks), the rest are
-- averaged as power. It's an unweighted RMS loudness, close to LUFS for pop music.
--
-- Run from the command bar in Edit (takes a few minutes; output in the console):
--   require(game.ServerStorage.Tools.MeasureLoudness).Run()
-- It prints one line per song plus the suggested Volume, and keeps the results in
-- _G.Loudness = { Target, Songs = { { File, Name, Db, Volume } } } for tooling to read.
--
-- Volume = 10^((Target − Db) / 20), Target = the median song, rounded to 0.05 and
-- clamped to MIN_VOLUME..MAX_VOLUME. Write a song's Volume only when it isn't 1 (Songs/init).

local MeasureLoudness = {}

--| Tunables

local SECONDS = 15 -- measured from the snippet start: the full snippet (last Song tier)
local BATCH = 30 -- songs measured at once
local GATE_DB = -50 -- frames below this count as silence and are skipped
local MIN_VOLUME, MAX_VOLUME = 0.5, 6
local LOAD_TIMEOUT = 15

--| Helpers

local function db(power: number): number
	return 10 * math.log10(math.max(power, 1e-12))
end

-- plays one song silently and returns its gated loudness in dB (nil if it never loaded)
local function measure(song, parent: Instance): number?
	local clip = song.Clip
	local folder = Instance.new("Folder")
	local player = Instance.new("AudioPlayer")
	player.Asset = clip.MusicId
	player.PlaybackSpeed = clip.PlaybackSpeed or 1
	player.Parent = folder
	local analyzer = Instance.new("AudioAnalyzer")
	analyzer.Parent = folder
	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = analyzer
	wire.Parent = folder
	folder.Parent = parent

	local started = os.clock()
	while not player.IsReady and os.clock() - started < LOAD_TIMEOUT do
		task.wait()
	end
	if not player.IsReady then
		folder:Destroy()
		return nil
	end

	player.TimePosition = clip.TimePosition or player.TimeLength / 2
	player:Play()
	local sum, count = 0, 0
	local stop = os.clock() + SECONDS / (clip.PlaybackSpeed or 1)
	while os.clock() < stop and player.IsPlaying do
		task.wait()
		local power = analyzer.RmsLevel ^ 2
		if db(power) > GATE_DB then
			sum += power
			count += 1
		end
	end
	player:Stop()
	folder:Destroy()
	return if count > 0 then db(sum / count) else nil
end

--| Functions

function MeasureLoudness.Run()
	local Songs = require(game:GetService("ServerScriptService").Songs:Clone())
	local songs = Songs.Raw(false)
	local parent = Instance.new("Folder")
	parent.Name = "__MeasureLoudness"
	parent.Parent = workspace

	local results = {}
	for first = 1, #songs, BATCH do
		local pending = 0
		for i = first, math.min(first + BATCH - 1, #songs) do
			pending += 1
			task.spawn(function()
				local ok, value = pcall(measure, songs[i], parent)
				results[i] = if ok then value else nil
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(0.25)
		end
		print(`[MeasureLoudness] {math.min(first + BATCH - 1, #songs)}/{#songs}`)
	end
	parent:Destroy()

	local levels = {}
	for i = 1, #songs do
		if results[i] then
			table.insert(levels, results[i])
		end
	end
	table.sort(levels)
	local target = levels[math.max(1, math.floor(#levels / 2))] or 0

	local out = { Target = target, Songs = {} }
	for i, song in songs do
		local level = results[i]
		local volume = if level
			then math.clamp(math.round(10 ^ ((target - level) / 20) * 20) / 20, MIN_VOLUME, MAX_VOLUME)
			else nil
		table.insert(out.Songs, { File = song.File, Name = song.Name, Db = level, Volume = volume })
		print(
			if level
				then string.format("%-48s %6.1f dB  Volume %.2f", song.Label, level, volume)
				else `{song.Label}  (didn't load)`
		)
	end
	print(string.format("[MeasureLoudness] target %.1f dB over %d songs", target, #levels))
	_G.Loudness = out
	return out
end

return MeasureLoudness
