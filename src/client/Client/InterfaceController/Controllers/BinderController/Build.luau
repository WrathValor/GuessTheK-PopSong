--| Binder UI builder
-- Builds Interface.Frames.Binder: the K-POPPED! binder, full screen (design board "27 · Binder ·
-- full screen (one group a page)"). Run once in Studio Edit mode from the command bar, then save
-- the place:
--   require(game.StarterPlayer.StarterPlayerScripts.Client.InterfaceController.Controllers.BinderController.Build).Build(game.StarterGui.Interface.Frames)
-- Safe to run again: it replaces the old frame.
-- BinderController finds everything by name and fills lists by cloning the hidden templates.
--
-- One full-screen frame over the dark backdrop:
--   Header   title + totals, the Binder / Songs tabs, coins, COLLECT, close
--   (left)   the group list, shared by both tabs, with a By group / All cards (All songs) switch
--            over it: Binder shows My pins above it, Songs shows My songs (lobby music)
--   Binder   your pins (My pins: the cards that earn coins) over the group list on the left
--            (search, All / Girls / Boys / Most done), and the page:
--            the album's header (progress, coins an hour, OPEN PACK, one tab per album), the
--            rarity columns and a row per member with a slot per rarity (a card, "?", or the
--            One of One slot: "Owned by …" / "Unclaimed")
--   All      every card you own as a grid, best first (in the page's place, by the group list)
--   Songs    the Songs tab (design board "46 · Binder · Songs tab"): Group (a group's songs:
--            % mastered, milestone bar, PRACTISE, a row per song with stars and lobby music)
--            and AllSongs (every song, sorted)
--   Detail   one card: serials, copies and level, earnings, Sell, the member's other cards
--            (Grade, Show on profile and Trade are shown as coming soon)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local PINK = C("FF9EC4")
local MUTED = C("5C566B")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local Currencies = require(game:GetService("ReplicatedStorage").Constants.Currencies)
local CardDecor = require(game:GetService("ReplicatedStorage").Modules.UI.CardDecor)
local Ladders = require(game:GetService("ReplicatedStorage").Modules.Library.Ladders)
local COIN = Currencies.Coins.Icon

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FF5A4E")),
	ColorSequenceKeypoint.new(0.2, C("FFE07A")),
	ColorSequenceKeypoint.new(0.4, C("A7E9B8")),
	ColorSequenceKeypoint.new(0.6, C("9ED8F5")),
	ColorSequenceKeypoint.new(0.8, C("B9A6FF")),
	ColorSequenceKeypoint.new(1, C("FF9EC4")),
})

-- the rarity columns (AlbumConstants.RARITIES order): header label and dot colour
local COLUMNS = {
	{ "Standard", WHITE },
	{ "Selca", C("FFD2E5") },
	{ "Store", MINT },
	{ "Lucky Draw", C("DDE6F0") },
	{ "Fansign", PINK },
	{ "Polaroid", C("F2C94C") },
	{ "1 of 1", nil },
}

-- the page (design: left 330, top 124, 910×570)
local PAGE_X, PAGE_Y, PAGE_W, PAGE_H = 330, 124, 910, 570
local ROW_H = 102 -- one member
local SLOT_X, SLOT_STEP = 172, 104 -- first slot's left and the column pitch, inside the page
local DIM = 0.35 -- TextTransparency for quiet cream text

local Build = {}

-- [[ Helpers ]]

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
local function stroke(p: Instance, t: number, colour: Color3?, transparency: number?)
	new("UIStroke", { Color = colour or INK, Thickness = t, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function pad(p: Instance, l: number, r: number?, t: number?, b: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0) }, p)
end
local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function chip(parent: Instance, name: string, label: string, colour: Color3, size: number, props: { [string]: any }?): TextLabel
	local base = {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 8),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		FontFace = BODY,
		TextSize = size,
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Center,
	}
	for k, v in props or {} do
		base[k] = v
	end
	local c = text(parent, name, base)
	corner(c, 7)
	stroke(c, 2)
	pad(c, 6)
	return c
end
local function list(parent: Instance, horizontal: boolean, gap: number, props: { [string]: any }?): UIListLayout
	local base = {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
	}
	for k, v in props or {} do
		base[k] = v
	end
	return new("UIListLayout", base, parent)
end
-- a centre-anchored button with a hard shadow. With an icon: a row of Label + Icon + Amount.
local function button(parent: Instance, name: string, cx: number, cy: number, w: number, h: number, colour: Color3, label: string, size: number, icon: string?, drop: number?): TextButton
	local d = drop or 4
	local edge = if h >= 40 then 4 else 3 -- the outline (UIStroke draws outside the button)
	if d > 0 then
		-- the shadow covers the outline too, so it shows d px past it (like the design's box-shadow)
		local s = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + d, cy + d), Size = UDim2.fromOffset(w + edge * 2, h + edge * 2), BackgroundColor3 = INK }, parent)
		corner(s, 12 + edge)
	end
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		FontFace = HEAD,
		TextSize = size,
		TextColor3 = INK,
		Text = if icon then "" else label,
		AutoButtonColor = false,
		ZIndex = 2,
	}, parent)
	corner(b, 12)
	stroke(b, edge)
	if icon then
		local row = new("Frame", { Name = "Row", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, b)
		list(row, true, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
		text(row, "Label", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), FontFace = HEAD, TextSize = size, Text = label, LayoutOrder = 1, ZIndex = 2 })
		new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(size + 6, size + 6), BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 2, ZIndex = 2 }, row)
		text(row, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), FontFace = HEAD, TextSize = size, Text = "0", LayoutOrder = 3, ZIndex = 2 })
	end
	return b
end
-- the grey silhouette that stands in for idol art that hasn't landed yet
local function silhouette(parent: Instance, scale: number, z: number?)
	local s = new("Frame", { Name = "Silhouette", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(200 * scale, 240 * scale), BackgroundTransparency = 1, ZIndex = z or 1 }, parent)
	local head = new("Frame", { Name = "Head", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44 * scale), Size = UDim2.fromOffset(96 * scale, 96 * scale), BackgroundColor3 = INK, BackgroundTransparency = 0.84, ZIndex = z or 1 }, s)
	corner(head, 999)
	local body = new("Frame", { Name = "Body", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 148 * scale), Size = UDim2.fromOffset(172 * scale, 92 * scale), BackgroundColor3 = INK, BackgroundTransparency = 0.84, ZIndex = z or 1 }, s)
	corner(body, math.max(1, math.floor(46 * scale)))
end
-- a thin progress bar: Bar (track) › Fill (Size.X.Scale = done)
local function bar(parent: Instance, x: number, y: number, w: number, h: number, track: Color3, trackT: number, fill: Color3, outline: boolean?): Frame
	local b = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = track, BackgroundTransparency = trackT, ClipsDescendants = true }, parent)
	corner(b, math.ceil(h / 2))
	if outline then
		stroke(b, 2)
	end
	local f = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = fill, BorderSizePixel = 0 }, b)
	corner(f, math.ceil(h / 2))
	return b
end

-- [[ Cards ]]

local PIN_ICON = "rbxassetid://103300285748511" -- a red pushpin (assets/UI/HUD/Pin.png)

-- the pushpin stuck in the corner of a pinned card (Visible off; BinderController shows it)
local function pinBadge(parent: Instance, at: UDim2, size: number): ImageLabel
	return new("ImageLabel", { Name = "Pin", AnchorPoint = Vector2.new(1, 0), Position = at, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = PIN_ICON, ScaleType = Enum.ScaleType.Fit, Visible = false, ZIndex = 4 }, parent)
end

