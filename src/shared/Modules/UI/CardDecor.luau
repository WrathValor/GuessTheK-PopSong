--| CardDecor
-- The v2 rarity looks and the star levels, matched to the design canvas: board "38 · Card
-- types v2", "39 · One of One" (A · Cosmic) and "41 · Levels" (C · Star rating). Laid over
-- any photocard face; every size below is the canvas's own px for a 150-wide card, scaled.
--   CardDecor.Build(root, face, photo)            -- in Studio, from a screen's Build module
--   CardDecor.Paint(root, face, cardId, copies, { Serial = n?, Date = os.time? })  -- at runtime
--   CardDecor.Clear(root, face)                   -- a face showing no card
-- root is the card holder (Glow, Shadow, Face), face the framed card and photo its picture.
-- Build adds three Decor folders (root, face, photo) whose pieces start hidden and records the
-- face's own geometry (Base* attributes) so Paint can turn a face into a Polaroid and back.
-- Paint shows the pieces for the card's rarity, restyles the serial as the gold tag and hides
-- the old Glow, Level chip, Shine, Stamp and Signature. Moving pieces share one loop.
--   Standard  white print                    Selca     pink + white doodles (♡ ✦ hi~)
--   Store     mint + round STORE BENEFIT sticker
--   Lucky     gold glitter frame + gold LUCKY DRAW tag + a gold light sweep
--   Fansign   holo frame + foil ♡ FANSIGN ribbon + a gently bobbing handwritten note
--   Polaroid  thick-bottom polaroid, washi tape, marker signature, date stamp, sparkles,
--             handwritten caption and the serial in the foot
--   One of One (Cosmic)  a slim, slowly turning rainbow rim + glow, night sky with gold stars, prism, light
--             sweep, gold sparkles, rising gold dust, gold 1/1 seal, gold name + ONLY ONE
-- Levels: three chunky stars on the top edge. Normal 1 cream, Gold 2 gold, Rainbow pink,
-- yellow, blue; an unearned star is a faded cream one.
-- Tiles: a root with CardFx = "Tile" (set in Studio on grid and slot cards: binder, All
-- cards, profile showcase, pack tray) get every effect a full card has (sweep, prism,
-- sparkles, dust, hearts, the bobbing note). With Settings.LowEffects on
-- (CardDecor.SetLowEffects) tiles keep still and hide those moving pieces (the sweep, prism,
-- sparkles, dust, hearts); full cards (pull, card detail) always move. The small binder slots
-- keep the Store sticker's and Fansign ribbon's words, at a size they can still be read.
-- Not carried over from the canvas: the One of One's 3D tilt and the Polaroid's -2° lean (a
-- rotated card stops clipping its photo in Roblox).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Albums = require(ReplicatedStorage.Modules.Library.Albums)

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local CREAM = C("FBF7F0")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local HAND = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold) -- the canvas's Caveat
local MARKER = Font.new("rbxasset://fonts/families/PermanentMarker.json")
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

local STAR = "rbxassetid://139700917749751" -- white star, ink outline (assets/UI/Cards/Star.png)
local SPARKLE = "rbxassetid://112483120350596" -- 4-point ✦ (assets/UI/Cards/Sparkle.png)
local DOT = "rbxassetid://133556938627126" -- one dot in a 64px tile (assets/UI/Cards/Dot.png)
local DOT_SMALL = "rbxassetid://103047197364184" -- a smaller dot (assets/UI/Cards/DotSmall.png)
local GLOW = "rbxassetid://80565779904016" -- soft rounded glow, 9-slice (assets/UI/Cards/Glow.png)
local RADIAL = "rbxassetid://97414923574122" -- soft round falloff (assets/UI/Cards/Radial.png)

local function seq(stops: { { any } }): ColorSequence
	local keys = {}
	for _, s in stops do
		table.insert(keys, ColorSequenceKeypoint.new(s[1], C(s[2])))
	end
	return ColorSequence.new(keys)
end
local function alpha(stops: { { number } }): NumberSequence
	local keys = {}
	for _, s in stops do
		table.insert(keys, NumberSequenceKeypoint.new(s[1], s[2]))
	end
	return NumberSequence.new(keys)
end

