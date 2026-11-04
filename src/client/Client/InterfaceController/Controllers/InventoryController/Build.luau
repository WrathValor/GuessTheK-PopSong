--| Inventory UI builder
-- Builds Interface.Frames.Inventory (the "Inventory redesign"): orange header, a category rail
-- (Stages / Mic stands / Titles / Song packs with counts), a big heading + one-line description
-- with Sort ⌄ and a ‹ 1 / 4 › pager, then a roomy 4 × 2 grid of item cards:
--   • stages + mics: the art, the name, a full-width Equip (green "✓ Equipped" when worn)
--   • titles: your name with the title chip on a dark panel
--   • song packs: stacked photocards with the pack's initials, a progress bar or "Complete ✓",
--     and "Roll for more" on My Pack
-- Run once in Studio (the old frame is kept as ServerStorage.Inventory_Legacy);
-- InventoryController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local RED = C("FF5A4E")
local ORANGE = C("FFB38A")
local MUTED = C("5C566B")
local LINE = C("DCD3C4")
local TRACK = C("ECE6DA")
local GREEN = C("6FD08C")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CLOSE_ICON = "rbxassetid://118345756178429"

local Build = {}

Build.CATEGORIES = { "Stages", "Mic stands", "Titles", "Song packs" }
Build.PER_PAGE = 8
Build.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
	ColorSequenceKeypoint.new(1, C("B5DDFF")),
})

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

local function outlined(parent: Instance, name: string, pos: UDim2, size: UDim2, label: string): TextButton
	local b = new("TextButton", { Name = name, Position = pos, Size = size, BackgroundColor3 = WHITE, FontFace = BODY, TextSize = 13, TextColor3 = INK, Text = label, AutoButtonColor = false }, parent)
	corner(b, 10)
	stroke(b, 2)
	return b
end

