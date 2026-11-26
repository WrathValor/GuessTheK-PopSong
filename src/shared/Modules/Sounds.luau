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
	Open = { Id = 120401943587131, Volume = 0.5 }, -- every frame that opens (Interface:Open)
	Notify = { Id = 17208361335, Volume = 0.5 }, -- a tip popping up (tutorial)
	Success = { Id = 85349663780737, Volume = 0.5 }, -- claims, buys, any action that worked
	CardReveal = { Id = 79749665932688, Volume = 0.5 }, -- "Rare_Pull1": shake build-up + the hit as the roll cards turn face up (shop Songs tab)

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
	Wrong = { Id = 110348286467545, Volume = 0.5 },

	-- results
	Win = { Id = 102844356541414, Volume = 0.55 },
	Lose = { Id = 100291570059220, Volume = 0.5 },
	Coins = { Id = 135483737426662, Volume = 0.55 },
	Perfect = { Id = 134464238316794, Volume = 0.55 },
	Encore = { Id = 126615573673174, Volume = 0.5 }, -- "Crowd Cheering": the ENCORE sign lights up before the final round
	Rematch = { Id = 9119669160, Volume = 0.5 }, -- the Rematch button popping in at the end of the results reveal

	-- photocard packs (AlbumsController + its Reveal). Made for K-POPPED and uploaded to group
	-- 430052409; the files are in assets/Audio/Pull.
	PackTear = { Id = 125029448795160, Volume = 0.6 }, -- the sleeve tears open
	CardsFan = { Id = 110210104620379, Volume = 0.5 }, -- the backs fan out and shuffle
	CardFlip = { Id = 92154559223982, Volume = 0.55 }, -- a card turns over
	CardPop = { Id = 92257500937903, Volume = 0.5 }, -- an everyday card lands face up
	CardSleeve = { Id = 135634827790210, Volume = 0.45 }, -- a card slides into the tray
	PullResults = { Id = 111912323567547, Volume = 0.55 }, -- the pack summary
	LuckyShimmer = { Id = 122090780287728, Volume = 0.4 }, -- Lucky Draw back: gold shimmer
	LuckyCoins = { Id = 86377083697427, Volume = 0.6 }, -- Lucky Draw reveal: coin shower
	Heartbeat = { Id = 72997439216698, Volume = 0.6 }, -- Fansign back: each heartbeat hop (boosted)
	FansCheer = { Id = 75897094659596, Volume = 0.5 }, -- Fansign reveal: fans squealing
	FansCrowd = { Id = 139897621361299, Volume = 0.6 }, -- Fansign: a 10 s crowd that carries on (loops, Sounds.Loop)
	MarkerScribble = { Id = 107473596009477, Volume = 0.55 }, -- Fansign scribble, Polaroid signature
	FlashBeep = { Id = 130153053632764, Volume = 0.4 }, -- Polaroid back: each flash-charge blink
	Shutter = { Id = 139616424292770, Volume = 0.65 }, -- Polaroid: the flash goes off
	-- (the One of One's rumble and burst are made bright, not bass: small speakers drop the lows)
	OneRumble = { Id = 75843853222606, Volume = 0.7 }, -- One of One: the build-up (rising riser)
	OneBurst = { Id = 139670621136034, Volume = 0.85 }, -- One of One: the back bursts (shatter)
	OneChoir = { Id = 89786628076615, Volume = 0.85 }, -- One of One: the reveal
	OneLoop = { Id = 94049951477499, Volume = 0.45 }, -- One of One: a 12 s heavenly choir pad that carries on (loops, Sounds.Loop)
	OneLoopAlt = { Id = 79682352932621, Volume = 0.45 }, -- One of One: the other take (a golden synth hum with choir)

	-- notifications (Modules/UI/Notify plays one per kind). Made for K-POPPED and uploaded to group
	-- 430052409; the files are in assets/Audio/Notify. Neutral and Error came out quiet, so they're
	-- turned up to sit level with the other two.
	NotifySuccess = { Id = 119279721309022, Volume = 0.45 }, -- rising bell chime
	NotifyBell = { Id = 96600478594728, Volume = 0.45 }, -- bubbly double ding: a gift, a badge
	NotifyNeutral = { Id = 94314107915255, Volume = 2.2 }, -- soft single tick
	NotifyError = { Id = 70795520957999, Volume = 1.6 }, -- gentle descending "nope"

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

-- Starts a sound looping (opts as Play) and returns a function that stops it with a fade
-- (seconds, default 0.4). For a sound that lasts as long as something is on screen.
function Sounds.Loop(name: string, opts: { Pitch: number?, Volume: number?, FadeIn: number?, At: number? }?): (number?) -> ()
	if not RunService:IsClient() then
		return function() end
	end
	setup()
	local template = templates[name]
	if not template then
		warn("[Sounds] unknown sound", name)
		return function() end
	end
	local s = template:Clone()
	s.Looped = true
	s.PlaybackSpeed = template.PlaybackSpeed * (opts and opts.Pitch or 1)
	local volume = template.Volume * (opts and opts.Volume or 1)
	s.Volume = 0
	s.Parent = SoundService
	s.TimePosition = opts and opts.At or 0 -- (where in the loop to come in)
	s:Play()
	TweenService:Create(s, TweenInfo.new(opts and opts.FadeIn or 0.3), { Volume = volume }):Play()
	local stopped = false
	return function(fade: number?)
		if stopped then
			return
		end
		stopped = true
		local out = TweenService:Create(s, TweenInfo.new(fade or 0.4), { Volume = 0 })
		out.Completed:Once(function()
			s:Destroy()
		end)
		out:Play()
	end
end

-- did any of these sounds start in the last `seconds`? (Notify skips its own cue when the
-- caller already played one, e.g. Wrong with the Shop's "Not enough coins")
function Sounds.PlayedWithin(names: { string }, seconds: number): boolean
	local now = os.clock()
	for _, name in names do
		local at = lastPlayed[name]
		if at and now - at < seconds then
			return true
		end
	end
	return false
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