-- (CSS gradient angles become UIGradient Rotation = angle - 90)
local GOLD_FRAME = seq({ { 0, "FFF1B8" }, { 0.3, "F6D77E" }, { 0.55, "E8C15A" }, { 0.8, "C9952B" }, { 1, "F6D77E" } })
local GOLD_TAG = seq({ { 0, "F6D77E" }, { 1, "C9952B" } })
local GOLD_SEAL = seq({ { 0, "FFF1B8" }, { 0.45, "E8C15A" }, { 1, "A87A1E" } })
local GOLD_TEXT = seq({ { 0, "A87A1E" }, { 0.25, "FFF1B8" }, { 0.5, "E8C15A" }, { 0.75, "FFF1B8" }, { 1, "A87A1E" } })
local HOLO = seq({ { 0, "DDE6F5" }, { 0.4, "F6F8FC" }, { 0.6, "BFD7F2" }, { 1, "E9E1FB" } })
-- the Fansign's living holo frame (canvas 43 B): pink, white, blue, lilac, drifting over 6s
local DRIFT = seq({ { 0, "FFD2E5" }, { 0.18, "F6F8FC" }, { 0.32, "BFD7F2" }, { 0.46, "E9E1FB" }, { 0.6, "FFB8DA" }, { 0.74, "F6F8FC" }, { 0.88, "C9E8F7" }, { 1, "FFD2E5" } })
local RIBBON = seq({ { 0, "C9D3E3" }, { 0.25, "FFFFFF" }, { 0.5, "FF9EC4" }, { 0.75, "FFFFFF" }, { 1, "C9D3E3" } })
local RAINBOW = seq({ { 0, "FF5A4E" }, { 1 / 6, "FFE07A" }, { 2 / 6, "A7E9B8" }, { 3 / 6, "9ED8F5" }, { 4 / 6, "B9A6FF" }, { 5 / 6, "FF9EC4" }, { 1, "FF5A4E" } })
-- washi tape: pink and yellow stripes at 45°
local WASHI = (function()
	local keys, n = {}, 9
	for i = 0, n - 1 do
		local colour = if i % 2 == 0 then C("FF9EC4") else C("FFE07A")
		table.insert(keys, ColorSequenceKeypoint.new(i / n, colour))
		table.insert(keys, ColorSequenceKeypoint.new(math.min(1, (i + 1) / n - 0.001), colour))
	end
	keys[#keys] = ColorSequenceKeypoint.new(1, keys[#keys].Value)
	return ColorSequence.new(keys)
end)()

-- the light sweep's colour across its band (white for the One of One)
local SWEEP = {
	luckydraw = seq({ { 0, "E8C15A" }, { 0.35, "FFF1B8" }, { 0.5, "FFFFFF" }, { 0.65, "FFF1B8" }, { 1, "E8C15A" } }),
}

local FACE = {
	standard = WHITE,
	selca = C("FFD2E5"),
	store = C("A7E9B8"),
	luckydraw = WHITE, -- under the gold frame gradient
	fansign = WHITE, -- under the holo gradient
	polaroid = C("FBFAF6"),
	oneofone = C("14111F"),
}
local STARS = {
	Normal = { CREAM, false, false },
	Gold = { C("F2C94C"), C("F2C94C"), false },
	Rainbow = { C("FF9EC4"), C("FFE07A"), C("9ED8F5") },
}
local POLAROID_PHOTO = 150 / 216 -- the polaroid's photo height, of the card's

local CardDecor = {}

-- each foiled rarity's own colours, for its dots and chips (Odds sheet, Binder, Market): the gold
-- Lucky Draw, the drifting Fansign holo, the One of One rainbow
CardDecor.FOILS = table.freeze({ luckydraw = GOLD_FRAME, fansign = DRIFT, oneofone = RAINBOW })

-- [[ Build (Studio) ]]

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
local function round(p: Instance)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
end
local function stroke(p: Instance, t: number, colour: Color3?, transparency: number?)
	new("UIStroke", { Color = colour or INK, Thickness = t, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function label(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 12, Visible = false }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
-- Auto-sized sticker text spills out of its box on phones (at a few on-screen px the glyphs
-- draw bigger than the box that was sized for them), so these boxes are measured once at design
-- size and the text drawn TextScaled inside: it fills the box on PC and can't spill out on mobile.
-- `legacy` is the closest Enum.Font, for measuring; TextSize stays the design size.
local function fitBox(l: TextLabel, legacy: Enum.Font, keepHeight: boolean?)
	local ok, b = pcall(function()
		return TextService:GetTextSize(l.Text, l.TextSize, legacy, Vector2.new(4000, 4000))
	end)
	if not ok then
		return
	end
	local pad = l:FindFirstChildOfClass("UIPadding")
	local px = if pad then pad.PaddingLeft.Offset + pad.PaddingRight.Offset else 0
	local py = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
	l.AutomaticSize = Enum.AutomaticSize.None
	l.TextScaled = true
	l.Size = UDim2.fromOffset(math.ceil(b.X) + px + 1, if keepHeight then l.Size.Y.Offset else math.ceil(b.Y) + py)
end
-- Gotham's "#" and tabular digits carry extra space on their left, so "#12" sits off to the
-- right of a centred chip; trade some left padding for right padding to centre it by eye
local function balance(chip: TextLabel)
	local pad = chip:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = new("UIPadding", {}, chip)
	end
	-- (the even padding is kept, so building again doesn't stack the shift)
	local base = chip:GetAttribute("BasePad") or math.max(pad.PaddingLeft.Offset, pad.PaddingRight.Offset, 2)
	chip:SetAttribute("BasePad", base)
	local shift = math.max(1, math.floor(chip.TextSize * 0.12 + 0.5))
	pad.PaddingLeft = UDim.new(0, math.max(0, base - shift))
	pad.PaddingRight = UDim.new(0, base + shift)
end
local function widthOf(g: Instance): number
	if not g:IsA("GuiObject") then
		return 150
	end
	local size = g.Size.X
	if size.Scale == 0 then
		return size.Offset
	end
	return size.Offset + size.Scale * widthOf(g.Parent :: Instance)
end
local function heightOf(g: Instance): number
	if not g:IsA("GuiObject") then
		return 216
	end
	local size = g.Size.Y
	if size.Scale == 0 then
		return size.Offset
	end
	return size.Offset + size.Scale * heightOf(g.Parent :: Instance)
end

function CardDecor.Build(root: Frame, face: Frame, photo: Frame)
	local w = widthOf(face)
	local k = w / 150
	local small = k < 0.6 -- binder slots: no handwriting, only the shapes
	local tile = root:GetAttribute("CardFx") == "Tile" -- grid and slot cards: no costly pieces
	local function n(v: number): number
		return math.max(1, math.floor(v * k + 0.5))
	end
	local faceCorner = face:FindFirstChildOfClass("UICorner")
	local radius = if faceCorner then faceCorner.CornerRadius.Offset else n(12)
	for _, parent in { root, face, photo } do
		local old = parent:FindFirstChild("Decor")
		if old then
			old:Destroy()
		end
	end

	-- the face's own geometry, for Paint to put back after a Polaroid
	local photoCorner = photo:FindFirstChildOfClass("UICorner")
	local photoStroke = photo:FindFirstChildOfClass("UIStroke")
	photo:SetAttribute("BasePosition", photo.Position)
	photo:SetAttribute("BaseSize", photo.Size)
	photo:SetAttribute("BaseCorner", if photoCorner then photoCorner.CornerRadius.Offset else 0)
	photo:SetAttribute("BaseStroke", if photoStroke then photoStroke.Thickness else 0)
	face:SetAttribute("BaseCorner", radius)
	local polaroidTop = photo.Position.Y.Offset
	local footY = (polaroidTop + POLAROID_PHOTO * heightOf(face) + heightOf(face)) / 2 -- the polaroid foot's centre
	local padX = photo.Position.X.Offset

	-- [ around the card ]
	local outer = new("Folder", { Name = "Decor" }, root)
	-- One of One: a blurred rainbow glow (canvas .aura: 16px out, blur 12px) and the rim
	local aura = new("ImageLabel", { Name = "Aura", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, n(96), 1, n(96)), BackgroundTransparency = 1, Image = GLOW, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(48, 48, 80, 80), SliceScale = k, ZIndex = 0, Visible = false }, outer)
	new("UIGradient", { Name = "Colour", Color = RAINBOW, Rotation = 45 }, aura)
	-- (a UIStroke draws outside its frame, so the rim also clears the face's own outline)
	local faceStroke = face:FindFirstChildOfClass("UIStroke")
	local outline = if faceStroke then math.ceil(faceStroke.Thickness) * 2 else 0
	local rim = new("Frame", { Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, n(5) + outline, 1, n(5) + outline), BackgroundColor3 = WHITE, ZIndex = 0, Visible = false }, outer)
	corner(rim, radius + n(2) + outline // 2)
	stroke(rim, math.max(1, n(2)))
	new("UIGradient", { Name = "Colour", Color = RAINBOW, Rotation = 0 }, rim)
	-- the level stars: 25px, 1px apart, on the top edge, with a 2px hard shadow
	local stars = new("Frame", { Name = "Stars", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -n(3)), Size = UDim2.fromOffset(n(80), n(28)), BackgroundTransparency = 1, ZIndex = 6, Visible = false }, outer)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, math.max(0, n(1))), SortOrder = Enum.SortOrder.Name }, stars)
	for i = 1, 3 do
		local slot = new("Frame", { Name = "Star" .. i, Size = UDim2.fromOffset(n(25), n(25)), BackgroundTransparency = 1, ZIndex = 6 }, stars)
		new("ImageLabel", { Name = "Shadow", Position = UDim2.fromOffset(math.max(1, n(2)), math.max(1, n(2))), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = STAR, ImageColor3 = INK, ZIndex = 6 }, slot)
		new("ImageLabel", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = STAR, ZIndex = 6 }, slot)
	end
	-- One of One: gold dust rising from the bottom (canvas .dust: 4px, glow 6px, 230px, 3.2s)
	local dust = new("Frame", { Name = "Dust", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6, Visible = false }, outer)
	for i, x in { 16, 54, 96, 128 } do
		local mote = new("ImageLabel", { Name = "Mote" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x / 150, 0, 1, -n(6)), Size = UDim2.fromOffset(n(16), n(16)), BackgroundTransparency = 1, Image = RADIAL, ImageColor3 = C("FFD36B"), ZIndex = 6 }, dust)
		mote:SetAttribute("Delay", ({ 0, 0.9, 1.7, 2.4 })[i])
		local dot = new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(math.max(2, n(4)), math.max(2, n(4))), BackgroundColor3 = C("FFE7A0"), BorderSizePixel = 0, ZIndex = 6 }, mote)
		round(dot)
	end
	-- Fansign (canvas 43 B): pink hearts drifting up past the card, and pink-glow sparkles
	-- twinkling on its edges
	do
		local hearts = new("Frame", { Name = "Hearts", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6, Visible = false }, outer)
		for i, spec in { { 14, 13, 0, 6 }, { 52, 10, 0.9, -8 }, { 92, 13, 1.8, 6 }, { 124, 11, 2.6, -5 } } do
			local heart = label(hearts, "Heart" .. i, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(spec[1] / 150, 0, 1, 0), Size = UDim2.fromOffset(n(spec[2] * 2.4), n(spec[2] * 2.4)), FontFace = HEAD, TextSize = n(spec[2] * 1.7), TextColor3 = C("FF9EC4"), Text = "♥", TextTransparency = 1, ZIndex = 6, Visible = true })
			new("UIStroke", { Color = INK, Thickness = math.max(1, n(1.2)), Transparency = 1 }, heart)
			new("UIScale", { Name = "Scale" }, heart)
			heart:SetAttribute("Home", spec[1] / 150)
			heart:SetAttribute("Delay", spec[3])
			heart:SetAttribute("Drift", spec[4] / 150)
		end
		local twinkles = new("Frame", { Name = "Twinkles", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6, Visible = false }, outer)
		for i, spec in { { UDim.new(0, -n(1)), UDim.new(1, -n(46)), 14, 0 }, { UDim.new(1, n(1)), UDim.new(0, n(66)), 11, 0.6 } } do
			local size = n(spec[3] * 1.15)
			local spark = new("ImageLabel", { Name = "Spark" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(spec[1], spec[2]), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = SPARKLE, ImageColor3 = WHITE, ZIndex = 6 }, twinkles)
			new("ImageLabel", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(2.2, 2.2), BackgroundTransparency = 1, Image = RADIAL, ImageColor3 = C("FF5A9E"), ImageTransparency = 0.45, ZIndex = 6 }, spark)
			spark:SetAttribute("Size", size)
			spark:SetAttribute("Delay", spec[4])
		end
	end
	-- One of One: the gold 1/1 seal over the top-right corner (48px, -18px out)
	local seal = new("Frame", { Name = "Seal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -n(6), 0, n(6)), Size = UDim2.fromOffset(n(48), n(48)), BackgroundTransparency = 1, ZIndex = 7, Visible = false }, outer)
	new("ImageLabel", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.7, 1.7), BackgroundTransparency = 1, Image = RADIAL, ImageColor3 = C("FFD36B"), ImageTransparency = 0.2, ZIndex = 7 }, seal)
	local sealShadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(n(3), n(3)), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, ZIndex = 7 }, seal)
	round(sealShadow)
	local disc = label(seal, "Disc", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = n(13), Text = "1/1", ZIndex = 7, Visible = true })
	round(disc)
	stroke(disc, math.max(1.5, n(2.5)))
	new("UIGradient", { Color = GOLD_SEAL, Rotation = 45 }, disc)
	new("UIScale", { Name = "Stamp" }, seal) -- (the pull reveal stamps it on: Reveal)

	-- [ on the face ]
	local mid = new("Folder", { Name = "Decor" }, face)
	-- Lucky Draw: white and pale-gold glitter dots over the gold frame (9px and 13px)
	local glitter = new("Frame", { Name = "Glitter", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0, Visible = false }, mid)
	for i, spec in { { 9, WHITE }, { 13, C("FFF1B8") } } do
		local tile = new("ImageLabel", { Name = "Dots" .. i, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = DOT, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(math.max(3, n(spec[1])), math.max(3, n(spec[1]))), ImageColor3 = spec[2], ZIndex = 0 }, glitter)
		corner(tile, radius)
	end
	-- Fansign: pink and white glitter over the holo frame that glints (10px and 14px)
	local glint = new("Frame", { Name = "Glint", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0, Visible = false }, mid)
	for i, spec in { { 10, WHITE, 0 }, { 14, C("FF9EC4"), 0.4 } } do
		local tile = new("ImageLabel", { Name = "Dots" .. i, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = DOT, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(math.max(3, n(spec[1])), math.max(3, n(spec[1]))), ImageColor3 = spec[2], ZIndex = 0 }, glint)
		tile:SetAttribute("Delay", spec[3])
		corner(tile, radius)
	end
	-- One of One: the night sky (a violet glow at 30% 20%, gold and white star dots)
	local sky = new("Frame", { Name = "Sky", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0, Visible = false }, mid)
	local glow = new("ImageLabel", { Name = "Glow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = RADIAL, ImageRectOffset = Vector2.new(38, 48), ImageRectSize = Vector2.new(85, 80), ImageColor3 = C("3B2F66"), ZIndex = 0 }, sky)
	corner(glow, radius)
	for i, spec in { { 23, C("FFE7A0"), 0 }, { 17, WHITE, 0.25 } } do
		local tile = new("ImageLabel", { Name = "Dots" .. i, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = DOT_SMALL, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(math.max(6, n(spec[1])), math.max(6, n(spec[1]))), ImageColor3 = spec[2], ImageTransparency = spec[3], ZIndex = 0 }, sky)
		corner(tile, radius)
	end
	-- Fansign: the foil ribbon over the left edge (left -8, top 14, -8°, 2px hard shadow); on
	-- the small binder slots no smaller than its words can be read
	do
		local rw, rh, rt = n(76), n(17), n(9)
		if small then
			rw, rh, rt = math.max(rw, 40), math.max(rh, 11), math.max(rt, 6.5)
		end
		local ribbon = new("Frame", { Name = "Ribbon", Position = UDim2.fromOffset(-n(8), n(14)), Size = UDim2.fromOffset(rw, rh), Rotation = -8, BackgroundTransparency = 1, ZIndex = 5, Visible = false }, mid)
		local ribbonShadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(n(2), n(2)), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, ZIndex = 5 }, ribbon)
		corner(ribbonShadow, n(4))
		local band = label(ribbon, "Band", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = rt, Text = "♡ FANSIGN", ZIndex = 5, Visible = true })
		corner(band, n(4))
		stroke(band, math.max(1.5, n(2)))
		new("UIGradient", { Name = "Foil", Color = RIBBON, Rotation = 0 }, band)
	end
	-- Polaroid: washi tape over the top (58×20, -4°, pink/yellow stripes)
	local washi = new("Frame", { Name = "Washi", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -n(2)), Size = UDim2.fromOffset(n(58), n(20)), Rotation = -4, BackgroundColor3 = WHITE, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 5, Visible = false }, mid)
	stroke(washi, 1, INK, 0.75)
	new("UIGradient", { Color = WASHI, Rotation = 45 }, washi)
	-- Polaroid: the handwritten caption and the serial in the thick foot
	label(mid, "Caption", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(padX, footY), Size = UDim2.new(1, -padX * 2 - n(34), 0, n(26)), FontFace = HAND, TextSize = n(18), TextColor3 = C("2C3FA8"), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "felix ♡ stay", ZIndex = 2 })
	local footSerial = label(mid, "FootSerial", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -padX, 0, footY), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, n(14)), BackgroundTransparency = 0, BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = n(9), Text = "#12", ZIndex = 2 })
	corner(footSerial, n(5))
	stroke(footSerial, math.max(1, n(1.5)))
	new("UIPadding", { PaddingLeft = UDim.new(0, n(5)), PaddingRight = UDim.new(0, n(5)) }, footSerial)
	balance(footSerial)
	new("UIGradient", { Name = "Gold", Color = GOLD_TAG, Rotation = 45 }, footSerial)
	-- One of One: gold foil name (the face's Member) and ONLY ONE beside it
	local member = face:FindFirstChild("Member")
	if member and member:IsA("TextLabel") then
		local old = member:FindFirstChild("Gold")
		if old then
			old:Destroy()
		end
		new("UIGradient", { Name = "Gold", Color = GOLD_TEXT, Enabled = false }, member)
		if not face:FindFirstChild("Rarity") then -- the big faces already say the rarity there
			local y = member.Position.Y
			local only = label(mid, "OnlyOne", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -member.Position.X.Offset, y.Scale, y.Offset + member.Size.Y.Offset / 2), Size = UDim2.fromOffset(n(56), n(12)), FontFace = BODY, TextSize = n(9), TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Right, Text = "ONLY ONE", ZIndex = 2 })
			new("UIGradient", { Name = "Gold", Color = GOLD_TEXT }, only)
		end
	end

	-- [ on the photo (clipped to it) ]
	local top = new("Folder", { Name = "Decor" }, photo)
	do -- (with Low effects on, Paint hides these on tiles)
		-- One of One: the colour-cycling prism and the light sweep
		local prism = new("Frame", { Name = "Prism", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 3, Visible = false }, top)
		new("UIGradient", { Name = "Hue", Color = RAINBOW, Rotation = 120 }, prism)
		-- (the sweep is a tall bar, so it sits in a CanvasGroup: that crops it to the photo even
		-- when the card is tilted or squashed, where a frame's ClipsDescendants stops working)
		local shine = new("CanvasGroup", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Visible = false }, top)
		corner(shine, photo:GetAttribute("BaseCorner") or 0)
		local sweep = new("Frame", { Name = "Sweep", Position = UDim2.fromScale(-0.6, -0.2), Size = UDim2.fromScale(0.4, 1.4), Rotation = 18, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, shine)
		new("UIGradient", { Name = "Band", Transparency = alpha({ { 0, 1 }, { 0.5, 0.15 }, { 1, 1 } }) }, sweep)
		-- sparkles: white on the Polaroid, gold on the One of One (twinkle over 1.8s)
		for _, set in {
			{ "Sparks", WHITE, { { 10, 12, 14, 0, false, false }, { 14, 30, 10, 0.6, true, false }, { 40, 26, 12, 1.1, true, true } } },
			{ "GoldSparks", C("FFE7A0"), { { 10, 12, 14, 0, false, false }, { 12, 40, 10, 0.8, true, false }, { 26, 18, 11, 1.3, false, true } } },
		} do
			local holder = new("Frame", { Name = set[1], Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Visible = false }, top)
			for i, s in set[3] do
				local size = math.max(5, n(s[3] * 1.15))
				local x = if s[5] then UDim.new(1, -n(s[1]) - size / 2) else UDim.new(0, n(s[1]) + size / 2)
				local y = if s[6] then UDim.new(1, -n(s[2]) - size / 2) else UDim.new(0, n(s[2]) + size / 2)
				local spark = new("ImageLabel", { Name = "Spark" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, y), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = SPARKLE, ImageColor3 = set[2], ZIndex = 4 }, holder)
				spark:SetAttribute("Size", size)
				spark:SetAttribute("Delay", s[4])
			end
		end
	end
	-- Lucky Draw: the gold tag (top-left, 5px in)
	local tag = label(top, "Tag", { Position = UDim2.fromOffset(n(5), n(5)), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, n(14)), BackgroundTransparency = 0, BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = n(9), Text = "LUCKY DRAW", ZIndex = 4 })
	corner(tag, n(5))
	stroke(tag, math.max(1, n(1.5)))
	new("UIPadding", { PaddingLeft = UDim.new(0, n(5)), PaddingRight = UDim.new(0, n(5)) }, tag)
	new("UIGradient", { Color = GOLD_TAG, Rotation = 45 }, tag)
	fitBox(tag, Enum.Font.GothamBlack, true)
	-- Store: the round STORE BENEFIT sticker (44px, bottom-right, -10°)
	-- (the small binder slots: a bigger sticker, so its words can still be read)
	local sealSize, sealText = n(44), n(7.5)
	if small then
		sealSize, sealText = math.max(sealSize, 26), math.max(sealText, 5.5)
	end
	label(top, "Seal", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -n(4), 1, -n(4)), Size = UDim2.fromOffset(sealSize, sealSize), BackgroundTransparency = 0, BackgroundColor3 = CREAM, FontFace = BODY, TextSize = sealText, TextWrapped = true, LineHeight = 1, Text = "STORE\nBENEFIT", Rotation = -10, ZIndex = 4 })
	round(top.Seal)
	stroke(top.Seal, math.max(1.5, n(2)))
	-- Polaroid: silver marker signature across the photo, and the orange date stamp
	local sig = new("Frame", { Name = "Sig", Position = UDim2.fromOffset(n(10), n(52)), Size = UDim2.new(1, -n(10), 0, n(38)), Rotation = -14, BackgroundTransparency = 1, ZIndex = 4, Visible = false }, top)
	label(sig, "Shadow", { Position = UDim2.fromOffset(1, 1), Size = UDim2.fromScale(1, 1), FontFace = MARKER, TextSize = n(30), TextColor3 = INK, TextTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Left, Text = "Felix", ZIndex = 4, Visible = true })
	local ink = label(sig, "Text", { Size = UDim2.fromScale(1, 1), FontFace = MARKER, TextSize = n(30), TextColor3 = C("F4F4F8"), TextXAlignment = Enum.TextXAlignment.Left, Text = "Felix", ZIndex = 4, Visible = true })
	new("UIStroke", { Color = WHITE, Thickness = math.max(1, n(1.5)), Transparency = 0.7 }, ink)
	local date = label(top, "Date", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -n(6), 1, -n(4)), Size = UDim2.fromOffset(n(80), n(13)), FontFace = MONO, TextSize = n(11), TextColor3 = C("FF8A3D"), TextXAlignment = Enum.TextXAlignment.Right, Text = "'25 11 25", ZIndex = 4 })
	new("UIStroke", { Color = C("FF8A3D"), Thickness = 1, Transparency = 0.75 }, date)
	if not small then
		-- Selca: white doodles with a pink offset shadow (♡ ✦ hi~)
		local doodles = new("Frame", { Name = "Doodles", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Visible = false }, top)
		-- (the fonts have no ✦, so that one is the sparkle image; Kalam draws smaller than Caveat)
		for i, d in { { "♡", UDim2.fromOffset(n(6), n(6)), -12, 30 }, { "✦", UDim2.new(1, -n(10) - n(18), 0, n(46)), 10, 18 }, { "hi~", UDim2.new(0, n(12), 1, -n(8) - n(26)), -6, 21 } } do
			local holder = new("Frame", { Name = "Doodle" .. i, Position = d[2], Size = UDim2.fromOffset(n(if d[1] == "✦" then 18 else 40), n(if d[1] == "✦" then 18 else 26)), Rotation = d[3], BackgroundTransparency = 1, ZIndex = 4 }, doodles)
			for _, layer in { { "Shadow", C("FF5A9E"), math.max(1, n(1.5)) }, { "Text", WHITE, 0 } } do
				if d[1] == "✦" then
					new("ImageLabel", { Name = layer[1], Position = UDim2.fromOffset(layer[3], layer[3]), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = SPARKLE, ImageColor3 = layer[2], ZIndex = 4 }, holder)
				else
					label(holder, layer[1], { Position = UDim2.fromOffset(layer[3], layer[3]), Size = UDim2.fromScale(1, 1), FontFace = HAND, TextSize = n(d[4]), TextColor3 = layer[2], TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = d[1], ZIndex = 4, Visible = true })
				end
			end
		end
		-- Fansign: the handwritten note (bottom-left, white card, -4°)
		local note = label(top, "Note", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, n(8), 1, -n(8)), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.15, BackgroundColor3 = WHITE, FontFace = HAND, TextSize = n(13), LineHeight = 0.95, TextXAlignment = Enum.TextXAlignment.Left, Text = "to. you ♡\nthank u for\ncoming!! - momo", Rotation = -4, ZIndex = 4 })
		note:SetAttribute("Home", note.Position) -- where the bob animation returns it to
		corner(note, n(6))
		new("UIPadding", { PaddingLeft = UDim.new(0, n(6)), PaddingRight = UDim.new(0, n(6)), PaddingTop = UDim.new(0, n(4)), PaddingBottom = UDim.new(0, n(4)) }, note)
	end

	-- the decor is drawn to scale with the card, so FitText must leave its text alone: on a
	-- shrunk card (a tray mini under a UIScale) its "never below half size" rule would blow the
	-- sticker and seal text up past their circles
	for _, folder in { outer, mid, top } do
		for _, d in folder:GetDescendants() do
			if d:IsA("TextLabel") then
				d:SetAttribute("FitTextSkip", true)
			end
		end
	end

	-- ZIndex values above are relative (0 = just under the card); lift them onto the card's own
	-- layer, which a modal window may have raised (the binder detail sits at 26)
	for folder, base in { [outer] = face.ZIndex - 1, [mid] = photo.ZIndex - 1, [top] = photo.ZIndex - 1 } do
		for _, d in folder:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex += base
			end
		end
	end

	-- the gold serial tag ("#88", top-right, 5px in): restyle the face's own Serial
	local serial = photo:FindFirstChild("Serial")
	if serial and serial:IsA("TextLabel") then
		for _, old in { "Gold" } do
			local inst = serial:FindFirstChild(old)
			if inst then
				inst:Destroy()
			end
		end
		new("UIGradient", { Name = "Gold", Color = GOLD_TAG, Rotation = 45 }, serial)
		if not serial:FindFirstChildOfClass("UIStroke") then
			stroke(serial, math.max(1, n(1.5)))
		end
		if not serial:FindFirstChildOfClass("UICorner") then
			corner(serial, n(5))
		end
		balance(serial)
		serial.AnchorPoint = Vector2.new(1, 0)
		serial.Position = UDim2.new(1, -n(5), 0, n(5))
		serial.BackgroundColor3 = WHITE
		serial.BackgroundTransparency = 0
		serial.TextColor3 = INK
		serial.ZIndex = math.max(serial.ZIndex, photo.ZIndex + 4)
	end
