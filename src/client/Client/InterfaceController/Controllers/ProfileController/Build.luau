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

local Photocard = require(game:GetService("ReplicatedStorage").Modules.UI.Photocard)

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
	{ Name = "Season", Label = "SEASON", Colour = "FFFFFF" },
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

-- ------------------------- K-POPPED! full screen ------------------------- --
-- Design board "34 · Profile · full screen with a card showcase": the dark backdrop like the
-- binder and packs; your player card (avatar, name, title + bias chips, level badge), XP and
-- TITLE / STYLE on the left; on the right a cream panel with the photocard SHOWCASE (5 slots
-- on a shelf, Modules/UI/Photocard), five stat tiles and your SETS (completed albums; ALL-KILL
-- = every member at Gold). Edit mode (no tint) shows Slot / Hit / Unpin / Add per slot
-- but a slot's card is picked in the Picker sheet here (owned cards, best first).
--   require(<this module>).BuildFullScreen(game.StarterGui.Interface.Frames)

local CREAM_TEXT = CREAM
local PINK = C("FF9EC4")

local function scaledZ(root: Instance, add: number)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 1) + add
		end
	end
	if root:IsA("GuiObject") then
		root.ZIndex = math.max(root.ZIndex, 1) + add
	end
end

local function squareButton(parent: Instance, name: string, cx: number, cy: number, size: number, colour: Color3, icon: string?, label: string?): GuiButton
	local s = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + 3, cy + 3), Size = UDim2.fromOffset(size, size), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(s, 12)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(size, size), BackgroundColor3 = colour, AutoButtonColor = false, FontFace = HEAD, TextSize = 18, TextColor3 = INK, Text = label or "" }, parent)
	corner(b, 12)
	stroke(b, 3)
	if icon then
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size * 0.36, size * 0.36), BackgroundTransparency = 1, Image = icon }, b)
	end
	return b
end

local function fsLeft(root: Frame)
	local left = new("Frame", { Name = "Left", Position = UDim2.fromOffset(40, 128), Size = UDim2.fromOffset(290, 470), BackgroundTransparency = 1 }, root)
	local pc = new("Frame", { Name = "Photocard", Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(262, 330), BackgroundTransparency = 1, Rotation = -2 }, left)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(7, 7), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0 }, pc)
	corner(shadow, 20)
	local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, pc)
	corner(face, 20)
	stroke(face, 4)
	Build.Photo(face, UDim2.fromOffset(12, 12), UDim2.new(1, -24, 1, -24 - 84), 3)
	text(face, "PlayerName", { Position = UDim2.new(0, 12, 1, -84), Size = UDim2.new(1, -24, 0, 32), FontFace = HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Text = "Player" })
	local chips = new("Frame", { Name = "Chips", Position = UDim2.new(0, 10, 1, -46), Size = UDim2.new(1, -20, 0, 30), BackgroundTransparency = 1 }, face)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	local title = Build.TitleLabel(chips, "Title", UDim2.new(), UDim2.fromOffset(0, 28), 14)
	title.LayoutOrder = 1
	local bias = new("TextLabel", { Name = "Bias", LayoutOrder = 2, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = PINK, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = "♥ Bias", Visible = false }, chips)
	corner(bias, 9)
	stroke(bias, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, bias)
	local lv = new("Frame", { Name = "LevelBadge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(62, 62), BackgroundColor3 = YELLOW, Rotation = 6, ZIndex = 3 }, face)
	corner(lv, UDim.new(0.5, 0))
	stroke(lv, 4)
	text(lv, "Caption", { Position = UDim2.fromOffset(0, 11), Size = UDim2.new(1, 0, 0, 12), FontFace = BODY, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "LV", ZIndex = 3 })
	text(lv, "Level", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), FontFace = HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Text = "1", ZIndex = 3 })

	local xp = new("Frame", { Name = "XP", Position = UDim2.fromOffset(14, 356), Size = UDim2.fromOffset(262, 40), BackgroundTransparency = 1 }, left)
	text(xp, "Level", { Size = UDim2.fromOffset(110, 18), TextSize = 14, TextColor3 = CREAM_TEXT, Text = "Level 1" })
	text(xp, "Amount", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(150, 18), TextSize = 14, TextColor3 = CREAM_TEXT, TextTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Right, Text = "0 / 0 XP" })
	local track = new("CanvasGroup", { Name = "Track", Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = CREAM }, xp)
	corner(track, 9)
	stroke(track, 3)
	new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, track)

	button(left, "ChangeTitle", 14, 414, 124, 46, YELLOW, "TITLE", 15, 4)
	button(left, "StyleButton", 152, 414, 124, 46, WHITE, "STYLE", 15, 4) -- (not "Style": a Frame property)

	-- someone else's profile: what you can do with them, in place of XP / TITLE / STYLE
	local actions = new("Frame", { Name = "Actions", Position = UDim2.fromOffset(0, 352), Size = UDim2.fromOffset(290, 118), BackgroundTransparency = 1, Visible = false }, left)
	button(actions, "Duel", 14, 8, 262, 52, RED, "CHALLENGE TO A DUEL", 16, 4)
	button(actions, "AddFriend", 14, 70, 124, 44, WHITE, "ADD FRIEND", 13, 4)
	button(actions, "Gift", 152, 70, 124, 44, YELLOW, "GIFT", 13, 4)
	return left