-- a drawn chevron (two short bars), like the Index's A–Z ⌄
local function chevron(parent: Instance, pos: UDim2)
	local chev = new("Frame", { Name = "Chevron", AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(10, 6), BackgroundTransparency = 1 }, parent)
	for i, rot in { 40, -40 } do
		local l = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(if i == 1 then 0.3 else 0.7, 0, 0.5, 0), Size = UDim2.fromOffset(7, 2), Rotation = rot, BackgroundColor3 = INK, BorderSizePixel = 0 }, chev)
		corner(l, UDim.new(0.5, 0))
	end
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Inventory")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("Inventory_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "Inventory_Legacy"
		old.Parent = storage
	end

	local inv = new("Frame", { Name = "Inventory", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, inv)
	scrim.Active = true

	local PW, PH = 1040, 620
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(128, 58), Size = UDim2.fromOffset(PW, PH), BackgroundColor3 = INK }, inv)
	corner(shadow, 18)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(120, 50), Size = UDim2.fromOffset(PW, PH), BackgroundColor3 = CREAM, ClipsDescendants = true }, inv)
	corner(panel, 18)
	stroke(panel, 3)

	-- header
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(header, "Title", { Position = UDim2.fromOffset(24, 0), Size = UDim2.fromOffset(300, 64), FontFace = HEAD, TextSize = 26, Text = "INVENTORY" })
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(PW - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", Position = UDim2.fromOffset(PW - 14 - 42, 11), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- rail: one row per category, with its count (no icons)
	local RW = 210
	local rail = new("Frame", { Name = "Rail", Position = UDim2.fromOffset(0, 67), Size = UDim2.new(0, RW, 1, -67), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "RailRule", Position = UDim2.fromOffset(RW, 67), Size = UDim2.new(0, 3, 1, -67), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 18) }, rail)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rail)
	for i, name in Build.CATEGORIES do
		local b = new("TextButton", { Name = "Category" .. i, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, rail)
		corner(b, 10)
		stroke(b, 2, WHITE)
		text(b, "Label", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -64, 1, 0), Text = name })
		text(b, "Count", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 40, 1, 0), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "0" })
	end

	-- content (24 px in from the rail and the edges)
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(RW + 3 + 24, 67 + 20), Size = UDim2.fromOffset(PW - RW - 3 - 48, PH - 67 - 20 - 20), BackgroundTransparency = 1 }, panel)
	local cw = content.Size.X.Offset

	-- heading + one-line description, Sort ⌄ | ‹ 1 / 4 ›
	local HY = 0
	text(content, "Heading", { Position = UDim2.fromOffset(0, HY), Size = UDim2.fromOffset(400, 30), FontFace = HEAD, TextSize = 22, Text = "Stages" })
	text(content, "Sub", { Position = UDim2.fromOffset(0, HY + 30), Size = UDim2.fromOffset(460, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "0 owned" })
	local BY, BH = HY + 6, 34
	outlined(content, "Next", UDim2.new(1, -BH, 0, BY), UDim2.fromOffset(BH, BH), "›")
	text(content, "Page", { Position = UDim2.new(1, -BH - 54, 0, BY), Size = UDim2.fromOffset(54, BH), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })
	outlined(content, "Prev", UDim2.new(1, -BH - 54 - BH, 0, BY), UDim2.fromOffset(BH, BH), "‹")
	new("Frame", { Name = "Divider", Position = UDim2.new(1, -BH * 2 - 54 - 12, 0, BY + 4), Size = UDim2.fromOffset(2, BH - 8), BackgroundColor3 = LINE, BorderSizePixel = 0 }, content)
	local sort = outlined(content, "Sort", UDim2.new(1, -BH * 2 - 54 - 24 - 136, 0, BY), UDim2.fromOffset(136, BH), "")
	text(sort, "Label", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -36, 1, 0), TextSize = 13, Text = "Sort: Rarity" })
	chevron(sort, UDim2.new(1, -18, 0.5, 1))
	for _, n in { "Prev", "Next" } do
		content[n].TextSize = 22
	end

	-- the grid: 4 × 2 cards
	local GY = HY + 64
	local GAP = 14
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(0, GY), Size = UDim2.new(1, 0, 1, -GY), BackgroundTransparency = 1 }, content)
	local itemW = (cw - 3 * GAP) / 4
	local itemH = (content.Size.Y.Offset - GY - GAP - 4) / 2
	for i = 1, Build.PER_PAGE do
		local col, row = (i - 1) % 4, (i - 1) // 4
		local holder = new("Frame", { Name = "Item" .. i, Position = UDim2.fromOffset(col * (itemW + GAP), row * (itemH + GAP)), Size = UDim2.fromOffset(itemW - 3, itemH), BackgroundTransparency = 1 }, grid)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, holder)
		corner(sh, 14)
		local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, holder)
		corner(face, 14)
		stroke(face, 3)

		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -74), BackgroundColor3 = C("F3EBDD"), ClipsDescendants = true }, face)
		corner(art, 10)
		stroke(art, 2)
		new("UIGradient", { Name = "Rainbow", Enabled = false, Rotation = 20, Color = Build.RAINBOW }, art)
		-- stage art (drawn; CosmeticView shows the real model over it when it can)
		local stage = new("Frame", { Name = "Stage", Position = UDim2.fromScale(0.2, 0.3), Size = UDim2.fromScale(0.6, 0.4), BackgroundColor3 = WHITE }, art)
		corner(stage, UDim.new(0.5, 0))
		stroke(stage, 2)
		local plat = new("Frame", { Name = "Platform", Position = UDim2.fromScale(0.27, 0.44), Size = UDim2.fromScale(0.46, 0.2), BackgroundColor3 = WHITE }, art)
		corner(plat, UDim.new(0.5, 0))
		stroke(plat, 2)
		-- mic art
		local micParts = new("Frame", { Name = "MicArt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, art)
		local base = new("Frame", { Name = "MicBase", Position = UDim2.fromScale(0.38, 0.8), Size = UDim2.fromScale(0.24, 0.1), BackgroundColor3 = C("CFC8E6") }, micParts)
		corner(base, UDim.new(0.5, 0))
		stroke(base, 2)
		new("Frame", { Name = "MicPole", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.new(0, 4, 0.52, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, micParts)
		local head = new("Frame", { Name = "Mic", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromScale(0.26, 0.26), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundColor3 = WHITE, Rotation = -24 }, micParts)
		corner(head, 8)
		stroke(head, 2)
		-- pack art: three stacked photocards, the pack's initials on the front one
		local covers = new("Frame", { Name = "Covers", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, art)
		for c, spec in { { -0.09, -9 }, { 0.09, 9 }, { 0, 0 } } do
			local pc = new("Frame", { Name = if c == 3 then "Front" else "Card" .. c, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + spec[1], 0.52), Size = UDim2.new(0, 52, 0.66, 0), Rotation = spec[2], BackgroundColor3 = WHITE }, covers)
			corner(pc, 7)
			stroke(pc, 2)
			if c == 3 then
				text(pc, "Initials", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "ME" })
			end
		end
		-- title art: your name, the title chip under it
		local titleArt = new("Frame", { Name = "TitleArt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, art)
		-- your name + the chip, centred as one block
		text(titleArt, "Player", { Position = UDim2.new(0, 0, 0.5, -24), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, Text = "Player" })
		local chip = text(titleArt, "Chip", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 2), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundTransparency = 0, BackgroundColor3 = C("FFE07A"), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "Fan" })
		corner(chip, 6)
		new("UIStroke", { Color = INK, Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
		pad(chip, 9)
		new("UIGradient", { Name = "Rainbow", Color = Build.RAINBOW, Enabled = false }, chip)

		local rarity = text(art, "Rarity", { Position = UDim2.fromOffset(7, 7), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BackgroundTransparency = 0, BackgroundColor3 = C("FFE07A"), TextSize = 10, TextTruncate = Enum.TextTruncate.None, Text = "Common", ZIndex = 2 })
		new("UIGradient", { Name = "Tier", Enabled = false }, rarity) -- a Gold / Rainbow tag shines / scrolls (TierShine)
		corner(rarity, 6)
		stroke(rarity, 2)
		pad(rarity, 6)

		text(face, "ItemName", { Position = UDim2.new(0, 10, 1, -60), Size = UDim2.new(1, -20, 0, 18), Text = "Item" })
		-- packs: a progress bar + count (or "Complete ✓") under the name
		local prog = new("Frame", { Name = "Progress", Position = UDim2.new(0, 10, 1, -56), Size = UDim2.new(1, -20, 0, 14), BackgroundTransparency = 1, Visible = false }, face)
		local bar = new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, -66, 0, 7), BackgroundColor3 = TRACK, BorderSizePixel = 0, ClipsDescendants = true }, prog)
		corner(bar, UDim.new(0.5, 0))
		local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, bar)
		corner(fill, UDim.new(0.5, 0))
		text(prog, "Count", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 62, 1, 0), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Text = "8 / 15" })

		local action = new("TextButton", { Name = "Action", Position = UDim2.new(0, 8, 1, -8 - 30), Size = UDim2.new(1, -16, 0, 30), BackgroundColor3 = WHITE, FontFace = BODY, TextSize = 13, TextColor3 = INK, Text = "Equip", AutoButtonColor = false }, face)
		corner(action, 9)
		stroke(action, 2, LINE)
	end
	text(content, "Empty", { Position = UDim2.fromOffset(0, GY + 120), Size = UDim2.new(1, 0, 0, 40), FontFace = BODY_BOLD, TextSize = 15, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Nothing here yet", Visible = false })

	-- toast
	local toast = text(inv, "Toast", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(640, 700), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = C("FFE07A"), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "", Visible = false, ZIndex = 10 })
	corner(toast, 10)
	pad(toast, 16)

	inv.Parent = frames
	-- centre every button's AnchorPoint so the ButtonScale tween grows from the middle
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(inv)
	return inv
end

return Build
