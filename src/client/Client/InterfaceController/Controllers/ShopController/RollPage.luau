--| Shop · Roll (builder)
-- Builds the shop's Roll tab (Pages.Roll) from the "Song roll 1" + "Song roll 2" boards: "Your
-- collection" on the left (songs pulled, one bar per generation, the odds, how copies work)
-- and the roll stage on the right (a deck of face-down photocards, ROLL ×1 / ROLL ×10, the
-- guaranteed-new counter). RollReveal (on the Shop frame, over everything) is the card flip
-- after a roll: one big photocard for ×1, a 5 × 2 grid of small ones for ×10.
-- Run once in Studio (the shop's Build.Build calls it too); it skips anything already there.
-- After that both frames live in Studio and can be restyled by hand; ./Roll finds
-- everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local PINK = C("FF9EC4")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local BLUE = C("9ED8F5")
local STAGE = C("DCD3FF")
local MUTED = C("5C566B")
local BODYTEXT = C("4A4460")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local COIN = require(game:GetService("ReplicatedStorage").Constants.Currencies).Coins.Icon -- same coin as the HUD + shop

local Build = {}
Build.GENS = { "2nd", "3rd", "4th", "5th" }
Build.GEN_COLOURS = { ["2nd"] = "FFD2A8", ["3rd"] = "B9A6FF", ["4th"] = "FF9EC4", ["5th"] = "A7E9B8" }
Build.TEN = 10
Build.COIN = COIN
Build.GLOW = "rbxassetid://115546863310722" -- soft white radial glow (assets/RadialGlow.png, decal 98573002093572), tinted per use
Build.PARTICLES = 24
Build.RINGS = 5
Build.BARS = 7

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
		TextWrapped = false,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a box with a hard offset shadow behind it (shadow is a sibling, so it isn't clipped)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, r: number, drop: number, line: number): Frame
	if drop > 0 then
		local s = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
		corner(s, r)
	end
	local f = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(f, r)
	stroke(f, line)
	return f
end

-- a chunky button, centre-anchored for ButtonScale, with its shadow as a sibling
local function button(parent: Instance, name: string, centre: Vector2, size: Vector2, colour: Color3, drop: number): TextButton
	local s = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X + drop, centre.Y + drop), Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = INK }, parent)
	corner(s, 14)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X, centre.Y), Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = colour, AutoButtonColor = false, Text = "" }, parent)
	corner(b, 14)
	stroke(b, 4)
	return b
end

-- "<coin> 150" row, centred
local function coinRow(parent: Instance, name: string, props: { [string]: any }, size: number): Frame
	local row = new("Frame", { Name = name, BackgroundTransparency = 1 }, parent)
	for k, v in props do
		(row :: any)[k] = v
	end
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = COIN }, row)
	text(row, "Amount", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size), TextSize = 14, Text = "150" })
	return row
end

