--| Index UI builder
-- Builds Interface.Frames.Index (the "Song Index redesign"): blue header (♪ ROLL SONGS + Close),
-- a rail with All songs and one row per company (each with a small progress bar), then the
-- content: a big heading + "22 of 82 collected" + the Collected bar, Gold / Rainbow stat cards
-- on the right, one row of chips (groups of a company, or the companies on All songs) with
-- Show + Sort, a roomy 3 × 4 card grid, and a footer with a hint and the pager. Run once in
-- Studio (any old frame is kept as ServerStorage.Index_Legacy); IndexController finds
-- everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local BLUE = C("9ED8F5")
local MUTED = C("5C566B")
local BODYTEXT = C("4A4460")
local GREEN = C("6FD08C")
local GOLD = C("F2C94C")
local TRACK = C("EDE4D4")
local CHIP_LINE = C("DCD3C4") -- an unpicked chip's outline
local SEG_TRACK = C("ECE6DA") -- the All | Owned toggle's track

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CLOSE_ICON = "rbxassetid://118345756178429"

local Build = {}

Build.RAIL_ROWS = 8 -- All songs, then up to 7 companies
Build.PER_PAGE = 12 -- 3 × 4 cards
Build.CHIPS = 20 -- chip slots: "All groups" / "All companies", then every company or group
-- Rainbow cards (copies, Modules/Library/Cards): the card face's "Level" gradient, and the
-- Rainbow stat card's dot
Build.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
	ColorSequenceKeypoint.new(1, C("B5DDFF")),
})
-- art tiles: one pastel per group (picked by name, so a group always gets the same one)
Build.TILE_COLOURS = { "C8EFD6", "D4E8FF", "FFD2CE", "E3D7FF", "FFE5B4", "FFD6E8", "D9F2F7", "F1E3C8" }

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

-- a title chip built here, painted by TitleChip.Paint (tier colour, or greyed + 🔒)
local function titleChip(parent: Instance, name: string, textSize: number, h: number, order: number): TextLabel
	local c = text(parent, name, { LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), BackgroundTransparency = 0, BackgroundColor3 = C("B9A6FF"), TextSize = textSize, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "CARAT" })
	corner(c, 6)
	stroke(c, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, c)
	new("UIGradient", { Name = "Rainbow", Color = Build.RAINBOW, Enabled = false }, c)
	return c
end

local function bar(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, track: Color3, line: number?): Frame
	local b = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = track, BorderSizePixel = 0, ClipsDescendants = true }, parent)
	corner(b, UDim.new(0.5, 0))
	if line then
		stroke(b, line)
	end
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = colour, BorderSizePixel = 0 }, b)
	corner(fill, UDim.new(0.5, 0))
	return b
end

