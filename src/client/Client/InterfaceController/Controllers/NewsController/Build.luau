--| News UI builder
-- Builds Interface.Frames.News from the "News" design board: pink header with an
-- "Update log" chip, the latest update as a big card on the left (art, version + date,
-- title, write-up, tag chips) and "Earlier" on the right (3 cards per page, ‹ › to page).
-- Also adds the red unread Dot to the HUD's News button. Run once in Studio (an existing
-- frame is kept as ServerStorage.News_Legacy); NewsController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local PINK = C("FF9EC4")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local BODYTEXT = C("4A4460")
local PAPER = C("F3EBDD")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local BODY_SEMI = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)

local CLOSE_ICON = "rbxassetid://118345756178429"

local Build = {}
Build.PER_PAGE = 3
Build.MAX_TAGS = 4

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number | UDim)
	new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r :: number) }, p)
end

local function stroke(p: Instance, t: number, colour: Color3?)
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function pad(p: Instance, l: number, r: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l) }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function chip(parent: Instance, name: string, label: string, colour: Color3, order: number?): TextLabel
	local c = text(parent, name, {
		LayoutOrder = order or 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
	})
	corner(c, 8)
	stroke(c, 2)
	pad(c, 8)
	return c
end

local function row(parent: Instance, gap: number)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function smallButton(parent: Instance, name: string, pos: UDim2, label: string): TextButton
	local b = new("TextButton", { Name = name, Position = pos, Size = UDim2.fromOffset(32, 28), BackgroundColor3 = WHITE, FontFace = BODY, TextSize = 20, TextColor3 = INK, Text = label, AutoButtonColor = false }, parent)
	corner(b, 8)
	stroke(b, 2)
	return b
end

-- Red unread dot on the HUD's News button.
function Build.AddHudDot(newsButton: GuiObject)
	local old = newsButton:FindFirstChild("Dot")
	if old then
		old:Destroy()
	end
	local dot = new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = RED,
		Visible = false,
		ZIndex = 3,
	}, newsButton)
	corner(dot, UDim.new(0.5, 0))
	stroke(dot, 2.5)
	return dot
end

