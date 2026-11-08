--| CinematicCamera
-- Recording mode for promo videos. F4 toggles it for players allowed to use it (Studio, or
-- the owning group's MIN_RANK+, matching CmdrController). It hides every UI, name tag and
-- the mouse cursor, and flies a smoothed free camera. Drop keyframes and play them back
-- as a smooth dolly shot through the map.
--
--   WASD move · Q/E down/up · hold right mouse to look · Shift slow · scroll = fly speed
--   [ / ] lens (FOV) · K add keyframe · P play path · C clear keyframes · H hide yourself

--| Services
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

--| Variables
local LOCAL_PLAYER = Players.LocalPlayer
local RENDER_NAME = "CinematicCamera"
local MOVE_ACTION = "CinematicMove"
local MIN_RANK = 254 -- keep in step with CmdrController / CmdrService.MIN_RANK

-- tuning
local TOGGLE_KEY = Enum.KeyCode.F4
local FLY_SPEED = 14 -- studs/s at the start
local SLOW_FACTOR = 0.3 -- holding Shift
local MOVE_SMOOTH = 3 -- lower = floatier starts and stops
local LOOK_SMOOTH = 6 -- lower = lazier, more cinematic turns
local LOOK_SENSITIVITY = 0.0035 -- radians per pixel
local FOV_STEP = 5
local FOV_MIN, FOV_MAX = 15, 100
local SEGMENT_SECONDS = 3 -- path playback time between two keyframes

local MOVE_KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.LeftShift, Enum.KeyCode.Space,
}

--| CinematicCamera
local CinematicCamera = {}
CinematicCamera.Active = false

local keys: { [Enum.KeyCode]: boolean } = {}
local position = Vector3.zero
local velocity = Vector3.zero
local yaw, pitch = 0, 0
local targetYaw, targetPitch = 0, 0
local fov, targetFov = 70, 70
local speed = FLY_SPEED
local hideSelf = false
local looking = false

local keyframes: { { CFrame: CFrame, Fov: number } } = {}
local playing: { Start: number, Total: number }? = nil

-- what we turned off, so leaving puts back exactly what was on
local saved = {
	CameraType = Enum.CameraType.Custom,
	CameraSubject = nil :: Instance?,
	Fov = 70,
	Guis = {} :: { LayerCollector },
	CoreGuis = {} :: { Enum.CoreGuiType },
	MouseIcon = true,
}

local toast: TextLabel? = nil
local inputConns: { RBXScriptConnection } = {}

-- --------------------------------- Helpers -------------------------------- --

local function allowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank >= MIN_RANK
	end
	return player.UserId == game.CreatorId
end

-- A tiny corner note (keyframe added, path playing). Fades on its own; cut it in the edit.
local function notify(text: string)
	local label = toast
	if not label or not label.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "CinematicToast"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 1000
		label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0, 1)
		label.Position = UDim2.new(0, 16, 1, -16)
		label.Size = UDim2.fromOffset(320, 22)
		label.BackgroundTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
		label.TextSize = 16
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.5
		label.Parent = gui
		gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
		toast = label
	end
	assert(label)
	label.Text = text
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.5
	TweenService:Create(label, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.2), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

local function hideInterface()
	table.clear(saved.Guis)
	for _, gui in LOCAL_PLAYER:WaitForChild("PlayerGui"):GetChildren() do
		if gui:IsA("LayerCollector") and gui.Enabled and gui.Name ~= "CinematicToast" then
			gui.Enabled = false
			table.insert(saved.Guis, gui)
		end
	end
	-- name tags, rival tags and any other floating labels in the world
	for _, gui in workspace:GetDescendants() do
		if gui:IsA("BillboardGui") and gui.Enabled then
			gui.Enabled = false
			table.insert(saved.Guis, gui)
		end
	end

	table.clear(saved.CoreGuis)
	for _, coreType in Enum.CoreGuiType:GetEnumItems() do
		if coreType ~= Enum.CoreGuiType.All and StarterGui:GetCoreGuiEnabled(coreType) then
			table.insert(saved.CoreGuis, coreType)
		end
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)

	saved.MouseIcon = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false
end

local function showInterface()
	for _, gui in saved.Guis do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(saved.Guis)
	for _, coreType in saved.CoreGuis do
		StarterGui:SetCoreGuiEnabled(coreType, true)
	end
	pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", true)
	UserInputService.MouseIconEnabled = saved.MouseIcon
end

local function setSelfHidden(hidden: boolean)
	local char = LOCAL_PLAYER.Character
	if not char then
		return
	end
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function cameraCFrame(): CFrame
	return CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
end

-- jump the free camera to a shot (used when a path ends, so flying carries on from there)
local function setFromCFrame(cf: CFrame)
	position = cf.Position
	local rx, ry = cf:ToEulerAnglesYXZ()
	pitch, yaw = rx, ry
	targetPitch, targetYaw = rx, ry
	velocity = Vector3.zero
end

local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- eases the whole path in and out, so the shot starts and lands gently
local function smootherstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
end

-- ---------------------------------- Frame --------------------------------- --