end

local FS_STATS = {
	{ Name = "Wins", Label = "DUEL WINS", Colour = "FFFFFF" },
	{ Name = "BestStreak", Label = "BEST STREAK", Colour = "FFFFFF" },
	{ Name = "Cards", Label = "CARDS", Colour = "FFFFFF" },
	{ Name = "Binder", Label = "BINDER", Colour = "FFE07A" },
	{ Name = "Sets", Label = "SETS DONE", Colour = "FFFFFF" },
}
Build.FS_STATS = FS_STATS

local function fsPanel(root: Frame)
	local W, H = 864, 500
	local outer = card(root, "Panel", UDim2.fromOffset(372, 128), UDim2.fromOffset(W, H), CREAM, 22, 8, 4)
	-- the Showcase tab's page (the Stats and Titles tabs have their own, fsStats / fsTitles)
	local panel = new("Frame", { Name = "ShowcasePage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, outer)
	text(panel, "ShowcaseHeading", { Position = UDim2.fromOffset(22, 14), Size = UDim2.fromOffset(130, 30), FontFace = HEAD, TextSize = 20, Text = "SHOWCASE" })
	text(panel, "ShowcaseSub", { Position = UDim2.fromOffset(154, 18), Size = UDim2.fromOffset(420, 24), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "your best pulls, for everyone to see" })
	local edit = button(panel, "Edit", W - 22 - 100, 12, 100, 36, WHITE, "", 14, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = Build.ICONS.Pencil }, edit)
	text(edit, "Label", { Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -48, 1, 0), FontFace = HEAD, TextSize = 14, Text = "EDIT" })
	-- someone else's profile: what you have in common, in place of EDIT
	local common = new("Frame", { Name = "Common", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(W - 22, 30), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = PINK, Rotation = -2, Visible = false }, panel)
	corner(common, 11)
	stroke(common, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, common)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 12) }, common)
	local commonIcon = new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(26, 26), BackgroundColor3 = WHITE, ScaleType = Enum.ScaleType.Crop, Image = "" }, common)
	corner(commonIcon, 7)
	stroke(commonIcon, 2)
	text(common, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextTruncate = Enum.TextTruncate.None, Text = "You both stan aespa" })

	-- the shelf: five slots standing on a ledge
	local shelf = new("Frame", { Name = "Showcase", Position = UDim2.fromOffset(22, 58), Size = UDim2.fromOffset(W - 44, 262), BackgroundTransparency = 1 }, panel)
	local ledge = new("Frame", { Name = "Ledge", Position = UDim2.fromOffset(0, 230), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = C("E9DDC6"), BorderSizePixel = 0 }, shelf)
	corner(ledge, 6)
	stroke(ledge, 3)
	local ledgeShadow = new("Frame", { Name = "LedgeShadow", Position = UDim2.fromOffset(0, 236), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = INK, BorderSizePixel = 0 }, shelf)
	corner(ledgeShadow, 6)
	ledge.Parent = nil
	ledge.Parent = shelf -- (over its shadow)
	local cw, ch = 124, 176
	local gap = math.floor((W - 44 - 28 - Build.SHOWCASE * cw) / (Build.SHOWCASE - 1))
	local tilt = { -3, 2, -1.5, 2.5, -2 }
	for i = 1, Build.SHOWCASE do
		local holder = new("Frame", { Name = "Card" .. i, Position = UDim2.fromOffset(14 + (i - 1) * (cw + gap), 14), Size = UDim2.fromOffset(cw, 206), BackgroundTransparency = 1, ZIndex = 2 }, shelf)
		local pc = Photocard.Build(holder, "Card", cw, ch, tilt[i])
		pc.Visible = false
		local rarity = new("TextLabel", { Name = "Rarity", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, ch + 10), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = "Standard", Visible = false }, holder)
		corner(rarity, 7)
		stroke(rarity, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, rarity)
		-- an empty slot (always shows; a + while editing)
		local add = new("Frame", { Name = "Add", Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = INK, BackgroundTransparency = 0.95 }, holder)
		corner(add, 12)
		new("UIStroke", { Color = INK, Transparency = 0.65, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, add)
		text(add, "Plus", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 30, TextColor3 = INK, TextTransparency = 0.6, TextXAlignment = Enum.TextXAlignment.Center, Text = "+" })
		text(holder, "AddLabel", { Position = UDim2.fromOffset(0, ch + 10), Size = UDim2.new(1, 0, 0, 20), FontFace = BODY, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Add a card" })
		local slot = new("TextLabel", { Name = "Slot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cw / 2, 0), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = BODY, TextSize = 11, TextColor3 = YELLOW, Text = `SLOT {i}`, Visible = false, ZIndex = 6 }, holder)
		corner(slot, 7)
		new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, slot)
		local hit = new("TextButton", { Name = "Hit", Size = UDim2.fromOffset(cw, ch), BackgroundTransparency = 1, Text = "", Visible = false, ZIndex = 7 }, holder)
		hit:SetAttribute("NoButtonScale", true)
		local remove = new("ImageButton", { Name = "Unpin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cw - 2, 2), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = RED, Image = "", AutoButtonColor = false, Visible = false, ZIndex = 8 }, holder)
		corner(remove, UDim.new(0.5, 0))
		stroke(remove, 3)
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 1, Image = Build.ICONS.Close, ZIndex = 8 }, remove)
	end

	-- stats
	local stats = new("Frame", { Name = "Stats", Position = UDim2.fromOffset(22, 336), Size = UDim2.fromOffset(W - 44, 76), BackgroundTransparency = 1 }, panel)
	local tw = math.floor((W - 44 - 4 * 12) / 5)
	for i, spec in FS_STATS do
		local tile = card(stats, spec.Name, UDim2.fromOffset((i - 1) * (tw + 12), 0), UDim2.fromOffset(tw, 72), C(spec.Colour), 13, 0, 3)
		text(tile, "Label", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 14), TextSize = 11, TextColor3 = if spec.Name == "Binder" then INK else MUTED, Text = spec.Label })
		text(tile, "Value", { Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 0, 28), FontFace = HEAD, TextSize = 22, RichText = true, Text = "0" })
		text(tile, "Sub", { Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -24, 0, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = if spec.Name == "Binder" then INK else MUTED, Text = "" })
	end

	-- sets: completed albums (ALL-KILL when every member is Gold)
	text(panel, "SetsHeading", { Position = UDim2.fromOffset(22, 432), Size = UDim2.fromOffset(60, 40), FontFace = HEAD, TextSize = 14, Text = "SETS" })
	local sets = new("ScrollingFrame", {
		Name = "Sets",
		Position = UDim2.fromOffset(80, 428),
		Size = UDim2.fromOffset(W - 80 - 22, 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
	}, panel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, sets)
	new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, sets)
	local chip = new("Frame", { Name = "Template", Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = MINT, Visible = false }, sets)
	corner(chip, 12)
	stroke(chip, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, chip)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10) }, chip)
	local icon = new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(26, 26), BackgroundColor3 = PINK, ScaleType = Enum.ScaleType.Crop, Image = "" }, chip)
	corner(icon, 7)
	stroke(icon, 2)
	text(chip, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextTruncate = Enum.TextTruncate.None, Text = "NewJeans · Get Up" })
	local badge = new("TextLabel", { Name = "Badge", LayoutOrder = 3, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = HEAD, TextSize = 10, TextColor3 = YELLOW, Text = "ALL-KILL" }, chip)
	corner(badge, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, badge)
	text(chip, "Tick", { LayoutOrder = 4, Size = UDim2.fromOffset(14, 30), TextSize = 14, Text = "✓" })
	text(sets, "Empty", { LayoutOrder = 9999, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "Own every member of an album to complete its set", Visible = false })

	return outer
