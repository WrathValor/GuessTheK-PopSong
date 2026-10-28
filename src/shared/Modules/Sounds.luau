-- UI + game sound effects and background music (client only). All IDs are free
-- Creator Store audio, checked to load in this experience. SFX go through the "SFX"
-- SoundGroup and music through the "Music" SoundGroup, so settings sliders can turn
-- them down separately later.
--
-- Library entries:  Id, Volume, plus optional
--   Pitch   default playback speed (opts.Pitch multiplies it)
--   Length  cut the sound after this many seconds with a short fade (quick cues)
--   Soft    roll off the highs with an EqualizerEffect (takes the edge off harsh SFX)

-- -------------------------------- Services -------------------------------- --
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- -------------------------------- Library -------------------------------- --
local LIBRARY = {
	-- buttons
	Hover = { Id = 139800881181209, Volume = 0.25 },
	Click = { Id = 88442833509532, Volume = 0.5 },
	Open = { Id = 90131163815841, Volume = 0.35 },

	-- queue / pre-duel
	RivalFound = { Id = 113645757352689, Volume = 0.6 },
	Countdown = { Id = 84856624449997, Volume = 0.45 },
	SpinTick = { Id = 88442833509532, Volume = 0.35 },
	SpinLand = { Id = 113094761228279, Volume = 0.55 },
	Vote = { Id = 111174530730534, Volume = 0.5 },
	ModeReveal = { Id = 3406813517, Volume = 0.5 },
	-- quick, soft cue: much quieter, trimmed short and with the highs rolled off
	GameStart = { Id = 9045808549, Volume = 0.12, Pitch = 1.1, Length = 0.4, Soft = true },

	-- rounds
	RivalAnswered = { Id = 81657538737806, Volume = 0.4 },
	Correct = { Id = 123903547626734, Volume = 0.6 },
	-- gentle "nope": quieter, slightly lower, highs rolled off and cut short.
	-- Swap the Id here for a softer sample once one is picked.
	Wrong = { Id = 94135799095134, Volume = 0.22, Pitch = 0.9, Length = 0.5, Soft = true },

	-- results
	Win = { Id = 102844356541414, Volume = 0.55 },
	Lose = { Id = 87193628501201, Volume = 0.5 },
	Coins = { Id = 135483737426662, Volume = 0.55 },
	Perfect = { Id = 134464238316794, Volume = 0.55 },
}

-- Looping background music. Id = 0 means "not picked yet" and is skipped quietly.
-- Use music the experience can play (Roblox's licensed library in the Toolbox, or
-- tracks uploaded to group 430052409).
local MUSIC = {
	Lobby = { Id = 0, Volume = 0.35 }, -- main BGM: lobby, queue, results
	Select = { Id = 0, Volume = 0.35 }, -- round selection: stake spin + mode vote
}

-- the same sound can't re-fire faster than this (stops hover spam)
local MIN_GAP = 0.05
local MUSIC_FADE = 1.2
local CUT_FADE = 0.12

-- -------------------------------- Setup ---------------------------------- --
local Sounds = {}
Sounds.Library = LIBRARY
Sounds.Music = MUSIC

local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local group: SoundGroup? = nil
local musicGroup: SoundGroup? = nil
local clipGroup: SoundGroup? = nil
local currentMusic: { Name: string, Sound: Sound }? = nil
local warnedMusic: { [string]: boolean } = {}

local function getGroup(name: string): SoundGroup
	local g = SoundService:FindFirstChild(name) :: SoundGroup?
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = SoundService
	end
	return g :: SoundGroup
end

local function setup()
	if group then
		return
	end
	group = getGroup("SFX")
	musicGroup = getGroup("Music")
	clipGroup = getGroup("Clips")
	local folder = Instance.new("Folder")
	folder.Name = "SFXTemplates"
	folder.Parent = SoundService
	local list = {}
	for name, info in LIBRARY do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = "rbxassetid://" .. info.Id
		s.Volume = info.Volume
		s.PlaybackSpeed = info.Pitch or 1
		s.SoundGroup = group
		if info.Soft then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.HighGain = -14
			eq.MidGain = -4
			eq.LowGain = 0
			eq.Parent = s
		end
		s.Parent = folder
		templates[name] = s
		table.insert(list, s)
	end
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, list)
end