local function stepPath(camera: Camera): boolean
	local path = playing
	if not path then
		return false
	end
	local alpha = (os.clock() - path.Start) / path.Total
	local count = #keyframes
	if alpha >= 1 then
		local last = keyframes[count]
		playing = nil
		setFromCFrame(last.CFrame)
		fov, targetFov = last.Fov, last.Fov
		camera.CFrame = last.CFrame
		camera.FieldOfView = last.Fov
		return true
	end

	local along = smootherstep(alpha) * (count - 1)
	local i = math.min(math.floor(along) + 1, count - 1)
	local t = along - (i - 1)
	local a, b = keyframes[i], keyframes[i + 1]
	local before = keyframes[math.max(i - 1, 1)]
	local after = keyframes[math.min(i + 2, count)]

	local pos = catmullRom(before.CFrame.Position, a.CFrame.Position, b.CFrame.Position, after.CFrame.Position, t)
	local rot = a.CFrame.Rotation:Lerp(b.CFrame.Rotation, t)
	camera.CFrame = CFrame.new(pos) * rot
	camera.FieldOfView = a.Fov + (b.Fov - a.Fov) * t
	return true
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	if hideSelf then
		setSelfHidden(true)
	end
	if stepPath(camera) then
		return
	end

	-- look
	local lookAlpha = 1 - math.exp(-dt * LOOK_SMOOTH)
	yaw += (targetYaw - yaw) * lookAlpha
	pitch += (targetPitch - pitch) * lookAlpha
	fov += (targetFov - fov) * lookAlpha

	-- move, relative to where the camera faces
	local cf = cameraCFrame()
	local dir = Vector3.zero
	if keys[Enum.KeyCode.W] then dir += cf.LookVector end
	if keys[Enum.KeyCode.S] then dir -= cf.LookVector end
	if keys[Enum.KeyCode.D] then dir += cf.RightVector end
	if keys[Enum.KeyCode.A] then dir -= cf.RightVector end
	if keys[Enum.KeyCode.E] then dir += Vector3.yAxis end
	if keys[Enum.KeyCode.Q] then dir -= Vector3.yAxis end
	local wanted = Vector3.zero
	if dir.Magnitude > 0 then
		wanted = dir.Unit * speed * (keys[Enum.KeyCode.LeftShift] and SLOW_FACTOR or 1)
	end
	velocity = velocity:Lerp(wanted, 1 - math.exp(-dt * MOVE_SMOOTH))
	position += velocity * dt

	camera.CFrame = cameraCFrame()
	camera.FieldOfView = fov
end

-- ---------------------------------- Input --------------------------------- --

local function onMoveKey(_name: string, state: Enum.UserInputState, input: InputObject)
	keys[input.KeyCode] = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink -- your character stays put while the camera flies
end

local function onKey(input: InputObject, processed: boolean)
	if processed or not CinematicCamera.Active then
		return
	end
	local code = input.KeyCode
	if code == Enum.KeyCode.K then
		table.insert(keyframes, { CFrame = workspace.CurrentCamera.CFrame, Fov = fov })
		notify(`Keyframe {#keyframes}`)
	elseif code == Enum.KeyCode.P then
		if #keyframes < 2 then
			notify("Add at least 2 keyframes (K)")
		else
			playing = { Start = os.clock(), Total = SEGMENT_SECONDS * (#keyframes - 1) }
		end
	elseif code == Enum.KeyCode.C then
		table.clear(keyframes)
		playing = nil
		notify("Keyframes cleared")
	elseif code == Enum.KeyCode.H then
		hideSelf = not hideSelf
		setSelfHidden(hideSelf)
	elseif code == Enum.KeyCode.LeftBracket then
		targetFov = math.clamp(targetFov + FOV_STEP, FOV_MIN, FOV_MAX)
	elseif code == Enum.KeyCode.RightBracket then
		targetFov = math.clamp(targetFov - FOV_STEP, FOV_MIN, FOV_MAX)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end

local function onKeyEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and looking then
		looking = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function onChanged(input: InputObject)
	if not CinematicCamera.Active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement and looking and not playing then
		targetYaw -= input.Delta.X * LOOK_SENSITIVITY
		targetPitch = math.clamp(targetPitch - input.Delta.Y * LOOK_SENSITIVITY, -1.45, 1.45)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		speed = math.clamp(speed * (1.25 ^ input.Position.Z), 2, 150)
	end
end

-- ----------------------------------- API ---------------------------------- --

function CinematicCamera.Enable()
	if CinematicCamera.Active then
		return
	end
	CinematicCamera.Active = true
	local camera = workspace.CurrentCamera
	saved.CameraType = camera.CameraType
	saved.CameraSubject = camera.CameraSubject
	saved.Fov = camera.FieldOfView

	setFromCFrame(camera.CFrame)
	fov, targetFov = camera.FieldOfView, camera.FieldOfView
	table.clear(keys)
	hideInterface()

	ContextActionService:BindActionAtPriority(MOVE_ACTION, onMoveKey, false, Enum.ContextActionPriority.High.Value + 100, table.unpack(MOVE_KEYS))
	-- after the default camera and DuelCamera, so this shot always wins
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 10, step)
end

function CinematicCamera.Disable()
	if not CinematicCamera.Active then
		return
	end
	CinematicCamera.Active = false
	playing = nil
	looking = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
	ContextActionService:UnbindAction(MOVE_ACTION)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	table.clear(keys)

	hideSelf = false
	setSelfHidden(false)
	showInterface()

	local camera = workspace.CurrentCamera
	camera.CameraType = saved.CameraType
	camera.CameraSubject = saved.CameraSubject
	camera.FieldOfView = saved.Fov
end

function CinematicCamera.Start()
	if not allowed(LOCAL_PLAYER) then
		return
	end
	table.insert(inputConns, UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == TOGGLE_KEY and not processed then
			if CinematicCamera.Active then
				CinematicCamera.Disable()
			else
				CinematicCamera.Enable()
			end
			return
		end
		onKey(input, processed)
	end))
	table.insert(inputConns, UserInputService.InputEnded:Connect(onKeyEnded))
	table.insert(inputConns, UserInputService.InputChanged:Connect(onChanged))
	-- respawning mid-shot: keep yourself hidden if you asked to be
	LOCAL_PLAYER.CharacterAdded:Connect(function()
		if CinematicCamera.Active and hideSelf then
			task.defer(setSelfHidden, true)
		end
	end)
end

return CinematicCamera