end

-- the Stats tab: every stat, a rank tag on the ones with a leaderboard
local FS_ALL_STATS = {
	{ Name = "Wins", Label = "DUEL WINS", Colour = "A7E9B8" },
	{ Name = "Duels", Label = "DUELS PLAYED", Colour = "FFFFFF" },
	{ Name = "BestStreak", Label = "BEST STREAK", Colour = "FFD2CE" },
	{ Name = "Perfect", Label = "PERFECT GAMES", Colour = "FFE07A" },
	{ Name = "Correct", Label = "CORRECT ANSWERS", Colour = "CDEBFA" },
	{ Name = "SoloBest", Label = "SOLO BEST", Colour = "FFFFFF" },
	{ Name = "Cards", Label = "CARDS", Colour = "DCD3FF" },
	{ Name = "Binder", Label = "BINDER", Colour = "FFE07A" },
	{ Name = "Sets", Label = "SETS", Colour = "FFFFFF" },
}
Build.FS_ALL_STATS = FS_ALL_STATS

local function fsStats(outer: Frame)
	local W = outer.Size.X.Offset
	local page = new("Frame", { Name = "StatsPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, outer)
	text(page, "Heading", { Position = UDim2.fromOffset(22, 14), Size = UDim2.fromOffset(130, 30), FontFace = HEAD, TextSize = 20, Text = "STATS" })
	text(page, "Sub", { Position = UDim2.fromOffset(110, 18), Size = UDim2.fromOffset(420, 24), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "all time" })
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(22, 64), Size = UDim2.fromOffset(W - 44, 400), BackgroundTransparency = 1 }, page)
	local gap, th = 16, 112
	local tw = math.floor((W - 44 - 2 * gap - 4) / 3)
	for i, spec in FS_ALL_STATS do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local tile = card(grid, spec.Name, UDim2.fromOffset(col * (tw + gap), row * (th + gap)), UDim2.fromOffset(tw, th), C(spec.Colour), 16, 4, 3)
		text(tile, "Label", { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 16), TextSize = 13, TextColor3 = BODYTEXT, Text = spec.Label })
		text(tile, "Value", { Position = UDim2.fromOffset(16, 32), Size = UDim2.new(1, -32, 0, 40), FontFace = HEAD, TextSize = 32, RichText = true, Text = "0" })
		text(tile, "Sub", { Position = UDim2.fromOffset(16, 78), Size = UDim2.new(1, -32, 0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = BODYTEXT, Text = "" })
		local rank = new("TextLabel", { Name = "Rank", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = BODY, TextSize = 13, TextColor3 = YELLOW, Text = "#1 all time", Visible = false, ZIndex = 3 }, tile)
		corner(rank, 8)
		new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, rank)
	end
	return page
