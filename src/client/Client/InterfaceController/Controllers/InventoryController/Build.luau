--| Inventory UI builder
-- Builds Interface.Frames.Inventory from the "Inventory · loadout" design board: orange
-- header, a category rail on the left (no colour swatches), the loadout strip (stage, mic,
-- duel pack + on/off toggle) and a 4×2 grid of item cards with a pager instead of scrolling. Run once in Studio (the old frame is kept as
-- ServerStorage.Inventory_Legacy); InventoryController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local ORANGE = C("FFB38A")
local MUTED = C("5C566B")
local NIGHT = C("2B2346")
local NIGHT_SLOT = C("3B2F63")
local LILAC_TEXT = C("D9D3F0")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CLOSE_ICON = "rbxassetid://118345756178429"
local NOTE_ICON = "rbxassetid://139417424771393"

local Build = {}

Build.CATEGORIES = { "Stages", "Mic stands", "Titles", "Song packs" }
Build.SLOTS = { "Stage", "Mic", "Pack" }
Build.PER_PAGE = 8

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

-- a face with a hard ink shadow (<name>Shadow sits behind it)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number)
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function button(parent: Instance, name: string, pos: UDim2, size: UDim2, label: string, colour: Color3?): TextButton
	local b = new("TextButton", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = colour or WHITE,
		FontFace = BODY,
		TextSize = 13,
		TextColor3 = INK,
		Text = label,
		AutoButtonColor = false,
	}, parent)
	corner(b, 9)
	stroke(b, 2)
	return b
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
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, inv)
	scrim.Active = true

	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(128, 58), Size = UDim2.fromOffset(1040, 620), BackgroundColor3 = INK }, inv)
	corner(shadow, 18)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(120, 50), Size = UDim2.fromOffset(1040, 620), BackgroundColor3 = CREAM, ClipsDescendants = true }, inv)
	corner(panel, 18)
	stroke(panel, 3)

	-- header
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(header, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(300, 64), FontFace = HEAD, TextSize = 26, Text = "INVENTORY" })
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(1040 - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", Position = UDim2.fromOffset(1040 - 14 - 42, 11), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- category rail (no colour swatches)
	local rail = new("Frame", { Name = "Rail", Position = UDim2.fromOffset(0, 67), Size = UDim2.new(0, 210, 1, -67), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "RailRule", Position = UDim2.fromOffset(210, 67), Size = UDim2.new(0, 3, 1, -67), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 12) }, rail)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rail)
	for i, name in Build.CATEGORIES do
		local b = new("TextButton", { Name = "Category" .. i, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, rail)
		corner(b, 10)
		stroke(b, 2, WHITE)
		text(b, "Label", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -60, 1, 0), Text = name })
		text(b, "Count", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 40, 1, 0), TextSize = 12, TextTransparency = 0.25, TextXAlignment = Enum.TextXAlignment.Right, Text = "0" })
	end

	-- content
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(213 + 18, 67 + 14), Size = UDim2.fromOffset(1040 - 213 - 36, 620 - 67 - 30), BackgroundTransparency = 1 }, panel)
	local cw = content.Size.X.Offset

	-- loadout strip
	local strip = card(content, "Loadout", UDim2.new(), UDim2.fromOffset(cw - 4, 86), NIGHT, 14, 4, 3)
	text(strip, "Label", { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(74, 86), FontFace = HEAD, TextSize = 14, TextColor3 = WHITE, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = "YOUR\nLOADOUT" })
	local slotW = (cw - 4 - 12 - 86 - 2 * 10 - 12) / 3
	for i, slot in Build.SLOTS do
		local b = new("TextButton", {
			Name = slot .. "Slot",
			Position = UDim2.fromOffset(86 + (i - 1) * (slotW + 10), 13),
			Size = UDim2.fromOffset(slotW, 60),
			BackgroundColor3 = NIGHT_SLOT,
			Text = "",
			AutoButtonColor = false,
		}, strip)
		corner(b, 11)
		stroke(b, 2, WHITE)
		local sw = new("Frame", { Name = "Swatch", Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = C("FF9EC4") }, b)
		corner(sw, 8)
		stroke(sw, 2)
		local right = if slot == "Pack" then 64 else 10
		text(b, "SlotLabel", { Position = UDim2.fromOffset(60, 12), Size = UDim2.new(1, -60 - right, 0, 14), TextSize = 10, TextColor3 = LILAC_TEXT, Text = if slot == "Pack" then "DUEL PACK" else string.upper(slot) })
		text(b, "SlotName", { Position = UDim2.fromOffset(60, 27), Size = UDim2.new(1, -60 - right, 0, 20), TextSize = 14, TextColor3 = WHITE, Text = "Classic" })
		if slot == "Pack" then
			local t = new("TextButton", { Name = "Toggle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -33, 0.5, 0), Size = UDim2.fromOffset(46, 24), BackgroundColor3 = MINT, Text = "", AutoButtonColor = false }, b)
			corner(t, 12)
			stroke(t, 2)
			local knob = new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = WHITE }, t)
			corner(knob, UDim.new(0.5, 0))
			stroke(knob, 2)
		end
	end

	-- heading + pager
	local hy = 100
	text(content, "Heading", { Position = UDim2.fromOffset(0, hy), Size = UDim2.fromOffset(170, 32), FontFace = HEAD, TextSize = 20, Text = "Stages" })
	text(content, "Sub", { Position = UDim2.fromOffset(160, hy), Size = UDim2.fromOffset(330, 32), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "5 owned" })
	button(content, "Sort", UDim2.new(1, -140, 0, hy), UDim2.fromOffset(140, 32), "Sort: Rarity")
	button(content, "Prev", UDim2.new(1, -140 - 10 - 32 - 46 - 32, 0, hy), UDim2.fromOffset(32, 32), "‹")
	text(content, "Page", { Position = UDim2.new(1, -140 - 10 - 32 - 46, 0, hy), Size = UDim2.fromOffset(46, 32), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })
	button(content, "Next", UDim2.new(1, -140 - 10 - 32, 0, hy), UDim2.fromOffset(32, 32), "›")
	for _, n in { "Prev", "Next" } do
		content[n].TextSize = 22
	end

	local gridY = hy + 44
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(0, gridY), Size = UDim2.new(1, 0, 1, -gridY), BackgroundTransparency = 1 }, content)
	local itemW = (cw - 3 * 14) / 4
	local itemH = 172
	for i = 1, Build.PER_PAGE do
		local col, row = (i - 1) % 4, (i - 1) // 4
		local holder = new("Frame", { Name = "Item" .. i, Position = UDim2.fromOffset(col * (itemW + 14), row * (itemH + 14)), Size = UDim2.fromOffset(itemW - 4, itemH), BackgroundTransparency = 1 }, grid)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, holder)
		corner(sh, 14)
		local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, holder)
		corner(face, 14)
		stroke(face, 3)
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 82), BackgroundColor3 = C("F3EBDD"), ClipsDescendants = true }, face)
		corner(art, 8)
		stroke(art, 2)
		-- stage art
		local stage = new("Frame", { Name = "Stage", Position = UDim2.fromScale(0.2, 0.14), Size = UDim2.fromScale(0.6, 0.42), BackgroundColor3 = WHITE }, art)
		corner(stage, UDim.new(0.3, 0))
		stroke(stage, 2)
		local plat = new("Frame", { Name = "Platform", Position = UDim2.fromScale(0.27, 0.48), Size = UDim2.fromScale(0.46, 0.26), BackgroundColor3 = WHITE }, art)
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
		-- pack art: two photocards
		local covers = new("Frame", { Name = "Covers", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, art)
		for c, spec in { { 0.24, -8, "B9A6FF" }, { 0.42, 7, "FF9EC4" } } do
			local pc = new("Frame", { Name = "Card" .. c, Position = UDim2.fromScale(spec[1], 0.16), Size = UDim2.fromScale(0.34, 0.64), Rotation = spec[2], BackgroundColor3 = C(spec[3]) }, covers)
			corner(pc, 6)
			stroke(pc, 2)
		end
		text(art, "Big", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = "", Visible = false })
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, Image = NOTE_ICON, Visible = false }, art)
		local rarity = text(art, "Rarity", {
			Position = UDim2.fromOffset(5, 5),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = MINT,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.None,
			Text = "Common",
			ZIndex = 2,
		})
		corner(rarity, 6)
		stroke(rarity, 2)
		pad(rarity, 5)
		text(face, "ItemName", { Position = UDim2.fromOffset(8, 95), Size = UDim2.new(1, -16, 0, 18), Text = "Item" })
		text(face, "ItemSub", { Position = UDim2.fromOffset(8, 112), Size = UDim2.new(1, -16, 0, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "", Visible = false })
		button(face, "Action", UDim2.new(0, 8, 1, -8 - 32), UDim2.new(1, -16, 0, 32), "Equip", MINT)
	end
	text(content, "Empty", {
		Position = UDim2.fromOffset(0, 220),
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = BODY_BOLD,
		TextSize = 15,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Nothing here yet — check the shop!",
		Visible = false,
	})

	-- toast
	local toast = text(inv, "Toast", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(640, 700),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		TextColor3 = C("FFE07A"),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Text = "",
		Visible = false,
		ZIndex = 10,
	})
	corner(toast, 10)
	pad(toast, 16)

	inv.Parent = frames
	-- centre every button's AnchorPoint so the ButtonScale tween grows from the middle
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(inv)
	return inv
end

return Build