-- A photocard: art box (generation colour + ♪), song name, artist · year, level chip.
-- Back is the face-down side (shown before the flip). Level is a pastel UIGradient for Rainbow.
function Build.Photocard(parent: Instance, name: string, w: number, h: number, small: boolean?): Frame
	-- clips, so the flip (squashing the width to 0) never shows anything poking out
	local f = new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true }, parent)
	corner(f, if small then 12 else 18)
	stroke(f, if small then 3 else 5)
	new("UIGradient", {
		Name = "Rainbow",
		Enabled = false,
		Rotation = 35,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C("FFB3C7")),
			ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
			ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
			ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
			ColorSequenceKeypoint.new(1, C("B5DDFF")),
		}),
	}, f)
	local p = if small then 7 else 14
	local footer = if small then 40 else 70
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(p, p), Size = UDim2.new(1, -p * 2, 1, -p * 2 - footer), BackgroundColor3 = BLUE }, f)
	corner(art, if small then 8 else 12)
	stroke(art, if small then 2 else 4)
	text(art, "Glyph", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = if small then 28 else 64, TextXAlignment = Enum.TextXAlignment.Center, Text = "♪" })
	text(f, "SongName", { Position = UDim2.new(0, p, 1, -footer - p + (if small then 4 else 8)), Size = UDim2.new(1, -p * 2, 0, if small then 16 else 30), FontFace = HEAD, TextSize = if small then 12 else 22, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Very Nice" })
	text(f, "Meta", { Position = UDim2.new(0, p, 1, -p - (if small then 16 else 24)), Size = UDim2.new(1, -p * 2 - (if small then 60 else 80), 0, if small then 14 else 20), TextSize = if small then 10 else 14, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd, Text = "SEVENTEEN · 2016" })
	local chip = text(f, "Level", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -p, 1, if small then -9 else -p), -- bottom right, on the artist line
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, if small then 14 else 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = CREAM,
		TextSize = if small then 9 else 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "NORMAL",
	})
	corner(chip, 7)
	stroke(chip, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
	-- the face-down side
	local back = new("Frame", { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, ZIndex = 5 }, f)
	corner(back, if small then 12 else 18)
	new("UIGradient", { Rotation = 45, Color = ColorSequence.new(C("2B2740"), INK) }, back)
	local ring = new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(if small then 40 else 80, if small then 40 else 80), BackgroundTransparency = 1, ZIndex = 5 }, back)
	corner(ring, 40)
	stroke(ring, if small then 3 else 4, CREAM)
	text(ring, "Q", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = if small then 20 else 38, TextColor3 = PINK, TextXAlignment = Enum.TextXAlignment.Center, Text = "?", ZIndex = 5 })
	-- small cards get a NEW / LEVEL UP badge
	if small then
		local badge = text(f, "Badge", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), BackgroundTransparency = 0, BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, Text = "NEW", ZIndex = 4, Visible = false })
		corner(badge, 6)
		stroke(badge, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, badge)
	end
	return f
end

