--| RivalTag
-- Name tag over the opponent's head during a duel (or over your solo double), built from
-- the "Rival name tag" design board: white name plate with a lilac level badge, and a
-- status chip tucked under it — mint "Listening…" with bouncing bars, yellow "Answered!"
-- with a tick — then a small pointer down to the head. Only exists on your screen.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local LILAC = C("B9A6FF")
local CHIP = {
	Listening = C("A7E9B8"),
	Answered = C("FFE07A"),
}
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local PLATE_H = 30
local CHIP_H = 22
local CHIP_Y = PLATE_H - 1 -- chip tucks just under the plate's outline

local RivalTag = {}

local gui: BillboardGui? = nil
local bars: { Frame } = {}
local barConn: RBXScriptConnection? = nil

-- --------------------------------- Helpers -------------------------------- --

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function round(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function outline(parent: Instance, thickness: number)
	new("UIStroke", {
		Color = INK,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function row(parent: Instance, gap: number, padL: number, padR: number)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
	new("UIPadding", { PaddingLeft = UDim.new(0, padL), PaddingRight = UDim.new(0, padR) }, parent)
end

-- A centred group: an auto-width face with a hard ink shadow behind it (offset `drop`).
-- The group auto-sizes to the face, so a UIScale on it pops both together.
local function card(parent: Instance, name: string, y: number, height: number, radius: number, stroke: number, drop: number, colour: Color3)
	local group = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, parent)
	new("UIScale", {}, group)
	local shadow = new("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(drop, drop),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = INK,
		ZIndex = 1,
	}, group)
	round(shadow, radius)
	outline(shadow, stroke)
	local face = new("Frame", {
		Name = "Face",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
		BackgroundColor3 = colour,
		ZIndex = 2,
	}, group)
	round(face, radius)
	outline(face, stroke)
	return group, face
end

local function label(parent: Instance, text: string, size: number, font: Font, order: number, height: number): TextLabel
	return new("TextLabel", {
		Name = "Label",
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
		BackgroundTransparency = 1,
		FontFace = font,
		TextSize = size,
		TextColor3 = INK,
		Text = text,
		ZIndex = 3,
	}, parent)
end

local function stopBars()
	if barConn then
		barConn:Disconnect()
		barConn = nil
	end
end

local function startBars()
	stopBars()
	barConn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for i, bar in bars do
			local h = 4 + 7 * math.abs(math.sin(t * 7 + i * 1.3))
			bar.Size = UDim2.fromOffset(3, math.floor(h))
		end
	end)
end

-- --------------------------------- API ------------------------------------ --

-- Puts the tag on `model`'s head. Replaces any existing tag.
function RivalTag.Attach(model: Model?, name: string, level: number?)
	RivalTag.Clear()
	local head = model and model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	local bb = new("BillboardGui", {
		Name = "RivalTag",
		Adornee = head,
		Size = UDim2.fromOffset(240, 76),
		StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 140,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- name plate: [LV n] Name
	local plateGroup, plate = card(bb, "Plate", 0, PLATE_H, 11, 3, 3, WHITE)
	plateGroup.ZIndex = 2 -- the plate's outline sits over the top edge of the chip
	row(plate, 7, 10, 14)
	if level then
		local badge = new("TextLabel", {
			Name = "Level",
			LayoutOrder = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			BackgroundColor3 = LILAC,
			FontFace = FONT_HEAVY,
			TextSize = 10,
			TextColor3 = INK,
			Text = `LV {level}`,
			ZIndex = 3,
		}, plate)
		round(badge, 6)
		outline(badge, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, badge)
	end
	local nameLabel = label(plate, name, 17, FONT, 2, PLATE_H)
	nameLabel.Name = "PlayerName"

	-- status chip: icon + text
	local chipGroup, chip = card(bb, "Status", CHIP_Y, CHIP_H, 8, 2.5, 2, CHIP.Listening)
	chipGroup.ZIndex = 1
	row(chip, 6, 7, 9)

	-- listening icon: three bouncing bars
	local eq = new("Frame", {
		Name = "Bars",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(13, 12),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, chip)
	bars = {}
	for i = 1, 3 do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, (i - 1) * 5, 1, 0),
			Size = UDim2.fromOffset(3, 7),
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, eq)
		round(bar, 1)
		table.insert(bars, bar)
	end
	-- answered icon: a tick
	new("TextLabel", {
		Name = "Tick",
		LayoutOrder = 1,
		Visible = false,
		Size = UDim2.fromOffset(12, 14),
		BackgroundTransparency = 1,
		FontFace = FONT_HEAVY,
		TextSize = 14,
		TextColor3 = INK,
		Text = "✓",
		ZIndex = 3,
	}, chip)
	label(chip, "Listening…", 12, FONT, 2, CHIP_H)

	-- pointer down to the head
	new("TextLabel", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CHIP_Y + CHIP_H + 4),
		Size = UDim2.fromOffset(16, 10),
		BackgroundTransparency = 1,
		FontFace = FONT_HEAVY,
		TextSize = 13,
		TextColor3 = INK,
		Text = "▼",
	}, bb)

	bb.Parent = head
	gui = bb
	startBars()
end

-- "Listening…", "Answered!" or "" (between rounds: name only).
function RivalTag.SetStatus(text: string)
	local bb = gui
	if not bb or not bb.Parent then
		return
	end
	local group = bb:FindFirstChild("Status") :: Frame
	local chip = group:FindFirstChild("Face") :: Frame
	local pointer = bb:FindFirstChild("Pointer") :: TextLabel

	if text == "" then
		group.Visible = false
		pointer.Position = UDim2.new(0.5, 0, 0, PLATE_H + 6)
		stopBars()
		return
	end

	local answered = text:find("Answer") ~= nil
	local changed = not group.Visible or (chip:FindFirstChild("Label") :: TextLabel).Text ~= text
	group.Visible = true
	pointer.Position = UDim2.new(0.5, 0, 0, CHIP_Y + CHIP_H + 4)
	chip.BackgroundColor3 = if answered then CHIP.Answered else CHIP.Listening
	;(chip:FindFirstChild("Label") :: TextLabel).Text = text
	;(chip:FindFirstChild("Bars") :: Frame).Visible = not answered
	;(chip:FindFirstChild("Tick") :: TextLabel).Visible = answered
	if answered then
		stopBars()
	elseif not barConn then
		startBars()
	end

	if changed then
		local scale = group:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale = 0.6
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
	end
end

function RivalTag.Clear()
	stopBars()
	bars = {}
	if gui then
		gui:Destroy()
		gui = nil
	end
end

return RivalTag
