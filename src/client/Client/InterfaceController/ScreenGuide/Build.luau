--| ScreenGuide UI builder
-- Builds Interface.Frames.Guide from the "Screen guides" boards on the design canvas (Roll
-- guide 1–3): the same spotlight + speech bubble as the lobby nudges (HUDController/Nudges),
-- with steps. It sits over every screen in the Frames canvas (ZIndex above them all):
--   Blocker   full-canvas, transparent: swallows clicks while a guide is up
--   Spot      Dim (a frame on the lit part whose 4000 px outline dims everything else) +
--             the yellow Ring, both placed by code
--   Bubble    holder, placed by code; Shadow (sized by code), Arrow (the tail, a cream square
--             turned 45° under the face), Face, Join (cream strip over the face's outline
--             where the tail meets it)
--   Face      a vertical list, each part shown or hidden per step:
--             Title · Body · Ladder (Normal › Gold › Rainbow cards + copies) · Heading ·
--             Points (Point1..3: swatch + text) · Tiles (Tile1..3: Label + Text) ·
--             Footer (Dots Dot1..5 + Step "1 of 3", Next button + its PadIcon)
-- Run once in Studio from the command bar (Edit mode):
--   local B = require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.ScreenGuide.Build)
--   B.Build(game.StarterGui.Interface.Frames)
-- An existing Guide is replaced. ScreenGuide (./init) finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local GOLD = C("FFD34E")
local MUTED = C("5C566B")
local BODY_INK = C("3E3850")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
-- body copy is Medium so <b> in it stands out (Builder Sans Bold)
local BODY_TEXT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

local PAD_SHEET = "rbxassetid://135713292515019" -- PadBinds' Xbox sheet (A is cell 0, 0)

local Build = {}
Build.WIDTH = 420
Build.POINTS = 3
Build.TILES = 3
Build.DOTS = 5

-- [[ Helpers (same shapes as the other builders) ]]

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end

local function stroke(p: Instance, t: number)
	new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function list(parent: Instance, gap: number, horizontal: boolean?, centred: boolean?)
	new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		HorizontalAlignment = if centred then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

-- [[ Parts ]]