end

-- the Titles tab (design board "49 · Profile · Titles tab with group badges"): WEAR, a Titles /
-- Badges switch and what you're wearing; Titles = every title you own as a chip you tap to wear
-- (the worn one gets a mint Ring); Badges = a row per group (Modules/Library/Ladders) with its
-- cards and songs chips in fixed columns (Legend in the songs column once both are Diamond).
local function wearChip(parent: Instance, name: string, order: number?, width: number?): TextButton
	-- a tap target holding a TitleChip label (Chip) and the mint ring shown when it's worn
	local hit = new("TextButton", { Name = name, LayoutOrder = order or 0, Size = UDim2.fromOffset(width or 0, 34), AutomaticSize = if width then Enum.AutomaticSize.None else Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, parent)
	local chip = Build.TitleLabel(hit, "Chip", UDim2.new(0, 4, 0.5, -13), UDim2.fromOffset(0, 26), 13, 0)
	if width then
		chip.AutomaticSize = Enum.AutomaticSize.None
		chip.Size = UDim2.new(1, -8, 0, 26)
		chip.TextXAlignment = Enum.TextXAlignment.Left
		chip.TextTruncate = Enum.TextTruncate.AtEnd
	else
		new("UIPadding", { PaddingRight = UDim.new(0, 4) }, hit)
	end
	local ring = new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 0 }, hit)
	corner(ring, 12)
	new("UIStroke", { Color = MINT, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	return hit
end

local function fsTitles(outer: Frame)
	local W, H = outer.Size.X.Offset, outer.Size.Y.Offset
	local page = new("Frame", { Name = "TitlesPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, outer)
	text(page, "Heading", { Position = UDim2.fromOffset(22, 14), Size = UDim2.fromOffset(80, 30), FontFace = HEAD, TextSize = 20, Text = "WEAR" })
	-- Titles / Badges
	local mode = new("Frame", { Name = "Mode", Position = UDim2.fromOffset(96, 12), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE }, page)
	corner(mode, 11)
	stroke(mode, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, mode)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, mode)
	for i, spec in { { "Titles", "Titles · 0" }, { "Badges", "Badges · 0" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), BackgroundColor3 = INK, BackgroundTransparency = if i == 1 then 0 else 1, FontFace = BODY, TextSize = 14, TextColor3 = if i == 1 then CREAM else INK, Text = spec[2], AutoButtonColor = false }, mode)
		corner(b, 8)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, b)
	end
	-- what you're wearing
	local wearing = new("Frame", { Name = "Wearing", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(W - 22, 12), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, page)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, wearing)
	text(wearing, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), FontFace = BODY, TextSize = 13, TextColor3 = MUTED, Text = "Wearing" })
	local worn = Build.TitleLabel(wearing, "Chip", UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 26), 13, 0)
	worn.LayoutOrder = 2

	-- Titles: a wrapping row of chips
	local titles = new("ScrollingFrame", {
		Name = "Titles",
		Position = UDim2.fromOffset(14, 58),
		Size = UDim2.fromOffset(W - 28, H - 72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, titles)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14) }, titles)
	local t = wearChip(titles, "Template")
	t.Visible = false
	text(titles, "Empty", { LayoutOrder = 9999, Size = UDim2.fromOffset(500, 40), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "Level up and play seasons to unlock titles", Visible = false })

	-- Badges: sorts, column heads and a row per group
	local badges = new("Frame", { Name = "Badges", Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), BackgroundTransparency = 1, Visible = false }, page)
	local sorts = new("Frame", { Name = "Sorts", Position = UDim2.fromOffset(22, 4), Size = UDim2.fromOffset(420, 26), BackgroundTransparency = 1 }, badges)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sorts)
	for i, spec in { { "Best", "Best first" }, { "Name", "A–Z" }, { "Legend", "Legend only" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundColor3 = if i == 1 then INK else WHITE, FontFace = BODY, TextSize = 13, TextColor3 = if i == 1 then CREAM else INK, Text = spec[2], AutoButtonColor = false }, sorts)
		corner(b, 13)
		stroke(b, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, b)
	end
	-- the chip columns, measured from the row's right edge (rows: list x 14 + padding 8, width
	-- W - 52) so the songs chip keeps ROW_PAD clear of it
	local COL_W, ROW_PAD, GAP = 170, 16, 10
	local songsX = 22 + (W - 52) - ROW_PAD - COL_W
	local cardsX = songsX - GAP - COL_W
	text(badges, "CardsHead", { Position = UDim2.fromOffset(cardsX + 4, 8), Size = UDim2.fromOffset(COL_W, 18), FontFace = BODY, TextSize = 12, TextColor3 = MUTED, Text = "CARDS" })
	text(badges, "SongsHead", { Position = UDim2.fromOffset(songsX + 4, 8), Size = UDim2.fromOffset(COL_W, 18), FontFace = BODY, TextSize = 12, TextColor3 = MUTED, Text = "SONGS" })
	local list = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -28, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, badges)
	new("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14) }, list)
	local row = new("Frame", { Name = "Template", Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, Visible = false }, list)
	local face = card(row, "Face", UDim2.fromOffset(0, 0), UDim2.new(1, -4, 0, 54), WHITE, 12, 3, 3)
	local icon = new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = LILAC, ScaleType = Enum.ScaleType.Crop, Image = "" }, face)
	corner(icon, 8)
	stroke(icon, 2)
	text(icon, "Initial", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 16, Text = "A", TextXAlignment = Enum.TextXAlignment.Center })
	text(face, "GroupName", { Position = UDim2.fromOffset(58, 7), Size = UDim2.fromOffset(cardsX - 22 - 70, 22), FontFace = BODY, TextSize = 16, Text = "aespa", TextTruncate = Enum.TextTruncate.AtEnd })
	text(face, "Sub", { Position = UDim2.fromOffset(58, 28), Size = UDim2.fromOffset(cardsX - 22 - 70, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Next cards: every member Store+ · 2/4", TextTruncate = Enum.TextTruncate.AtEnd })
	local c = wearChip(face, "Cards", nil, COL_W)
	c.AnchorPoint = Vector2.new(1, 0.5)
	c.Position = UDim2.new(1, -(ROW_PAD + COL_W + GAP), 0.5, 0)
	local sg = wearChip(face, "Songs", nil, COL_W)
	sg.AnchorPoint = Vector2.new(1, 0.5)
	sg.Position = UDim2.new(1, -ROW_PAD, 0.5, 0)
	text(list, "Empty", { LayoutOrder = 9999, Size = UDim2.fromOffset(600, 40), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "Collect a group's photocards or master its songs for your first badge", Visible = false })
	return page
end

-- Rebuilds just the Titles tab (board 49) on an existing Profile frame, in Edit mode:
--   require(<this module>).RebuildTitles(game.StarterGui.Interface.Frames)
function Build.RebuildTitles(frames: Instance)
	local outer = frames.Profile.Panel
	local old = outer:FindFirstChild("TitlesPage")
	if old then
		old:Destroy()
	end
	return fsTitles(outer)
end

local function fsPicker(root: Frame)
	local picker = new("Frame", { Name = "Picker", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, root)
	local dim = new("TextButton", { Name = "Dim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.35, Text = "", AutoButtonColor = false }, picker)
	dim:SetAttribute("NoButtonScale", true)
	local W, H = 780, 540
	local sheet = card(picker, "Sheet", UDim2.fromOffset(640 - W / 2, 360 - H / 2 + 10), UDim2.fromOffset(W, H), CREAM, 20, 8, 4)
	text(sheet, "Title", { Position = UDim2.fromOffset(22, 16), Size = UDim2.fromOffset(500, 30), FontFace = HEAD, TextSize = 22, Text = "Pick a card for slot 1" })
	text(sheet, "Sub", { Position = UDim2.fromOffset(22, 46), Size = UDim2.fromOffset(600, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Your cards, best first" })
	squareButton(sheet, "Close", W - 22 - 21, 36, 42, RED, Build.ICONS.Close)
	local grid = new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(14, 76),
		Size = UDim2.fromOffset(W - 28, H - 90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, sheet)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(96, 158), CellPadding = UDim2.fromOffset(12, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 14) }, grid)
	local tile = new("TextButton", { Name = "Template", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false }, grid)
	Photocard.Build(tile, "Card", 96, 136)
	text(tile, "Rarity", { Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 16), FontFace = BODY, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Standard" })
	local using = new("TextLabel", { Name = "Using", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(48, 4), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = BODY, TextSize = 10, TextColor3 = YELLOW, Text = "ON SHOW", Visible = false, ZIndex = 5 }, tile)
	corner(using, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, using)
	text(grid, "Empty", { LayoutOrder = 9999, Size = UDim2.fromOffset(500, 40), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "Open packs to get cards for your showcase", Visible = false })
	scaledZ(picker, 40)
	return picker
end

function Build.BuildFullScreen(frames: Instance)
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
	local bg = new("Frame", { Name = "Backdrop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, root)
	bg.Active = true
	new("UIGradient", { Color = ColorSequence.new(C("3B2F66"), C("221C36")), Rotation = 90, Offset = Vector2.new(0, 0.05) }, bg)

	-- (headings sit below Roblox's top bar buttons)
	text(root, "Title", { Position = UDim2.fromOffset(40, 54), Size = UDim2.fromOffset(300, 36), FontFace = HEAD, TextSize = 30, TextColor3 = CREAM_TEXT, Text = "Profile" })
	text(root, "Sub", { Position = UDim2.fromOffset(40, 90), Size = UDim2.fromOffset(560, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = CREAM_TEXT, TextTransparency = 0.4, Text = "What other players see when they tap you" })
	squareButton(root, "Close", 1214, 79, 46, RED, Build.ICONS.Close)

	-- the Showcase / Stats / Titles switch
	local tabs = new("Frame", { Name = "Tabs", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 60), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, BackgroundTransparency = 0.92 }, root)
	corner(tabs, 12)
	new("UIStroke", { Color = CREAM, Transparency = 0.75, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tabs)
	new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, tabs)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, spec in { { "Showcase", "Showcase" }, { "Stats", "Stats" }, { "Titles", "Titles" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), BackgroundColor3 = CREAM, BackgroundTransparency = if i == 1 then 0 else 1, FontFace = BODY, TextSize = 16, TextColor3 = if i == 1 then INK else CREAM, Text = spec[2], AutoButtonColor = false }, tabs)
		corner(b, 9)
		new("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) }, b)
	end

	fsLeft(root)
	local outer = fsPanel(root)
	fsStats(outer)
	fsTitles(outer)
	fsPicker(root)
	root.Parent = frames
	return root
end

return Build
