--| CosmeticView
-- Shows the real 3D model of a stage, mic or set in a card's Art frame: a night-ink card
-- (CardGradient, deep purple fading to ink, like the street at night) so the pastels pop,
-- a ViewportFrame
-- ("Model3D") with the model, and – on stages and sets – the local player's own avatar
-- standing on the pad, facing the mic. Models come from ReplicatedStorage.Assets.Cosmetics
-- .Stages / .Mics (named by ShopCatalog id, WorldPivot = bottom centre, LookVector = front:
-- stage towards the mic, mic towards the player). Without a model the drawn shapes stay.
--   CosmeticView.Show(art, "Stage" | "Mic", id)
--   CosmeticView.Show(art, "Set", setId)   – its stage, the avatar on it, its mic in front
--   CosmeticView.Show(art, "Dance" | "Accessory", assetId)
--                                         – a group UGC item (Engine/UGCService loads them into
--                                           Assets.UGC): the avatar doing the dance / wearing it
--   CosmeticView.Clear(art)               – back to the drawn art (packs, titles…)
--   CosmeticView.EnableSpin(art)          – drag on the art's "Spin" button to turn around
--                                           the model (once per art; resets on a new model)
--   CosmeticView.SetAvatar(model?)        – who stands on the pads (the client tracks the
--                                           local player's character by itself)
-- Stages, mics and sets turn slowly on their own while the card is on screen (AUTO_SPIN);
-- a drag takes over and the turning picks up again shortly after letting go.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CosmeticView = {}

local FOV = 30
local MARGIN = 0.86 -- < 1 zooms in past the box's outline (its corners are empty air)
local AUTO_SPIN = 0.45 -- radians a second the camera circles a stage / mic / set
local SPIN_RESUME = 1.5 -- seconds after a drag before the auto turn picks up again
local SPINS = { Stage = true, Mic = true, Set = true }
local SPIN_DELAY = 0.8 -- seconds a fresh model holds still while its meshes / avatar load in
local MAX_STEP = 1 / 30 -- a hitch never makes the model jump further than one 30fps frame
local CARD = Color3.fromHex("FFFFFF") -- tinted by the gradient below
local NIGHT = ColorSequence.new(Color3.fromHex("4A3F78"), Color3.fromHex("1E1B2E"))
local SHADOW = Color3.fromHex("1E1B2E")
-- what stays visible in the Art frame; everything else is the old drawn art
local KEEP = { Rarity = true, Model3D = true, Kind = true, InGame = true, Hint = true, Select = true, Spin = true }

local avatarTemplate: Model? = nil
-- art -> where its camera orbits: { Centre, Dir, Dist, Yaw } (EnableSpin turns Yaw)
-- Plain tables, not weak ones: a weak key on an Instance drops out whenever Lua lets go of
-- its wrapper (the GuiObject still exists), which made the spin stop at random. Entries go
-- when the art is destroyed instead (forget).
local orbits = {} :: { [GuiObject]: any }
local shown = {} :: { [GuiObject]: { string } } -- art -> { kind, id }
local watched = {} :: { [GuiObject]: boolean }
local function forget(art: GuiObject)
	if watched[art] then
		return
	end
	watched[art] = true
	art.Destroying:Once(function()
		orbits[art] = nil
		shown[art] = nil
		watched[art] = nil
	end)
end

-- a group item's preview: the Animation (dance) or Accessory, loaded by Engine/UGCService
local function ugcAsset(id: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ugc = assets and assets:FindFirstChild("UGC")
	return ugc and ugc:FindFirstChild(id)
end

local function template(kind: string, id: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local root = assets and assets:FindFirstChild("Cosmetics")
	local folder = root and root:FindFirstChild(if kind == "Stage" then "Stages" else "Mics")
	local model = folder and folder:FindFirstChild(id)
	return if model and model:IsA("Model") then model else nil
end

local function hideDrawnArt(art: Instance)
	for _, child in art:GetChildren() do
		if child:IsA("GuiObject") and not KEEP[child.Name] then
			child.Visible = false
		end
	end
end

local function viewport(art: GuiObject): (ViewportFrame, WorldModel)
	local vf = art:FindFirstChild("Model3D") :: ViewportFrame?
	if not vf then
		vf = Instance.new("ViewportFrame")
		vf.Name = "Model3D"
		vf.BackgroundTransparency = 1
		vf.Size = UDim2.fromScale(1, 1)
		vf.ZIndex = art.ZIndex + 2
		vf.Ambient = Color3.fromRGB(205, 200, 218)
		vf.LightColor = Color3.fromRGB(255, 250, 245)
		vf.LightDirection = Vector3.new(-0.6, -1, -0.8)
		vf.Parent = art
		-- keep the chips (rarity, kind…) and click catchers above the model
		for name in KEEP do
			local chip = art:FindFirstChild(name)
			if name ~= "Model3D" and chip and chip:IsA("GuiObject") then
				chip.ZIndex = math.max(chip.ZIndex, vf.ZIndex + 1)
			end
		end
	end
	local world = vf:FindFirstChildOfClass("WorldModel")
	if not world then
		world = Instance.new("WorldModel")
		world.Parent = vf
	end
	return vf :: ViewportFrame, world :: WorldModel
end

-- the idle the avatar plays on the cards: the player's own (from their Animate script, so
-- animation packs carry over), else Roblox's default for the rig type
local DEFAULT_IDLE = {
	[Enum.HumanoidRigType.R15] = "rbxassetid://507766666",
	[Enum.HumanoidRigType.R6] = "rbxassetid://180435571",
}
local function idleOf(character: Model): string?
	local animate = character:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	if idle then
		for _, a in idle:GetChildren() do
			if a:IsA("Animation") and a.AnimationId ~= "" then
				return a.AnimationId
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid and DEFAULT_IDLE[humanoid.RigType]
end

-- Characters with Roblox's newer avatar joints are held together by AnimationConstraints
-- (limbs) and RigidConstraints (accessories). Those are solved by physics, which a WorldModel
-- doesn't run, so turn them back into Motor6Ds / Welds at the same attachments: the Animator
-- drives Motor6Ds without physics. Older characters already have Motor6Ds and are untouched.
local function classicJoints(copy: Model)
	for _, d in copy:GetDescendants() do
		if d:IsA("AnimationConstraint") or d:IsA("RigidConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				local joint = Instance.new(if d:IsA("AnimationConstraint") then "Motor6D" else "Weld") :: any
				joint.Name = d.Name
				joint.Part0 = p0
				joint.Part1 = p1
				joint.C0 = a0.CFrame
				joint.C1 = a1.CFrame
				joint.Parent = p1
			end
			d:Destroy()
		elseif d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then
			d:Destroy() -- the joint-limit helpers that come with the new joints
		end
	end
end

-- a copy of the avatar that can sit in a ViewportFrame: no scripts, frozen while it's posed
-- (standOn unfreezes the limbs so the idle can play)
local function avatarCopy(extra: Instance?): Model?
	if not avatarTemplate then
		return nil
	end
	local idle = idleOf(avatarTemplate)
	local wasArchivable = avatarTemplate.Archivable
	avatarTemplate.Archivable = true
	local copy = avatarTemplate:Clone()
	avatarTemplate.Archivable = wasArchivable
	if not copy then
		return nil
	end
	classicJoints(copy)
	for _, d in copy:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	-- neutral pose: rebuild every joint from its rest offsets (C0/C1), ignoring whatever
	-- animation the live character was mid-way through. Walk out from the root so each
	-- joint's Part0 is already in place.
	local root = copy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local motors = {}
		for _, d in copy:GetDescendants() do
			if d:IsA("Motor6D") and d.Part0 and d.Part1 then
				table.insert(motors, d)
			end
		end
		local placed = { [root] = true }
		local progress = true
		while progress do
			progress = false
			for i = #motors, 1, -1 do
				local motor = motors[i]
				if placed[motor.Part0] then
					motor.Part1.CFrame = motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
					placed[motor.Part1] = true
					table.remove(motors, i)
					progress = true
				end
			end
		end
		-- parts no joint reached (a rig that was never built): line up their matching
		-- "…RigAttachment"s, the way Humanoid:BuildRigFromAttachments does for R15
		local rigAttachments = {} -- name -> { attachment, … }
		for _, d in copy:GetDescendants() do
			if d:IsA("Attachment") and d.Name:match("RigAttachment$") and d.Parent:IsA("BasePart") then
				rigAttachments[d.Name] = rigAttachments[d.Name] or {}
				table.insert(rigAttachments[d.Name], d)
			end
		end
		progress = true
		while progress do
			progress = false
			for _, list in rigAttachments do
				if #list == 2 then
					local a, b = list[1], list[2]
					if placed[a.Parent] and not placed[b.Parent] then
						a, b = a, b
					elseif placed[b.Parent] and not placed[a.Parent] then
						a, b = b, a
					else
						continue
					end
					local part = b.Parent :: BasePart
					part.CFrame = a.WorldCFrame * b.CFrame:Inverse()
					placed[part] = true
					progress = true
				end
			end
		end
	end
	-- snap each accessory onto its body attachment (a rig that never spawned has them loose)
	local bodyAttachments = {}
	for _, d in copy:GetDescendants() do
		if d:IsA("Attachment") and d.Parent and d.Parent:IsA("BasePart") and not d:FindFirstAncestorOfClass("Accessory") then
			bodyAttachments[d.Name] = d
		end
	end
	for _, accessory in copy:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			for _, a in handle:GetChildren() do
				local body = a:IsA("Attachment") and bodyAttachments[a.Name]
				if body then
					handle.CFrame = body.WorldCFrame * a.CFrame:Inverse()
					break
				end
			end
		end
	end
	-- a group item to try on: wear the accessory (welded, so it moves with the idle) or
	-- dance the dance instead of idling
	if extra and extra:IsA("Accessory") then
		local accessory = extra:Clone()
		local handle = accessory:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			handle.Anchored = true
			handle.CanCollide = false
			for _, w in handle:GetChildren() do
				if w:IsA("JointInstance") or w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			for _, a in handle:GetChildren() do
				local body = a:IsA("Attachment") and bodyAttachments[a.Name]
				if body then
					handle.CFrame = body.WorldCFrame * a.CFrame:Inverse()
					local weld = Instance.new("Weld")
					weld.Part0 = body.Parent
					weld.Part1 = handle
					weld.C0 = body.CFrame
					weld.C1 = a.CFrame
					weld.Parent = handle
					break
				end
			end
			accessory.Parent = copy
		end
	elseif extra and extra:IsA("Animation") then
		idle = extra.AnimationId
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if idle then
		copy:SetAttribute("IdleAnimation", idle)
	end
	return copy
end

-- Plays the idle on an avatar already in the WorldModel. Only the root stays anchored; the
-- limbs hang off it by their joints, and accessories by their welds (a handle with no weld
-- stays anchored where it was snapped). Nothing falls: a WorldModel has no physics.
local function playIdle(avatar: Model)
	local id = avatar:GetAttribute("IdleAnimation")
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	local root = avatar:FindFirstChild("HumanoidRootPart")
	if not (id and humanoid and root) then
		warn("[CosmeticView] idle skipped:", if not id then "no idle animation id" elseif not humanoid then "no Humanoid" else "no HumanoidRootPart")
		return
	end
	local jointed = {}
	for _, d in avatar:GetDescendants() do
		if d:IsA("Motor6D") and d.Part1 then
			jointed[d.Part1] = true
		elseif (d:IsA("Weld") or d:IsA("WeldConstraint")) and d.Part1 then
			jointed[d.Part1] = true
			if d.Part0 then
				jointed[d.Part0] = true
			end
		end
	end
	if not next(jointed) then
		warn("[CosmeticView] idle skipped: the avatar copy has no joints (Motor6Ds)")
		return -- an unbuilt rig: keep it standing still
	end
	for _, d in avatar:GetDescendants() do
		if d:IsA("BasePart") and d ~= root and jointed[d] then
			d.Anchored = false
		end
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if ok and track then
		track.Looped = true
		track:Play(0)
	else
		warn("[CosmeticView] idle failed to load:", track, "| in DataModel:", avatar:IsDescendantOf(game))
	end
end

-- stands the avatar on whatever is under `at` (the pad's top), facing `face`
local function standOn(world: WorldModel, at: Vector3, face: Vector3, extra: Instance?): boolean
	local avatar = avatarCopy(extra)
	if not avatar then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { avatar }
	local hit = world:Raycast(at + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
	local floorY = if hit then hit.Position.Y else at.Y
	-- face the mic, then lift so the lowest body part rests exactly on the pad
	avatar:PivotTo(CFrame.lookAt(Vector3.new(at.X, floorY, at.Z), Vector3.new(face.X, floorY, face.Z)))
	local lowest = math.huge
	for _, d in avatar:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and not d:FindFirstAncestorOfClass("Accessory") then
			local cf, size = d.CFrame, d.Size
			for _, x in { -0.5, 0.5 } do
				for _, y in { -0.5, 0.5 } do
					for _, z in { -0.5, 0.5 } do
						lowest = math.min(lowest, cf:PointToWorldSpace(size * Vector3.new(x, y, z)).Y)
					end
				end
			end
		end
	end
	if lowest < math.huge then
		avatar:PivotTo(avatar:GetPivot() + Vector3.new(0, floorY - lowest, 0))
	end
	avatar.Parent = world
	playIdle(avatar)
	return true
end

-- a soft dark disc under the model so it sits on something
local function shadow(world: WorldModel, radius: number)
	local disc = Instance.new("Part")
	disc.Name = "Shadow"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.02, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(0, -0.03, 0) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = SHADOW
	disc.Transparency = 0.86
	disc.Material = Enum.Material.SmoothPlastic
	disc.Anchored = true
	disc.CastShadow = false
	disc.Parent = world
end

-- a copy of a cosmetic for the preview (queryable, so standOn's raycast can find the pad)
local function copyOf(source: Model): Model
	local copy = source:Clone()
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = true
		end
	end
	return copy
end

-- the scene for this kind + id, built around the origin; returns the camera direction
local function build(world: WorldModel, kind: string, id: string): Vector3?
	if kind == "Dance" or kind == "Accessory" then
		local asset = ugcAsset(id)
		if not asset or not standOn(world, Vector3.zero, Vector3.new(0, 0, -10), asset) then
			return nil
		end
		shadow(world, 1.6)
		return if kind == "Dance" then Vector3.new(0.3, 0.12, -1).Unit else Vector3.new(0.55, 0.1, -1).Unit
	end
	if kind == "Set" then
		local stage, mic = template("Stage", id .. "Stage"), template("Mic", id .. "Mic")
		if not (stage and mic) then
			return nil
		end
		local s = copyOf(stage)
		s:PivotTo(CFrame.new())
		s.Parent = world
		-- the mic stands in front of the pad, a little to the side, facing it
		local micAt = Vector3.new(-1.6, 0, -3.4)
		local m = copyOf(mic)
		m:PivotTo(CFrame.lookAt(micAt, Vector3.zero))
		m.Parent = world
		standOn(world, Vector3.zero, micAt)
		shadow(world, 3.1)
		return Vector3.new(0.8, 0.22, -1).Unit -- front-right, a little above the pad
	end
	local source = template(kind, id)
	if not source then
		return nil
	end
	local model = copyOf(source)
	model:PivotTo(CFrame.new()) -- front = -Z
	model.Parent = world
	if kind == "Stage" then
		standOn(world, Vector3.zero, Vector3.new(0, 0, -10))
		shadow(world, 3.0)
		return Vector3.new(0.65, 0.22, -1).Unit -- angled from the front, a little above the pad
	end
	shadow(world, 0.9)
	return Vector3.new(0.85, 0.12, -0.75).Unit -- mic: three-quarter view of the head
end

local function frameCamera(vf: ViewportFrame, world: WorldModel, dir: Vector3, margin: number?)
	-- fit the scene's box to the card: project its corners onto the camera's view plane
	local cf, size = world:GetBoundingBox()
	local centre = cf.Position
	local axes = CFrame.lookAt(Vector3.zero, -dir) -- camera orientation only
	local halfW, halfH, halfD = 0, 0, 0
	for _, x in { -0.5, 0.5 } do
		for _, y in { -0.5, 0.5 } do
			for _, z in { -0.5, 0.5 } do
				local corner = axes:VectorToObjectSpace(cf:PointToWorldSpace(size * Vector3.new(x, y, z)) - centre)
				halfW = math.max(halfW, math.abs(corner.X))
				halfH = math.max(halfH, math.abs(corner.Y))
				halfD = math.max(halfD, math.abs(corner.Z))
			end
		end
	end
	local abs = vf.AbsoluteSize
	local aspect = if abs.Y > 0 then abs.X / abs.Y else 1.8
	local t = math.tan(math.rad(FOV / 2))
	-- distance that fits the box's outline, plus a bit of its depth (the near side is bigger)
	local dist = math.max(halfH / t, halfW / (t * aspect)) * (margin or MARGIN) + halfD * 0.3
	local cam = vf.CurrentCamera or Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	cam.Parent = vf
	vf.CurrentCamera = cam
	return centre, dist
end

-- the night-ink card behind a model (white base, so the gradient shows its true colours)
local function paintCard(art: GuiObject)
	art.BackgroundColor3 = CARD
	local gradient = art:FindFirstChild("CardGradient") :: UIGradient?
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "CardGradient"
		gradient.Rotation = 90
		gradient.Color = NIGHT
		gradient.Parent = art
	end
	gradient.Enabled = true
end

local function render(art: GuiObject, kind: string, id: string): boolean
	local vf, world = viewport(art)
	world:ClearAllChildren()
	local dir = build(world, kind, id)
	if not dir then
		vf.Visible = false
		return false
	end
	-- a dance swings the arms well outside the standing pose: leave room around it
	-- a turning model is framed for its widest side, so nothing gets cut off mid-turn
	local sideDist = 0
	if SPINS[kind] then
		_, sideDist = frameCamera(vf, world, CFrame.Angles(0, math.pi / 2, 0):VectorToWorldSpace(dir))
	end
	local centre, dist = frameCamera(vf, world, dir, if kind == "Dance" then 1.45 elseif kind == "Accessory" then 1.1 else nil)
	if sideDist > dist then
		dist = sideDist
		vf.CurrentCamera.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	end
	orbits[art] = { Centre = centre, Dir = dir, Dist = dist, Yaw = 0, Auto = SPINS[kind] == true, HeldUntil = os.clock() + SPIN_DELAY }
	forget(art)
	paintCard(art)
	vf.Visible = true
	hideDrawnArt(art)
	return true
end

function CosmeticView.Show(art: GuiObject?, kind: string, id: string?)
	if not art or not id then
		return CosmeticView.Clear(art)
	end
	forget(art)
	local key = `{kind}:{id}`
	local vf = art:FindFirstChild("Model3D")
	if vf and vf:GetAttribute("Shown") == key and vf.Visible then
		paintCard(art) -- the caller may have just repainted the card's own colour
		hideDrawnArt(art)
		return
	end
	if render(art, kind, id) then
		art.Model3D:SetAttribute("Shown", key)
		shown[art] = { kind, id }
	else
		-- The local avatar may not have finished loading yet (especially on mobile).
		-- Remember the request so SetAvatar can retry the viewport when it becomes available.
		shown[art] = { kind, id }
	end
end

function CosmeticView.Clear(art: GuiObject?)
	if not art then
		return
	end
	shown[art] = nil
	local vf = art:FindFirstChild("Model3D")
	if vf then
		vf.Visible = false
		vf:SetAttribute("Shown", nil)
	end
	local gradient = art:FindFirstChild("CardGradient")
	if gradient then
		gradient.Enabled = false -- the caller's own background colour shows again
	end
end

-- Drag on art.Spin (a transparent button over the model) to turn the camera around it.
function CosmeticView.EnableSpin(art: GuiObject?)
	local catcher = art and art:FindFirstChild("Spin") :: GuiButton?
	if not catcher or catcher:GetAttribute("SpinOn") then
		return
	end
	catcher:SetAttribute("SpinOn", true)
	local UserInputService = game:GetService("UserInputService")
	local dragging: InputObject? = nil
	local lastX = 0
	catcher.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = input
			lastX = input.Position.X
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local moved = input.UserInputType == Enum.UserInputType.MouseMovement
			or (input.UserInputType == Enum.UserInputType.Touch and input == dragging)
		local orbit = orbits[art :: GuiObject]
		local vf = (art :: GuiObject):FindFirstChild("Model3D") :: ViewportFrame?
		local cam = vf and vf.CurrentCamera
		if not (moved and orbit and cam) then
			return
		end
		orbit.Yaw -= (input.Position.X - lastX) * 0.012
		orbit.HeldUntil = os.clock() + SPIN_RESUME
		lastX = input.Position.X
		local dir = CFrame.Angles(0, orbit.Yaw, 0):VectorToWorldSpace(orbit.Dir)
		cam.CFrame = CFrame.lookAt(orbit.Centre + dir * orbit.Dist, orbit.Centre)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = nil
		end
	end)
end

-- Who stands on the pads. Redraws every card already showing a stage or set.
function CosmeticView.SetAvatar(model: Model?)
	avatarTemplate = model
	for art, what in shown do
		if art.Parent and what[1] ~= "Mic" then
			render(art, what[1], what[2])
		end
	end
end

-- on the client, the avatar is the local player's character (re-copied when it respawns
-- or their look changes)
if RunService:IsClient() and Players.LocalPlayer then
	local player = Players.LocalPlayer
	local function track(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not player:HasAppearanceLoaded() then
			player.CharacterAppearanceLoaded:Wait()
		end
		task.wait(0.2) -- accessories finish welding
		if player.Character == character and humanoid then
			CosmeticView.SetAvatar(character)
		end
	end
	if player.Character then
		task.spawn(track, player.Character)
	end
	player.CharacterAdded:Connect(track)
end

-- the auto turn: one loop for every card, only the ones actually on screen move
-- (hidden, or scrolled / clipped out of view: a viewport off screen still costs a render)
local function onScreen(gui: GuiObject): boolean
	local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
			if node ~= gui and (node.ClipsDescendants or node:IsA("ScrollingFrame")) then
				local p, s = node.AbsolutePosition, node.AbsoluteSize
				if pos.X > p.X + s.X or pos.Y > p.Y + s.Y or pos.X + size.X < p.X or pos.Y + size.Y < p.Y then
					return false
				end
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

if RunService:IsClient() and RunService:IsRunning() then
	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, MAX_STEP)
		local now = os.clock()
		for art, orbit in orbits do
			if not orbit.Auto or now < orbit.HeldUntil or not art.Parent then
				continue
			end
			local vf = art:FindFirstChild("Model3D") :: ViewportFrame?
			local cam = vf and vf.CurrentCamera
			if not (vf and cam and onScreen(vf)) then
				continue
			end
			orbit.Yaw += dt * AUTO_SPIN
			local dir = CFrame.Angles(0, orbit.Yaw, 0):VectorToWorldSpace(orbit.Dir)
			cam.CFrame = CFrame.lookAt(orbit.Centre + dir * orbit.Dist, orbit.Centre)
		end
	end)
end

return CosmeticView