function Build.Build(frames: Instance, hud: Instance?)
	local old = frames:FindFirstChild("News")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("News_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "News_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "News", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, root)
	scrim.Active = true

	local W, H = 900, 580
	local panel = card(root, "Panel", UDim2.fromOffset(190, 70), UDim2.fromOffset(W, H), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true

	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = PINK, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	local titleRow = new("Frame", { Name = "TitleRow", Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(400, 64), BackgroundTransparency = 1 }, header)
	row(titleRow, 12)
	text(titleRow, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), FontFace = HEAD, TextSize = 26, TextTruncate = Enum.TextTruncate.None, Text = "NEWS" })
	chip(titleRow, "Chip", "Update log", WHITE, 2)
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(W - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W - 14 - 21, 32), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- body
	local bx, by = 20, 67 + 18
	local bw, bh = W - 6 - 40, H - 67 - 36
	local gap = 16
	local leftW = math.floor((bw - gap) * 1.35 / 2.35)
	local rightW = bw - gap - leftW

	-- latest update
	local latest = card(panel, "Latest", UDim2.fromOffset(bx, by), UDim2.fromOffset(leftW - 5, bh - 5), WHITE, 16, 5, 3)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 190), BackgroundColor3 = C("B9A6FF"), ClipsDescendants = true }, latest)
	corner(art, 10)
	stroke(art, 2)
	new("UIGradient", { Name = "Tint", Rotation = 35, Color = ColorSequence.new(WHITE, C("FFD6E8")) }, art)
	for i, spec in { { 0.30, -10, YELLOW }, { 0.44, 6, WHITE } } do
		local pc = new("Frame", { Name = "Card" .. i, Position = UDim2.fromScale(spec[1], 0.18), Size = UDim2.fromScale(0.22, 0.64), Rotation = spec[2], BackgroundColor3 = spec[3] }, art)
		corner(pc, 8)
		stroke(pc, 3)
	end
	new("ImageLabel", { Name = "Image", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Image = "", Visible = false, ZIndex = 2 }, art)
	local badge = chip(art, "Badge", "NEW UPDATE", YELLOW)
	badge.Position = UDim2.fromOffset(10, 10)
	badge.ZIndex = 3

	local meta = new("Frame", { Name = "Meta", Position = UDim2.fromOffset(12, 214), Size = UDim2.new(1, -24, 0, 22), BackgroundTransparency = 1 }, latest)
	row(meta, 8)
	chip(meta, "Version", "v1.2", MINT, 1)
	text(meta, "Date", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "28 Oct 2026" })
	text(latest, "Title", { Position = UDim2.fromOffset(12, 244), Size = UDim2.new(1, -24, 0, 30), FontFace = HEAD, TextSize = 22, Text = "Update title" })
	text(latest, "Body", {
		Position = UDim2.fromOffset(12, 280),
		Size = UDim2.new(1, -24, 0, 104),
		FontFace = BODY_SEMI,
		TextSize = 14,
		TextColor3 = BODYTEXT,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.15,
		Text = "Update text",
	})
	local tags = new("Frame", { Name = "Tags", Position = UDim2.new(0, 12, 1, -12 - 22), Size = UDim2.new(1, -24, 0, 22), BackgroundTransparency = 1 }, latest)
	row(tags, 6)
	for i = 1, Build.MAX_TAGS do
		chip(tags, "Tag" .. i, "Tag", PAPER, i)
	end

	-- earlier
	local rx = bx + leftW + gap
	local earlier = new("Frame", { Name = "Earlier", Position = UDim2.fromOffset(rx, by), Size = UDim2.fromOffset(rightW, bh), BackgroundTransparency = 1 }, panel)
	text(earlier, "Heading", { Size = UDim2.fromOffset(120, 28), FontFace = HEAD, TextSize = 16, Text = "Earlier" })
	smallButton(earlier, "Prev", UDim2.new(1, -32 - 6 - 32, 0, 0), "‹")
	smallButton(earlier, "Next", UDim2.new(1, -32, 0, 0), "›")
	text(earlier, "Empty", { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 40), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "No older updates yet.", Visible = false })
	local top = 28 + 12
	local itemH = math.floor((bh - top - (Build.PER_PAGE - 1) * 12) / Build.PER_PAGE) - 4
	for i = 1, Build.PER_PAGE do
		local item = card(earlier, "Item" .. i, UDim2.fromOffset(0, top + (i - 1) * (itemH + 4 + 12)), UDim2.fromOffset(rightW - 4, itemH), WHITE, 14, 4, 3)
		local box = new("Frame", { Name = "IconBox", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = C("B9A6FF") }, item)
		corner(box, 10)
		stroke(box, 2)
		text(box, "Glyph", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "♪" })
		local tagRow = new("Frame", { Name = "TagRow", Position = UDim2.fromOffset(80, 14), Size = UDim2.new(1, -92, 0, 20), BackgroundTransparency = 1 }, item)
		row(tagRow, 6)
		chip(tagRow, "Tag", "NEW", YELLOW, 1)
		text(tagRow, "Date", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "24 Oct" })
		text(item, "Title", { Position = UDim2.fromOffset(80, 38), Size = UDim2.new(1, -92, 0, 20), TextSize = 15, Text = "Title" })
		text(item, "Body", {
			Position = UDim2.fromOffset(80, 60),
			Size = UDim2.new(1, -92, 1, -70),
			FontFace = BODY_SEMI,
			TextSize = 12,
			TextColor3 = MUTED,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "Body",
		})
	end

	root.Parent = frames
	if hud then
		Build.AddHudDot(hud.Buttons.News)
	end
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(root)
	return root
end

return Build
