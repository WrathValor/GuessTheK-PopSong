--| Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RivalTag = require(script.RivalTag)

--| Variables
local LOCAL_PLAYER = Players.LocalPlayer
local RENDER_NAME = "DuelCamera"

-- tuning
local DEFAULT_FOV = 70
local ZOOM_FOV = 45 -- tighter lens = closer, flatter close-up
local SONG_FOV = 34 -- over-the-shoulder lens: opponent across the stage fills the frame
local FOLLOW_SPEED = 6 -- higher = snappier glide into the shot
local FOV_TWEEN = TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local RIG_HEIGHT = 2.6 -- RigSpot -> dancer's chest
local RIG_DISTANCE = 9 -- how far the camera sits from the dancer
-- Song: over-the-shoulder, behind your right shoulder looking at the opponent
local OTS_BACK = 8 -- behind your head
local OTS_SIDE = 3.4 -- out past your shoulder
local OTS_UP = 1.2 -- a little above your head
local OTS_AIM_DROP = 1 -- aim a little under the opponent's face so both of you sit above the answer buttons

--| CameraController
-- Duel camera. Song mode: a straight-on close-up of the opponent's face, shot from your side
-- of the stage. Choreography mode (and solo Song, where there's no opponent): a close shot of
-- the dancer on the RigSpot. Reset() hands the camera back to the normal follow camera.
local CameraController = {}
CameraController.Active = false

local fovTween: Tween? = nil
local soloDouble: Model? = nil -- solo Song: a copy of you standing on the other spot

local function stageModel(): Model?
	local name = LOCAL_PLAYER:GetAttribute("Stage")
	local map = workspace:FindFirstChild("Map")
	local stages = map and map:FindFirstChild("DuelStages")
	return if name and stages then stages:FindFirstChild(name) :: Model? else nil
end

local function rootOf(player: Player?): BasePart?
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function opponentOf(info): Player?
	if not info or info.Solo then
		return nil
	end
	for _, profile in info.Players or {} do
		if profile.UserId ~= LOCAL_PLAYER.UserId then
			return Players:GetPlayerByUserId(profile.UserId)
		end
	end
	return nil
end

-- Solo Song has no opponent to look at, so a local copy of your character stands on the
-- spot you're not on, facing you, playing your idle animation.
local function makeSoloDouble(): Model?
	local char = LOCAL_PLAYER.Character
	local myRoot = rootOf(LOCAL_PLAYER)
	local stage = stageModel()
	if not (char and myRoot and stage) then
		return nil
	end
	local a = stage:FindFirstChild("SpotA") :: BasePart?
	local b = stage:FindFirstChild("SpotB") :: BasePart?
	if not (a and b) then
		return nil
	end
	-- the free spot is whichever one is further from you
	local spot = if (a.Position - myRoot.Position).Magnitude > (b.Position - myRoot.Position).Magnitude then a else b

	-- grab the idle animation before the Animate script is stripped
	local idleId: string? = nil
	local animate = char:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	local idleAnim = idle and idle:FindFirstChildOfClass("Animation")
	if idleAnim then
		idleId = idleAnim.AnimationId
	end

	local was = char.Archivable
	char.Archivable = true
	local double = char:Clone()
	char.Archivable = was
	if not double then
		return nil
	end
	for _, d in double:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	double.Name = "SoloDouble"
	local humanoid = double:FindFirstChildOfClass("Humanoid")
	local root = double:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (humanoid and root) then
		double:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local top = spot.Position.Y + spot.Size.Y / 2
	local pos = Vector3.new(spot.Position.X, top + humanoid.HipHeight + root.Size.Y / 2, spot.Position.Z)
	double:PivotTo(CFrame.lookAt(pos, Vector3.new(myRoot.Position.X, pos.Y, myRoot.Position.Z)))
	root.Anchored = true
	double.Parent = workspace

	if idleId then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local anim = Instance.new("Animation")
		anim.AnimationId = idleId
		local ok, track = pcall(animator.LoadAnimation, animator, anim)
		if ok then
			track.Looped = true
			track:Play(0)
		end
	end
	return double
end

local function clearSoloDouble()
	if soloDouble then
		soloDouble:Destroy()
		soloDouble = nil
	end
end

local function tweenFov(fov: number)
	local camera = workspace.CurrentCamera
	if fovTween then
		fovTween:Cancel()
	end
	fovTween = TweenService:Create(camera, FOV_TWEEN, { FieldOfView = fov })
	fovTween:Play()
end

-- Where the camera should be this frame, or nil if the shot can't be built yet.
local function shot(mode: string, opponent: Player?): CFrame?
	local myRoot = rootOf(LOCAL_PLAYER)
	if not myRoot then
		return nil
	end

	-- Song: over your shoulder at the opponent (or your solo double)
	local target: Model? = if opponent then opponent.Character elseif mode == "Song" then soloDouble else nil
	if mode == "Song" and target then
		local head = target:FindFirstChild("Head") :: BasePart?
		local myChar = LOCAL_PLAYER.Character
		local myHead = myChar and myChar:FindFirstChild("Head") :: BasePart?
		if head then
			local face = head.Position - Vector3.new(0, OTS_AIM_DROP, 0)
			local me = if myHead then myHead.Position else myRoot.Position + Vector3.new(0, 1.5, 0)
			local forward = Vector3.new(face.X - me.X, 0, face.Z - me.Z)
			if forward.Magnitude < 0.01 then
				forward = myRoot.CFrame.LookVector
			end
			forward = forward.Unit
			local right = forward:Cross(Vector3.yAxis)
			local from = me - forward * OTS_BACK + right * OTS_SIDE + Vector3.new(0, OTS_UP, 0)
			return CFrame.lookAt(from, face)
		end
	end

	-- Choreography (or no opponent): close on the rig, from the local player's side
	local stage = stageModel()
	local spot = stage and stage:FindFirstChild("RigSpot") :: BasePart?
	if not spot then
		return nil
	end
	local rig = spot.Position + Vector3.new(0, RIG_HEIGHT, 0)
	local toMe = Vector3.new(myRoot.Position.X - rig.X, 0, myRoot.Position.Z - rig.Z)
	if toMe.Magnitude < 0.01 then
		toMe = spot.CFrame.LookVector
	end
	local distance = math.min(RIG_DISTANCE, toMe.Magnitude * 0.8)
	local from = rig + toMe.Unit * distance + Vector3.new(0, 0.6, 0)
	return CFrame.lookAt(from, rig)
end

--| Functions

-- Zooms in for a duel. `mode` is "Song" or "Choreography"; `info` is the PreDuel packet.
function CameraController.Focus(mode: string, info)
	local camera = workspace.CurrentCamera
	local opponent = opponentOf(info)
	CameraController.Active = true
	CameraController.Mode = mode

	clearSoloDouble()
	if mode == "Song" and info and info.Solo then
		soloDouble = makeSoloDouble()
	end

	-- name tag over whoever you're up against (your double in solo)
	local function levelOf(userId: number): number?
		for _, profile in (info and info.Players) or {} do
			if profile.UserId == userId then
				return profile.Level
			end
		end
		return nil
	end
	if opponent and opponent.Character then
		RivalTag.Attach(opponent.Character, opponent.DisplayName, levelOf(opponent.UserId))
	elseif soloDouble then
		RivalTag.Attach(soloDouble, LOCAL_PLAYER.DisplayName, levelOf(LOCAL_PLAYER.UserId))
	end

	RunService:UnbindFromRenderStep(RENDER_NAME)
	camera.CameraType = Enum.CameraType.Scriptable
	tweenFov(if mode == "Song" then SONG_FOV else ZOOM_FOV)

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local target = shot(mode, opponent)
		if target then
			-- frame-rate independent glide into (and along with) the shot
			camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-FOLLOW_SPEED * dt))
		end
	end)
end

-- Back to the normal follow camera.
function CameraController.Reset()
	if not CameraController.Active then
		return
	end
	CameraController.Active = false
	CameraController.Mode = nil
	RunService:UnbindFromRenderStep(RENDER_NAME)
	clearSoloDouble()
	RivalTag.Clear()

	local camera = workspace.CurrentCamera
	local char = LOCAL_PLAYER.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
	tweenFov(DEFAULT_FOV)
end

function CameraController.Start()
	-- respawning mid-duel drops you off the stage, so never leave the camera stuck
	LOCAL_PLAYER.CharacterAdded:Connect(function()
		CameraController.Reset()
	end)
end

return CameraController
