--| Snippet
-- Plays the unlocked part of a round's clip on this client only.
-- Song mode: the audio clip. Choreography mode: the dance on a copy of the local avatar,
-- standing in the middle of the stage, frozen when the snippet runs out.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local LOCAL_PLAYER = Players.LocalPlayer

local Snippet = {}
Snippet.__index = Snippet

function Snippet.new(clip, mode: string, stageModel: Model?)
	local self = setmetatable({}, Snippet)
	self.Clip = clip
	self.Mode = mode
	self.Stage = stageModel
	self._token = 0
	if mode == "Song" then
		local sound = Instance.new("Sound")
		sound.Name = "DuelSnippet"
		sound.SoundId = clip.MusicId or ""
		sound.Volume = clip.Volume or 1
		sound.PlaybackSpeed = clip.Pitch or 1
		sound.Parent = SoundService
		self.Sound = sound
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
	-- stand in the middle of the stage, facing the local player
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

-- Plays the first `seconds` of the clip. Returns how long it will play for.
function Snippet:Play(seconds: number)
	self._token += 1
	local token = self._token
	if self.Sound then
		self.Sound.TimePosition = self.Clip.Start or 0
		self.Sound:Play()
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

-- Plays the whole clip (used during the reveal).
function Snippet:PlayFull()
	self._token += 1
	if self.Sound then
		self.Sound.TimePosition = self.Clip.Start or 0
		self.Sound:Play()
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