function Build.Build(pages: Instance, shop: Instance): (Frame, Frame)
	local page = pages:FindFirstChild("Roll")
	if not page then
		page = new("Frame", { Name = "Roll", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, pages)

		-- left: your collection
		local left = new("Frame", { Name = "Collection", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(466, 531), BackgroundTransparency = 1 }, page)
		text(left, "Heading", { Size = UDim2.fromOffset(300, 18), TextSize = 13, TextColor3 = MUTED, Text = "YOUR COLLECTION" })
		local total = card(left, "Total", UDim2.fromOffset(0, 26), UDim2.fromOffset(460, 96), WHITE, 14, 4, 3)
		text(total, "Count", { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(300, 44), FontFace = HEAD, TextSize = 36, RichText = true, Text = "84 / 196" })
		text(total, "Label", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 22), Size = UDim2.fromOffset(160, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Text = "songs pulled" })
		local bar = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 0, 16), BackgroundColor3 = CREAM, ClipsDescendants = true }, total)
		corner(bar, 8)
		stroke(bar, 3)
		new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.43, 1), BackgroundColor3 = PINK, BorderSizePixel = 0 }, bar)

		for i, gen in Build.GENS do
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			local g = card(left, "Gen" .. i, UDim2.fromOffset(col * 235, 140 + row * 72), UDim2.fromOffset(225, 62), C(Build.GEN_COLOURS[gen]), 12, 0, 3)
			text(g, "GenName", { Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(120, 20), FontFace = HEAD, TextSize = 15, Text = `{string.upper(gen)} GEN` })
			text(g, "Owned", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(90, 20), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Text = "18 / 52" })
			local gb = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 12), BackgroundColor3 = WHITE, ClipsDescendants = true }, g)
			corner(gb, 6)
			stroke(gb, 2)
			new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.35, 1), BackgroundColor3 = INK, BorderSizePixel = 0 }, gb)
		end

		for _, spec in { { "Odds", 296, BLUE, "ODDS" }, { "Levels", 404, YELLOW, "COPIES" } } do
			local box = card(left, spec[1], UDim2.fromOffset(0, spec[2]), UDim2.fromOffset(460, 96), WHITE, 12, 0, 3) -- room for 4 lines on phones
			local chip = text(box, "Chip", { Position = UDim2.fromOffset(12, 37), Size = UDim2.fromOffset(64, 22), BackgroundTransparency = 0, BackgroundColor3 = spec[3], FontFace = HEAD, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = spec[4] })
			corner(chip, 6)
			stroke(chip, 2)
			text(box, "Text", { Position = UDim2.fromOffset(86, 6), Size = UDim2.new(1, -98, 1, -12), FontFace = BODY_BOLD, TextSize = 13, TextWrapped = true, RichText = true, TextColor3 = BODYTEXT, Text = "" })
		end

		-- right: the roll stage
		local stage = new("Frame", { Name = "Stage", Position = UDim2.fromOffset(490, 0), Size = UDim2.fromOffset(466, 520), BackgroundColor3 = STAGE }, page)
		corner(stage, 16)
		stroke(stage, 4)
		text(stage, "Heading", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "ROLL FROM ALL SONGS" })
		local deck = new("Frame", { Name = "Deck", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 50), Size = UDim2.fromOffset(240, 250), BackgroundTransparency = 1 }, stage)
		for i, spec in { { YELLOW, -10, -8 }, { BLUE, 6, 8 } } do
			local c = new("Frame", { Name = "Under" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(120 + spec[3], 125), Size = UDim2.fromOffset(170, 220), Rotation = spec[2], BackgroundColor3 = spec[1] }, deck)
			corner(c, 14)
			stroke(c, 4)
		end
		local top = Build.Photocard(deck, "Top", 170, 220)
		top.Position = UDim2.fromOffset(120, 122)

		local by = 380
		local one = button(stage, "RollOne", Vector2.new(233 - 105, by), Vector2.new(198, 70), MINT, 5)
		text(one, "Label", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 28), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "ROLL ×1" })
		coinRow(one, "Cost", { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 20) }, 17)
		local ten = button(stage, "RollTen", Vector2.new(233 + 105, by), Vector2.new(198, 70), YELLOW, 5)
		text(ten, "Label", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 28), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "ROLL ×10" })
		coinRow(ten, "Cost", { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 20) }, 17)
		text(stage, "Pity", { Position = UDim2.fromOffset(20, by + 52), Size = UDim2.new(1, -40, 0, 44), FontFace = BODY_BOLD, TextSize = 13, TextWrapped = true, RichText = true, TextColor3 = BODYTEXT, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
	end

	-- the reveal, over the whole shop
	local reveal = shop:FindFirstChild("RollReveal")
	if not reveal then
		reveal = new("Frame", { Name = "RollReveal", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, shop)
		local dim = new("Frame", { Name = "Dim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = C("2A2340"), BackgroundTransparency = 0.05, BorderSizePixel = 0 }, reveal)
		dim.Active = true
		local banner = text(reveal, "Banner", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 70), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 44), BackgroundTransparency = 0, BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Rotation = -2, Text = "NEW SONG!" })
		corner(banner, 12)
		stroke(banner, 4)
		new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, banner)

		local big = Build.Photocard(reveal, "Card", 270, 360)
		big.Position = UDim2.fromOffset(640, 300)

		-- ×10: 5 × 2 small cards, between the banner (ends y 92) and the info line (y 506)
		local CW, CH, GAP = 140, 186, 18
		local grid = new("Frame", { Name = "Grid", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(5 * CW + 4 * GAP, 2 * CH + GAP), BackgroundTransparency = 1, Visible = false }, reveal)
		for i = 1, Build.TEN do
			local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
			local c = Build.Photocard(grid, "Card" .. i, CW, CH, true)
			c.Position = UDim2.fromOffset(CW / 2 + col * (CW + GAP), CH / 2 + row * (CH + GAP))
		end

		text(reveal, "Info", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 506), Size = UDim2.fromOffset(700, 22), TextSize = 16, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Center, RichText = true, Text = "" })
		local pips = new("Frame", { Name = "Pips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 534), Size = UDim2.fromOffset(400, 22), BackgroundTransparency = 1 }, reveal)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, pips)
		for i = 1, 5 do
			local pip = new("Frame", { Name = "Pip" .. i, LayoutOrder = i, Size = UDim2.fromOffset(18, 18), BackgroundColor3 = CREAM }, pips)
			corner(pip, 9)
			stroke(pip, 3)
		end
		local refund = new("Frame", { Name = "Refund", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 562), Size = UDim2.fromOffset(260, 28), BackgroundColor3 = WHITE }, reveal)
		corner(refund, 10)
		stroke(refund, 3)
		coinRow(refund, "Row", { Size = UDim2.fromScale(1, 1) }, 18)

		local again = button(reveal, "Again", Vector2.new(640 - 95, 638), Vector2.new(200, 52), MINT, 4)
		text(again, "Label", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "ROLL AGAIN" })
		local done = button(reveal, "Done", Vector2.new(640 + 115, 638), Vector2.new(140, 52), WHITE, 0)
		text(done, "Label", { Size = UDim2.fromScale(1, 1), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "Done" })
		-- EQUIP: in ROLL AGAIN's place after a title moment
		local equip = button(reveal, "Equip", Vector2.new(640 - 95, 638), Vector2.new(200, 52), MINT, 4)
		equip.Visible = false
		reveal.EquipShadow.Visible = false
		text(equip, "Label", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "EQUIP" })

		-- the title moment: "TITLE UNLOCKED / UPGRADED", the title chip, why (in the info line's place)
		local ts = new("Frame", { Name = "TitleShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(646, 506), Size = UDim2.fromOffset(440, 96), BackgroundColor3 = INK, Visible = false }, reveal)
		corner(ts, 16)
		local tp = new("Frame", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 500), Size = UDim2.fromOffset(440, 96), BackgroundColor3 = CREAM, Visible = false }, reveal)
		corner(tp, 16)
		stroke(tp, 4)
		new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tp)
		text(tp, "Kicker", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 14), FontFace = HEAD, TextSize = 12, TextColor3 = MUTED, Text = "TITLE UNLOCKED" })
		local chip = text(tp, "Chip", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), BackgroundTransparency = 0, BackgroundColor3 = C("B9A6FF"), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "CARAT" })
		corner(chip, 9)
		stroke(chip, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, chip)
		new("UIGradient", { Name = "Rainbow", Enabled = false, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C("FFB3C7")),
			ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
			ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
			ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
			ColorSequenceKeypoint.new(1, C("B5DDFF")),
		}) }, chip)
		text(tp, "Why", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = C("4A4460"), Text = "" })
	end
	Build.Motion(reveal)
	return page :: Frame, reveal :: Frame