-- A binder slot's card, 60×88 (design "27": the small photocard). The controller sets the face
-- colour, Foil, Photo (colour, Art, Silhouette, Shine, Stamp, Serial), Name, Level and Copies.
local function slotCard(parent: Instance): Frame
	local root = new("Frame", { Name = "Card", Size = UDim2.fromOffset(60, 88), BackgroundTransparency = 1, Visible = false }, parent)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, root)
	corner(shadow, 6)
	local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, root)
	corner(face, 6)
	stroke(face, 2)
	new("UIGradient", { Name = "Foil", Enabled = false, Rotation = 45 }, face)
	local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -17), BackgroundColor3 = C("FFD2E5"), ClipsDescendants = true }, face)
	corner(photo, 4)
	stroke(photo, 1.5)
	silhouette(photo, 0.27)
	local art = new("ImageLabel", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Image = "" }, photo)
	corner(art, 4) -- (ClipsDescendants doesn't round an image's corners)
	new("Frame", { Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.new(1.6, 0, 0, 6), Rotation = -24, BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false }, photo)
	local stamp = text(photo, "Stamp", { Position = UDim2.fromOffset(1, 1), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 8), BackgroundTransparency = 0, BackgroundColor3 = MINT, TextSize = 6, Text = "STORE", Rotation = -8, Visible = false })
	stroke(stamp, 1)
	pad(stamp, 1)
	local serial = text(photo, "Serial", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -1, 0, 1), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 9), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = YELLOW, FontFace = HEAD, TextSize = 7, Text = "#4", Visible = false })
	pad(serial, 1)
	text(face, "Member", { Position = UDim2.new(0, 4, 1, -13), Size = UDim2.new(1, -8, 0, 11), FontFace = HEAD, TextSize = 7, Text = "JISOO", TextTruncate = Enum.TextTruncate.AtEnd })
	local level = text(face, "Level", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -3, 1, -12), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 8), BackgroundTransparency = 0, BackgroundColor3 = C("F2C94C"), TextSize = 6, Text = "GOLD", Visible = false })
	stroke(level, 1)
	pad(level, 1)
	new("UIGradient", { Name = "Rainbow", Enabled = false, Color = RAINBOW }, level)
	chip(root, "Copies", "×2", CREAM, 10, { Position = UDim2.fromOffset(-7, -9), ZIndex = 3, Visible = false })
	pinBadge(root, UDim2.new(1, 14, 0, -18), 36)
	CardDecor.Build(root, face, photo) -- the v2 rarity looks + level stars
	return root
end

-- A photocard face, 260×380 (the same face as the packs screen). The controller fills Photo,
-- Member, Album, Rarity, Bias, Level, the serial and the rarity look (Foil, Stamp, Signature, Shine).
local function cardFace(parent: Instance, name: string): Frame
	local root = new("Frame", { Name = name, Size = UDim2.fromOffset(260, 380), BackgroundTransparency = 1 }, parent)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(9, 9), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, root)
	corner(shadow, 18)
	local glow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 18, 1, 18), BackgroundColor3 = C("F2C94C"), Visible = false }, root)
	corner(glow, 24)
	new("UIGradient", { Name = "Rainbow", Enabled = false, Rotation = 45, Color = RAINBOW }, glow)
	local c = new("Frame", { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, root)
	corner(c, 18)
	stroke(c, 5)
	new("UIGradient", { Name = "Foil", Enabled = false, Rotation = 45 }, c)
	local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -96), BackgroundColor3 = C("FFD2E5"), ClipsDescendants = true }, c)
	corner(photo, 12)
	stroke(photo, 4)
	silhouette(photo, 1)
	local art = new("ImageLabel", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Image = "" }, photo)
	corner(art, 12)
	new("Frame", { Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(116, 96), Size = UDim2.fromOffset(300, 22), Rotation = -24, BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, Visible = false }, photo)
	chip(photo, "Stamp", "STORE", MINT, 10, { Position = UDim2.fromOffset(8, 8), Visible = false, Rotation = -8 })
	chip(photo, "Serial", "#12", INK, 16, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), FontFace = HEAD, TextColor3 = YELLOW, Visible = false })
	text(photo, "Signature", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -8), Size = UDim2.fromOffset(150, 36), FontFace = Font.new("rbxasset://fonts/families/IndieFlower.json"), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Right, Text = "Jimin", Rotation = -8, Visible = false })
	text(c, "Member", { Position = UDim2.new(0, 14, 1, -76), Size = UDim2.new(1, -110, 0, 32), FontFace = HEAD, TextSize = 26, Text = "Jimin", TextTruncate = Enum.TextTruncate.AtEnd })
	chip(c, "Bias", "BIAS", PINK, 10, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -72), Visible = false })
	chip(c, "Level", "GOLD", INK, 10, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 1, -72), TextColor3 = C("F2C94C"), Visible = false })
	local albumLine = text(c, "Album", { Position = UDim2.new(0, 14, 1, -38), Size = UDim2.new(1, -120, 0, 22), TextSize = 12, Text = "BTS · Love Yourself", TextTruncate = Enum.TextTruncate.AtEnd })
	albumLine:SetAttribute("FitTextSkip", true) -- stays readable and cuts off with "…" (the controller widths it beside the rarity chip)
	chip(c, "Rarity", "LUCKY DRAW", INK, 10, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -36), TextColor3 = CREAM })
	CardDecor.Build(root, c, photo) -- the v2 rarity looks + level stars
	return root
end

-- [[ Backdrop + header ]]

local function backdrop(root: Frame)
	local bg = new("Frame", { Name = "Backdrop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, root)
	bg.Active = true
	new("UIGradient", { Color = ColorSequence.new(C("3B2F66"), C("221C36")), Rotation = 90, Offset = Vector2.new(0, 0.05) }, bg)
end

local function header(root: Frame)
	text(root, "Title", { Position = UDim2.fromOffset(40, 54), Size = UDim2.fromOffset(300, 36), FontFace = HEAD, TextSize = 30, TextColor3 = CREAM, Text = "Binder" })
	text(root, "Sub", { Position = UDim2.fromOffset(40, 90), Size = UDim2.fromOffset(560, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = CREAM, TextTransparency = 0.4, Text = "86 of 2,261 cards · 51 groups · earning 72 coins an hour" })

	-- the Binder / Songs tabs
	local tabs = new("Frame", { Name = "Tabs", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 60), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, BackgroundTransparency = 0.92 }, root)
	corner(tabs, 12)
	stroke(tabs, 2, CREAM, 0.75)
	pad(tabs, 3, 3, 3, 3)
	list(tabs, true, 2)
	for i, spec in { { "Binder", "Binder" }, { "Songs", "Songs" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), BackgroundColor3 = CREAM, BackgroundTransparency = if i == 1 then 0 else 1, FontFace = BODY, TextSize = 16, TextColor3 = if i == 1 then INK else CREAM, Text = spec[2], AutoButtonColor = false }, tabs)
		corner(b, 9)
		pad(b, 20)
	end

	-- coins, COLLECT, close (right edge 1240)
	button(root, "Close", 1219, 81, 42, 42, RED, "X", 18, nil, 0)
	local collect = button(root, "Collect", 1104, 81, 176, 42, YELLOW, "COLLECT", 15, COIN, 4)
	collect.Row.Amount.Text = "1,240"
	local coins = new("Frame", { Name = "Coins", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(1000, 81), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), BackgroundColor3 = CREAM, BackgroundTransparency = 0.9 }, root)
	corner(coins, 12)
	stroke(coins, 2, CREAM, 0.8)
	pad(coins, 10, 14)
	list(coins, true, 7)
	new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, coins)
	text(coins, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextSize = 17, TextColor3 = CREAM, Text = "5,068", LayoutOrder = 2 })
	Build.BiasButton(root)
end

-- the pink Bias button (design board "55 · Bias button"): left of the coins, opens the Bias
-- page in Packs (BinderController keeps it 12 px left of the coins as they grow)
function Build.BiasButton(root: Instance): TextButton
	local old = root:FindFirstChild("Bias")
	if old then
		old:Destroy()
	end
	local b = new("TextButton", {
		Name = "Bias",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(870, 81),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 38),
		BackgroundColor3 = PINK,
		FontFace = BODY,
		TextSize = 15,
		TextColor3 = INK,
		Text = "Bias",
		AutoButtonColor = false,
	}, root)
	corner(b, 12)
	stroke(b, 3, INK)
	pad(b, 18)
	return b
end

-- [[ Binder: the group list ]]

-- a pin slot (My pins, the swap sheet): a 60×88 slot card drawn at `w` wide, an empty "+",
-- a lock for slots not unlocked yet
local function pinSlot(parent: Instance, name: string, order: number, w: number): Frame
	local scale = w / 60
	local slot = new("Frame", { Name = name, LayoutOrder = order, Size = UDim2.fromOffset(w + 4, math.ceil(88 * scale) + 4), BackgroundTransparency = 1 }, parent)
	local holder = new("Frame", { Name = "Holder", Position = UDim2.fromOffset(1, 3), Size = UDim2.fromOffset(60, 88), BackgroundTransparency = 1 }, slot)
	new("UIScale", { Scale = scale }, holder)
	local empty = new("Frame", { Name = "Empty", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.95 }, holder)
	corner(empty, 9)
	stroke(empty, 2.5, INK, 0.65)
	text(empty, "Mark", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 24, TextColor3 = INK, TextTransparency = 0.6, Text = "+", TextXAlignment = Enum.TextXAlignment.Center })
	-- a lock (shackle over a body) for a slot that isn't unlocked
	local lock = new("Frame", { Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(20, 24), BackgroundTransparency = 1, Visible = false }, empty)
	local shackle = new("Frame", { Name = "Shackle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(13, 14), BackgroundTransparency = 1 }, lock)
	corner(shackle, 7)
	stroke(shackle, 3, MUTED)
	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 10), Size = UDim2.fromOffset(20, 14), BackgroundColor3 = C("E9E2CF") }, lock)
	corner(body, 3)
	stroke(body, 3, MUTED)
	slotCard(holder)
	return slot