-- Play a sound by name. opts.Pitch scales playback speed, opts.Volume scales volume.
function Sounds.Play(name: string, opts: { Pitch: number?, Volume: number? }?)
	if not RunService:IsClient() then
		return
	end
	setup()
	local template = templates[name]
	if not template then
		warn("[Sounds] unknown sound", name)
		return
	end
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < MIN_GAP then
		return
	end
	lastPlayed[name] = now

	local s = template:Clone()
	if opts then
		s.PlaybackSpeed = template.PlaybackSpeed * (opts.Pitch or 1)
		s.Volume = template.Volume * (opts.Volume or 1)
	end
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()

	-- quick cues: cut after Length seconds with a tiny fade so it doesn't click
	local length = LIBRARY[name].Length
	if length then
		task.delay(length, function()
			if s.Parent then
				local fade = TweenService:Create(s, TweenInfo.new(CUT_FADE), { Volume = 0 })
				fade.Completed:Once(function()
					s:Destroy()
				end)
				fade:Play()
			end
		end)
	end
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function Sounds.SetVolume(volume: number)
	setup()
	if group then
		group.Volume = volume
	end
end

-- [[ Music ]]

local function fadeOutAndDestroy(sound: Sound, fade: number)
	local tween = TweenService:Create(sound, TweenInfo.new(fade), { Volume = 0 })
	tween.Completed:Once(function()
		sound:Destroy()
	end)
	tween:Play()
end

-- Crossfades to a looping track. nil fades the music out. Playing the track that's already
-- on only re-targets its volume, so it can be called freely on every screen change.
-- opts.Volume scales the track's volume (e.g. 0.4 to duck it under gameplay).
function Sounds.PlayMusic(name: string?, opts: { Volume: number?, Fade: number? }?)
	if not RunService:IsClient() then
		return
	end
	setup()
	local fade = opts and opts.Fade or MUSIC_FADE
	local info = name and MUSIC[name]
	local target = info and info.Volume * (opts and opts.Volume or 1) or 0

	if currentMusic and currentMusic.Name == name then
		TweenService:Create(currentMusic.Sound, TweenInfo.new(fade), { Volume = target }):Play()
		return
	end

	if currentMusic then
		fadeOutAndDestroy(currentMusic.Sound, fade)
		currentMusic = nil
	end
	if not name then
		return
	end
	if not info then
		warn("[Sounds] unknown music", name)
		return
	end
	if info.Id == 0 then
		if not warnedMusic[name] then
			warnedMusic[name] = true
			warn(`[Sounds] music "{name}" has no Id yet (set it in Sounds.MUSIC)`)
		end
		return
	end

	local s = Instance.new("Sound")
	s.Name = "Music_" .. name
	s.SoundId = "rbxassetid://" .. info.Id
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = musicGroup
	s.Parent = SoundService
	s:Play()
	TweenService:Create(s, TweenInfo.new(fade), { Volume = target }):Play()
	currentMusic = { Name = name, Sound = s }
end

function Sounds.StopMusic(fade: number?)
	Sounds.PlayMusic(nil, { Fade = fade })
end

function Sounds.SetMusicVolume(volume: number)
	setup()
	if musicGroup then
		musicGroup.Volume = volume
	end
	-- the lobby playlist (Client/BackgroundMusic) plays through SoundService.Background
	local background = SoundService:FindFirstChild("Background")
	if background and background:IsA("SoundGroup") then
		background.Volume = volume
	end
end

-- Round snippets and the reveal song play through this group (Settings → Song clips).
function Sounds.ClipGroup(): SoundGroup?
	setup()
	return clipGroup
end

function Sounds.SetClipVolume(volume: number)
	setup()
	if clipGroup then
		clipGroup.Volume = volume
	end
end

if RunService:IsClient() then
	task.defer(setup)
end

return Sounds