end

-- [[ Animation ]]

type Entry = { Kind: string, Parts: { [string]: any }, Seed: number, Shown: boolean, NextCheck: number, Tile: boolean }
local active: { [Instance]: Entry } = {}
local loop: RBXScriptConnection? = nil
local CHECK_EVERY = 0.25 -- seconds between a card's on-screen checks (staggered per card)
local stats = { Active = 0, Animated = 0, StepMs = 0 }
local lowEffects = false -- Settings.LowEffects: tiles keep still

-- Whether a face can be seen right now: every ancestor up to its ScreenGui is visible, the
-- ScreenGui is on, and the face overlaps the screen and any scrolling or clipping frame
-- round it. Cards on closed screens, hidden templates and tiles scrolled out of view fail,
-- so they stop animating (they freeze where they were and pick up again when seen).
local function onScreen(face: Instance): boolean
	if not face:IsA("GuiObject") then
		return false
	end
	local pos, size = face.AbsolutePosition, face.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return false
	end
	local minX, minY, maxX, maxY = pos.X, pos.Y, pos.X + size.X, pos.Y + size.Y
	local node: Instance? = face
	while node do
		if node:IsA("LayerCollector") then
			if not node.Enabled then
				return false
			end
			local view = node.AbsoluteSize
			return maxX > 0 and maxY > 0 and minX < view.X and minY < view.Y
		elseif node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
			if node ~= face and (node:IsA("ScrollingFrame") or node.ClipsDescendants) then
				local cp, cs = node.AbsolutePosition, node.AbsoluteSize
				if maxX <= cp.X or maxY <= cp.Y or minX >= cp.X + cs.X or minY >= cp.Y + cs.Y then
					return false
				end
			end
		end
		node = node.Parent
	end
	return false -- (not under a ScreenGui: a template in storage)