end

-- The reveal's motion pieces (the "Roll motion" boards), added to RollReveal once:
--   FX         glows (GlowA: the mystery lilac, GlowB: the group's colour), Ring1–5 (the
--              circular waveform), Dot1–24 (particles), all hidden; ./RollMotion drives them
--   Flash      the white flash on the turn, over the card
--   Card       UIScale "Motion"; Art.Bars (7 equaliser bars, the ♪ glyph goes); Sweep (the
--              gold / prism light that crosses the card on an upgrade)
--   Card.Back  the mystery face: dark art with Bars, a pulsing Note and a Gloss; ? ring hidden
--   Banner     a "Rainbow" UIGradient for NOW RAINBOW!
-- Layers: Dim 1 · FX 2 · Card / Grid 3 · Flash 5 · everything else 6.
function Build.Motion(reveal: Instance)
	if reveal:FindFirstChild("FX") then
		return
	end
	local CENTRE = Vector2.new(640, 300)
	-- a full-screen button under everything: clicks on the reveal never reach the shop behind it
	new("TextButton", { Name = "Blocker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 1 }, reveal)
	local fx = new("Frame", { Name = "FX", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, reveal)
	for _, g in { { "GlowA", C("B9A6FF") }, { "GlowB", PINK } } do
		new("ImageLabel", { Name = g[1], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CENTRE.X, CENTRE.Y), Size = UDim2.fromOffset(640, 640), BackgroundTransparency = 1, Image = Build.GLOW, ImageColor3 = g[2], ImageTransparency = 1, ZIndex = 2 }, fx)
	end
	for i = 1, Build.RINGS do
		local r = new("Frame", { Name = "Ring" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CENTRE.X, CENTRE.Y), Size = UDim2.fromOffset(340, 340), BackgroundTransparency = 1, ZIndex = 2 }, fx)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r)
		new("UIStroke", { Color = C("B9A6FF"), Thickness = 4, Transparency = 1 }, r)
		new("UIScale", { Name = "S" }, r)
	end
	for i = 1, Build.PARTICLES do
		local size = 8 + (i % 3) * 4
		local d = new("Frame", { Name = "Dot" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CENTRE.X, CENTRE.Y), Size = UDim2.fromOffset(size, size), BackgroundColor3 = BLUE, BackgroundTransparency = 1, ZIndex = 2 }, fx)
		new("UICorner", { CornerRadius = if i % 2 == 0 then UDim.new(0.5, 0) else UDim.new(0, 3) }, d)
		new("UIStroke", { Color = INK, Thickness = 2, Transparency = 1 }, d)
	end
	new("ImageLabel", { Name = "Flash", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(CENTRE.X, CENTRE.Y), Size = UDim2.fromOffset(1600, 1600), BackgroundTransparency = 1, Image = Build.GLOW, ImageTransparency = 1, ZIndex = 5 }, reveal)

	-- layers
	for _, child in reveal:GetChildren() do
		if child:IsA("GuiObject") then
			child.ZIndex = if child.Name == "Dim" or child.Name == "Blocker" then 1 elseif child.Name == "FX" then 2 elseif child.Name == "Card" or child.Name == "Grid" then 3 elseif child.Name == "Flash" then 5 else 6
		end
	end

	local function bars(parent: Instance, zindex: number)
		local row = new("Frame", { Name = "Bars", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(Build.BARS * 20 - 6, 100), BackgroundTransparency = 1, ZIndex = zindex }, parent)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		for i = 1, Build.BARS do
			local b = new("Frame", { Name = "Bar" .. i, LayoutOrder = i, Size = UDim2.fromOffset(14, 60), BackgroundColor3 = CREAM, ZIndex = zindex }, row)
			corner(b, 5)
			stroke(b, 3)
		end
		return row
	end

	local big = reveal.Card
	new("UIScale", { Name = "Motion" }, big)
	local glyph = big.Art:FindFirstChild("Glyph")
	if glyph then
		glyph.Visible = false
	end
	bars(big.Art, 1)
	-- light bands are full-size frames whose UIGradient slides (Offset -1 → 1): a rotated frame
	-- isn't clipped by ClipsDescendants, so the angle lives on the gradient instead
	local sweep = new("Frame", { Name = "Sweep", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C("FFF6D6"), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, big)
	new("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.05), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1) }) }, sweep)

	-- the mystery face
	local back = big.Back
	back.BackgroundColor3 = C("4C4278")
	local grad = back:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Enabled = false
	end
	if back:FindFirstChild("Ring") then
		back.Ring.Visible = false
	end
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -98), BackgroundColor3 = C("2A2340"), ClipsDescendants = true, ZIndex = 5 }, back)
	corner(art, 12)
	stroke(art, 4)
	local mb = bars(art, 5)
	for i, b in mb:GetChildren() do
		if b:IsA("Frame") then
			b.BackgroundColor3 = if b.LayoutOrder % 2 == 0 then C("B9A6FF") else BLUE
		end
	end
	local note = text(art, "Note", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.36, 0), Size = UDim2.fromOffset(80, 80), FontFace = HEAD, TextSize = 64, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Center, Text = "♪", ZIndex = 5 })
	new("UIStroke", { Color = INK, Thickness = 2 }, note)
	new("UIScale", { Name = "Pulse" }, note)
	local gloss = new("Frame", { Name = "Gloss", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 5 }, art)
	new("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.38, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.62, 1), NumberSequenceKeypoint.new(1, 1) }) }, gloss)
	-- where the song name + artist will be
	local l1 = new("Frame", { Name = "Line1", Position = UDim2.new(0, 14, 1, -74), Size = UDim2.fromOffset(150, 22), BackgroundColor3 = CREAM, BackgroundTransparency = 0.82, ZIndex = 5 }, back)
	corner(l1, 6)
	local l2 = new("Frame", { Name = "Line2", Position = UDim2.new(0, 14, 1, -38), Size = UDim2.fromOffset(110, 14), BackgroundColor3 = CREAM, BackgroundTransparency = 0.88, ZIndex = 5 }, back)
	corner(l2, 5)
	text(back, "Mark", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(30, 26), FontFace = HEAD, TextSize = 20, TextColor3 = C("B9A6FF"), TextXAlignment = Enum.TextXAlignment.Right, Text = "?", ZIndex = 5 })

	new("UIGradient", { Name = "Rainbow", Enabled = false, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C("FFB3C7")),
		ColorSequenceKeypoint.new(0.25, C("FFF1A8")),
		ColorSequenceKeypoint.new(0.5, C("B8F0C8")),
		ColorSequenceKeypoint.new(0.75, C("B5DDFF")),
		ColorSequenceKeypoint.new(1, C("D8C4FF")),
	}) }, reveal.Banner)
end

return Build
