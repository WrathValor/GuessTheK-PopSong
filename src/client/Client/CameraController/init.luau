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
-- Walk-on (the queue intermission, rival found): show both spots, then each player on their
-- own stage + mic, so what you've equipped is actually seen (by you and your rival)
local WALK_ON = {
	{ Shot = "Wide", Time = 1.3 },
	{ Shot = "A", Time = 1.5 },
	{ Shot = "B", Time = 1.5 },
	{ Shot = "Wide", Time = 0.7 }, -- (then holds until the pre-duel screen / round camera)
}
local WALK_ON_FOV = 50
local WALK_ON_SPEED = 3.5 -- glide between shots (lower = slower, more cinematic)
local WIDE_FROM, WIDE_TO, WIDE_UP = 21, 16, 5.5 -- the wide shot dollies in from WIDE_FROM to WIDE_TO studs
local CLOSE_FRONT, CLOSE_SIDE, CLOSE_UP = 8, 3.5, 4.6 -- close shot: in front of the player (past their mic), off to the side, about head height
local CLOSE_AIM = 3 -- what the close shot looks at, above the spot (their chest, so the head isn't cut off)
-- Waiting (queue open, no rival yet): a slow sway in front of you on your own stage, framed
-- so you sit left of centre (the queue card is on the right)
local WAIT_FOV = 50
local WAIT_DISTANCE, WAIT_UP, WAIT_AIM = 10.5, 4.4, 2.9
local WAIT_SHIFT = 2.6 -- aim this far to your right, which puts you left of centre
local WAIT_SWAY = math.rad(48) -- how far round either side it swings (never behind your backdrop)
local WAIT_PERIOD = 18 -- seconds for one full swing there and back
local WAIT_SPEED = 2 -- glide into the shot
-- Victory (end of a duel, before the results card): in front of the winner on their own spot,
-- a little above head height and far enough back that the whole stage + mic are in the shot,
-- pushing in slowly
local WIN_FOV = 50
local WIN_FROM, WIN_TO = 15, 12.5 -- distance in front of them, start → end of the push
local WIN_SIDE, WIN_UP, WIN_AIM = 3, 4.2, 2.3 -- off to the side, above head height, aimed at their waist so the platform shows
local WIN_PUSH = 3 -- seconds the push takes
-- Party lobby (on a Party Stage, before a match): a slow circle round the outside of the ring,
-- so every player's spot (their stage + mic) drifts through the shot; the lobby card is on
-- the right, so the ring sits left of centre
local PAN_FOV = 50
local PAN_RADIUS, PAN_UP, PAN_AIM = 17, 8, 1.5
local PAN_SHIFT = 4.5 -- aim this far right of the middle (the ring sits left of centre)
local PAN_PERIOD = 45 -- seconds for one full circle
local PAN_SPEED = 2 -- glide into the shot

--| CameraController
-- Duel camera. Song mode: a straight-on close-up of the opponent's face, shot from your side
-- of the stage. Choreography mode (and solo Song, where there's no opponent): a close shot of
-- the dancer on the RigSpot. Showcase() sways in front of you on your stage while you wait in
-- the queue; PartyPan() circles a Party Stage's ring in its lobby; Victory() is the winner on
-- their spot before the results; WalkOn() is the rival-found intro (both stages, then each player
-- on theirs). Reset() hands the camera back to the normal follow camera.
local CameraController = {}
CameraController.Active = false

local fovTween: Tween? = nil
local soloDouble: Model? = nil -- solo Song: a copy of you standing on the other spot
local cachedTargetModel: Model? = nil
local cachedTargetHead: BasePart? = nil
local cachedLocalCharacter: Model? = nil
local cachedLocalHead: BasePart? = nil

local function stageModel(): Model?
	local name = LOCAL_PLAYER:GetAttribute("Stage")
	local map = workspace:FindFirstChild("Map")
	if not (name and map) then
		return nil
	end
	-- a duel stage, or a Party Stage (same RigSpot in the middle)
	for _, folder in { "DuelStages", "PartyStages" } do
		local stages = map:FindFirstChild(folder)
		local stage = stages and stages:FindFirstChild(name)
		if stage then
			return stage :: Model
		end
	end
	return nil
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
local function makeSoloDouble(stage: Model?): Model?
	local char = LOCAL_PLAYER.Character
	local myRoot = rootOf(LOCAL_PLAYER)
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
local function shot(mode: string, opponent: Player?, rigSpot: BasePart?): CFrame?
	local myRoot = rootOf(LOCAL_PLAYER)
	if not myRoot then
		return nil
	end

	-- Song: over your shoulder at the opponent (or your solo double)
	local target: Model? = if opponent then opponent.Character elseif mode == "Song" then soloDouble else nil
	if mode == "Song" and target then
		local head = if target == cachedTargetModel then cachedTargetHead else target:FindFirstChild("Head") :: BasePart?
		cachedTargetModel = target
		cachedTargetHead = head
		local myChar = LOCAL_PLAYER.Character
		local myHead = if myChar == cachedLocalCharacter then cachedLocalHead else myChar and myChar:FindFirstChild("Head") :: BasePart?
		cachedLocalCharacter = myChar
		cachedLocalHead = myHead
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
	local spot = rigSpot
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

-- the walk-on's shots, worked out from the stage's two spots. The camera side of the stage
-- is whichever has more open space (a raycast each way); ALeft says which side A lands on.
local function walkOnShots(stage: Model)
	local a = stage:FindFirstChild("SpotA", true) :: BasePart?
	local b = stage:FindFirstChild("SpotB", true) :: BasePart?
	if not (a and b) then
		return nil
	end
	local pa, pb = a.Position, b.Position
	local mid = (pa + pb) / 2
	local across = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z)
	if across.Magnitude < 0.01 then
		return nil
	end
	across = across.Unit -- screen right
	local look = Vector3.yAxis:Cross(across) -- facing this way puts A left, B right
	-- the camera stands at mid - look * distance: if that side is walled in, view from the other
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { stage }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local eye = mid + Vector3.new(0, WIDE_UP, 0)
	local function room(dir: Vector3): number
		local hit = workspace:Raycast(eye, dir * WIDE_FROM, params)
		return if hit then hit.Distance else WIDE_FROM
	end
	local aLeft = true
	if room(look) > room(-look) then
		look = -look -- seen from the other side: A is on the right now
		aLeft = false
	end
	local up = Vector3.yAxis
	local focus = mid + up * 2
	local function wide(t: number): CFrame
		local d = WIDE_FROM + (WIDE_TO - WIDE_FROM) * t
		return CFrame.lookAt(mid - look * d + up * WIDE_UP, focus)
	end
	local function close(spot: Vector3, other: Vector3): CFrame
		local toward = Vector3.new(other.X - spot.X, 0, other.Z - spot.Z).Unit
		local from = spot + toward * CLOSE_FRONT - look * CLOSE_SIDE + up * CLOSE_UP
		return CFrame.lookAt(from, spot + up * CLOSE_AIM - toward * 0.4)
	end
	return {
		Wide = wide,
		A = close(pa, pb),
		B = close(pb, pa),
		ALeft = aLeft,
	}
end

--| Functions

-- Waiting for a rival: the camera sways slowly in front of you on your spot, so your stage +
-- mic are on screen while you queue. Holds until WalkOn / Focus / Reset take over.
function CameraController.Showcase(): boolean
	local stage = stageModel()
	local a = stage and stage:FindFirstChild("SpotA", true) :: BasePart?
	local b = stage and stage:FindFirstChild("SpotB", true) :: BasePart?
	if not (a and b) then
		return false
	end
	local camera = workspace.CurrentCamera
	CameraController.Active = true
	CameraController.Mode = "Showcase"
	RunService:UnbindFromRenderStep(RENDER_NAME)
	camera.CameraType = Enum.CameraType.Scriptable
	tweenFov(WAIT_FOV)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local started = os.clock()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		-- your spot is whichever is nearer (you may still be stepping on)
		local root = rootOf(LOCAL_PLAYER)
		if not root then
			return
		end
		local mine, other = a.Position, b.Position
		if (root.Position - b.Position).Magnitude < (root.Position - a.Position).Magnitude then
			mine, other = b.Position, a.Position
		end
		local forward = Vector3.new(other.X - mine.X, 0, other.Z - mine.Z)
		if forward.Magnitude < 0.01 then
			return
		end
		local angle = math.sin((os.clock() - started) / WAIT_PERIOD * math.pi * 2) * WAIT_SWAY
		local dir = CFrame.Angles(0, angle, 0):VectorToWorldSpace(forward.Unit)
		local right = (-dir):Cross(Vector3.yAxis)
		local aim = mine + Vector3.new(0, WAIT_AIM, 0) + right * WAIT_SHIFT
		local from = mine + dir * WAIT_DISTANCE + Vector3.new(0, WAIT_UP, 0)
		-- don't end up inside a lamp post or a wall: stop just short of whatever's in the way
		local ignore = { stage :: Instance }
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(aim, from - aim, params)
		if hit then
			from = hit.Position + (aim - from).Unit * 0.6
		end
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(from, aim), 1 - math.exp(-WAIT_SPEED * dt))
	end)
	return true
