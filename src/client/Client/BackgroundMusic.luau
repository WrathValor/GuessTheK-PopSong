--| BackgroundMusic
-- The lobby playlist: every Sound inside SoundService.Background, played in name order
-- (KPOP_Cafe_Music_part01of14 … part14of14). When a part ends the next one starts straight
-- away, and after the last it wraps back to part 1.
--
-- Duck() fades it out and pauses when a duel's rounds start (the snippets need silence);
-- Resume() picks it back up from the same spot and fades in when the duel is over.
-- The Background SoundGroup's volume follows Settings.MusicVolume (see Sounds.SetMusicVolume).
--
-- Your own background music: a Rainbow card set from the Index (Profile.BgMusic, mirrored to
-- the "BgMusic" attribute by Engine/ProfileService) plays on a loop instead of the playlist,
-- through the same group (so the Music slider and mute cover it) and ducks the same way.
-- Clearing it picks the playlist back up where it paused.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Songs = require(ReplicatedStorage.Modules.Library.Songs)
local SongClips = require(ReplicatedStorage.Modules.SongClips) -- your song's audio, from the server

local FADE_OUT = 0.8
local FADE_IN = 1.5
local SONG_VOLUME = 0.5 -- your own song, under the group's volume (the playlist parts are ~0.5)

local BackgroundMusic = {}

local tracks: { Sound } = {}
local volumes: { [Sound]: number } = {} -- each part's volume as set in Studio
local index = 0
local current: Sound? = nil
local ducked = false
local fadeTweens: { [Sound]: Tween } = {} -- one per sound, so a fade-in never cancels another's fade-out
local group: SoundGroup? = nil
local mine: Sound? = nil -- your own background song, while one is set

local function fade(sound: Sound, to: number, time: number): Tween
	local old = fadeTweens[sound]
	if old then
		old:Cancel()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(time, Enum.EasingStyle.Sine), { Volume = to })
	fadeTweens[sound] = tween
	tween.Completed:Once(function()
		if fadeTweens[sound] == tween then
			fadeTweens[sound] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Starts part `i` from the beginning.
local function playIndex(i: number)
	if #tracks == 0 or mine then
		return
	end
	index = ((i - 1) % #tracks) + 1
	if current and current ~= tracks[index] then
		current:Stop()
	end
	current = tracks[index]
	local sound = current :: Sound
	sound.TimePosition = 0
	sound.Volume = if ducked then 0 else volumes[sound]
	if not ducked then
		sound:Play()
	end
	-- warm up the part after this one so the hand-over is instant
	local nextSound = tracks[(index % #tracks) + 1]
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { nextSound })
	end)
end

-- Quiet down and pause (keeps the spot).
function BackgroundMusic.Duck()
	if ducked then
		return
	end
	ducked = true
	local sound = current
	if sound and sound.IsPlaying then
		fade(sound, 0, FADE_OUT).Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and ducked and current == sound then
				sound:Pause()
			end
		end)
	end
end

-- Carry on from where it paused, fading back in.
function BackgroundMusic.Resume()
	if not ducked then
		return
	end
	ducked = false
	local sound = current
	if not sound then
		playIndex(1)
		return
	end
	if not sound.IsPlaying then
		sound:Resume()
	end
	fade(sound, volumes[sound] or SONG_VOLUME, FADE_IN)
end

-- [[ Your own song ]]

local function speedOf(song): number
	local speed = song.PlaybackSpeed or song.Pitch or 1
	return if type(speed) == "number" and speed > 0 then speed else 1
end

local wanted: string? = nil -- the song SetSong was last asked for (its clip may still be on its way)

-- id = a song id (your Rainbow card), or nil / "" for the playlist
function BackgroundMusic.SetSong(id: string?)
	local song = if id and id ~= "" then Songs.GetById(id) else nil
	if mine and song and mine:GetAttribute("SongId") == song.Id then
		return -- already playing it
	end
	wanted = song and song.Id
	if not song then
		BackgroundMusic._applySong(nil, nil)
		return
	end
	SongClips.Get(song.Id):andThen(function(clip)
		if wanted == song.Id then
			BackgroundMusic._applySong(song, clip)
		end
	end)
end

-- swaps to `song` (with its clip from the server), or back to the playlist with no clip
function BackgroundMusic._applySong(song, clip)
	local musicId = clip and clip.MusicId
	-- out with your previous song, if any
	if mine then
		local sound = mine
		mine = nil
		volumes[sound] = nil
		fade(sound, 0, FADE_OUT).Completed:Once(function()
			sound:Destroy()
		end)
	end
	-- your song replaces the playlist: fade the part out and pause it (it keeps its spot)
	if type(musicId) == "string" and musicId ~= "" then
		local part = tracks[index]
		if part and part.IsPlaying then
			fade(part, 0, FADE_OUT).Completed:Once(function()
				if mine then
					part:Pause()
				end
			end)
		end
	end
	if type(musicId) == "string" and musicId ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = "MyBackgroundSong"
		sound.SoundId = musicId
		sound.PlaybackSpeed = speedOf(clip)
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = group
		sound:SetAttribute("SongId", song.Id)
		sound.Parent = group or SoundService
		volumes[sound] = SONG_VOLUME
		mine = sound
		current = sound
		if not ducked then
			sound:Play()
			fade(sound, SONG_VOLUME, FADE_IN)
		end
	else
		-- back to the playlist, where it paused
		current = tracks[index]
		local part = current
		if part and not ducked then
			if part.TimePosition > 0 then
				part:Resume()
			else
				part:Play()
			end
			fade(part, volumes[part], FADE_IN)
		elseif not part then
			playIndex(1)
		end
	end
end

function BackgroundMusic.Start()
	group = SoundService:WaitForChild("Background", 10) :: SoundGroup?
	if not group then
		warn("[BackgroundMusic] SoundService.Background not found")
		return
	end
	for _, child in group:GetChildren() do
		if child:IsA("Sound") then
			table.insert(tracks, child)
		end
	end
	-- part01of14, part02of14 … (zero-padded names sort correctly)
	table.sort(tracks, function(a, b)
		return a.Name < b.Name
	end)
	for _, sound in tracks do
		volumes[sound] = sound.Volume
		sound.Looped = false
		sound.SoundGroup = group -- parented under the group isn't enough; this routes the volume
		sound.Ended:Connect(function()
			if sound == current and not ducked then
				playIndex(index + 1)
			end
		end)
	end
	if #tracks == 0 then
		warn("[BackgroundMusic] no Sounds in SoundService.Background")
		return
	end
	playIndex(1)
	-- your own song (set from the Index), now and whenever it changes
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("BgMusic"):Connect(function()
		BackgroundMusic.SetSong(player:GetAttribute("BgMusic"))
	end)
	BackgroundMusic.SetSong(player:GetAttribute("BgMusic"))
end

return BackgroundMusic
