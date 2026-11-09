--| Profile UI builder
-- Builds Interface.Frames.Profile from the "Profile 1 · your card" design board: lilac
-- header, your photocard (avatar, name, title chip, level badge), the XP bar and Change Title
-- on the left; six stat tiles (with a rank tag when you're on a board) and the 5-card
-- showcase on the right. Edit puts the showcase in edit mode (the rest dims under DimLeft /
-- DimStats): each slot shows SLOT n, a ✕ on a filled card (Unpin: not "Remove", which is an
-- Instance method) and an Add tile on an empty one; tapping a slot (Hit) picks its card in the
-- Index (IndexController).
-- Run once in Studio (an existing frame is kept as ServerStorage.Profile_Legacy):
--   require(<this module>).Build(game.StarterGui.Interface.Frames)
-- ProfileController finds everything by name. SongCard() is shared with the player card
-- (PlayerCardController/Build); Modules/UI/SongCard paints them.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local LILAC = C("B9A6FF")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local MINT = C("A7E9B8")
local MUTED = C("5C566B")
local BODYTEXT = C("4A4458")
local PAPER = C("F3EBDD")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Build = {}

Build.ICONS = {
	Close = "rbxassetid://118345756178429",
	Pencil = "rbxassetid://131794619630827", -- assets/ui/i_pencil.png
	User = "rbxassetid://135068275231868", -- assets/ui/i_user.png (the HUD's Profile tile)
}

Build.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
	ColorSequenceKeypoint.new(1, C("B5DDFF")),
})

-- the stat tiles, in grid order (ProfileController fills them by Name)
Build.STATS = {
	{ Name = "Wins", Label = "WINS", Colour = "A7E9B8" },
	{ Name = "BestStreak", Label = "BEST STREAK", Colour = "FFD2CE" },
	{ Name = "Perfect", Label = "PERFECT GAMES", Colour = "FFE07A" },
	{ Name = "Correct", Label = "CORRECT ANSWERS", Colour = "CDEBFA" },
	{ Name = "Songs", Label = "SONGS OWNED", Colour = "DCD3FF" },
	{ Name = "SoloBest", Label = "SOLO BEST", Colour = "FFFFFF" },
}

Build.SHOWCASE = 5

-- --------------------------------- Helpers -------------------------------- --

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end
Build.new = new

local function corner(p: Instance, r: number | UDim)
	new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r :: number) }, p)
end
Build.corner = corner

local function stroke(p: Instance, t: number, colour: Color3?)
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
Build.stroke = stroke

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
Build.text = text

-- face + hard shadow (<name>Shadow behind it)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end
Build.card = card

-- a chunky button with a hard shadow (<name>Shadow); centre-anchored for ButtonScale
local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string, textSize: number, drop: number?): TextButton
	local d = drop or 5
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + d, y + d), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, 14)
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + w / 2, y + h / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		AutoButtonColor = false,
		FontFace = HEAD,
		TextSize = textSize,
		TextColor3 = INK,
		Text = label,
	}, parent)
	corner(b, 14)
	stroke(b, 3)
	return b
end
Build.button = button

-- a TextLabel chip TitleChip.Paint() can style (UIStroke + "Rainbow" gradient)
function Build.TitleLabel(parent: Instance, name: string, pos: UDim2, size: UDim2, textSize: number, anchorX: number?): TextLabel
	local chip = new("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(anchorX or 0.5, 0),
		Position = pos,
		Size = size,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = LILAC,
		FontFace = BODY,
		TextSize = textSize,
		TextColor3 = INK,
		Text = "Fan",
	}, parent)
	corner(chip, 9)
	stroke(chip, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, chip)
	new("UIGradient", { Name = "Rainbow", Color = Build.RAINBOW, Rotation = 25, Enabled = false }, chip)
	return chip
end