end

local function twinkle(sparks: { Instance }, s: number)
	for _, spark in sparks do
		local base = spark:GetAttribute("Size") or 14
		local p = ((s - (spark:GetAttribute("Delay") or 0)) % 1.8) / 1.8
		local wave = 0.5 - 0.5 * math.cos(p * 2 * math.pi) -- 0 → 1 → 0, eased
		local size = math.floor(base * (0.7 + 0.45 * wave) + 0.5)
		spark.Size = UDim2.fromOffset(size, size)
		spark.ImageTransparency = 0.75 - 0.75 * wave
	end
end

local function step()
	local t = os.clock()
	local count, animated = 0, 0
	-- (the on-screen checks all come first: reading a frame's AbsolutePosition after this
	-- frame's writes makes Roblox lay the whole screen out again, once per read)
	for face, entry in active do
		if not face.Parent then
			active[face] = nil
			continue
		end
		count += 1
		if t >= entry.NextCheck then
			entry.Shown = onScreen(face)
			entry.NextCheck = t + CHECK_EVERY * (0.75 + 0.5 * math.random()) -- (spread out)
		end
	end
	for face, entry in active do
		if not entry.Shown or (entry.Tile and lowEffects) then
			continue
		end
		animated += 1
		local p, kind = entry.Parts, entry.Kind
		local s = t + entry.Seed
		if kind == "luckydraw" or kind == "oneofone" then
			-- the light sweep crosses in the first 60% of 2.6s, ease-in-out, then waits
			local q = (s % 2.6) / 2.6
			local x = if q < 0.6 then 0.5 - 0.5 * math.cos(q / 0.6 * math.pi) else 1
			if p.Sweep then
				p.Sweep.Position = UDim2.fromScale(-0.6 + x * 1.9, -0.2)
			end
		end
		if kind == "fansign" and p.Note then
			-- the note bobs gently: up 3px and back, tipping a degree either way, every 2.4s
			-- (moved by Scale, not Offset: an Offset is whole pixels, which steps)
			local wave = math.sin(s / 2.4 * 2 * math.pi)
			local home = p.NoteHome
			local lift = p.Bob * (0.5 + 0.5 * wave) / p.PhotoHeight
			p.Note.Position = UDim2.new(home.X, UDim.new(home.Y.Scale - lift, home.Y.Offset))
			p.Note.Rotation = -4 + 1.2 * math.sin(s / 2.4 * 2 * math.pi + 0.8)
		end
		if kind == "fansign" then
			-- the holo frame drifts back and forth over 6s, the ribbon's foil over 2.4s, the
			-- glitter glints (opacity .35 ↔ .95 over 1.6s), and hearts float up (3.4s each)
			p.Foil.Offset = Vector2.new(0.3 * math.sin(s / 6 * 2 * math.pi), 0)
			if p.Ribbon then
				p.Ribbon.Offset = Vector2.new(0.35 * math.sin(s / 2.4 * 2 * math.pi), 0)
			end
			for _, tile in p.Glint do
				local wave = 0.5 - 0.5 * math.cos(((s - tile:GetAttribute("Delay")) / 1.6) * 2 * math.pi)
				tile.ImageTransparency = 0.65 - 0.6 * wave
			end
			twinkle(p.Sparks, s)
			for _, heart in p.Hearts do
				local r = ((s - heart:GetAttribute("Delay")) % 3.4) / 3.4
				local eased = 1 - (1 - r) * (1 - r) -- ease-out
				local fade = if r < 0.12 then r / 0.12 else 1 - (r - 0.12) / 0.88
				heart.Position = UDim2.new(heart:GetAttribute("Home") + heart:GetAttribute("Drift") * eased, 0, 1 - 1.02 * eased, 0)
				heart.Scale.Scale = 0.6 + 0.4 * eased
				heart.TextTransparency = 1 - fade
				heart.UIStroke.Transparency = 1 - fade
			end
		end
		if kind == "polaroid" then
			twinkle(p.Sparks, s)
		elseif kind == "oneofone" then
			local turn = (s / 8 % 1) * 360 -- one slow turn every 8s
			p.Rim.Rotation = turn
			p.AuraColour.Rotation = turn
			p.Aura.ImageTransparency = 0.225 - 0.225 * math.cos(s / 2.4 * 2 * math.pi) -- opacity .55 ↔ 1
			if p.Hue then
				p.Hue.Rotation = (120 + s / 12 * 360) % 360
			end
			p.Name.Offset = Vector2.new(1 - 2 * ((s / 2.5) % 1), 0)
			if p.Only then
				p.Only.Offset = p.Name.Offset
			end
			twinkle(p.Sparks, s)
			for _, mote in p.Dust do
				local r = ((s - mote:GetAttribute("Delay")) % 3.2) / 3.2
				local fade = if r < 0.15 then r / 0.15 else 1 - (r - 0.15) / 0.85
				mote.Position = UDim2.new(mote.Position.X, UDim.new(1, -p.Lift * r * r - p.Base))
				mote.ImageTransparency = 1 - fade * 0.7
				mote.Dot.BackgroundTransparency = 1 - fade
			end
		end
	end
	stats.Active, stats.Animated = count, animated
	stats.StepMs = stats.StepMs * 0.9 + (os.clock() - t) * 1000 * 0.1 -- (smoothed)
	if next(active) == nil and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function animate(face: Instance, kind: string?, parts: { [string]: any }?, tile: boolean?)
	if not kind or not parts then
		active[face] = nil
		return
	end
	-- (checked for the screen on the next frame, each card at its own moment)
	active[face] = { Kind = kind, Parts = parts, Seed = (active[face] and active[face].Seed) or math.random() * 10, Shown = false, NextCheck = 0, Tile = tile == true }
	if not loop and RunService:IsRunning() then
		loop = RunService.RenderStepped:Connect(step)
	end
end

-- Settings.LowEffects (Client/SettingsController): on, the tiles stop moving
function CardDecor.SetLowEffects(on: boolean)
	lowEffects = on
	-- the tiles on show put their moving pieces away (or back)
	for _, entry in active do
		if entry.Tile and entry.Parts.Costly then
			for piece, shown in entry.Parts.Costly do
				piece.Visible = shown and not on
			end
		end
	end
end

-- how many cards are registered to animate, how many animated on the last frame, and the
-- loop's average cost per frame (for the performance checks)
function CardDecor.Stats(): { Active: number, Animated: number, StepMs: number }
	return table.clone(stats)
end

-- [[ Paint (runtime) ]]

-- the serial chip in its rarity's colour (canvas 44 A): the Fansign's in the ribbon's foil,
-- the Polaroid's cream with orange date-stamp digits, anything else gold
local SERIAL_FOIL = seq({ { 0, "C9D3E3" }, { 0.3, "FFFFFF" }, { 0.55, "FF9EC4" }, { 0.75, "FFFFFF" }, { 1, "C9D3E3" } })
local function tintSerial(chip: Instance?, key: string)
	if not (chip and chip:IsA("TextLabel")) then
		return
	end
	local gradient = chip:FindFirstChild("Gold")
	local stamp = key == "polaroid"
	if gradient then
		gradient.Enabled = not stamp
		gradient.Color = if key == "fansign" then SERIAL_FOIL else GOLD_TAG
	end
	chip.BackgroundColor3 = if stamp then C("FBF7F0") else WHITE
	chip.TextColor3 = if stamp then C("FF8A3D") else INK
	chip.FontFace = if stamp then MONO else HEAD
end

type Options = { Serial: number?, Date: number? }

-- turns the face into the polaroid shape (square corners, thick bottom) or back
local function shape(face: Instance, photo: Instance, polaroid: boolean)
	local photoCorner = photo:FindFirstChildOfClass("UICorner")
	local photoStroke = photo:FindFirstChildOfClass("UIStroke")
	local faceCorner = face:FindFirstChildOfClass("UICorner")
	local art = photo:FindFirstChild("Art")
	local artCorner = art and art:FindFirstChildOfClass("UICorner")
	local basePos, baseSize = photo:GetAttribute("BasePosition"), photo:GetAttribute("BaseSize")
	if not (basePos and baseSize) then
		return
	end
	local k = widthOf(face) / 150
	if polaroid then
		photo.Position = UDim2.new(basePos.X, UDim.new(0, basePos.Y.Offset))
		photo.Size = UDim2.new(baseSize.X, UDim.new(POLAROID_PHOTO, 0))
	else
		photo.Position = basePos
		photo.Size = baseSize
	end
	local photoRadius = if polaroid then 0 else photo:GetAttribute("BaseCorner") or 0
	if photoCorner then
		photoCorner.CornerRadius = UDim.new(0, photoRadius)
	end
	if artCorner then
		artCorner.CornerRadius = UDim.new(0, photoRadius)
	end
	if photoStroke then
		photoStroke.Thickness = if polaroid then math.max(1, 1.5 * k) else photo:GetAttribute("BaseStroke") or photoStroke.Thickness
		photoStroke.Color = if polaroid then C("3A3550") else INK
	end
	if faceCorner then
		faceCorner.CornerRadius = UDim.new(0, if polaroid then math.max(2, math.floor(4 * k + 0.5)) else face:GetAttribute("BaseCorner") or faceCorner.CornerRadius.Offset)
	end
end

function CardDecor.Paint(root: Instance, face: Instance, cardId: string?, copies: number, options: Options?): any
	local outer, mid = root:FindFirstChild("Decor"), face:FindFirstChild("Decor")
	local photo = face:FindFirstChild("Photo")
	local top = photo and photo:FindFirstChild("Decor")
	if not (outer and mid and top) then
		return nil
	end
	local info = cardId and cardId ~= "" and Albums.Card(cardId)
	if not info then
		CardDecor.Clear(root, face)
		return nil
	end
	options = options or {}
	local key = info.Rarity.Key
	local member, album = info.Member, info.Album
	local isPolaroid, isOne = key == "polaroid", key == "oneofone"
	local serialText = Albums.SerialText(info.Id, options.Serial)

	CardDecor.ShowEdges(root, face, true) -- (a repaint starts from everything showing)
	-- the face
	shape(face, photo, isPolaroid)
	face.BackgroundColor3 = FACE[key] or WHITE
	local foil = face:FindFirstChild("Foil")
	if foil then
		foil.Enabled = key == "luckydraw" or key == "fansign"
		foil.Color = if key == "luckydraw" then GOLD_FRAME elseif key == "fansign" then DRIFT else HOLO
		foil.Rotation = if key == "fansign" then 30 else 45
		foil.Offset = Vector2.zero
		foil.Transparency = NumberSequence.new(0)
	end
	mid.Glitter.Visible = key == "luckydraw"
	if mid:FindFirstChild("Glint") then
		mid.Glint.Visible = key == "fansign"
	end
	mid.Sky.Visible = isOne
	mid.Washi.Visible = isPolaroid
	if mid:FindFirstChild("Ribbon") then
		mid.Ribbon.Visible = key == "fansign"
		-- the band's words drawn TextScaled inside it (padded so they stay at design size), so on a
		-- phone they can't run past the band's end
		local band = mid.Ribbon:FindFirstChild("Band")
		if band and not band.TextScaled then
			local h = mid.Ribbon.Size.Y.Offset
			local v = math.max(0, math.floor((h - band.TextSize * 1.15) / 2))
			local padding = band:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
			padding.PaddingTop, padding.PaddingBottom = UDim.new(0, v), UDim.new(0, v)
			padding.PaddingLeft, padding.PaddingRight = UDim.new(0, math.ceil(h * 0.25)), UDim.new(0, math.ceil(h * 0.25))
			padding.Parent = band
			band.TextScaled = true
		end
	end
	mid.Caption.Visible = isPolaroid
	mid.Caption.Text = `{string.lower(member.Person or member.Name)} ♡ {string.lower(album.Artist or "")}`
	mid.FootSerial.Visible = isPolaroid and serialText ~= nil
	mid.FootSerial.Text = serialText or ""
	local name = face:FindFirstChild("Member")
	local gold = name and name:FindFirstChild("Gold")
	if name and name:IsA("TextLabel") then
		name.Visible = not isPolaroid
		name.TextColor3 = if isOne then WHITE else INK
		if gold then
			gold.Enabled = isOne
		end
	end
	-- the BIAS chip sits beside the name, so it goes with it (it hid behind the foot serial)
	local biasChip = face:FindFirstChild("Bias")
	if isPolaroid and biasChip and biasChip:IsA("GuiObject") then
		biasChip.Visible = false
	end
	local albumLabel = face:FindFirstChild("Album")
	if albumLabel and albumLabel:IsA("TextLabel") then
		albumLabel.Visible = not isPolaroid
		albumLabel.TextColor3 = if isOne then CREAM else INK
	end
	if mid:FindFirstChild("OnlyOne") then
		mid.OnlyOne.Visible = isOne
	end
	local photoStroke = photo:FindFirstChildOfClass("UIStroke")
	if photoStroke and not isPolaroid then
		photoStroke.Color = if isOne then C("E8C15A") else INK
	end
	local shadow = root:FindFirstChild("Shadow")
	if shadow then
		shadow.Visible = not isOne -- the Cosmic card glows instead of casting a shadow
	end

	-- the photo
	-- Lucky Draw uses the One of One's one-way light sweep in gold (not the back-and-forth
	-- pastel sheen); the Fansign has no shine
	local tile = root:GetAttribute("CardFx") == "Tile"
	local prism, shine = top:FindFirstChild("Prism"), top:FindFirstChild("Shine")
	local sparks, goldSparks = top:FindFirstChild("Sparks"), top:FindFirstChild("GoldSparks")
	if prism then
		prism.Visible = isOne
	end
	if shine then
		shine.Visible = isOne or key == "luckydraw" -- (the Fansign has no shine)
		shine.Sweep.Band.Color = SWEEP[key] or ColorSequence.new(WHITE)
	end
	if goldSparks then
		goldSparks.Visible = isOne
	end
	if sparks then
		sparks.Visible = isPolaroid
	end
	top.Tag.Visible = key == "luckydraw"
	if top.Tag.Visible and top.Tag.AutomaticSize ~= Enum.AutomaticSize.None then
		fitBox(top.Tag, Enum.Font.GothamBlack, true) -- cards built before the tag was boxed
	end
	top.Seal.Visible = key == "store"
	-- a smaller sticker that just says STORE, drawn TextScaled inside its circle (the two-line
	-- STORE BENEFIT wrapped into "STOR / E" on phones)
	if top.Seal.Visible and not top.Seal:GetAttribute("Short") then
		local seal = top.Seal
		seal:SetAttribute("Short", true)
		local s = math.floor(seal.Size.X.Offset * 0.72 + 0.5)
		seal.Size = UDim2.fromOffset(s, s)
		seal.Text = "STORE"
		seal.TextWrapped = false
		seal.TextScaled = true
		local inset = math.max(2, math.floor(s * 0.16))
		new("UIPadding", { PaddingLeft = UDim.new(0, inset), PaddingRight = UDim.new(0, inset), PaddingTop = UDim.new(0, inset), PaddingBottom = UDim.new(0, inset) }, seal)
	end
	top.Sig.Visible = isPolaroid
	top.Sig.Shadow.Text = member.Person or member.Name -- (a signature is the person, never "Ver. 2")
	top.Sig.Text.Text = member.Person or member.Name
	local date = options.Date
	top.Date.Visible = isPolaroid and date ~= nil
	top.Date.Text = if date then os.date("'%y %m %d", date) else ""
	if top:FindFirstChild("Doodles") then
		top.Doodles.Visible = key == "selca"
	end
	if top:FindFirstChild("Note") then
		top.Note.Visible = key == "fansign"
		top.Note.Text = `to. you ♡\nthank u for\ncoming!! - {string.lower(member.Person or member.Name)}`
		fitBox(top.Note, Enum.Font.Kalam)
	end
	for _, old in { "Shine", "Stamp", "Signature" } do
		local inst = photo:FindFirstChild(old)
		if inst then
			inst.Visible = false
		end
	end
	local serial = photo:FindFirstChild("Serial")
	if serial and serial:IsA("TextLabel") then
		-- the polaroid keeps its number in the foot; the 1/1 seal already says it
		serial.Visible = serialText ~= nil and not isOne and not isPolaroid
		serial.Text = serialText or ""
	end
	tintSerial(serial, key)
	-- (on the big faces the serial takes the rarity chip's place in the polaroid's foot)
	local rarityChip = face:FindFirstChild("Rarity")
	if rarityChip and rarityChip:IsA("GuiObject") then
		rarityChip.Visible = not (isPolaroid and serialText ~= nil)
	end
	tintSerial(mid.FootSerial, key)

	-- the level stars (in place of the Level chip and the halo)
	local level = Albums.Level(copies) or "Normal"
	local colours = STARS[level] or STARS.Normal
	for i = 1, 3 do
		local star = outer.Stars:FindFirstChild("Star" .. i)
		if star then
			local colour = colours[i]
			star.Fill.ImageColor3 = colour or CREAM
			star.Fill.ImageTransparency = if colour then 0 else 0.6
			star.Shadow.ImageTransparency = if colour then 0 else 0.75
		end
	end
	outer.Stars.Visible = true
	for _, old in { face:FindFirstChild("Level"), root:FindFirstChild("Glow") } do
		if old then
			old.Visible = false
		end
	end
	outer.Aura.Visible = isOne
	outer.Rim.Visible = isOne
	outer.Dust.Visible = isOne
	outer.Seal.Visible = isOne
	for _, name in { "Hearts", "Twinkles" } do
		local piece = outer:FindFirstChild(name)
		if piece then
			piece.Visible = key == "fansign"
		end
	end

	-- the moving pieces: on a tile with Low effects on they're put away (SetLowEffects puts
	-- them back when it's turned off)
	local costly = {}
	for _, piece in { prism, shine, sparks, goldSparks, outer.Dust, outer:FindFirstChild("Hearts"), outer:FindFirstChild("Twinkles") } do
		if piece then
			costly[piece] = piece.Visible
			if tile and lowEffects then
				piece.Visible = false
			end
		end
	end

	-- moving parts
	if key == "luckydraw" or key == "fansign" then
		local note = top:FindFirstChild("Note")
		local ribbon = mid:FindFirstChild("Ribbon")
		local hearts, twinkles, glint = outer:FindFirstChild("Hearts"), outer:FindFirstChild("Twinkles"), mid:FindFirstChild("Glint")
		animate(face, key, {
			Foil = foil or Instance.new("UIGradient"),
			Ribbon = ribbon and ribbon.Band:FindFirstChild("Foil"),
			Glint = if glint then glint:GetChildren() else {},
			Hearts = if hearts then hearts:GetChildren() else {},
			Sparks = if twinkles then twinkles:GetChildren() else {},
			Sweep = shine and shine.Sweep,
			Photo = photo,
			Note = if key == "fansign" then note else nil,
			Costly = costly,
			NoteHome = note and (note:GetAttribute("Home") or note.Position),
			Bob = 3 * widthOf(face) / 150,
			PhotoHeight = math.max(1, heightOf(photo)),
		}, tile)
	elseif isPolaroid then
		animate(face, key, { Sparks = if sparks then sparks:GetChildren() else {}, Costly = costly }, tile)
	elseif isOne then
		local k = widthOf(face) / 150
		animate(face, key, {
			Rim = outer.Rim.Colour,
			Aura = outer.Aura,
			AuraColour = outer.Aura.Colour,
			Hue = prism and prism.Hue,
			Sweep = shine and shine.Sweep,
			Photo = photo,
			Name = gold or Instance.new("UIGradient"),
			Only = mid:FindFirstChild("OnlyOne") and mid.OnlyOne.Gold,
			Sparks = if goldSparks then goldSparks:GetChildren() else {},
			Dust = outer.Dust:GetChildren(),
			Lift = 230 * k,
			Base = 6 * k,
			Costly = costly,
		}, tile)
	else
		animate(face, nil)
	end
	return info