local function buildSpot(guide: Frame)
	local spot = new("Frame", { Name = "Spot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, guide)
	-- the dim: one see-through frame over the lit part with a huge outline that covers the rest
	-- of the screen (four panels left hairline seams where they met; this also rounds the hole)
	local dim = new("Frame", { Name = "Dim", BackgroundTransparency = 1, Size = UDim2.new() }, spot)
	corner(dim, 16)
	new("UIStroke", { Color = INK, Transparency = 0.38, Thickness = 4000, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, dim)
	local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, Size = UDim2.new() }, spot)
	corner(ring, 16)
	new("UIStroke", { Color = YELLOW, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
end

-- one level card of the ladder: a small photocard, its name and the copies it needs
local function ladderCard(parent: Instance, name: string, order: number, colour: Color3)
	local holder = new("Frame", { Name = name, LayoutOrder = order, Size = UDim2.fromOffset(72, 112), BackgroundTransparency = 1 }, parent)
	local shadow = new("Frame", { Name = "CardShadow", Position = UDim2.fromOffset(8, 3), Size = UDim2.fromOffset(62, 80), BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(shadow, 9)
	local c = new("Frame", { Name = "Card", Position = UDim2.fromOffset(5, 0), Size = UDim2.fromOffset(62, 80), BackgroundColor3 = colour, BorderSizePixel = 0, ZIndex = 2 }, holder)
	corner(c, 9)
	stroke(c, 3)
	text(holder, "Label", { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 14), FontFace = HEAD, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, Text = string.upper(name) })
	text(holder, "Copies", { Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, Text = "1 copy" })
end

local function arrow(parent: Instance, order: number)
	text(parent, "Arrow" .. order, { LayoutOrder = order, Size = UDim2.fromOffset(14, 80), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "›" })
end

local function buildFace(bubble: Frame)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.fromOffset(Build.WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CREAM,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, bubble)
	corner(face, 14)
	stroke(face, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 12) }, face)
	list(face, 8)
	local inner = Build.WIDTH - 32

	text(face, "Title", { LayoutOrder = 1, Size = UDim2.fromOffset(inner, 22), FontFace = HEAD, TextSize = 18, Text = "Title" })
	text(face, "Body", { LayoutOrder = 2, Size = UDim2.fromOffset(inner, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = BODY_TEXT, TextSize = 15, TextColor3 = BODY_INK, Text = "Body" })

	-- Normal › Gold › Rainbow (the Rainbow card gets TierShine's moving rainbow at runtime)
	local ladder = new("Frame", { Name = "Ladder", LayoutOrder = 3, Size = UDim2.fromOffset(inner, 116), BackgroundTransparency = 1, Visible = false }, face)
	list(ladder, 6, true, true)
	ladderCard(ladder, "Normal", 1, WHITE)
	arrow(ladder, 2)
	ladderCard(ladder, "Gold", 3, GOLD)
	arrow(ladder, 4)
	ladderCard(ladder, "Rainbow", 5, WHITE)
	new("UIGradient", { Name = "Rainbow" }, ladder.Rainbow.Card)

	text(face, "Heading", { LayoutOrder = 4, Size = UDim2.fromOffset(inner, 14), TextSize = 12, TextColor3 = MUTED, TextWrapped = false, Text = "HEADING", Visible = false })

	local points = new("Frame", { Name = "Points", LayoutOrder = 5, Size = UDim2.fromOffset(inner, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false }, face)
	list(points, 7)
	for i = 1, Build.POINTS do
		local p = new("Frame", { Name = "Point" .. i, LayoutOrder = i, Size = UDim2.fromOffset(inner, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, points)
		local sw = new("Frame", { Name = "Swatch", Size = UDim2.fromOffset(22, 22), BackgroundColor3 = MINT, BorderSizePixel = 0 }, p)
		corner(sw, 6)
		stroke(sw, 2)
		text(p, "Text", { Position = UDim2.fromOffset(32, 1), Size = UDim2.new(1, -32, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = BODY_TEXT, TextSize = 14, TextColor3 = BODY_INK, Text = "Point" })
	end

	local tiles = new("Frame", { Name = "Tiles", LayoutOrder = 6, Size = UDim2.fromOffset(inner, 58), BackgroundTransparency = 1, Visible = false }, face)
	list(tiles, 8, true)
	local tw = math.floor((inner - 16) / Build.TILES)
	for i = 1, Build.TILES do
		local t = new("Frame", { Name = "Tile" .. i, LayoutOrder = i, Size = UDim2.fromOffset(tw, 58), BackgroundColor3 = YELLOW, BorderSizePixel = 0 }, tiles)
		corner(t, 10)
		stroke(t, 2)
		text(t, "Label", { Position = UDim2.fromOffset(8, 7), Size = UDim2.new(1, -16, 0, 16), FontFace = HEAD, TextSize = 13, TextWrapped = false, Text = "Name" })
		text(t, "Text", { Position = UDim2.fromOffset(8, 25), Size = UDim2.new(1, -16, 0, 28), TextSize = 12, TextYAlignment = Enum.TextYAlignment.Top, Text = "Text" })
	end

	local footer = new("Frame", { Name = "Footer", LayoutOrder = 7, Size = UDim2.fromOffset(inner, 38), BackgroundTransparency = 1 }, face)
	local dots = new("Frame", { Name = "Dots", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(0, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, footer)
	list(dots, 6, true)
	for i = 1, Build.DOTS do
		local d = new("Frame", { Name = "Dot" .. i, LayoutOrder = i, Size = UDim2.fromOffset(10, 10), BackgroundColor3 = INK, BorderSizePixel = 0 }, dots)
		corner(d, 5)
		stroke(d, 2)
	end
	text(dots, "Step", { LayoutOrder = 10, Size = UDim2.fromOffset(60, 16), TextSize = 13, TextColor3 = MUTED, TextWrapped = false, Text = "1 of 3" })

	local shadow = new("Frame", { Name = "NextShadow", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(96, 34), BackgroundColor3 = INK, BorderSizePixel = 0 }, footer)
	corner(shadow, 10)
	local nextButton = new("TextButton", {
		Name = "Next",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -51, 1, -20),
		Size = UDim2.fromOffset(96, 34),
		BackgroundColor3 = MINT,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = HEAD,
		TextSize = 13,
		TextColor3 = INK,
		Text = "Next",
		ZIndex = 2,
	}, footer)
	corner(nextButton, 10)
	stroke(nextButton, 3)
	new("ImageLabel", {
		Name = "PadIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, -20, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Image = PAD_SHEET,
		ImageRectSize = Vector2.new(128, 128),
		Visible = false,
		ZIndex = 3,
	}, nextButton)
end

local function buildBubble(guide: Frame)
	local bubble = new("Frame", { Name = "Bubble", Size = UDim2.fromOffset(Build.WIDTH, 200), BackgroundTransparency = 1, ZIndex = 3 }, guide)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(Build.WIDTH, 200), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 1 }, bubble)
	corner(shadow, 14)
	local tail = new("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), Rotation = 45, BackgroundColor3 = CREAM, BorderSizePixel = 0, ZIndex = 2 }, bubble)
	corner(tail, 3)
	stroke(tail, 3)
	buildFace(bubble)
	new("Frame", { Name = "Join", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 8), BackgroundColor3 = CREAM, BorderSizePixel = 0, ZIndex = 4 }, bubble)
end

-- [[ Build ]]

function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Guide")
	if old then
		old:Destroy()
	end
	local guide = new("Frame", {
		Name = "Guide",
		Size = UDim2.fromOffset(1280, 720),
		BackgroundTransparency = 1,
		ZIndex = 100, -- over every screen in Frames (Sibling ZIndex)
		Visible = false,
	})
	new("TextButton", { Name = "Blocker", Position = UDim2.fromOffset(-4000, -4000), Size = UDim2.fromOffset(9280, 8720), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = false, ZIndex = 1 }, guide)
	buildSpot(guide)
	buildBubble(guide)
	guide.Parent = frames
	return guide
end

return Build