end

-- The victory shot on `winner`'s spot. Holds until Reset / Focus. False if it can't be shot.
function CameraController.Victory(winner: Player?): boolean
	local stage = stageModel()
	local rig = stage and stage:FindFirstChild("RigSpot", true) :: BasePart?
	local root = rootOf(winner)
	if not (stage and rig and root) then
		return false
	end
	-- their spot: the nearest pad (SpotA / SpotB on a duel stage, Spot1–6 on a Party Stage);
	-- everyone faces the middle (the RigSpot), so that's the way the shot looks back from
	local pad, best = nil, math.huge
	for _, d in stage:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "SpotA" or d.Name == "SpotB" or d.Name:match("^Spot%d+$")) then
			local dist = (d.Position - root.Position).Magnitude
			if dist < best then
				pad, best = d, dist
			end
		end
	end
	if not pad then
		return false
	end
	local spot = pad.Position
	local toward = Vector3.new(rig.Position.X - spot.X, 0, rig.Position.Z - spot.Z)
	if toward.Magnitude < 0.01 then
		return false
	end
	toward = toward.Unit
	local side = toward:Cross(Vector3.yAxis)
	local aim = spot + Vector3.new(0, WIN_AIM, 0)
	local function at(t: number): CFrame
		local d = WIN_FROM + (WIN_TO - WIN_FROM) * t
		return CFrame.lookAt(spot + toward * d + side * WIN_SIDE + Vector3.new(0, WIN_UP, 0), aim)
	end

	local camera = workspace.CurrentCamera
	CameraController.Active = true
	CameraController.Mode = "Victory"
	RunService:UnbindFromRenderStep(RENDER_NAME)
	clearSoloDouble()
	RivalTag.Clear()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = at(0)
	tweenFov(WIN_FOV)
	local started = os.clock()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local t = math.clamp((os.clock() - started) / WIN_PUSH, 0, 1)
		camera.CFrame = at(1 - (1 - t) ^ 3) -- eases out into the close-up
	end)
	return true