end

local function pinsPanel(side: Frame)
	local shadow = new("Frame", { Name = "PinsShadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(270, 130), BackgroundColor3 = INK }, side)
	corner(shadow, 14)
	local panel = new("Frame", { Name = "Pins", Size = UDim2.fromOffset(270, 130), BackgroundColor3 = CREAM }, side)
	corner(panel, 14)
	stroke(panel, 3)
	text(panel, "Title", { Position = UDim2.fromOffset(11, 7), Size = UDim2.fromOffset(150, 18), FontFace = HEAD, TextSize = 14, Text = "MY PINS · 3/3" })
	local rate = new("Frame", { Name = "Rate", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(259, 7), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, panel)
	list(rate, true, 4)
	new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, rate)
	text(rate, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), TextSize = 14, Text = "45 an hour", LayoutOrder = 2 })
	local slots = new("Frame", { Name = "Slots", Position = UDim2.fromOffset(9, 30), Size = UDim2.fromOffset(252, 82), BackgroundTransparency = 1 }, panel)
	list(slots, true, 5, { VerticalAlignment = Enum.VerticalAlignment.Top })
	for i = 1, 5 do
		local slot = pinSlot(slots, "Slot" .. i, i, 42)
		local b = new("TextButton", { Name = "Tap", Size = UDim2.new(1, 0, 0, 66), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5 }, slot)
		b:SetAttribute("NoButtonScale", true)
		slot.Size = UDim2.fromOffset(46, 82)
		-- (below the card and its stroke, so the photocard doesn't cover it)
		text(slot, "Earn", { Position = UDim2.fromOffset(0, 70), Size = UDim2.fromOffset(46, 12), TextSize = 11, TextColor3 = MUTED, Text = "+175/hr", TextXAlignment = Enum.TextXAlignment.Center })
	end
	text(panel, "Help", { Position = UDim2.fromOffset(11, 112), Size = UDim2.fromOffset(250, 14), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Only pinned cards earn. Tap any card, then PIN." })
end

-- the Songs tab's panel in My pins' place: your songs mastered and your lobby music
local function musicPanel(side: Frame)
	local shadow = new("Frame", { Name = "MusicShadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(270, 130), BackgroundColor3 = INK, Visible = false }, side)
	corner(shadow, 14)
	local panel = new("Frame", { Name = "Music", Size = UDim2.fromOffset(270, 130), BackgroundColor3 = CREAM, Visible = false }, side)
	corner(panel, 14)
	stroke(panel, 3)
	text(panel, "Title", { Position = UDim2.fromOffset(11, 7), Size = UDim2.fromOffset(150, 18), FontFace = HEAD, TextSize = 14, Text = "MY SONGS" })
	text(panel, "Stat", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(259, 7), Size = UDim2.fromOffset(120, 18), TextSize = 14, Text = "96 mastered", TextXAlignment = Enum.TextXAlignment.Right })
	bar(panel, 11, 30, 248, 8, INK, 0.88, INK).Name = "Known"
	text(panel, "KnownText", { Position = UDim2.fromOffset(11, 41), Size = UDim2.fromOffset(248, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "You know 23% of every song" })
	local lobby = new("Frame", { Name = "Lobby", Position = UDim2.fromOffset(9, 62), Size = UDim2.fromOffset(252, 40), BackgroundColor3 = WHITE }, panel)
	corner(lobby, 10)
	stroke(lobby, 2)
	text(lobby, "Label", { Position = UDim2.fromOffset(10, 3), Size = UDim2.fromOffset(170, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "LOBBY MUSIC" })
	text(lobby, "Song", { Position = UDim2.fromOffset(10, 17), Size = UDim2.fromOffset(170, 18), TextSize = 14, Text = "Supernova · aespa", TextTruncate = Enum.TextTruncate.AtEnd })
	local stop = new("TextButton", { Name = "Stop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8 - 28, 0.5, 0), Size = UDim2.fromOffset(56, 24), BackgroundColor3 = CREAM, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = "STOP", AutoButtonColor = false }, lobby)
	corner(stop, 12)
	stroke(stop, 2)
	text(panel, "Help", { Position = UDim2.fromOffset(11, 108), Size = UDim2.fromOffset(250, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Master a song (3 stars) to play it here." })
end

local function groups(page: Frame)
	local side = new("Frame", { Name = "Groups", Position = UDim2.fromOffset(40, 124), Size = UDim2.fromOffset(270, 570), BackgroundTransparency = 1 }, page)
	pinsPanel(side)

	musicPanel(side)

	-- By group / All cards (All songs on the Songs tab): the controller sets the labels
	local mode = new("Frame", { Name = "Mode", Position = UDim2.fromOffset(0, 142), Size = UDim2.fromOffset(270, 34), BackgroundColor3 = CREAM, BackgroundTransparency = 0.94 }, side)
	corner(mode, 11)
	stroke(mode, 2, CREAM, 0.82)
	pad(mode, 3, 3, 3, 3)
	list(mode, true, 4)
	for i, spec in { { "Group", "By group" }, { "All", "All cards" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, Size = UDim2.new(0.5, -2, 1, 0), BackgroundColor3 = YELLOW, BackgroundTransparency = if i == 1 then 0 else 1, FontFace = BODY, TextSize = 14, TextColor3 = if i == 1 then INK else CREAM, Text = spec[2], AutoButtonColor = false }, mode)
		corner(b, 8)
		stroke(b, 2, INK, if i == 1 then 0 else 1)
	end

	local search = new("Frame", { Name = "Search", Position = UDim2.fromOffset(0, 184), Size = UDim2.fromOffset(270, 38), BackgroundColor3 = CREAM, BackgroundTransparency = 0.92 }, side)
	corner(search, 11)
	stroke(search, 2, CREAM, 0.8)
	local glass = new("Frame", { Name = "Glass", Position = UDim2.fromOffset(12, 11), Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 1 }, search)
	corner(glass, 6)
	stroke(glass, 2, CREAM, 0.25)
	new("Frame", { Name = "Handle", Position = UDim2.fromOffset(9, 11), Size = UDim2.fromOffset(6, 2), Rotation = 45, BackgroundColor3 = CREAM, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, glass)
	new("TextBox", {
		Name = "Box",
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		FontFace = BODY_BOLD,
		TextSize = 15,
		TextColor3 = CREAM,
		PlaceholderText = "Find a group",
		PlaceholderColor3 = C("BDB6CF"),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, search)

	local filters = new("Frame", { Name = "Filters", Position = UDim2.fromOffset(0, 230), Size = UDim2.fromOffset(270, 28), BackgroundTransparency = 1 }, side)
	list(filters, true, 6)
	-- fixed widths that add up to the row (auto-sized pills ran off the side on phones)
	for i, spec in { { "All", "All", 46 }, { "Girl", "Girls", 58 }, { "Boy", "Boys", 56 }, { "Done", "Most done", 92 } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, Size = UDim2.fromOffset(spec[3], 26), BackgroundColor3 = CREAM, BackgroundTransparency = if i == 1 then 0 else 0.9, FontFace = BODY, TextSize = 14, TextColor3 = if i == 1 then INK else CREAM, Text = spec[2], AutoButtonColor = false }, filters)
		corner(b, 10)
		stroke(b, 2, if i == 1 then INK else CREAM, if i == 1 then 0 else 0.75)
		pad(b, 8, 8, 5, 5)
	end

	local scroll = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 266),
		Size = UDim2.fromOffset(276, 304),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = CREAM,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, side)
	list(scroll, false, 7)
	pad(scroll, 0, 10, 2, 8)
	text(scroll, "Empty", { Size = UDim2.fromOffset(260, 40), TextColor3 = CREAM, TextTransparency = DIM, FontFace = BODY_BOLD, TextSize = 14, Text = "No groups match that", TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 9999, Visible = false })

	-- a group row (cloned per group; the picked one is yellow with a shadow)
	local row = new("Frame", { Name = "Template", Size = UDim2.fromOffset(258, 52), BackgroundTransparency = 1, Visible = false }, scroll)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, Visible = false }, row)
	corner(shadow, 12)
	local b = new("TextButton", { Name = "Button", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = CREAM, BackgroundTransparency = 0.95, Text = "", AutoButtonColor = false }, row)
	corner(b, 12)
	stroke(b, 2, CREAM, 0.9)
	local icon = new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = PINK, ScaleType = Enum.ScaleType.Crop, Image = "" }, b)
	corner(icon, 8)
	stroke(icon, 2)
	text(icon, "Initial", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 16, Text = "B", TextXAlignment = Enum.TextXAlignment.Center })
	text(b, "Label", { Position = UDim2.fromOffset(54, 7), Size = UDim2.fromOffset(150, 20), TextSize = 15, TextColor3 = CREAM, Text = "BLACKPINK · 3 albums", RichText = true, TextTruncate = Enum.TextTruncate.AtEnd })
	text(b, "Count", { Position = UDim2.fromOffset(160, 7), Size = UDim2.fromOffset(86, 20), TextSize = 13, TextColor3 = CREAM, TextTransparency = 0.25, Text = "14/84", TextXAlignment = Enum.TextXAlignment.Right })
	bar(b, 54, 32, 190, 5, CREAM, 0.88, MINT)
end

-- [[ Binder: the page ]]

local function page(root: Frame)
	local holder = new("Frame", { Name = "Binder", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1 }, root)
	groups(holder)

	local shadow = new("Frame", { Name = "PageShadow", Position = UDim2.fromOffset(PAGE_X + 8, PAGE_Y + 8), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = INK }, holder)
	corner(shadow, 22)
	local p = new("Frame", { Name = "Page", Position = UDim2.fromOffset(PAGE_X, PAGE_Y), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = CREAM }, holder)
	corner(p, 22)
	stroke(p, 4)

	-- the album header: a band in the album's colour fading to cream (top corners rounded only)
	local head = new("Frame", { Name = "Head", Size = UDim2.fromOffset(PAGE_W, 118), BackgroundColor3 = WHITE }, p)
	corner(head, 20)
	new("UIGradient", { Name = "Tint", Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, PINK), ColorSequenceKeypoint.new(0.6, C("FFD2E5")), ColorSequenceKeypoint.new(1, CREAM) }) }, head)
	local square = new("Frame", { Name = "Square", Position = UDim2.fromOffset(0, 60), Size = UDim2.fromOffset(PAGE_W, 58), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, head)
	new("UIGradient", { Name = "Tint", Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, PINK), ColorSequenceKeypoint.new(0.6, C("FFD2E5")), ColorSequenceKeypoint.new(1, CREAM) }) }, square)
	new("Frame", { Name = "Line", Position = UDim2.fromOffset(0, 116), Size = UDim2.fromOffset(PAGE_W, 4), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 2 }, head)

	local iconShadow = new("Frame", { Name = "IconShadow", Position = UDim2.fromOffset(25, 17), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = INK, ZIndex = 2 }, head)
	corner(iconShadow, 10)
	local icon = new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(22, 14), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = PINK, ScaleType = Enum.ScaleType.Crop, Image = "", ZIndex = 2 }, head)
	corner(icon, 10)
	stroke(icon, 3)
	text(icon, "Initial", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 22, Text = "B", TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	text(head, "Meta", { Position = UDim2.fromOffset(86, 14), Size = UDim2.fromOffset(420, 16), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Text = "BLACKPINK · 2018 · 3RD GEN · ALBUM 1 OF 3", ZIndex = 2 })
	local name = text(head, "AlbumName", { Position = UDim2.fromOffset(86, 32), Size = UDim2.fromOffset(420, 30), FontFace = HEAD, TextSize = 24, TextScaled = true, Text = "BLACKPINK IN YOUR AREA", ZIndex = 2 })

	-- the group's cards ladder (Modules/Library/Ladders, board 48): the photocard, "GOLD → PLATINUM"
	-- and what the next rung needs
	local badge = new("Frame", { Name = "Badge", Position = UDim2.fromOffset(518, 12), Size = UDim2.fromOffset(230, 52), BackgroundTransparency = 1, ZIndex = 2 }, head)
	new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = Ladders.ICONS.Cards, ScaleType = Enum.ScaleType.Fit, ZIndex = 2 }, badge)
	text(badge, "Rung", { Position = UDim2.fromOffset(28, 0), Size = UDim2.fromOffset(202, 26), FontFace = HEAD, TextSize = 17, RichText = true, Text = "GOLD <font transparency=\"0.5\" size=\"13\">→ PLATINUM</font>", ZIndex = 2 })
	local nextChip = chip(badge, "Next", "Lucky Draw+ · 2/4 members", Ladders.COLOURS.Platinum, 11, { Position = UDim2.fromOffset(0, 29), ZIndex = 2 })
	nextChip.TextTruncate = Enum.TextTruncate.AtEnd
	new("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 14 }, name)

	-- progress + coins an hour (design: left 1014 → 684 in the page)
	local progress = new("Frame", { Name = "Progress", Position = UDim2.fromOffset(684, 70), Size = UDim2.fromOffset(200, 34), BackgroundTransparency = 1, ZIndex = 2 }, head)
	text(progress, "Count", { Size = UDim2.fromOffset(110, 16), TextSize = 13, Text = "11 / 28 cards", ZIndex = 2 })
	local rate = new("Frame", { Name = "Rate", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(200, 0), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 2 }, progress)
	list(rate, true, 4)
	new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1, ZIndex = 2 }, rate)
	text(rate, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), TextSize = 13, Text = "24 an hour", LayoutOrder = 2, ZIndex = 2 })
	local b = bar(progress, 0, 22, 200, 10, CREAM, 0.2, INK, true)
	b.ZIndex = 2
	b.Fill.ZIndex = 2

	button(head, "OpenPack", 818, 32, 128, 38, CREAM, "OPEN PACK", 14, nil, 4)
	head.OpenPack.ZIndex = 3
	head.OpenPackShadow.ZIndex = 2

	-- one tab per album
	local tabs = new("ScrollingFrame", {
		Name = "Albums",
		Position = UDim2.fromOffset(22, 76),
		Size = UDim2.fromOffset(640, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ZIndex = 2,
	}, head)
	list(tabs, true, 6)
	pad(tabs, 2, 2, 0, 0)
	local tab = new("TextButton", { Name = "Template", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundColor3 = CREAM, BackgroundTransparency = 0.25, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 2 }, tabs)
	corner(tab, 9)
	stroke(tab, 2)
	pad(tab, 10, 8)
	list(tab, true, 6)
	text(tab, "Label", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), TextSize = 13, Text = "THE ALBUM", LayoutOrder = 1, ZIndex = 2 })
	text(tab, "Year", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), TextSize = 13, TextTransparency = 0.4, Text = "2020", LayoutOrder = 2, ZIndex = 2 })
	local count = text(tab, "Count", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), BackgroundTransparency = 0, BackgroundColor3 = MINT, TextSize = 12, Text = "3/28", LayoutOrder = 3, ZIndex = 2 })
	corner(count, 6)
	pad(count, 5)

	-- the rarity columns (design: left 480 → 150 in the page, 104 apart)
	local cols = new("Frame", { Name = "Columns", Position = UDim2.fromOffset(SLOT_X - 22, 126), Size = UDim2.fromOffset(SLOT_STEP * #COLUMNS, 18), BackgroundTransparency = 1 }, p)
	for i, spec in COLUMNS do
		local col = new("Frame", { Name = "Col" .. i, Position = UDim2.fromOffset((i - 1) * SLOT_STEP, 0), Size = UDim2.fromOffset(SLOT_STEP, 18), BackgroundTransparency = 1 }, cols)
		list(col, true, 5, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
		local dot = new("Frame", { Name = "Dot", Size = UDim2.fromOffset(11, 11), BackgroundColor3 = spec[2] or WHITE, LayoutOrder = 1 }, col)
		corner(dot, 6)
		stroke(dot, 2)
		if not spec[2] then
			new("UIGradient", { Color = RAINBOW, Rotation = 45 }, dot)
		end
		text(col, "Label", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), TextSize = 13, Text = spec[1], LayoutOrder = 2 })
	end

	-- the members: one row each, a slot per rarity
	local rows = new("ScrollingFrame", {
		Name = "Rows",
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.fromOffset(PAGE_W, PAGE_H - 144),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, p)
	list(rows, false, 0)
	pad(rows, 0, 0, 10, 6) -- room for the first row's ×n badges

	local row = new("Frame", { Name = "Template", Size = UDim2.fromOffset(PAGE_W - 10, ROW_H), BackgroundTransparency = 1, Visible = false }, rows)
	local nameRow = text(row, "Member", { Position = UDim2.fromOffset(22, 28), Size = UDim2.fromOffset(140, 20), FontFace = HEAD, TextSize = 17, Text = "JENNIE", RichText = true, TextTruncate = Enum.TextTruncate.AtEnd })
	new("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 11 }, nameRow)
	text(row, "Count", { Position = UDim2.fromOffset(22, 50), Size = UDim2.fromOffset(140, 14), TextSize = 13, TextColor3 = MUTED, Text = "5 / 7 cards" })
	chip(row, "Bias", "BIAS · 2× PULLS", PINK, 10, { Position = UDim2.fromOffset(22, 68), Visible = false })
	new("Frame", { Name = "Divider", Position = UDim2.new(0, 20, 1, -2), Size = UDim2.new(1, -30, 0, 2), BackgroundColor3 = INK, BackgroundTransparency = 0.88, BorderSizePixel = 0 }, row)
	for i = 1, #COLUMNS do
		local slot = new("TextButton", { Name = "Slot" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(SLOT_X + (i - 1) * SLOT_STEP + 30, 6 + 44), Size = UDim2.fromOffset(60, 88), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, row)
		-- not owned yet
		local empty = new("Frame", { Name = "Empty", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.95 }, slot)
		corner(empty, 10)
		stroke(empty, 2.5, INK, 0.72)
		text(empty, "Mark", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 18, TextColor3 = INK, TextTransparency = 0.75, Text = "?", TextXAlignment = Enum.TextXAlignment.Center })
		if i == #COLUMNS then
			-- the One of One: a rainbow frame with its owner's name
			empty.Visible = false
			local unique = new("Frame", { Name = "Unique", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.15 }, slot)
			corner(unique, 10)
			new("UIGradient", { Color = RAINBOW, Rotation = 45 }, unique)
			local inner = new("Frame", { Name = "Inner", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = CREAM }, unique)
			corner(inner, 8)
			text(inner, "Label", { Position = UDim2.fromOffset(3, 0), Size = UDim2.new(1, -6, 1, 0), TextSize = 10, TextColor3 = INK, TextTransparency = 0.25, Text = "Owned by\n<b>minji_luv</b>", RichText = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
		end
		slotCard(slot)
	end
end

-- [[ All cards ]]

local function allCards(root: Frame)
	local holder = new("Frame", { Name = "All", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, root)
	local shadow = new("Frame", { Name = "PageShadow", Position = UDim2.fromOffset(PAGE_X + 8, PAGE_Y + 8), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = INK }, holder)
	corner(shadow, 22)
	local p = new("Frame", { Name = "Page", Position = UDim2.fromOffset(PAGE_X, PAGE_Y), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = CREAM }, holder)
	corner(p, 22)
	stroke(p, 4)

	local sorts = new("Frame", { Name = "Sorts", Position = UDim2.fromOffset(22, 18), Size = UDim2.fromOffset(700, 28), BackgroundTransparency = 1 }, p)
	list(sorts, true, 6)
	for i, spec in { { "Best", "Best first" }, { "Group", "Group A–Z" }, { "Dupes", "Duplicates" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundColor3 = if i == 1 then INK else CREAM, FontFace = BODY, TextSize = 14, TextColor3 = if i == 1 then CREAM else INK, Text = spec[2], AutoButtonColor = false }, sorts)
		corner(b, 10)
		stroke(b, 2)
		pad(b, 13)
	end
	text(p, "Summary", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(PAGE_W - 22, 18), Size = UDim2.fromOffset(360, 26), TextSize = 14, TextColor3 = MUTED, Text = "86 cards · 12 duplicates", TextXAlignment = Enum.TextXAlignment.Right })

	local grid = new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.fromOffset(PAGE_W - 24, PAGE_H - 64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, p)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(104, 162), CellPadding = UDim2.fromOffset(10, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	pad(grid, 12, 12, 12, 12)

	local tile = new("TextButton", { Name = "Template", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false }, grid)
	local face = cardFace(tile, "Face")
	new("UIScale", { Scale = 0.38 }, face)
	face.Position = UDim2.fromOffset(2, 8)
	chip(tile, "Copies", "×2", CREAM, 11, { Position = UDim2.fromOffset(-2, 0), ZIndex = 3, Visible = false })

	local empty = text(p, "Empty", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(PAGE_W / 2, 290), Size = UDim2.fromOffset(600, 60), FontFace = HEAD, TextSize = 20, TextColor3 = MUTED, Text = "No cards yet. Open a pack to start your binder!", TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Visible = false })
	empty.ZIndex = 2
end

-- [[ Songs tab (design board "46 · Binder · Songs tab") ]]

local STAR = "rbxassetid://139700917749751" -- white star, ink outline (CardDecor's)

-- three stars in a row: Star1..3 (the controller tints the earned ones yellow)
local function stars(parent: Instance, name: string, size: number, props: { [string]: any }?): Frame
	local base = { Name = name, Size = UDim2.fromOffset(size * 3 + 4, size), BackgroundTransparency = 1 }
	for k, v in props or {} do
		base[k] = v
	end
	local f = new("Frame", base, parent)
	list(f, true, 2)
	for i = 1, 3 do
		new("ImageLabel", { Name = "Star" .. i, LayoutOrder = i, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = STAR, ImageColor3 = YELLOW, ScaleType = Enum.ScaleType.Fit }, f)
	end
	return f
end

-- a small pill button (USE / PLAYING / STOP)
local function pill(parent: Instance, name: string, label: string, colour: Color3, props: { [string]: any }?): TextButton
	local base = { Name = name, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundColor3 = colour, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = label, AutoButtonColor = false }
	for k, v in props or {} do
		base[k] = v
	end
	local b = new("TextButton", base, parent)
	corner(b, 12)
	stroke(b, 2)
	pad(b, 10)
	return b
end

local NOTE_ICON = "rbxassetid://139417424771393" -- (the old Index's note)

-- a song row (cloned per song): a note square in the group's colour, name, a MASTERED tag, "right · fastest" line, stars and the
-- lobby music pills (USE on a mastered song; PLAYING + STOP on the one in use)
local function songRow(parent: Instance)
	local row = new("Frame", { Name = "Template", Size = UDim2.fromOffset(430, 48), BackgroundTransparency = 1, Visible = false }, parent)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -3, 1, -3), BackgroundColor3 = INK }, row)
	corner(shadow, 12)
	local card = new("Frame", { Name = "Card", Size = UDim2.new(1, -3, 1, -3), BackgroundColor3 = WHITE }, row)
	corner(card, 12)
	stroke(card, 3)
	local note = new("Frame", { Name = "Note", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = C("9ED8F5") }, card)
	corner(note, 8)
	stroke(note, 2)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = NOTE_ICON, ImageColor3 = INK, ScaleType = Enum.ScaleType.Fit }, note)
	local info = new("Frame", { Name = "Info", Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -58, 1, 0), BackgroundTransparency = 1 }, card)
	local top = new("Frame", { Name = "Top", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, -170, 0, 20), BackgroundTransparency = 1 }, info)
	list(top, true, 6)
	text(top, "Name", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextSize = 15, Text = "Supernova", LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd })
	chip(top, "Mastered", "MASTERED", YELLOW, 10, { LayoutOrder = 2, Visible = false })
	text(info, "Sub", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -170, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "14 / 15 right · fastest 0.1s", TextTruncate = Enum.TextTruncate.AtEnd })
	local right = new("Frame", { Name = "Right", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(170, 30), BackgroundTransparency = 1 }, info)
	list(right, true, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Right })
	pill(right, "Stop", "STOP", WHITE, { LayoutOrder = 1, Visible = false })
	pill(right, "Music", "USE", WHITE, { LayoutOrder = 2, Visible = false })
	stars(right, "Stars", 16, { LayoutOrder = 3 })
	return row