-- The player's photocard art: a rainbow frame with their avatar (ProfileController /
-- PlayerCard set Avatar.Image).
function Build.Photo(parent: Instance, pos: UDim2, size: UDim2, line: number): Frame
	local photo = new("Frame", { Name = "Photo", Position = pos, Size = size, BackgroundColor3 = WHITE, ClipsDescendants = true }, parent)
	corner(photo, 12)
	stroke(photo, line)
	new("UIGradient", { Name = "Rainbow", Color = Build.RAINBOW, Rotation = 115 }, photo)
	new("ImageLabel", { Name = "Avatar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop }, photo)
	return photo
end

-- One song card (holder → Shadow + Face): Face has a "Level" gradient (Gold / Rainbow, via
-- TierShine), Art (GroupArt) with Initials, SongTitle, Artist and a Tag chip. Sizes scale
-- with the card. Modules/UI/SongCard.Paint() fills it.
function Build.SongCard(parent: Instance, name: string, pos: UDim2, w: number, h: number, rotation: number?): Frame
	local holder = new("Frame", { Name = name, Position = pos, Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, Rotation = rotation or 0 }, parent)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(shadow, 12)
	local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
	corner(face, 12)
	stroke(face, 3)
	new("UIGradient", { Name = "Level", Color = Build.RAINBOW, Rotation = 35, Enabled = false }, face)
	local pad = math.max(6, math.floor(w * 0.06))
	local small = h < 130
	local nameSize = if small then 11 else 13
	local artistSize = if small then 9 else 11
	local bottom = nameSize + artistSize + 10 + pad
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(pad, pad), Size = UDim2.new(1, -pad * 2, 1, -pad - bottom), BackgroundColor3 = C("D4E8FF"), ClipsDescendants = true }, face)
	corner(art, 8)
	stroke(art, 2)
	text(art, "Initials", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = if small then 18 else 26, TextXAlignment = Enum.TextXAlignment.Center, Text = "♪" })
	text(face, "SongTitle", { Position = UDim2.new(0, pad, 1, -bottom + 4), Size = UDim2.new(1, -pad * 2, 0, nameSize + 2), FontFace = HEAD, TextSize = nameSize, Text = "Song" })
	text(face, "Artist", { Position = UDim2.new(0, pad, 1, -artistSize - pad - 2), Size = UDim2.new(1, -pad * 2 - 44, 0, artistSize + 2), FontFace = BODY, TextSize = artistSize, Text = "Artist" })
	local tag = new("TextLabel", {
		Name = "Tag",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -pad + 2, 1, -pad + 1),
		Size = UDim2.fromOffset(0, artistSize + 5),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = LILAC,
		FontFace = BODY,
		TextSize = artistSize - 1,
		TextColor3 = INK,
		Text = "NORMAL",
	}, face)
	corner(tag, 5)
	stroke(tag, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, tag)
	new("UIGradient", { Name = "Rainbow", Color = Build.RAINBOW, Rotation = 0, Enabled = false }, tag)
	return holder
end

local function header(panel: Frame, w: number, title: string, colour: Color3)
	local h = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = colour, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(h, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(400, 64), FontFace = HEAD, TextSize = 26, Text = title })
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(w - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, h)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w - 14 - 21, 32), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, h)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = Build.ICONS.Close }, close)
	return h
end
Build.header = header

-- ---------------------------------- Parts ---------------------------------- --

local function leftColumn(content: Frame)
	local left = new("Frame", { Name = "Left", Size = UDim2.fromOffset(300, 517), BackgroundTransparency = 1 }, content)

	-- the photocard, tilted like the mockup
	local pc = new("Frame", { Name = "Photocard", Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(280, 334), BackgroundTransparency = 1, Rotation = -2 }, left)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(7, 7), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0 }, pc)
	corner(shadow, 20)
	local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, pc)
	corner(face, 20)
	stroke(face, 4)
	Build.Photo(face, UDim2.fromOffset(12, 12), UDim2.new(1, -24, 1, -24 - 82), 3)
	text(face, "PlayerName", { Position = UDim2.new(0, 12, 1, -84), Size = UDim2.new(1, -24, 0, 32), FontFace = HEAD, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Text = "Player" })
	Build.TitleLabel(face, "Title", UDim2.new(0.5, 0, 1, -46), UDim2.fromOffset(0, 30), 17)
	-- a sticker on the photo's corner (inside the card, clear of the Stats heading)
	local lv = new("Frame", { Name = "LevelBadge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(42, 42), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = YELLOW, Rotation = -8, ZIndex = 3 }, face)
	corner(lv, UDim.new(0.5, 0))
	stroke(lv, 4)
	text(lv, "Caption", { Position = UDim2.fromOffset(0, 11), Size = UDim2.new(1, 0, 0, 12), FontFace = BODY, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "LV", ZIndex = 3 })
	text(lv, "Level", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), FontFace = HEAD, TextSize = 23, TextXAlignment = Enum.TextXAlignment.Center, Text = "1", ZIndex = 3 })

	-- XP bar
	local xp = new("Frame", { Name = "XP", Position = UDim2.fromOffset(10, 360), Size = UDim2.fromOffset(280, 46), BackgroundTransparency = 1 }, left)
	text(xp, "Level", { Size = UDim2.fromOffset(120, 18), TextSize = 15, Text = "Level 1" })
	text(xp, "Amount", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(160, 18), TextSize = 15, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "0 / 0 XP" })
	local track = new("CanvasGroup", { Name = "Track", Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = WHITE }, xp)
	corner(track, 10)
	stroke(track, 3)
	new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, track)

	button(left, "ChangeTitle", 10, 424, 280, 56, YELLOW, "CHANGE TITLE", 18)
end