end

-- Hides (false) or brings back (true) the decor that reaches past the card's edge: the stars,
-- aura, rim, dust and seal round it, and the Fansign ribbon and Polaroid tape over its edge.
-- The pack reveal hides them while the card is face down, so they don't poke out round the
-- back (or give the rarity away), and brings them back once it has flipped.
function CardDecor.ShowEdges(root: Instance, face: Instance, show: boolean)
	local outer, mid = root:FindFirstChild("Decor"), face:FindFirstChild("Decor")
	local pieces = {}
	if outer then
		for _, child in outer:GetChildren() do
			table.insert(pieces, child)
		end
	end
	if mid then
		for _, name in { "Ribbon", "Washi" } do
			local child = mid:FindFirstChild(name)
			if child then
				table.insert(pieces, child)
			end
		end
	end
	for _, piece in pieces do
		if show then
			local want = piece:GetAttribute("ShownBeforeHide")
			if want ~= nil then
				piece.Visible = want
				piece:SetAttribute("ShownBeforeHide", nil)
			end
		elseif piece:GetAttribute("ShownBeforeHide") == nil then
			piece:SetAttribute("ShownBeforeHide", piece.Visible)
			piece.Visible = false
		end
	end
end

-- [[ Mini cards ]]

-- The HUD binder widget's pinned cards are 24 px wide: too small for the decor, so they only
-- take the rarity's frame. BuildMini adds a Foil gradient to the frame and a Rim gradient to
-- its outline; PaintMini sets them (nil cardId puts back the plain white frame).
function CardDecor.BuildMini(frame: Frame)
	for _, old in { frame:FindFirstChild("Foil") } do
		old:Destroy()
	end
	new("UIGradient", { Name = "Foil", Rotation = 45, Enabled = false }, frame)
	local outline = frame:FindFirstChildOfClass("UIStroke")
	if outline then
		local old = outline:FindFirstChild("Rim")
		if old then
			old:Destroy()
		end
		new("UIGradient", { Name = "Rim", Color = RAINBOW, Rotation = 45, Enabled = false }, outline)
	end