end

local function songList(parent: Instance, y: number): ScrollingFrame
	local scroll = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.fromOffset(PAGE_W - 24, PAGE_H - y - 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.7,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, parent)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(426, 48), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	pad(scroll, 10, 10, 6, 10)
	songRow(scroll)
	return scroll
end

local function songs(root: Frame)
	local holder = new("Frame", { Name = "Songs", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, root)

	-- one group's songs
	local shadow = new("Frame", { Name = "GroupShadow", Position = UDim2.fromOffset(PAGE_X + 8, PAGE_Y + 8), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = INK }, holder)
	corner(shadow, 22)
	local p = new("Frame", { Name = "Group", Position = UDim2.fromOffset(PAGE_X, PAGE_Y), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = CREAM }, holder)
	corner(p, 22)
	stroke(p, 4)
	local head = new("Frame", { Name = "Head", Size = UDim2.fromOffset(PAGE_W, 128), BackgroundColor3 = WHITE }, p)
	corner(head, 20)
	local tint = ColorSequence.new({ ColorSequenceKeypoint.new(0, C("9ED8F5")), ColorSequenceKeypoint.new(0.6, C("DCD3FF")), ColorSequenceKeypoint.new(1, CREAM) })
	new("UIGradient", { Name = "Tint", Color = tint, Rotation = 20 }, head)
	local square = new("Frame", { Name = "Square", Position = UDim2.fromOffset(0, 64), Size = UDim2.fromOffset(PAGE_W, 64), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, head)
	new("UIGradient", { Name = "Tint", Color = tint, Rotation = 20 }, square)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 128), Size = UDim2.fromOffset(PAGE_W, 4), BackgroundColor3 = INK, BorderSizePixel = 0 }, p)
	local icon = new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(22, 14), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = PINK, ScaleType = Enum.ScaleType.Crop, Image = "" }, head)
	corner(icon, 10)
	stroke(icon, 3)
	text(icon, "Initial", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 22, Text = "A", TextXAlignment = Enum.TextXAlignment.Center })
	text(head, "Kicker", { Position = UDim2.fromOffset(88, 16), Size = UDim2.fromOffset(480, 16), TextSize = 13, Text = "AESPA · 4TH GEN · 14 SONGS" })
	-- the songs ladder (Modules/Library/Ladders, board 48): the vinyl, "SILVER → GOLD"
	new("ImageLabel", { Name = "LadderIcon", Position = UDim2.fromOffset(88, 36), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Image = Ladders.ICONS.Songs, ScaleType = Enum.ScaleType.Fit }, head)
	text(head, "Percent", { Position = UDim2.fromOffset(120, 32), Size = UDim2.fromOffset(450, 34), FontFace = HEAD, TextSize = 26, RichText = true, Text = "SILVER <font transparency=\"0.5\" size=\"18\">→ GOLD</font>" })
	button(head, "Practise", PAGE_W - 22 - 100, 38, 200, 40, YELLOW, "PRACTISE AESPA", 13, nil, 4)

	-- the rungs: a node each (Bronze at the left end, Diamond at the right), a chip under each
	local track = new("Frame", { Name = "Milestones", Position = UDim2.fromOffset(34, 84), Size = UDim2.fromOffset(PAGE_W - 68, 12), BackgroundColor3 = CREAM }, head)
	corner(track, 6)
	stroke(track, 2)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.25, 1), BackgroundColor3 = INK, BorderSizePixel = 0 }, track)
	corner(fill, 6)
	for i, rung in Ladders.RUNGS do
		local share = (i - 1) / (#Ladders.RUNGS - 1)
		local node = new("Frame", { Name = "R" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(share, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Ladders.COLOURS[rung], ZIndex = 3 }, track)
		corner(node, 11)
		stroke(node, 3)
		local anchorX = if i == 1 then 0 elseif i == #Ladders.RUNGS then 1 else 0.5
		local c = chip(track, "C" .. i, `{string.upper(rung)} · 0`, CREAM, 11, {
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(share, if i == 1 then -12 elseif i == #Ladders.RUNGS then 12 else 0, 1, 8),
			ZIndex = 3,
			LayoutOrder = i,
		})
		new("UIGradient", { Name = "Sheen", Enabled = false, Rotation = 20, Color = Ladders.DIAMOND_SHEEN }, c)
	end

	-- the star key
	local legend = new("Frame", { Name = "Legend", Position = UDim2.fromOffset(22, 142), Size = UDim2.fromOffset(PAGE_W - 44, 22), BackgroundTransparency = 1 }, p)
	list(legend, true, 8)
	for i, spec in { { 1, "guessed it" }, { 2, "at 2 s or less" }, { 3, "at 0.5 s, three times" } } do
		local s3 = stars(legend, "Key" .. i, 13, { LayoutOrder = i * 2 - 1 })
		for k = spec[1] + 1, 3 do
			s3["Star" .. k].ImageColor3 = CREAM
			s3["Star" .. k].ImageTransparency = 0.5
		end
		text(legend, "KeyText" .. i, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), TextSize = 13, Text = spec[2] .. "   ", LayoutOrder = i * 2 })
	end
	text(p, "Hint", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(PAGE_W - 22, 142), Size = UDim2.fromOffset(340, 22), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Next: every song ★★ · 2 to go", TextXAlignment = Enum.TextXAlignment.Right })
	songList(p, 172)

	-- every song
	local allShadow = new("Frame", { Name = "AllShadow", Position = UDim2.fromOffset(PAGE_X + 8, PAGE_Y + 8), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = INK, Visible = false }, holder)
	corner(allShadow, 22)
	local a = new("Frame", { Name = "AllSongs", Position = UDim2.fromOffset(PAGE_X, PAGE_Y), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundColor3 = CREAM, Visible = false }, holder)
	corner(a, 22)
	stroke(a, 4)
	local sorts = new("Frame", { Name = "Sorts", Position = UDim2.fromOffset(22, 18), Size = UDim2.fromOffset(520, 28), BackgroundTransparency = 1 }, a)
	list(sorts, true, 6)
	for i, spec in { { "Stars", "Most stars" }, { "Near", "Nearly mastered" }, { "Name", "A–Z" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundColor3 = if i == 1 then INK else CREAM, FontFace = BODY, TextSize = 14, TextColor3 = if i == 1 then CREAM else INK, Text = spec[2], AutoButtonColor = false }, sorts)
		corner(b, 10)
		stroke(b, 2)
		pad(b, 13)
	end
	text(a, "Summary", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(PAGE_W - 22, 18), Size = UDim2.fromOffset(360, 26), TextSize = 14, TextColor3 = MUTED, Text = "412 songs · 96 mastered", TextXAlignment = Enum.TextXAlignment.Right })
	songList(a, 56)
end

-- [[ Card detail (design board "29 · Card detail (tap any card)") ]]

-- a small card for the member's strip, 50×73 (Build's slotCard look, smaller)
local function stripCard(parent: Instance, i: number, label: string)
	local item = new("TextButton", { Name = "Item" .. i, LayoutOrder = i, Size = UDim2.fromOffset(72, 96), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, parent)
	local holder = new("Frame", { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(36, 0), Size = UDim2.fromOffset(60, 88), BackgroundTransparency = 1 }, item)
	new("UIScale", { Scale = 50 / 60 }, holder)
	-- the picked card: a yellow ring
	local ring = new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 14, 1, 14), BackgroundTransparency = 1, Visible = false }, holder)
	corner(ring, 12)
	stroke(ring, 3.5, YELLOW)
	local empty = new("Frame", { Name = "Empty", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.95 }, holder)
	corner(empty, 10)
	stroke(empty, 2.5, INK, 0.72)
	text(empty, "Mark", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 18, TextColor3 = INK, TextTransparency = 0.75, Text = "?", TextXAlignment = Enum.TextXAlignment.Center })
	if i == #COLUMNS then
		local unique = new("Frame", { Name = "Unique", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.15, Visible = false }, holder)
		corner(unique, 10)
		new("UIGradient", { Color = RAINBOW, Rotation = 45 }, unique)
		local inner = new("Frame", { Name = "Inner", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = CREAM }, unique)
		corner(inner, 8)
		local label = text(inner, "Label", { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -4, 1, 0), TextSize = 9, TextColor3 = INK, TextTransparency = 0.25, Text = "Unclaimed", RichText = true, TextXAlignment = Enum.TextXAlignment.Center })
		label.TextWrapped = false -- (no wrapping: "Owned by\n…" breaks on its own)
		label:SetAttribute("FitTextSkip", true) -- (FitText would turn wrapping back on)
	end
	slotCard(holder)
	text(item, "Label", { Position = UDim2.fromOffset(0, 80), Size = UDim2.fromOffset(72, 14), TextSize = 12, TextTransparency = 0.3, Text = label, TextXAlignment = Enum.TextXAlignment.Center })