local function rightColumn(content: Frame)
	local right = new("Frame", { Name = "Right", Position = UDim2.fromOffset(326, 0), Size = UDim2.fromOffset(664, 517), BackgroundTransparency = 1 }, content)
	text(right, "StatsHeading", { Size = UDim2.fromOffset(100, 30), FontFace = HEAD, TextSize = 22, Text = "Stats" })
	text(right, "StatsSub", { Position = UDim2.fromOffset(92, 4), Size = UDim2.fromOffset(200, 26), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "all time" })

	local stats = new("Frame", { Name = "Stats", Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(664, 200), BackgroundTransparency = 1 }, right)
	local tw, th, gap = math.floor((664 - 2 * 14 - 4) / 3), 92, 14
	for i, spec in Build.STATS do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local tile = card(stats, spec.Name, UDim2.fromOffset(col * (tw + gap), row * (th + gap)), UDim2.fromOffset(tw, th), C(spec.Colour), 16, 4, 3)
		text(tile, "Label", { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 16), TextSize = 13, TextColor3 = BODYTEXT, Text = spec.Label })
		text(tile, "Value", { Position = UDim2.fromOffset(16, 28), Size = UDim2.new(1, -32, 0, 34), FontFace = HEAD, TextSize = 28, Text = "0" })
		text(tile, "Sub", { Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 0, 16), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = BODYTEXT, Text = "" })
		local rank = new("TextLabel", {
			Name = "Rank",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = INK,
			FontFace = BODY,
			TextSize = 13,
			TextColor3 = YELLOW,
			Text = "#1 this week",
			Visible = false,
			ZIndex = 3,
		}, tile)
		corner(rank, 8)
		new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, rank)
	end

	local y = 42 + 2 * th + gap + 18
	text(right, "ShowcaseHeading", { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(140, 36), FontFace = HEAD, TextSize = 22, Text = "Showcase" })
	text(right, "ShowcaseSub", { Position = UDim2.fromOffset(142, y + 4), Size = UDim2.fromOffset(260, 32), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "5 cards everyone sees" })
	local edit = button(right, "Edit", 664 - 104 - 4, y, 104, 36, WHITE, "", 14, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = Build.ICONS.Pencil }, edit)
	text(edit, "Label", { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -50, 1, 0), FontFace = HEAD, TextSize = 14, Text = "EDIT" })

	local showcase = new("Frame", { Name = "Showcase", Position = UDim2.fromOffset(0, y + 48), Size = UDim2.fromOffset(664, 172), BackgroundTransparency = 1 }, right)
	local cw, ch = 114, 164
	local cgap = math.floor((664 - 8 - Build.SHOWCASE * cw) / (Build.SHOWCASE - 1))
	local tilt = { -3, 2, -1, 3, -2 }
	for i = 1, Build.SHOWCASE do
		local holder = Build.SongCard(showcase, "Card" .. i, UDim2.fromOffset(4 + (i - 1) * (cw + cgap), 2), cw, ch, tilt[i])
		-- edit mode: an empty slot's Add tile, the ✕, the SLOT n chip and the tap area
		local add = new("Frame", { Name = "Add", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAPER, Visible = false }, holder)
		corner(add, 12)
		stroke(add, 3, C("8A8398"))
		local plus = new("TextLabel", { Name = "Plus", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -12), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, FontFace = HEAD, TextSize = 22, TextColor3 = MUTED, Text = "+" }, add)
		corner(plus, UDim.new(0.5, 0))
		stroke(plus, 3, C("8A8398"))
		text(add, "Label", { Position = UDim2.new(0, 0, 0.5, 14), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Add a card" })
		local slot = new("TextLabel", { Name = "Slot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = BODY, TextSize = 11, TextColor3 = YELLOW, Text = `SLOT {i}`, Visible = false, ZIndex = 4 }, holder)
		corner(slot, 7)
		new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, slot)
		local hit = new("TextButton", { Name = "Hit", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Visible = false, ZIndex = 5 }, holder)
		hit:SetAttribute("NoButtonScale", true) -- the card pops instead (ProfileController)
		local remove = new("ImageButton", { Name = "Unpin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = RED, Image = "", AutoButtonColor = false, Visible = false, ZIndex = 6 }, holder)
		corner(remove, UDim.new(0.5, 0))
		stroke(remove, 3)
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 1, Image = Build.ICONS.Close, ZIndex = 6 }, remove)
	end
	text(showcase, "Empty", { Size = UDim2.fromScale(1, 1), FontFace = BODY_BOLD, TextSize = 15, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Roll songs in the shop to fill your showcase", Visible = false })
end

-- ---------------------------------- Build ---------------------------------- --

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Profile")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("Profile_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "Profile_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "Profile", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, root)
	scrim.Active = true

	-- the standard full-size panel (same as Rewards): 1040 × 620
	local W, H = 1040, 620
	local panel = card(root, "Panel", UDim2.fromOffset(120, 50), UDim2.fromOffset(W, H), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true
	header(panel, W, "PROFILE", LILAC)

	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(22, 67 + 18), Size = UDim2.fromOffset(W - 44 - 6, H - 67 - 36), BackgroundTransparency = 1 }, panel)
	leftColumn(content)
	rightColumn(content)
	-- edit mode dims everything but the showcase (cream veils over the left column + stats)
	local stats = content.Right.Stats
	for name, area in {
		DimLeft = { UDim2.fromOffset(0, 0), UDim2.fromOffset(300, content.Size.Y.Offset) },
		DimStats = { UDim2.fromOffset(326, 0), UDim2.fromOffset(664 + 8, stats.Position.Y.Offset + stats.Size.Y.Offset) },
	} do
		new("Frame", { Name = name, Position = area[1], Size = area[2], BackgroundColor3 = CREAM, BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false, ZIndex = 8, Active = true }, content)
	end

	root.Parent = frames
	return root
end

return Build