end

-- Party Stage lobby: circles the ring slowly so every spot drifts past. Holds until Focus /
-- Victory / Reset take over. False if this isn't a stage with a RigSpot.
function CameraController.PartyPan(): boolean
	local stage = stageModel()
	local rig = stage and stage:FindFirstChild("RigSpot", true) :: BasePart?
	if not rig then
		return false
	end
	local camera = workspace.CurrentCamera
	CameraController.Active = true
	CameraController.Mode = "PartyPan"
	RunService:UnbindFromRenderStep(RENDER_NAME)
	camera.CameraType = Enum.CameraType.Scriptable
	tweenFov(PAN_FOV)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local centre = rig.Position
	-- start the circle from wherever the camera is now, so it doesn't swing across the map
	local now = camera.CFrame.Position - centre
	local startAngle = math.atan2(now.Z, now.X)
	local started = os.clock()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local angle = startAngle + (os.clock() - started) / PAN_PERIOD * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local right = (-dir):Cross(Vector3.yAxis)
		local aim = centre + Vector3.new(0, PAN_AIM, 0) + right * PAN_SHIFT
		local from = centre + dir * PAN_RADIUS + Vector3.new(0, PAN_UP, 0)
		local ignore = { stage :: Instance }
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(aim, from - aim, params)
		if hit then
			from = hit.Position + (aim - from).Unit * 0.6
		end
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(from, aim), 1 - math.exp(-PAN_SPEED * dt))
	end)
	return true
