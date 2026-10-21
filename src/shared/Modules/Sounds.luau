-- UI + game sound effects (client only). All IDs are free Creator Store audio,
-- checked to load in this experience. Volumes go through the "SFX" SoundGroup
-- so a settings slider can turn them down later.

-- -------------------------------- Services -------------------------------- --
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

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
	GameStart = { Id = 9045808549, Volume = 0.45 },

	-- rounds
	RivalAnswered = { Id = 81657538737806, Volume = 0.4 },
	Correct = { Id = 123903547626734, Volume = 0.6 },
	Wrong = { Id = 94135799095134, Volume = 0.45 },

	-- results
	Win = { Id = 102844356541414, Volume = 0.55 },
	Lose = { Id = 87193628501201, Volume = 0.5 },
	Coins = { Id = 135483737426662, Volume = 0.55 },
	Perfect = { Id = 134464238316794, Volume = 0.55 },
}

-- the same sound can't re-fire faster than this (stops hover spam)
local MIN_GAP = 0.05

-- -------------------------------- Setup ---------------------------------- --
local Sounds = {}
Sounds.Library = LIBRARY

local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local group: SoundGroup? = nil

local function setup()
	if group then
		return
	end
	group = SoundService:FindFirstChild("SFX") :: SoundGroup?
	if not group then
		local g = Instance.new("SoundGroup")
		g.Name = "SFX"
		g.Volume = 1
		g.Parent = SoundService
		group = g
	end
	local folder = Instance.new("Folder")
	folder.Name = "SFXTemplates"
	folder.Parent = SoundService
	local list = {}
	for name, info in LIBRARY do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = "rbxassetid://" .. info.Id
		s.Volume = info.Volume
		s.SoundGroup = group
		s.Parent = folder
		templates[name] = s
		table.insert(list, s)
	end
	task.spawn(ContentProvider.PreloadAsync, ContentProvider, list)
end

-- Play a sound by name. opts.Pitch shifts playback speed, opts.Volume scales it.
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
		s.PlaybackSpeed = opts.Pitch or 1
		s.Volume = template.Volume * (opts.Volume or 1)
	end
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
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

if RunService:IsClient() then
	task.defer(setup)
end

return Sounds
