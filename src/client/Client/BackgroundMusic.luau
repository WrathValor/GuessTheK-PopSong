--| BackgroundMusic
-- The lobby playlist: every Sound inside SoundService.Background, played in name order
-- (KPOP_Cafe_Music_part01of14 … part14of14). When a part ends the next one starts straight
-- away, and after the last it wraps back to part 1.
--
-- Duck() fades it out and pauses when a duel's rounds start (the snippets need silence);
-- Resume() picks it back up from the same spot and fades in when the duel is over.
-- The Background SoundGroup's volume follows Settings.MusicVolume (see Sounds.SetMusicVolume).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local FADE_OUT = 0.8
local FADE_IN = 1.5

local BackgroundMusic = {}

local tracks: { Sound } = {}
local volumes: { [Sound]: number } = {} -- each part's volume as set in Studio
local index = 0
local current: Sound? = nil
local ducked = false
local fadeTween: Tween? = nil

local function fade(sound: Sound, to: number, time: number): Tween
	if fadeTween then
		fadeTween:Cancel()
	end
	fadeTween = TweenService:Create(sound, TweenInfo.new(time, Enum.EasingStyle.Sine), { Volume = to })
	fadeTween:Play()
	return fadeTween
end

-- Starts part `i` from the beginning.
local function playIndex(i: number)
	if #tracks == 0 then
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
	fade(sound, volumes[sound], FADE_IN)
end

function BackgroundMusic.Start()
	local group = SoundService:WaitForChild("Background", 10) :: SoundGroup?
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
end

return BackgroundMusic