end

-- Who stands on which spot of your stage: { A = Player?, B = Player? } (nearest player
-- with the same Stage attribute to each spot)
function CameraController.SpotPlayers(): { A: Player?, B: Player? }
	local out = {}
	local stage = stageModel()
	local name = LOCAL_PLAYER:GetAttribute("Stage")
	if not stage then
		return out
	end
	for _, slot in { "A", "B" } do
		local spot = stage:FindFirstChild("Spot" .. slot, true) :: BasePart?
		local best, bestDist = nil, math.huge
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if spot and root and player:GetAttribute("Stage") == name then
				local d = (root.Position - spot.Position).Magnitude
				if d < bestDist and player ~= out.A then
					best, bestDist = player, d
				end
			end
		end
		out[slot] = best
	end
	return out
end

-- The walk-on: wide on both spots, a push in on A, then on B, then back wide and holds there
-- (Focus or Reset take over). onShot(shot) fires as each shot starts ("Wide" | "A" | "B").
-- Returns whether it runs, and whether spot A is on the left of the screen (for the chips).
function CameraController.WalkOn(onShot: ((string) -> ())?): (boolean, boolean)
	local stage = stageModel()
	local shots = stage and walkOnShots(stage)
	if not shots then
		return false, true
	end
	local camera = workspace.CurrentCamera
	CameraController.Active = true
	CameraController.Mode = "WalkOn"
	RunService:UnbindFromRenderStep(RENDER_NAME)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = shots.Wide(0)
	tweenFov(WALK_ON_FOV)

	local started = os.clock()
	local index = 0
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		-- which shot we're in, and how far through it
		local t = os.clock() - started
		local i, into = #WALK_ON, 1
		for n, step in WALK_ON do
			if t < step.Time then
				i, into = n, t / step.Time
				break
			end
			t -= step.Time
		end
		if i ~= index then
			index = i
			if onShot then
				task.spawn(onShot, WALK_ON[i].Shot)
			end
		end
		local name = WALK_ON[i].Shot
		local target = if name == "Wide" then shots.Wide(if i == 1 then into else 1) else shots[name]
		camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-WALK_ON_SPEED * dt))
	end)
	return true, shots.ALeft
end

-- Zooms in for a duel. `mode` is "Song" or "Choreography"; `info` is the PreDuel packet.
function CameraController.Focus(mode: string, info)
	local camera = workspace.CurrentCamera
	local opponent = opponentOf(info)
	local stage = stageModel()
	local rigSpot = stage and stage:FindFirstChild("RigSpot") :: BasePart?
	CameraController.Active = true
	CameraController.Mode = mode

	clearSoloDouble()
	if mode == "Song" and info and info.Solo then
		soloDouble = makeSoloDouble(stage)
	end
	cachedTargetModel = nil
	cachedTargetHead = nil
	cachedLocalCharacter = nil
	cachedLocalHead = nil

	-- name tag over whoever you're up against (your double in solo)
	local function levelOf(userId: number): number?
		for _, profile in (info and info.Players) or {} do
			if profile.UserId == userId then
				return profile.Level
			end
		end
		return nil
	end
	-- (not in a Party free-for-all: there's no one rival, the round screen's ticket shows everyone)
	local ffa = info and info.Party and info.Kind ~= "Duel"
	if ffa then
		-- no tag
	elseif opponent and opponent.Character then
		RivalTag.Attach(opponent.Character, opponent.DisplayName, levelOf(opponent.UserId))
	elseif soloDouble then
		RivalTag.Attach(soloDouble, LOCAL_PLAYER.DisplayName, levelOf(LOCAL_PLAYER.UserId))
	end

	RunService:UnbindFromRenderStep(RENDER_NAME)
	camera.CameraType = Enum.CameraType.Scriptable
	tweenFov(if mode == "Song" then SONG_FOV else ZOOM_FOV)

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local target = shot(mode, opponent, rigSpot)
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
	cachedTargetModel = nil
	cachedTargetHead = nil
	cachedLocalCharacter = nil
	cachedLocalHead = nil
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
