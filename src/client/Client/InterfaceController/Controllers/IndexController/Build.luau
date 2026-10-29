--| Index UI builder
-- Builds Interface.Frames.Index from the "Index" design board: blue header, a rail with
-- All songs / My Pack / one row per company pack, and an 18-card song grid (3 × 6) with a
-- pager instead of scrolling. Run once in Studio (any old frame is kept as
-- ServerStorage.Index_Legacy); IndexController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local BLUE = C("9ED8F5")
local MUTED = C("5C566B")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CLOSE_ICON = "rbxassetid://118345756178429"

local Build = {}

Build.RAIL_ROWS = 9 -- All songs, My Pack, then up to 7 company packs
-- owned cards (and the Owned bar) get this pastel rainbow, same as the HUD Shop tile
Build.HOLO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.2, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.4, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.6, C("B8F0C8")),
	ColorSequenceKeypoint.new(0.8, C("B5DDFF")),
	ColorSequenceKeypoint.new(1, C("D4C2FF")),
})
Build.PER_PAGE = 18

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

local function button(parent: Instance, name: string, pos: UDim2, size: UDim2, label: string): TextButton
	local b = new("TextButton", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = WHITE,
		FontFace = BODY,
		TextSize = 13,
		TextColor3 = INK,
		Text = label,
		AutoButtonColor = false,
	}, parent)
	corner(b, 10)
	stroke(b, 2)
	return b
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Index")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("Index_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "Index_Legacy"
		old.Parent = storage
	end

	local index = new("Frame", { Name = "Index", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, index)
	scrim.Active = true

	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(128, 58), Size = UDim2.fromOffset(1040, 620), BackgroundColor3 = INK }, index)
	corner(shadow, 18)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(120, 50), Size = UDim2.fromOffset(1040, 620), BackgroundColor3 = CREAM, ClipsDescendants = true }, index)
	corner(panel, 18)
	stroke(panel, 3)

	-- header
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = BLUE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(header, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(300, 64), FontFace = HEAD, TextSize = 26, Text = "INDEX" })
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(1040 - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", Position = UDim2.fromOffset(1040 - 14 - 42, 11), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- rail: All songs, My Pack, "YOUR PACKS" heading, then one row per company
	local rail = new("Frame", { Name = "Rail", Position = UDim2.fromOffset(0, 67), Size = UDim2.new(0, 220, 1, -67), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "RailRule", Position = UDim2.fromOffset(220, 67), Size = UDim2.new(0, 3, 1, -67), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 12) }, rail)
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, rail)
	local function railRow(i: number, order: number)
		local b = new("TextButton", { Name = "Row" .. i, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, rail)
		corner(b, 10)
		stroke(b, 2, WHITE)
		text(b, "Label", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -90, 1, 0), Text = "Row" })
		text(b, "Count", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 76, 1, 0), TextSize = 12, TextTransparency = 0.25, TextXAlignment = Enum.TextXAlignment.Right, Text = "0/0" })
	end
	railRow(1, 1)
	railRow(2, 2)
	text(rail, "PacksHeading", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 24), TextSize = 10, TextColor3 = MUTED, TextYAlignment = Enum.TextYAlignment.Bottom, Text = "   COMPANIES" })
	for i = 3, Build.RAIL_ROWS do
		railRow(i, i + 1)
	end

	-- content header: title, Discovered + Owned bars, Show filter, Sort, pager
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(223 + 20, 67 + 16), Size = UDim2.fromOffset(1040 - 223 - 40, 620 - 67 - 32), BackgroundTransparency = 1 }, panel)
	local cw = content.Size.X.Offset
	text(content, "Heading", { Size = UDim2.fromOffset(150, 36), FontFace = HEAD, TextSize = 20, Text = "All songs" })
	-- two stacked bars: label 72 · gap 10 · bar 86 · gap 8 · count
	for i, spec in { { "Discovered", MINT }, { "Owned", WHITE } } do
		local rowF = new("Frame", { Name = spec[1], Position = UDim2.fromOffset(150, if i == 1 then 1 else 19), Size = UDim2.fromOffset(230, 16), BackgroundTransparency = 1 }, content)
		text(rowF, "Label", { Size = UDim2.fromOffset(72, 16), FontFace = BODY, TextSize = 11, TextColor3 = MUTED, Text = spec[1] })
		local bar = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(82, 2), Size = UDim2.fromOffset(86, 12), BackgroundColor3 = WHITE, ClipsDescendants = true }, rowF)
		corner(bar, 6)
		stroke(bar, 2)
		local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = spec[2], BorderSizePixel = 0 }, bar)
		corner(fill, 4)
		if spec[1] == "Owned" then
			new("UIGradient", { Name = "Holo", Color = Build.HOLO }, fill)
		end
		text(rowF, "Count", { Position = UDim2.fromOffset(176, 0), Size = UDim2.fromOffset(54, 16), TextSize = 12, Text = "0 / 0" })
	end
	-- right side, from the edge: Sort 120 · Show 120 · gap 10 · › 34 · page 44 · ‹ 34
	button(content, "Prev", UDim2.new(1, -250 - 10 - 34 - 44 - 34, 0, 0), UDim2.fromOffset(34, 36), "‹")
	text(content, "Page", { Position = UDim2.new(1, -250 - 10 - 34 - 44, 0, 0), Size = UDim2.fromOffset(44, 36), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })
	button(content, "Next", UDim2.new(1, -250 - 10 - 34, 0, 0), UDim2.fromOffset(34, 36), "›")
	content.Prev.TextSize = 22
	content.Next.TextSize = 22
	button(content, "Show", UDim2.new(1, -250, 0, 0), UDim2.fromOffset(120, 36), "Show: All")
	button(content, "Sort", UDim2.new(1, -120, 0, 0), UDim2.fromOffset(120, 36), "Sort: A–Z")

	-- song grid (3 × 6)
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50), BackgroundTransparency = 1 }, content)
	local w = (cw - 2 * 14) / 3
	for i = 1, Build.PER_PAGE do
		local col, row = (i - 1) % 3, (i - 1) // 3
		local holder = new("Frame", { Name = "Card" .. i, Position = UDim2.fromOffset(col * (w + 14), row * (60 + 12)), Size = UDim2.fromOffset(w - 3, 60), BackgroundTransparency = 1 }, grid)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, holder)
		corner(sh, 12)
		local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, holder)
		corner(face, 12)
		stroke(face, 3)
		new("UIGradient", { Name = "Holo", Color = Build.HOLO, Rotation = 20, Enabled = false }, face)
		local badge = new("Frame", { Name = "Badge", Position = UDim2.fromOffset(8, 14), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = MINT }, face)
		corner(badge, UDim.new(0.5, 0))
		stroke(badge, 2)
		text(badge, "Mark", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 13, TextColor3 = C("A39A8C"), TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
		text(face, "SongTitle", { Position = UDim2.fromOffset(50, 10), Size = UDim2.new(1, -140, 0, 20), TextSize = 15, Text = "Song" })
		text(face, "Artist", { Position = UDim2.fromOffset(50, 30), Size = UDim2.new(1, -140, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = C("4A4460"), Text = "Artist" })
		-- right side: generation on top, DISCOVERED / OWNED tag under it
		text(face, "Gen", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(80, 12), TextSize = 10, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "4TH GEN" })
		local tag = text(face, "Tag", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 27),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			BackgroundTransparency = 0,
			BackgroundColor3 = MINT,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.None,
			Text = "DISCOVERED",
		})
		corner(tag, 7)
		stroke(tag, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, tag)
		local new_ = text(holder, "New", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 8, 0, -10),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = RED,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.None,
			Rotation = 8,
			Text = "NEW",
			Visible = false,
			ZIndex = 5,
		})
		corner(new_, 6)
		stroke(new_, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, new_)
	end
	text(content, "Empty", {
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = BODY_BOLD,
		TextSize = 15,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "No songs here yet",
		Visible = false,
	})

	index.Parent = frames
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(index)
	return index
end

return Build