end

-- a row of the detail's facts: Title on the left, Value (a horizontal list) on the right
local function factRow(parent: Instance, name: string, order: number, title: string): Frame
	local row = new("Frame", { Name = name, LayoutOrder = order, Size = UDim2.fromOffset(370, 40), BackgroundTransparency = 1 }, parent)
	new("Frame", { Name = "Divider", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = INK, BackgroundTransparency = 0.92, BorderSizePixel = 0 }, row)
	text(row, "Title", { Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(140, 38), FontFace = BODY_BOLD, TextSize = 15, TextColor3 = MUTED, Text = title })
	local value = new("Frame", { Name = "Value", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, row)
	list(value, true, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Right })
	return row
end

-- a fixed-height note (TextScaled by FitText): an auto-height one wrapped onto more lines on
-- phones, where text draws bigger, and pushed the column down over the strip of cards
local function note(parent: Instance, name: string, order: number, body: string, height: number): TextLabel
	return text(parent, name, { LayoutOrder = order, Size = UDim2.fromOffset(370, height), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = body, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
end

local function detail(root: Frame)
	-- (ZIndex 50: above the header's COLLECT and close, which sit at 2)
	local holder = new("Frame", { Name = "Detail", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 50 }, root)
	local scrim = new("TextButton", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false }, holder)
	scrim:SetAttribute("NoButtonScale", true)

	-- the panel (design: 780×640, the strip pulled up under the facts: 780×600), centred on screen and drawn a little smaller
	local window = new("Frame", { Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(644, 364), Size = UDim2.fromOffset(789, 609), BackgroundTransparency = 1 }, holder)
	new("UIScale", { Scale = 0.88 }, window)
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(780, 600), BackgroundColor3 = INK }, window)
	corner(shadow, 24)
	local panel = new("Frame", { Name = "Panel", Size = UDim2.fromOffset(780, 600), BackgroundColor3 = CREAM, Active = true }, window)
	corner(panel, 24)
	stroke(panel, 4)
	button(panel, "Close", 753, 33, 36, 36, RED, "X", 15, nil, 0)

	-- the card, big (cardFace is 260×380; 250 wide here)
	local face = cardFace(panel, "Face")
	face.Position = UDim2.fromOffset(40, 36)
	new("UIScale", { Scale = 250 / 260 }, face)
	chip(panel, "Copies", "×3", CREAM, 12, { Position = UDim2.fromOffset(33, 26), ZIndex = 3, Visible = false })

	-- the facts (one column, rows collapse when hidden)
	local col = new("Frame", { Name = "Info", Position = UDim2.fromOffset(362, 34), Size = UDim2.fromOffset(370, 440), BackgroundTransparency = 1 }, panel)
	list(col, false, 0)
	local chips = new("Frame", { Name = "Chips", LayoutOrder = 1, Size = UDim2.fromOffset(370, 22), BackgroundTransparency = 1 }, col)
	list(chips, true, 6)
	local rarity = chip(chips, "Rarity", "FANSIGN BENEFIT", PINK, 12, { LayoutOrder = 1 })
	new("UIGradient", { Name = "Foil", Enabled = false, Rotation = 45 }, rarity)
	chip(chips, "Numbered", "NUMBERED", INK, 12, { LayoutOrder = 2, TextColor3 = YELLOW })
	local name = text(col, "Member", { LayoutOrder = 2, Size = UDim2.fromOffset(370, 44), FontFace = HEAD, TextSize = 34, Text = "JENNIE", RichText = true, TextScaled = true })
	new("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 18 }, name)
	text(col, "Album", { LayoutOrder = 3, Size = UDim2.fromOffset(370, 18), TextSize = 14, TextColor3 = MUTED, Text = "BLACKPINK · BLACKPINK IN YOUR AREA · 2018", TextTruncate = Enum.TextTruncate.AtEnd })
	new("Frame", { Name = "Gap1", LayoutOrder = 4, Size = UDim2.fromOffset(370, 12), BackgroundTransparency = 1 }, col)

	-- Your serials: a chip each (the controller clones Serial)
	local serials = factRow(col, "Serials", 5, "Your serials")
	local serial = chip(serials.Value, "Template", "#4", CREAM, 14, { FontFace = HEAD, Visible = false })
	serial.Size = UDim2.fromOffset(0, 24)

	-- Copies: "3 of 5" + level, then the level bar
	local copies = factRow(col, "Copies", 6, "Copies")
	text(copies.Value, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextSize = 15, Text = "3 of 5", LayoutOrder = 1 })
	local level = chip(copies.Value, "Level", "GOLD", C("F2C94C"), 12, { LayoutOrder = 2 })
	new("UIGradient", { Name = "Rainbow", Enabled = false, Color = RAINBOW }, level)
	local track = new("Frame", { Name = "Levels", LayoutOrder = 7, Size = UDim2.fromOffset(370, 32), BackgroundTransparency = 1 }, col)
	bar(track, 0, 0, 370, 9, INK, 0.9, C("F2C94C"))
	text(track, "Normal", { Position = UDim2.fromOffset(0, 13), Size = UDim2.fromOffset(120, 15), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Normal" })
	text(track, "Gold", { Position = UDim2.fromOffset(125, 13), Size = UDim2.fromOffset(120, 15), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Gold · 3", TextXAlignment = Enum.TextXAlignment.Center })
	text(track, "Rainbow", { Position = UDim2.fromOffset(190, 13), Size = UDim2.fromOffset(180, 15), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Rainbow · 5 (2 more)", TextXAlignment = Enum.TextXAlignment.Right })

	-- Earns
	local earns = factRow(col, "Earns", 8, "Earns")
	new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, earns.Value)
	text(earns.Value, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextSize = 15, Text = "18 an hour", LayoutOrder = 2 })
	text(earns.Value, "Why", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "(15 × Gold 2)", LayoutOrder = 3 })

	-- Rolled: the day you first rolled it; a numbered copy also says who rolled it and its owners
	local rolled = factRow(col, "Rolled", 9, "Rolled")
	text(rolled.Value, "Date", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextSize = 15, Text = "25 Nov 2026", LayoutOrder = 1 })
	note(col, "Owners", 10, "Rolled by you · no other owners yet", 17)

	-- Grade (not in the game yet: shown, greyed out)
	local grade = factRow(col, "Grade", 11, "Grade")
	text(grade.Value, "State", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Not graded", LayoutOrder = 1 })
	local gradeWrap = new("Frame", { Name = "ButtonWrap", LayoutOrder = 2, Size = UDim2.fromOffset(140, 38), BackgroundTransparency = 1 }, grade.Value)
	local gb = button(gradeWrap, "Button", 68, 18, 128, 30, C("E9E2CF"), "GRADE", 12, nil, 3)
	text(gb, "Soon", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 12, TextColor3 = INK, TextTransparency = 0.45, Text = "GRADE · SOON", TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 })
	gb.Text = ""

	-- Sell + Show on profile
	new("Frame", { Name = "Gap2", LayoutOrder = 12, Size = UDim2.fromOffset(370, 6), BackgroundTransparency = 1 }, col)
	local actions = new("Frame", { Name = "Actions", LayoutOrder = 13, Size = UDim2.fromOffset(370, 54), BackgroundTransparency = 1 }, col) -- (room for the shadows before the note)
	button(actions, "Sell", 74, 26, 140, 44, WHITE, "SELL 1", 14, COIN, 4)
	button(actions, "Pin", 260, 26, 196, 44, YELLOW, "PIN", 14, nil, 4) -- PIN / UNPIN / PIN · 3/3 FULL (opens the swap sheet)
	note(col, "SellNote", 14, "Selling gives up #233, your highest number. You keep #4.", 30)
	new("Frame", { Name = "Gap3", LayoutOrder = 15, Size = UDim2.fromOffset(370, 10), BackgroundTransparency = 1 }, col)
	-- (hidden for now: the Rolled history row took its room above the strip)
	local trade = text(col, "Trade", { LayoutOrder = 16, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), TextSize = 14, TextColor3 = MUTED, Text = "Trade · coming soon", Visible = false })
	corner(trade, 10)
	stroke(trade, 2, INK, 0.7)
	pad(trade, 12)

	-- the member's cards, one per rarity
	local strip = new("Frame", { Name = "Strip", Position = UDim2.fromOffset(40, 456), Size = UDim2.fromOffset(720, 140), BackgroundTransparency = 1 }, panel)
	text(strip, "Title", { Size = UDim2.fromOffset(720, 18), TextSize = 13, TextColor3 = MUTED, Text = "JENNIE'S 7 CARDS · TAP ONE" })
	local items = new("Frame", { Name = "Items", Position = UDim2.fromOffset(-11, 28), Size = UDim2.fromOffset(740, 100), BackgroundTransparency = 1 }, strip)
	list(items, true, 0, { VerticalAlignment = Enum.VerticalAlignment.Top })
	for i, spec in COLUMNS do
		stripCard(items, i, spec[1])
	end

	-- above everything on the binder
	for _, d in holder:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 1) + 25
		end
	end
	scrim.ZIndex = 21

	-- the swap sheet: PIN with every unlocked slot used asks which pin to swap out
	local sheet = new("Frame", { Name = "Swap", Position = UDim2.fromOffset(330, 360), Size = UDim2.fromOffset(418, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = WHITE, Visible = false }, panel)
	corner(sheet, 18)
	stroke(sheet, 4)
	pad(sheet, 14, 14, 12, 14)
	local nub = new("Frame", { Name = "Nub", Position = UDim2.fromOffset(212, -24), Size = UDim2.fromOffset(18, 18), Rotation = 45, BackgroundColor3 = WHITE, BorderSizePixel = 0 }, sheet)
	stroke(nub, 4)
	text(sheet, "Title", { Size = UDim2.fromOffset(240, 20), FontFace = HEAD, TextSize = 16, Text = "Your pins are full" })
	text(sheet, "Gain", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(160, 18), TextSize = 13, TextColor3 = MUTED, Text = "Rosé earns +175/hr", TextXAlignment = Enum.TextXAlignment.Right })
	text(sheet, "Sub", { Position = UDim2.fromOffset(0, 22), Size = UDim2.fromOffset(300, 16), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Swap one out:" })
	local items = new("Frame", { Name = "Items", Position = UDim2.fromOffset(0, 46), Size = UDim2.fromOffset(390, 124), BackgroundTransparency = 1 }, sheet)
	list(items, true, 8, { VerticalAlignment = Enum.VerticalAlignment.Top })
	for i = 1, 5 do
		local item = new("Frame", { Name = "Item" .. i, LayoutOrder = i, Size = UDim2.fromOffset(72, 124), BackgroundTransparency = 1 }, items)
		local slot = pinSlot(item, "Slot", 1, 46)
		slot.Position = UDim2.fromOffset(12, 0)
		text(item, "Member", { Position = UDim2.fromOffset(0, 72), Size = UDim2.fromOffset(72, 14), TextSize = 12, Text = "JENNIE", TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
		text(item, "Rate", { Position = UDim2.fromOffset(0, 86), Size = UDim2.fromOffset(72, 13), TextSize = 11, TextColor3 = MUTED, Text = "175/hr", TextXAlignment = Enum.TextXAlignment.Center })
		local b = new("TextButton", { Name = "Swap", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(36, 100), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = "Swap", AutoButtonColor = false }, item)
		corner(b, 8)
		stroke(b, 2)
		pad(b, 9)
	end
	-- (the sheet floats over the strip of cards below it)
	for _, d in sheet:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 1) + 40
		end
	end
	sheet.ZIndex = 40
end

-- [[ Entry points ]]

-- [[ Event sets (design boards "79e · Binder · Christmas Stage '26", "79f · … after it ends") ]]
-- An event's card set (Modules/Library/Albums "Event sets") is shown like a group: one page,
-- a tab per act. This adds what it needs to a built binder (safe to run again):
--   Groups.List: EventsHead / GroupsHead (the two section labels) and EventTemplate (an event's
--                row: the group row with an icy Tint and a Chip, LIVE or ENDED)
--   Page.Head.Event   the LIVE · 9d left / ENDED chip (where the ladder badge sits for a group)
--   Page.Ended        the dark "this event is over" ribbon under the header
--   every slot's Empty.Lock (the row template's): a card that can't be got any more
--   Build.EventBits(game.StarterGui.Interface.Frames.Binder)
local SNOWFLAKE = "rbxassetid://119208551988683" -- assets/ui/Events/Snowflake.png
function Build.EventBits(binder: Instance)
	local scroll = binder.Binder.Groups.List
	for _, n in { "EventsHead", "GroupsHead", "EventTemplate" } do
		local old = scroll:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	for i, spec in { { "EventsHead", "EVENTS", -1000 }, { "GroupsHead", "GROUPS", -1 } } do
		text(scroll, spec[1], { LayoutOrder = spec[3], Size = UDim2.fromOffset(258, 18), TextSize = 11, TextColor3 = CREAM, TextTransparency = 0.45, Text = spec[2], Visible = false })
	end
	local ev = scroll.Template:Clone()
	ev.Name = "EventTemplate"
	ev.Visible = false
	local b = ev.Button
	b.BackgroundColor3 = WHITE
	b.BackgroundTransparency = 0
	local s = b:FindFirstChildOfClass("UIStroke")
	s.Color, s.Transparency, s.Thickness = INK, 0, 3
	new("UIGradient", { Name = "Ice", Color = ColorSequence.new(C("CFEFFF"), C("FFE4EF")) }, b)
	b.Icon.Image = SNOWFLAKE
	b.Icon.BackgroundColor3 = WHITE
	b.Icon.ScaleType = Enum.ScaleType.Fit
	b.Icon.Initial.Visible = false
	b.Label.TextColor3 = INK
	b.Label.Text = "Christmas Stage '26"
	b.Count.Visible = false
	b.Bar.BackgroundColor3 = INK
	b.Bar.BackgroundTransparency = 0.85
	b.Bar.Fill.BackgroundColor3 = C("9ED8F5")
	local c = chip(b, "Chip", "LIVE", MINT, 10, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(246, 8) })
	c.Size = UDim2.fromOffset(0, 16)
	ev.Shadow.Visible = true
	ev.Parent = scroll

	local p = binder.Binder.Page
	local head = p.Head
	for _, n in { "Event" } do
		local old = head:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local evChip = chip(head, "Event", "LIVE · 9d left", MINT, 13, { Position = UDim2.fromOffset(518, 18), Visible = false, ZIndex = 3 })
	evChip.Size = UDim2.fromOffset(0, 24)
	local oldRibbon = p:FindFirstChild("Ended")
	if oldRibbon then
		oldRibbon:Destroy()
	end
	local ribbon = new("Frame", { Name = "Ended", Position = UDim2.fromOffset(0, 120), Size = UDim2.fromOffset(PAGE_W, 28), BackgroundColor3 = INK, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, p)
	text(ribbon, "Label", { Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(PAGE_W - 44, 28), TextSize = 13, TextColor3 = CREAM, Text = "This event is over: these cards don't drop any more. Everything you got is yours to keep, pin and sell.", ZIndex = 4 })

	-- a lock in every empty slot of the member row template (for a card that's gone)
	for _, slot in p.Rows.Template:GetChildren() do
		local empty = slot:IsA("TextButton") and slot:FindFirstChild("Empty")
		if empty then
			local old = empty:FindFirstChild("Lock")
			if old then
				old:Destroy()
			end
			local lock = new("Frame", { Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(18, 22), BackgroundTransparency = 1, Visible = false }, empty)
			local shackle = new("Frame", { Name = "Shackle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(12, 13), BackgroundTransparency = 1 }, lock)
			corner(shackle, 6)
			stroke(shackle, 2.5, MUTED)
			local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 9), Size = UDim2.fromOffset(18, 13), BackgroundColor3 = C("E9E2CF") }, lock)
			corner(body, 3)
			stroke(body, 2.5, MUTED)
			local old2 = empty:FindFirstChild("Gone")
			if old2 then
				old2:Destroy()
			end
			text(empty, "Gone", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.6, 0), Size = UDim2.fromOffset(56, 14), TextSize = 10, TextColor3 = MUTED, Text = "GONE", TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
		end
	end
end

function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Binder")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Binder", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 1 })
	backdrop(root)
	header(root)
	page(root)
	allCards(root)
	songs(root)
	detail(root)
	local toast = text(root, "Toast", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 14), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = CREAM, TextSize = 16, Text = "", Visible = false, ZIndex = 60 })
	corner(toast, 10)
	pad(toast, 16)
	stroke(toast, 2, CREAM, 0.6)
	root.Parent = frames
	return root
end

return Build
