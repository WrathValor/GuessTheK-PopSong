--| Snippet
-- Plays the unlocked part of a round's clip on this client only.
-- Song mode: the audio clip. Choreography mode: the dance on a copy of the local avatar,
-- standing in the middle of the stage, frozen when the snippet runs out.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sounds = require(game:GetService("ReplicatedStorage").Modules.Sounds)

local LOCAL_PLAYER = Players.LocalPlayer

-- Songs are uploaded slowed down and played back at `PlaybackSpeed`, so the clip runs at
-- real speed. Tier lengths and `Start` are in real song seconds; the sound's own timeline
-- is `PlaybackSpeed` times longer, so Start is scaled to get the TimePosition.
local function speedOf(clip): number
	local speed = clip.PlaybackSpeed or clip.playbackSpeed or clip.Pitch or 1
	return if type(speed) == "number" and speed > 0 then speed else 1
end

local Snippet = {}
Snippet.__index = Snippet

function Snippet.new(clip, mode: string, stageModel: Model?)
	local self = setmetatable({}, Snippet)
	self.Clip = clip
	self.Mode = mode
	self.Stage = stageModel
	self.Speed = speedOf(clip)
	self._token = 0
	if mode == "Song" then
		local sound = Instance.new("Sound")
		sound.Name = "DuelSnippet"
		sound.SoundId = clip.MusicId or ""
		sound.Volume = clip.Volume or 1
		sound.PlaybackSpeed = self.Speed
		sound.SoundGroup = Sounds.ClipGroup() -- Settings → Song clips volume
		sound.Parent = SoundService
		self.Sound = sound
		-- start downloading now so the first Play isn't spent loading
		task.spawn(ContentProvider.PreloadAsync, ContentProvider, { sound })
	else
		self:_makeRig()
	end
	return self
end

function Snippet:_makeRig()
	local char = LOCAL_PLAYER.Character
	if not char then
		return
	end
	local was = char.Archivable
	char.Archivable = true
	local rig = char:Clone()
	char.Archivable = was
	if not rig then
		return
	end
	for _, d in rig:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	rig.Name = "SnippetDancer"
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		rig:Destroy()
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local spot = self.Stage and self.Stage:FindFirstChild("RigSpot")
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if spot and root then
		local myRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos = spot.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.2, 0)
		local look = myRoot and Vector3.new(myRoot.Position.X, pos.Y, myRoot.Position.Z) or pos + Vector3.zAxis
		rig:PivotTo(CFrame.lookAt(pos, look))
		root.Anchored = true
	end
	rig.Parent = workspace
	self.Rig = rig
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local anim = Instance.new("Animation")
	anim.AnimationId = self.Clip.AnimationId or ""
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if ok then
		track.Looped = false
		self.Track = track
	end
end

