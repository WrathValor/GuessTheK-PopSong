--| CustomPrompts
-- Every ProximityPrompt in the game drawn in the Photocard style instead of Roblox's grey
-- default: a white pill with an ink outline and hard shadow, a yellow key and the action, with
-- the object name under it in grey. The look is one BillboardGui built in Studio
-- (ReplicatedStorage.Assets.PromptTemplate); this sets every prompt to Style = Custom and
-- clones the template onto the prompt's part while Roblox says it's in range.
--   Keyboard: the prompt's key (E, or F for View Profile)
--   Gamepad:  the button's own icon, on a blue key
--   Touch:    TAP on a mint key, and the whole pill is the button
-- It pops in, gives a little squeeze when used and pops out. Prompts with a HoldDuration fill
-- the key pink while held (none use one today). The template has AlwaysOnTop off (with it on
-- it didn't draw), so each one is pulled toward the camera, clear of the part it sits on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LOCAL_PLAYER = Players.LocalPlayer
local C = Color3.fromHex

local KEY_COLOUR = {
	[Enum.ProximityPromptInputType.Keyboard] = C("FFE07A"),
	[Enum.ProximityPromptInputType.Gamepad] = C("9ED8F5"),
	[Enum.ProximityPromptInputType.Touch] = C("A7E9B8"),
}
local POP_IN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SQUEEZE = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHADOW = 4 -- px, the hard shadow's offset (matches the frames)
local FRONT_GAP = 0.6 -- studs between the prompt and the front of the part it's on

local CustomPrompts = {}

local template: BillboardGui? = nil
local shown = {} :: { [ProximityPrompt]: { Gui: BillboardGui, Connections: { RBXScriptConnection } } }

local function custom(d: Instance)
	if d:IsA("ProximityPrompt") then
		d.Style = Enum.ProximityPromptStyle.Custom
	end
end

-- what the key shows for this device
local function paintKey(gui: BillboardGui, prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local key = gui.Holder.Pill.Key
	key.BackgroundColor3 = KEY_COLOUR[inputType] or KEY_COLOUR[Enum.ProximityPromptInputType.Keyboard]
	local letter, icon = key.Letter, key.Icon
	letter.Visible, icon.Visible = true, false
	letter.TextSize = 16
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local ok, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, prompt.GamepadKeyCode)
		if ok and image and image ~= "" then
			icon.Image = image
			icon.Visible, letter.Visible = true, false
		else
			letter.Text = string.gsub(prompt.GamepadKeyCode.Name, "^Button", "")
		end
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		letter.Text = "TAP"
		letter.TextSize = 10
	else
		local ok, s = pcall(UserInputService.GetStringForKeyCode, UserInputService, prompt.KeyboardKeyCode)
		letter.Text = if ok and s and s ~= "" then string.upper(s) else prompt.KeyboardKeyCode.Name
	end
end

local function paintText(gui: BillboardGui, prompt: ProximityPrompt)
	local text = gui.Holder.Pill.Text
	local action = if prompt.ActionText ~= "" then prompt.ActionText else prompt.ObjectText
	text.Action.Text = if action ~= "" then action else "Interact"
	text.Object.Text = if prompt.ActionText ~= "" then prompt.ObjectText else ""
	text.Object.Visible = text.Object.Text ~= ""
end

-- the shadow and the touch button follow the pill, which sizes itself to its text
local function fit(gui: BillboardGui)
	local holder = gui.Holder
	local size = holder.Pill.AbsoluteSize / holder.Pop.Scale
	if size.X <= 0 then
		return
	end
	holder.Shadow.Size = UDim2.fromOffset(size.X, size.Y)
	holder.Shadow.Position = UDim2.new(0.5, SHADOW, 0.5, SHADOW)
	holder.Tap.Size = UDim2.fromOffset(size.X + 8, size.Y + 8)
end

local function hide(prompt: ProximityPrompt)
	local entry = shown[prompt]
	if not entry then
		return
	end
	shown[prompt] = nil
	for _, c in entry.Connections do
		c:Disconnect()
	end
	local gui = entry.Gui
	local tween = TweenService:Create(gui.Holder.Pop, POP_OUT, { Scale = 0 })
	tween.Completed:Once(function()
		gui:Destroy()
	end)
	tween:Play()
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if not template then
		return
	end
	hide(prompt)
	local gui = template:Clone()
	local adornee = prompt.Parent :: any
	gui.Adornee = adornee
	gui.Enabled = true
	-- drawn in the world (AlwaysOnTop off), so pull it toward the camera out of the part it's on
	if adornee and adornee:IsA("BasePart") then
		local size = adornee.Size
		gui.StudsOffset = Vector3.new(0, 0, math.max(size.X, size.Z) / 2 + FRONT_GAP)
	end
	local holder = gui.Holder
	local pop = holder.Pop
	pop.Scale = 0
	paintKey(gui, prompt, inputType)
	paintText(gui, prompt)
	local connections = {}
	shown[prompt] = { Gui = gui, Connections = connections }

	table.insert(connections, holder.Pill:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fit(gui)
	end))
	-- the text can change while it's up (e.g. the Fan Club machine: Join → Claim)
	for _, prop in { "ActionText", "ObjectText" } do
		table.insert(connections, prompt:GetPropertyChangedSignal(prop):Connect(function()
			paintText(gui, prompt)
		end))
	end
	-- a used prompt gives a little squeeze
	table.insert(connections, prompt.Triggered:Connect(function()
		local down = TweenService:Create(pop, SQUEEZE, { Scale = 0.88 })
		down.Completed:Once(function()
			if shown[prompt] then
				TweenService:Create(pop, POP_IN, { Scale = 1 }):Play()
			end
		end)
		down:Play()
	end))
	-- holds fill the key
	local fill = holder.Pill.Key.Fill
	table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function()
		if prompt.HoldDuration <= 0 then
			return
		end
		fill.Visible = true
		fill.Size = UDim2.fromScale(1, 0)
		TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
	end))
	table.insert(connections, prompt.PromptButtonHoldEnded:Connect(function()
		fill.Visible = false
	end))
	-- touch: the pill is the button
	local tap = holder.Tap
	tap.Visible = inputType == Enum.ProximityPromptInputType.Touch
	if tap.Visible then
		table.insert(connections, tap.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end))
		table.insert(connections, tap.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end))
	end

	gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")
	fit(gui)
	TweenService:Create(pop, POP_IN, { Scale = 1 }):Play()
end

function CustomPrompts.Start()
	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("Assets", 30)
		template = assets and assets:WaitForChild("PromptTemplate", 30) :: BillboardGui?
		if not template then
			warn("[CustomPrompts] no ReplicatedStorage.Assets.PromptTemplate: keeping Roblox's prompts")
			return
		end
		for _, d in workspace:GetDescendants() do
			custom(d)
		end
		workspace.DescendantAdded:Connect(custom)
		ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
			if prompt.Style == Enum.ProximityPromptStyle.Custom then
				show(prompt, inputType)
			end
		end)
		ProximityPromptService.PromptHidden:Connect(hide)
	end)
end

return CustomPrompts