end

function CardDecor.PaintMini(frame: Frame, cardId: string?)
	local info = cardId and cardId ~= "" and Albums.Card(cardId)
	local key = if info then info.Rarity.Key else nil
	frame.BackgroundColor3 = if key then FACE[key] or WHITE else WHITE
	local foil = frame:FindFirstChild("Foil")
	if foil then
		foil.Enabled = key == "luckydraw" or key == "fansign"
		foil.Color = if key == "luckydraw" then GOLD_FRAME elseif key == "fansign" then DRIFT else HOLO
		foil.Rotation = if key == "fansign" then 30 else 45
	end
	local outline = frame:FindFirstChildOfClass("UIStroke")
	local rim = outline and outline:FindFirstChild("Rim")
	if rim then
		rim.Enabled = key == "oneofone"
	end
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner:SetAttribute("Base", corner:GetAttribute("Base") or corner.CornerRadius.Offset)
		corner.CornerRadius = UDim.new(0, if key == "polaroid" then 1 else corner:GetAttribute("Base"))
	end
end

-- hides the stars and the glow (and stops the motion) on a face that shows no card
function CardDecor.Clear(root: Instance, face: Instance)
	animate(face, nil)
	local outer = root:FindFirstChild("Decor")
	if outer then
		for _, name in { "Stars", "Aura", "Rim", "Dust", "Seal", "Hearts", "Twinkles" } do
			local piece = outer:FindFirstChild(name)
			if piece then
				piece.Visible = false
			end
		end
	end
end

return CardDecor