-- Where the clip starts on the sound's own (slowed) timeline.
-- Where playback begins on the sound's timeline: the song's `TimePosition` (seconds on the
-- sound itself, same as Studio's TimePosition), else its `Start` (real song seconds),
-- else halfway through the audio.
function Snippet:_startPosition(): number
	local length = self.Sound and self.Sound.TimeLength or 0
	local tp = self.Clip.TimePosition
	if type(tp) == "number" then
		if length > 0 and tp >= length then
			warn(`[Snippet] TimePosition {tp} is past the end of {self.Sound.SoundId} ({length}s); playing from halfway`)
			return length / 2
		end
		return math.max(tp, 0)
	end
	local custom = self.Clip.Start or 0
	if custom <= 0 then
		return length / 2
	end
	local start = custom * self.Speed
	-- a start past the end of the audio plays nothing, so fall back to the beginning
	if length > 0 and start >= length then
		warn(`[Snippet] Start {self.Clip.Start}s is past the end of {self.Sound.SoundId} ({length}s); playing from 0`)
		return 0
	end
	return start
end

-- Waits (up to 5 s) for the audio to load. Returns false if it never did.
function Snippet:_waitLoaded(): boolean
	local sound = self.Sound
	if not sound then
		return false
	end
	if sound.IsLoaded then
		return true
	end
	local deadline = os.clock() + 5
	while not sound.IsLoaded and os.clock() < deadline and sound.Parent do
		task.wait()
	end
	if not sound.IsLoaded then
		warn(`[Snippet] {sound.SoundId} didn't load (missing asset or no permission for this experience)`)
	end
	return sound.IsLoaded
end

-- Yields until the clip can play: the audio has loaded (Song) or the dance animation
-- has (Choreography). Gives up after `timeout` seconds so a broken asset can't lock the round.
function Snippet:WaitReady(timeout: number?)
	if self.Sound then
		self:_waitLoaded()
		return
	end
	local deadline = os.clock() + (timeout or 5)
	while self.Track and self.Track.Length == 0 and os.clock() < deadline do
		task.wait()
	end
end

-- Plays the first `seconds` (real song time) of the clip. Returns how long it will play for.
function Snippet:Play(seconds: number)
	self._token += 1
	local token = self._token
	if self.Sound then
		-- the stop timer only starts once the audio is actually playing; before, a sound
		-- still loading was stopped before it made any noise
		task.spawn(function()
			if not self:_waitLoaded() or self._token ~= token then
				return
			end
			local sound = self.Sound
			local from = self:_startPosition()
			-- stop by the audio's own clock, not a wall-clock timer: Play() takes a moment
			-- to actually make noise, which ate the whole 0.1 s tier before
			local to = from + seconds * self.Speed
			sound.TimePosition = from
			sound:Play()
			local deadline = os.clock() + seconds + 2
			while self._token == token and sound.Parent and os.clock() < deadline do
				if sound.IsPlaying and sound.TimePosition >= to then
					break
				end
				RunService.Heartbeat:Wait()
			end
			if self._token == token and sound.Parent then
				sound:Stop()
			end
		end)
		return seconds
	elseif self.Track then
		self.Track:Stop(0)
		self.Track:Play(0)
		self.Track:AdjustSpeed(1)
	end
	task.delay(seconds, function()
		if self._token ~= token then
			return
		end
		if self.Sound then
			self.Sound:Stop()
		elseif self.Track then
			self.Track:AdjustSpeed(0) -- freeze on the last pose
		end
	end)
	return seconds
end

-- Where the reveal plays from: the song's `ChorusPosition`, else the snippet start.
function Snippet:_chorusPosition(): number
	local chorus = self.Clip.ChorusPosition
	local length = self.Sound and self.Sound.TimeLength or 0
	if type(chorus) == "number" and (length == 0 or chorus < length) then
		return math.max(chorus, 0)
	end
	return self:_startPosition()
end

-- Plays the song from its chorus (used during the reveal).
function Snippet:PlayFull()
	self._token += 1
	self._fading = false
	if self.Sound then
		self.Sound.Volume = self.Clip.Volume or 1
	end
	local token = self._token
	if self.Sound then
		task.spawn(function()
			if self:_waitLoaded() and self._token == token then
				self.Sound.TimePosition = self:_chorusPosition()
				self.Sound:Play()
			end
		end)
	elseif self.Track then
		self.Track:Stop(0)
		self.Track:Play(0)
		self.Track:AdjustSpeed(1)
	end
end

function Snippet:Stop()
	self._token += 1
	if self.Sound then
		self.Sound:Stop()
	end
	if self.Track then
		self.Track:AdjustSpeed(0)
	end
end

-- Fades the song out over `seconds`, then stops it. Safe to call more than once.
function Snippet:FadeOut(seconds: number)
	local sound = self.Sound
	if not sound or not sound.Parent or self._fading then
		return
	end
	self._fading = true
	self._token += 1 -- cancels any pending stop/replay
	local tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 })
	tween.Completed:Once(function()
		if sound.Parent then
			sound:Stop()
		end
	end)
	tween:Play()
end

-- Fades out (if the song is playing) and then cleans up.
function Snippet:FadeAndDestroy(seconds: number)
	if self.Sound and self.Sound.IsPlaying then
		self:FadeOut(seconds)
		task.delay(seconds + 0.05, function()
			self:Destroy()
		end)
	else
		self:Destroy()
	end
end

function Snippet:Destroy()
	self._token += 1
	if self.Sound then
		self.Sound:Destroy()
	end
	if self.Track then
		self.Track:Stop(0)
	end
	if self.Rig then
		self.Rig:Destroy()
	end
end

return Snippet