-- Showcase slot mode (Profile → Edit → a slot, see IndexController): the header gets Showcase
-- (Tray: your 5 slots, Slot1–Slot5 each with Chip + Label, the one being filled lit; Back where
-- ROLL SONGS sits), and every card a Pick tag ("SLOT 2" while that song fills a slot) and a
-- Hit button over it. Part of Build(); run it on its own to add them to an Index built before:
--   require(<this module>).AddShowcase(game.StarterGui.Interface.Frames.Index)
function Build.AddShowcase(index: Instance)
	local panel = index:FindFirstChild("Panel")
	local header = panel.Header
	local old = header:FindFirstChild("Showcase")
	if old then
		old:Destroy()
	end
	local PW = panel.Size.X.Offset
	local group = new("Frame", { Name = "Showcase", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, header)
	-- Back, where the close button is (that hides in this mode)
	local bw = 120
	local bx = PW - 14 - bw / 2
	local bs = new("Frame", { Name = "BackShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(bx + 3, 32 + 3), Size = UDim2.fromOffset(bw, 42), BackgroundColor3 = INK, BorderSizePixel = 0 }, group)
	corner(bs, 12)
	local back = new("TextButton", { Name = "Back", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(bx, 32), Size = UDim2.fromOffset(bw, 42), BackgroundColor3 = WHITE, BorderSizePixel = 0, AutoButtonColor = false, FontFace = HEAD, TextSize = 15, TextColor3 = INK, Text = "‹ BACK" }, group)
	corner(back, 12)
	stroke(back, 3)
	-- the tray: your 5 slots, between the title and Back
	local tx, tw = 300, PW - 300 - 14 - bw - 16
	local tray = new("Frame", { Name = "Tray", Position = UDim2.fromOffset(tx, 12), Size = UDim2.fromOffset(tw, 40), BackgroundTransparency = 1 }, group)
	local gap = 8
	local sw = math.floor((tw - gap * 4) / 5)
	for i = 1, 5 do
		local slot = new("Frame", { Name = "Slot" .. i, Position = UDim2.fromOffset((i - 1) * (sw + gap), 0), Size = UDim2.fromOffset(sw, 40), BackgroundColor3 = WHITE }, tray)
		corner(slot, 10)
		stroke(slot, 3)
		local chip = new("TextLabel", { Name = "Chip", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 7, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = TRACK, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = tostring(i) }, slot)
		corner(chip, UDim.new(0.5, 0))
		text(slot, "Label", { Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -40, 1, 0), FontFace = BODY, TextSize = 12, Text = "Empty" })
	end

	for _, holder in panel.Content.Grid:GetChildren() do
		if holder:IsA("Frame") and string.sub(holder.Name, 1, 4) == "Card" then
			for _, name in { "Pick", "Hit" } do
				local x = holder:FindFirstChild(name)
				if x then
					x:Destroy()
				end
			end
			-- "SLOT 2": this song already fills a slot (picking it swaps the two)
			local pick = new("TextLabel", { Name = "Pick", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -8), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = BODY, TextSize = 11, TextColor3 = C("FFE07A"), Text = "SLOT 1", Visible = false, ZIndex = 4 }, holder)
			corner(pick, 6)
			new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, pick)
			local hit = new("TextButton", { Name = "Hit", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Visible = false, ZIndex = 5 }, holder)
			hit:SetAttribute("NoButtonScale", true)
		end
	end
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

	local PW, PH = 1040, 620
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(128, 58), Size = UDim2.fromOffset(PW, PH), BackgroundColor3 = INK }, index)
	corner(shadow, 18)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(120, 50), Size = UDim2.fromOffset(PW, PH), BackgroundColor3 = CREAM, ClipsDescendants = true }, index)
	corner(panel, 18)
	stroke(panel, 3)

	-- header: INDEX · ♪ ROLL SONGS · Close
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = BLUE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(header, "Title", { Position = UDim2.fromOffset(24, 0), Size = UDim2.fromOffset(300, 64), FontFace = HEAD, TextSize = 26, Text = "INDEX" })
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(PW - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", Position = UDim2.fromOffset(PW - 14 - 42, 11), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)
	local rx = PW - 14 - 42 - 16 - 80
	local rs = new("Frame", { Name = "RollShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rx + 3, 32 + 3), Size = UDim2.fromOffset(160, 42), BackgroundColor3 = INK, BorderSizePixel = 0 }, header)
	corner(rs, 12)
	local roll = new("TextButton", { Name = "Roll", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rx, 32), Size = UDim2.fromOffset(160, 42), BackgroundColor3 = MINT, BorderSizePixel = 0, AutoButtonColor = false, FontFace = HEAD, TextSize = 16, TextColor3 = INK, Text = "♪ ROLL SONGS" }, header)
	corner(roll, 12)
	stroke(roll, 3)

	-- rail: All songs, "COMPANIES", one row per company; every row has a small progress bar
	local RW = 220
	local rail = new("Frame", { Name = "Rail", Position = UDim2.fromOffset(0, 67), Size = UDim2.new(0, RW, 1, -67), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "RailRule", Position = UDim2.fromOffset(RW, 67), Size = UDim2.new(0, 3, 1, -67), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 16) }, rail)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, rail)
	local function railRow(i: number, order: number)
		local b = new("TextButton", { Name = "Row" .. i, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, rail)
		corner(b, 12)
		stroke(b, 2, WHITE)
		text(b, "Label", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -96, 0, 18), TextSize = 14, Text = "Row" })
		text(b, "Count", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(80, 18), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "0 / 0" })
		local bar = bar(b, "Bar", UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 6), GREEN, TRACK)
		stroke(bar, 2, Color3.fromRGB(0, 0, 0))
	end
	railRow(1, 1)
	text(rail, "PacksHeading", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 28), TextSize = 10, TextColor3 = MUTED, TextYAlignment = Enum.TextYAlignment.Center, Text = "   COMPANIES" })
	for i = 2, Build.RAIL_ROWS do
		railRow(i, i + 1)
	end

	-- content (24 px in from the rail and the edges)
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(RW + 3 + 24, 67 + 20), Size = UDim2.fromOffset(PW - RW - 3 - 48, PH - 67 - 20 - 20), BackgroundTransparency = 1 }, panel)
	local cw, ch = content.Size.X.Offset, content.Size.Y.Offset

	-- title: heading + "22 of 82 collected", the Collected bar under them
	local titleRow = new("Frame", { Name = "TitleRow", Size = UDim2.fromOffset(cw - 250, 34), BackgroundTransparency = 1 }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, titleRow)
	text(titleRow, "Heading", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), FontFace = HEAD, TextSize = 28, TextTruncate = Enum.TextTruncate.None, Text = "All songs" })
	local sub = text(titleRow, "Sub", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "0 of 0 collected" })
	new("UIPadding", { PaddingBottom = UDim.new(0, 4) }, sub)
	-- the Collected bar: about 60% wide, beige track, thin outline
	local collected = bar(content, "Collected", UDim2.fromOffset(0, 46), UDim2.fromOffset(math.floor(cw * 0.62), 12), GREEN, SEG_TRACK)
	stroke(collected, 1.5)

	-- Gold / Rainbow stat cards (top right): soft white cards, light outline, no hard shadow
	local SW, SH, SG = 104, 52, 10
	local tiers = new("Frame", { Name = "Tiers", Position = UDim2.fromOffset(cw - (SW * 2 + SG), 0), Size = UDim2.fromOffset(SW * 2 + SG, SH), BackgroundTransparency = 1 }, content)
	for i, spec in { { "Gold", "GOLD" }, { "Rainbow", "RAINBOW" } } do
		local f = new("Frame", { Name = spec[1], Position = UDim2.fromOffset((i - 1) * (SW + SG), 0), Size = UDim2.fromOffset(SW, SH), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, tiers)
		corner(f, 12)
		stroke(f, 1.5, C("E3DCCD"))
		local dot = new("Frame", { Name = "Dot", Position = UDim2.fromOffset(14, 18), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = if spec[1] == "Gold" then GOLD else WHITE }, f)
		corner(dot, UDim.new(0.5, 0))
		stroke(dot, 1.5)
		if spec[1] == "Rainbow" then
			new("UIGradient", { Color = Build.RAINBOW, Rotation = 45 }, dot)
		end
		text(f, "Label", { Position = UDim2.fromOffset(40, 9), Size = UDim2.fromOffset(60, 14), FontFace = HEAD, TextSize = 10, TextColor3 = MUTED, Text = spec[2] })
		-- shrinks to fit, so a big total ("353 / 353") isn't cut off
		local count = text(f, "Count", { Position = UDim2.fromOffset(40, 23), Size = UDim2.fromOffset(58, 20), FontFace = HEAD, TextScaled = true, TextTruncate = Enum.TextTruncate.None, Text = "0 / 0" })
		new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 8 }, count)
	end

	-- the filter row (as in the redesign): chips that scroll sideways (a company's groups, or
	-- the companies on All songs) fading out on the right, an All | Owned toggle, A–Z ⌄
	local RY, RH = 78, 32
	local SEG_W, SORT_W, GAP = 108, 64, 8
	local groups = new("Frame", { Name = "Groups", Position = UDim2.fromOffset(0, RY), Size = UDim2.fromOffset(cw - SEG_W - SORT_W - GAP - 16, RH), BackgroundTransparency = 1 }, content)
	-- the strip is 12 px taller than the chips, so their outlines and hover grow aren't cropped
	local strip = new("ScrollingFrame", {
		Name = "Chips",
		Position = UDim2.fromOffset(0, -6),
		Size = UDim2.new(1, 0, 1, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, groups)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
	new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 40) }, strip) -- the last chip can scroll clear of the fade
	for i = 1, Build.CHIPS do
		local chip = new("TextButton", { Name = "Chip" .. i, LayoutOrder = i, Visible = i == 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, RH), BackgroundColor3 = if i == 1 then INK else WHITE, AutoButtonColor = false, FontFace = BODY, TextSize = 13, TextColor3 = if i == 1 then WHITE else INK, Text = if i == 1 then "All groups" else "Group" }, strip)
		corner(chip, UDim.new(0.5, 0))
		stroke(chip, 2, if i == 1 then INK else CHIP_LINE)
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, chip)
	end
	local fade = new("Frame", { Name = "Fade", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -6), Size = UDim2.new(0, 48, 1, 12), BackgroundColor3 = CREAM, BorderSizePixel = 0, ZIndex = 3 }, groups)
	new("UIGradient", { Transparency = NumberSequence.new(1, 0) }, fade)

	-- All | Owned: a beige track, a white thumb (with a soft drop) under the picked side
	local seg = new("Frame", { Name = "Show", Position = UDim2.new(1, -SORT_W - GAP - SEG_W, 0, RY), Size = UDim2.fromOffset(SEG_W, RH), BackgroundColor3 = SEG_TRACK, BorderSizePixel = 0 }, content)
	corner(seg, 12)
	local thumbShadow = new("Frame", { Name = "ThumbShadow", Position = UDim2.fromOffset(3, 5), Size = UDim2.fromOffset(46, RH - 6), BackgroundColor3 = C("CFC6B6"), BorderSizePixel = 0 }, seg)
	corner(thumbShadow, 10)
	local thumb = new("Frame", { Name = "Thumb", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(46, RH - 6), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, seg)
	corner(thumb, 10)
	for i, spec in { { "All", 3, 46 }, { "Owned", 49, SEG_W - 52 } } do
		new("TextButton", { Name = spec[1], Position = UDim2.fromOffset(spec[2], 3), Size = UDim2.fromOffset(spec[3], RH - 6), BackgroundTransparency = 1, FontFace = BODY, TextSize = 13, TextColor3 = if i == 1 then INK else MUTED, Text = spec[1], ZIndex = 2 }, seg)
	end

	-- A–Z ⌄: outlined, the label and a small drawn chevron
	local sort = button(content, "Sort", UDim2.new(1, -SORT_W, 0, RY), UDim2.fromOffset(SORT_W, RH), "")
	text(sort, "Label", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -30, 1, 0), TextSize = 13, Text = "A–Z" })
	local chev = new("Frame", { Name = "Chevron", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -16, 0.5, 1), Size = UDim2.fromOffset(10, 6), BackgroundTransparency = 1 }, sort)
	for i, rot in { 40, -40 } do
		local l = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(if i == 1 then 0.3 else 0.7, 0, 0.5, 0), Size = UDim2.fromOffset(7, 2), Rotation = rot, BackgroundColor3 = INK, BorderSizePixel = 0 }, chev)
		corner(l, UDim.new(0.5, 0))
	end

	-- song grid: 3 × 4, 14 px apart
	local GY, CH, CGAP = RY + RH + 18, 74, 14 -- cards 14 px apart
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(0, GY), Size = UDim2.new(1, 0, 0, 4 * CH + 3 * CGAP), BackgroundTransparency = 1 }, content)
	local w = (cw - 2 * CGAP) / 3
	for i = 1, Build.PER_PAGE do
		local col, row = (i - 1) % 3, (i - 1) // 3
		local holder = new("Frame", { Name = "Card" .. i, Position = UDim2.fromOffset(col * (w + CGAP), row * (CH + CGAP)), Size = UDim2.fromOffset(w - 3, CH), BackgroundTransparency = 1 }, grid)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, holder)
		corner(sh, 14)
		local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, holder)
		corner(face, 14)
		stroke(face, 3)
		new("UIGradient", { Name = "Level", Color = Build.RAINBOW, Rotation = 35, Enabled = false }, face) -- Rainbow cards only
		-- owned: art tile with the song's initials, name, artist line, level tag, copies
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = C("D4E8FF") }, face)
		corner(art, 10)
		stroke(art, 2)
		text(art, "Initials", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "A" })
		text(face, "SongTitle", { Position = UDim2.fromOffset(74, 15), Size = UDim2.new(1, -74 - 82, 0, 20), TextSize = 15, Text = "Song" }) -- the level tag beside it
		text(face, "Artist", { Position = UDim2.fromOffset(74, 37), Size = UDim2.new(1, -74 - 66, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = BODYTEXT, Text = "Artist · 4th gen" }) -- "×2 owned" beside it
		local tag = text(face, "Tag", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 15),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = INK,
			FontFace = HEAD,
			TextSize = 9,
			TextColor3 = C("FFE07A"),
			TextTruncate = Enum.TextTruncate.None,
			Text = "NORMAL",
		})
		corner(tag, 6)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tag)
		text(face, "Copies", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 40), Size = UDim2.fromOffset(80, 14), TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "×2 owned" })
		-- missing: a quiet locked placeholder
		local lock = new("Frame", { Name = "Lock", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = TRACK, Visible = false }, face)
		corner(lock, 10)
		text(lock, "Glyph", { Size = UDim2.fromScale(1, 1), TextSize = 18, TextTransparency = 0.15, TextXAlignment = Enum.TextXAlignment.Center, Text = "?" })
		local skel = new("Frame", { Name = "Skeleton", Position = UDim2.fromOffset(74, 31), Size = UDim2.new(0.45, 0, 0, 12), BackgroundColor3 = TRACK, Visible = false }, face)
		corner(skel, UDim.new(0.5, 0))
	end
	text(content, "Empty", {
		Position = UDim2.fromOffset(0, GY + 90),
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = BODY_BOLD,
		TextSize = 15,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "No songs here yet",
		Visible = false,
	})

	-- footer: hint on the left, pager on the right
	local FY = ch - 36
	text(content, "Hint", { Position = UDim2.fromOffset(0, FY), Size = UDim2.fromOffset(400, 36), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Locked songs can be rolled in the shop." })
	-- on a set, the hint gives way to the next step for its title: chip · step · bar · progress
	local nextRow = new("Frame", { Name = "NextStep", Position = UDim2.fromOffset(0, FY), Size = UDim2.new(1, -(38 + 8 + 104 + 8 + 38) - 12, 0, 36), BackgroundTransparency = 1, Visible = false }, content)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, nextRow)
	titleChip(nextRow, "Chip", 12, 20, 1)
	local stepText = text(nextRow, "Text", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 20), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, RichText = true, TextTruncate = Enum.TextTruncate.None, Text = "" })
	local nb = bar(nextRow, "Bar", UDim2.new(), UDim2.fromOffset(90, 10), GOLD, SEG_TRACK)
	nb.LayoutOrder = 3
	stroke(nb, 1.5)
	new("UIGradient", { Name = "Rainbow", Color = Build.RAINBOW, Enabled = false }, nb.Fill)
	text(nextRow, "Progress", { LayoutOrder = 4, Size = UDim2.fromOffset(84, 20), TextSize = 12, TextTruncate = Enum.TextTruncate.None, Text = "" })
	button(content, "Next", UDim2.new(1, -38, 0, FY), UDim2.fromOffset(38, 36), "›")
	text(content, "Page", { Position = UDim2.new(1, -38 - 8 - 104, 0, FY), Size = UDim2.fromOffset(104, 36), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = "Page 1 of 1" })
	button(content, "Prev", UDim2.new(1, -38 - 8 - 104 - 8 - 38, 0, FY), UDim2.fromOffset(38, 36), "‹")
	content.Prev.TextSize = 22
	content.Next.TextSize = 22

	Build.AddShowcase(index)
	index.Parent = frames
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(index)
	return index
end

return Build
