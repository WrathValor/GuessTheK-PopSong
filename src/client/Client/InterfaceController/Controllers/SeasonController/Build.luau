--| Season UI builder
-- Builds the season screens from the "Seasons" boards on the design canvas, as instances:
--   • Interface.Frames.Season   – the Season screen: pink header with TRACK / RANKS / REWARDS
--                                 tabs, days-left chip; Track (tier card, season-end rewards,
--                                 5 milestones a page on a road, Earn Stars, Coming up), Ranks
--                                 (top 3 podium cards, rows 4–10, pinned YOU row) and Rewards
--                                 (what each tier + placement unlocks)
--   • Interface.Frames.Banners  – the STYLE picker (Sets / Banners / Photocards tabs, preview, 4 × 3 grid)
--   • Season Track rewards (board "Seasons 12"): the Roll screen's ticket counter, ticket strip
--     and Pick a Group overlay (Roll.Picker), and the Index's card-upgrade bits (BuildRewards)
--   • Shop: the "Banners + photocards" section (StyleTitle + Style, 4 rotating cards) after
--     Stages + mics, from the "Shop v3 · Banners + photocards" board (ShopController fills it)
--   • patches: Profile (banner band, photocard over it, title + tier chips side by side), PlayerCard (banner behind
--     the top strip, tier chip), PreDuel (banner strip + tier chip on both cards), Results
--     (Season bar: tier, SP change, progress, Stars, PROMOTED sticker) and the HUD (tier chip
--     under Roll / UGC that opens the Season screen)
-- Run once in Studio, Edit mode (safe to run again: each part replaces its own instances):
--   require(<this module>).BuildAll(game.StarterGui.Interface)
-- SeasonController / BannersController and the screens' own controllers fill them by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local P = require(script.Parent.Parent.ProfileController.Build)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)

local new, corner, stroke, text, card, button = P.new, P.corner, P.stroke, P.text, P.card, P.button

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local PINK = C("FF9EC4")
local LILAC = C("B9A6FF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local BLUE = C("9ED8F5")
local MUTED = C("4A4458")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local COIN = Currencies.Coins.Icon
local CLOSE = P.ICONS.Close
local ICONS = SeasonConstants.ICONS

local Build = {}

-- [[ Shared bits ]]

local function clear(parent: Instance, name: string)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- header with rounded top corners: UICorner + a SquareBottom so only the top is round
local function roundedHeader(panel: Frame, w: number, h: number, colour: Color3, radius: number): Frame
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = colour, BorderSizePixel = 0 }, panel)
	corner(header, radius)
	new("Frame", { Name = "SquareBottom", Position = UDim2.fromOffset(0, h / 2), Size = UDim2.new(1, 0, 0, h / 2), BackgroundColor3 = colour, BorderSizePixel = 0, ZIndex = 0 }, header)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, h), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(w - 14 - 42 + 3, (h - 42) / 2 + 3), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w - 14 - 21, h / 2), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE }, close)
	return header
end

-- a full-screen root with the scrim, shadow + rounded panel (like Profile / Rewards)
local function screen(frames: Instance, name: string, w: number, h: number): (Frame, Frame)
	clear(frames, name)
	-- same root as Profile / Rewards: the full 1280 × 720 canvas in offsets, top-left anchored
	-- (a centred, scale-sized root got its Position rewritten to scale and opened off-screen)
	local root = new("Frame", { Name = name, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = true }, root)
	scrim.ZIndex = 0
	local x, y = (1280 - w) / 2, (720 - h) / 2
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(x + 8, y + 8), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(shadow, 18)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, root)
	corner(panel, 18)
	stroke(panel, 3)
	root.Parent = frames
	return root, panel
end

local function chip(parent: Instance, name: string, pos: UDim2, h: number, colour: Color3, label: string, textSize: number, anchor: Vector2?): TextLabel
	local c = new("TextLabel", { Name = name, AnchorPoint = anchor or Vector2.zero, Position = pos, Size = UDim2.fromOffset(0, h), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = colour, FontFace = BODY, TextSize = textSize, TextColor3 = INK, Text = label }, parent)
	corner(c, math.floor(h * 0.36))
	stroke(c, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, c)
	return c
end

local function bar(parent: Instance, name: string, pos: UDim2, size: UDim2, fill: Color3, line: number?): Frame
	local track = new("CanvasGroup", { Name = name, Position = pos, Size = size, BackgroundColor3 = WHITE }, parent)
	corner(track, math.floor(size.Y.Offset / 2))
	stroke(track, line or 3)
	new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = fill, BorderSizePixel = 0 }, track)
	return track
end

local function pips(parent: Instance, name: string, pos: UDim2, size: number): Frame
	local row = new("Frame", { Name = name, Position = pos, Size = UDim2.fromOffset(size * 3 + 12, size + 4), BackgroundTransparency = 1 }, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.Name }, row)
	for i = 1, 3 do
		local p = new("Frame", { Name = "Pip" .. i, Size = UDim2.fromOffset(size, size), Rotation = 45, BackgroundColor3 = CREAM }, row)
		corner(p, 3)
		stroke(p, 2)
	end
	return row
end

-- an icon from the season icon sheet (SeasonConstants.ICONS)
local function icon(parent: Instance, name: string, key: string, pos: UDim2, size: number, anchor: Vector2?): ImageLabel
	return new("ImageLabel", { Name = name, AnchorPoint = anchor or Vector2.zero, Position = pos, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = ICONS[key] or "", ScaleType = Enum.ScaleType.Fit }, parent)
end

-- a chip's leading icon: pads the chip on the left and sits the icon in that space
local function chipIcon(c: GuiObject, key: string, size: number)
	local pad = c:FindFirstChildOfClass("UIPadding") or new("UIPadding", {}, c)
	pad.PaddingLeft = UDim.new(0, size + 10)
	icon(c, "Icon", key, UDim2.new(0, -size - 4, 0.5, 0), size, Vector2.new(0, 0.5))
end

-- [[ Milestone card art ]]
-- every card carries all the art kinds; SeasonController shows the one for its reward

-- a small photocard (card frame, photo window + skin, stickers when withDeco) in the
-- Profile card's proportions; SeasonArt.PaintPhotocard fills it
local function miniCard(parent: Instance, name: string, pos: UDim2, w: number, rot: number, withDeco: boolean): Frame
	local h = math.floor(w * 334 / 280)
	local m = new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(w, h), Rotation = rot, BackgroundColor3 = WHITE }, parent)
	corner(m, 6)
	stroke(m, 2)
	local ph = P.Photo(m, UDim2.fromScale(12 / 280, 12 / 334), UDim2.fromScale(256 / 280, 228 / 334), 2)
	ph:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 4)
	SeasonArt.BuildCardSkin(m, ph, 6, withDeco)
	return m
end

-- a banner reward in a box, the way the purchase reveal shows one: the banner across the top
-- (right-aligned so its art side shows), your photocard tucked bottom-left and your name beside
-- it, like your profile. Clipped to the box's rounded corners. SeasonController paints it.
local function bannerBox(parent: Instance, radius: number): CanvasGroup
	local box = new("CanvasGroup", { Name = "Banner", Size = UDim2.fromScale(1, 1), BackgroundColor3 = CREAM, Visible = false }, parent)
	corner(box, radius)
	local top = 54
	local strip = SeasonArt.BuildBanner(box, "Strip", UDim2.fromScale(1, 0), UDim2.fromOffset(top * 4, top), 0, false)
	strip.AnchorPoint = Vector2.new(1, 0)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 2 }, box)
	local me = miniCard(box, "Me", UDim2.fromOffset(24, 62), 30, -4, false)
	me.ZIndex = 3
	local name = new("TextLabel", { Name = "PlayerName", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(42, 72), Size = UDim2.new(1, -46, 0, 18), BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = 9, TextColor3 = INK, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Player", ZIndex = 3 }, box)
	corner(name, 5)
	new("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, name)
	return box
end

-- a title reward, like the Inventory's title art: your name with the title chip under it, on the
-- rewards' pastel blue tile (SeasonController paints it; Gold / Rainbow via the chip's "Rainbow" gradient)
local function titleArt(parent: Instance, pos: UDim2, size: UDim2, nameSize: number, chipH: number, chipText: number, panel: boolean): Frame
	clear(parent, "TitleChip")
	clear(parent, "TitleArt")
	local f = new("Frame", { Name = "TitleArt", Position = pos, Size = size, BackgroundTransparency = if panel then 0 else 1, BackgroundColor3 = C("CDEBFA"), Visible = false, ZIndex = 3 }, parent)
	if panel then
		corner(f, 8)
		stroke(f, 3)
	end
	local nameH = nameSize + 5
	text(f, "Player", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -1), Size = UDim2.new(1, -8, 0, nameH), FontFace = BODY, TextSize = nameSize, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Center, Text = "Player", ZIndex = 3 })
	local chip = text(f, "Chip", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 3), Size = UDim2.fromOffset(0, chipH), AutomaticSize = Enum.AutomaticSize.X, FontFace = BODY, TextSize = chipText, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "S0 Comeback", BackgroundTransparency = 0, BackgroundColor3 = YELLOW, ZIndex = 3 })
	corner(chip, 6)
	new("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, chip)
	new("UIGradient", { Name = "Rainbow", Rotation = 20, Enabled = false }, chip)
	return f
end

local function cardArt(art: Frame)
	-- coins: the shop's coin-pile art (SeasonController picks the pile by amount)
	-- the pile art sits low in a mostly empty square, so it's drawn big and anchored on the coins
	new("ImageLabel", { Name = "Coins", AnchorPoint = Vector2.new(0.5, 0.64), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(170, 170), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit, Visible = false }, art)
	-- everything else: its icon from the sheet (SeasonController sets Image per reward kind)
	icon(art, "Icon", "Ticket", UDim2.fromScale(0.5, 0.5), 80, Vector2.new(0.5, 0.5)).Visible = false
	-- banner / photocard rewards: the real thing (SeasonController paints them)
	bannerBox(art, 10)
	miniCard(art, "Card", UDim2.fromScale(0.5, 0.5), 62, -4, true).Visible = false
	-- title rewards: your name + the title chip, like the Inventory
	titleArt(art, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 16, 26, 15, false)
end

-- [[ Season screen ]]

local function trackPage(page: Frame)
	-- left: tier card, season-end rewards, duels / wins
	local left = new("Frame", { Name = "Left", Size = UDim2.fromOffset(236, 519), BackgroundTransparency = 1 }, page)
	local tier = card(left, "Tier", UDim2.fromOffset(0, 0), UDim2.fromOffset(232, 236), LILAC, 18, 6, 4)
	SeasonArt.BuildEmblem(tier, "Emblem", UDim2.new(0.5, 0, 0, 10), 92, Vector2.new(0.5, 0))
	text(tier, "TierName", { Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 30), FontFace = HEAD, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Text = "TRAINEE III" })
	local tp = pips(tier, "Pips", UDim2.new(0.5, -27, 0, 138), 12)
	tp.AnchorPoint = Vector2.zero
	text(tier, "SP", { Position = UDim2.fromOffset(14, 160), Size = UDim2.fromOffset(100, 18), TextSize = 14, Text = "0 SP" })
	text(tier, "NextAt", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 160), Size = UDim2.fromOffset(120, 18), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Text = "Trainee II · 100" })
	bar(tier, "Bar", UDim2.fromOffset(14, 182), UDim2.new(1, -28, 0, 16), INK)
	text(tier, "ToGo", { Position = UDim2.fromOffset(0, 204), Size = UDim2.new(1, 0, 0, 18), FontFace = BODY_BOLD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "100 SP to go · about 4 wins" })

	local ends = card(left, "SeasonEnd", UDim2.fromOffset(0, 254), UDim2.fromOffset(232, 150), WHITE, 14, 0, 3)
	text(ends, "Heading", { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 14), TextSize = 11, TextColor3 = MUTED, Text = "AT SEASON END YOU GET" })
	local row = new("Frame", { Name = "Rewards", Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 80), BackgroundTransparency = 1 }, ends)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i = 1, 3 do
		local slot = new("Frame", { Name = "Slot" .. i, LayoutOrder = i, Size = UDim2.fromOffset(64, 80), BackgroundTransparency = 1 }, row)
		local tile = new("TextLabel", { Name = "Tile", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 11, TextWrapped = true, TextColor3 = INK, Text = "S0" }, slot)
		corner(tile, 12)
		stroke(tile, 3)
		icon(tile, "Icon", "Badge", UDim2.fromScale(0.5, 0.5), 44, Vector2.new(0.5, 0.5))
		text(slot, "Label", { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "Badge" })
	end
	text(ends, "Next", { Position = UDim2.fromOffset(12, 118), Size = UDim2.new(1, -24, 0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Reach Rookie for a title too" })

	for i, spec in { { "Duels", "DUELS", WHITE }, { "Wins", "WINS", MINT } } do
		local t = card(left, spec[1], UDim2.fromOffset((i - 1) * 120, 420), UDim2.fromOffset(112, 60), spec[3], 12, 0, 3)
		text(t, "Label", { Position = UDim2.fromOffset(10, 7), Size = UDim2.new(1, -20, 0, 13), TextSize = 11, TextColor3 = MUTED, Text = spec[2] })
		text(t, "Value", { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 0, 30), FontFace = HEAD, TextSize = 22, Text = "0" })
		icon(t, "Icon", if i == 1 then "Duel" else "Win", UDim2.new(1, -6, 0.5, 0), 40, Vector2.new(1, 0.5))
	end

	-- right: stars, milestones, road, earn + coming up
	local right = new("Frame", { Name = "Right", Position = UDim2.fromOffset(256, 0), Size = UDim2.fromOffset(726, 519), BackgroundTransparency = 1 }, page)
	text(right, "Heading", { Size = UDim2.fromOffset(170, 30), FontFace = HEAD, TextSize = 22, Text = "Season Track" })
	local stars = new("Frame", { Name = "Stars", Position = UDim2.fromOffset(176, 2), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = YELLOW }, right)
	corner(stars, 10)
	stroke(stars, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10) }, stars)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, stars)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = ICONS.Stars, ScaleType = Enum.ScaleType.Fit }, stars)
	new("TextLabel", { Name = "Value", LayoutOrder = 2, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, FontFace = BODY, TextSize = 15, TextColor3 = INK, Text = "0 Stars" }, stars)
	text(right, "Count", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -168, 0, 6), Size = UDim2.fromOffset(160, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Text = "0 / 25 milestones" })
	bar(right, "TrackBar", UDim2.new(1, -158, 0, 8), UDim2.fromOffset(150, 14), PINK)

	local miles = new("Frame", { Name = "Milestones", Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(726, 214), BackgroundTransparency = 1 }, right)
	for i, spec in { { "Prev", 0 }, { "Next", 726 - 38 } } do
		local b = button(miles, spec[1], spec[2], 89, 38, 38, WHITE, if i == 1 then "‹" else "›", 22, 3)
		b.FontFace = HEAD
	end
	local cw, gap = 118, 12
	for i = 1, 5 do
		local x = 48 + (i - 1) * (cw + gap)
		local holder = new("Frame", { Name = "Card" .. i, Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(cw, 196), BackgroundTransparency = 1 }, miles)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0, Visible = false }, holder)
		corner(sh, 14)
		local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, holder)
		corner(face, 14)
		stroke(face, 3)
		text(face, "Number", { Position = UDim2.fromOffset(9, 7), Size = UDim2.fromOffset(40, 20), FontFace = HEAD, TextSize = 15, Text = "1" })
		chip(face, "State", UDim2.new(1, -8, 0, 8), 18, MINT, "CLAIMED", 10, Vector2.new(1, 0))
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, 34), Size = UDim2.new(1, -16, 0, 90), BackgroundColor3 = YELLOW, ClipsDescendants = false }, face)
		corner(art, 10)
		stroke(art, 3)
		cardArt(art)
		text(face, "Amount", { Position = UDim2.fromOffset(9, 130), Size = UDim2.new(1, -18, 0, 20), FontFace = HEAD, TextSize = 16, Text = "250" })
		text(face, "Kind", { Position = UDim2.fromOffset(9, 150), Size = UDim2.new(1, -18, 0, 16), TextSize = 12, TextColor3 = MUTED, Text = "coins" })
		local claim = button(face, "Claim", 8, 160, cw - 16, 28, MINT, "CLAIM", 13, 0)
		claim.Visible = false
		local cs = face:FindFirstChild("ClaimShadow")
		if cs then
			cs:Destroy()
		end
	end
	-- the road under the cards
	local road = new("Frame", { Name = "Road", Position = UDim2.fromOffset(48, 254), Size = UDim2.fromOffset(cw * 5 + gap * 4, 26), BackgroundTransparency = 1 }, right)
	local base = new("Frame", { Name = "Line", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.1, 0, 0.5, 0), Size = UDim2.new(0.8, 0, 0, 8), BackgroundColor3 = WHITE }, road)
	corner(base, 4)
	stroke(base, 2)
	local fill = new("Frame", { Name = "Fill", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.1, 0, 0.5, 0), Size = UDim2.new(0.4, 0, 0, 8), BackgroundColor3 = PINK }, road)
	corner(fill, 4)
	stroke(fill, 2)
	for i = 1, 5 do
		local n = new("Frame", { Name = "Node" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.1 + (i - 1) * 0.2, 0, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = WHITE, ZIndex = 2 }, road)
		corner(n, UDim.new(0.5, 0))
		stroke(n, 3)
	end
	new("ImageLabel", { Name = "Here", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, Image = ICONS.Stars, ScaleType = Enum.ScaleType.Fit, ZIndex = 3 }, road)

	-- earn stars (2 × 2) + coming up
	text(right, "EarnHeading", { Position = UDim2.fromOffset(0, 286), Size = UDim2.fromOffset(200, 24), FontFace = HEAD, TextSize = 17, Text = "Earn Stars" })
	local earn = new("Frame", { Name = "Earn", Position = UDim2.fromOffset(0, 314), Size = UDim2.fromOffset(392, 206), BackgroundTransparency = 1 }, right)
	for i = 1, 4 do
		local col, rowN = (i - 1) % 2, math.floor((i - 1) / 2)
		local t = card(earn, "Tile" .. i, UDim2.fromOffset(col * 200, rowN * 104), UDim2.fromOffset(192, 96), WHITE, 12, 0, 3)
		icon(t, "Icon", "Duel", UDim2.fromOffset(13, 18), 44)
		text(t, "Value", { Position = UDim2.fromOffset(8, 62), Size = UDim2.fromOffset(54, 22), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Text = "+10" })
		text(t, "Label", { Position = UDim2.fromOffset(66, 26), Size = UDim2.new(1, -74, 0, 20), TextSize = 15, Text = "Duel played" })
		text(t, "Sub", { Position = UDim2.fromOffset(66, 48), Size = UDim2.new(1, -74, 0, 30), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "15 a day count" })
	end
	text(right, "UpHeading", { Position = UDim2.fromOffset(412, 286), Size = UDim2.fromOffset(200, 24), FontFace = HEAD, TextSize = 17, Text = "Coming up" })
	local up = new("Frame", { Name = "ComingUp", Position = UDim2.fromOffset(412, 314), Size = UDim2.fromOffset(314, 200), BackgroundTransparency = 1 }, right)
	for i = 1, 2 do
		local t = card(up, "Big" .. i, UDim2.fromOffset(0, (i - 1) * 104), UDim2.fromOffset(314, 96), WHITE, 12, 0, 3)
		SeasonArt.BuildBanner(t, "Preview", UDim2.fromOffset(10, 18), UDim2.fromOffset(120, 58), 8, false)
		stroke(t.Preview, 3)
		icon(t, "Icon", "Frame", UDim2.fromOffset(70, 47), 64, Vector2.new(0.5, 0.5)).ZIndex = 3
		local pc = miniCard(t, "Card", UDim2.fromOffset(70, 47), 56, -4, true)
		pc.ZIndex = 3
		pc.Visible = false
		titleArt(t, UDim2.fromOffset(10, 18), UDim2.fromOffset(120, 58), 13, 20, 12, true)
		text(t, "Title", { Position = UDim2.fromOffset(142, 22), Size = UDim2.new(1, -150, 0, 22), FontFace = HEAD, TextSize = 14, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = "20 · S0 Comeback banner" })
		text(t, "Sub", { Position = UDim2.fromOffset(142, 50), Size = UDim2.new(1, -150, 0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "660 Stars away" })
	end
end

local function ranksPage(page: Frame)
	local left = new("Frame", { Name = "Left", Size = UDim2.fromOffset(300, 519), BackgroundTransparency = 1 }, page)
	for i, spec in { { "Rating", "Season Rating", INK }, { "Wins", "Season Wins", WHITE } } do
		local b = new("TextButton", { Name = spec[1], Position = UDim2.fromOffset((i - 1) * 140, 0), Size = UDim2.fromOffset(132, 34), BackgroundColor3 = spec[3], AutoButtonColor = false, FontFace = BODY, TextSize = 14, TextColor3 = if i == 1 then CREAM else INK, Text = spec[2] }, left)
		corner(b, 9)
		stroke(b, 3)
		b:SetAttribute("NoButtonScale", true)
	end
	local medals = { YELLOW, C("E6E1EE"), C("F2B38A") }
	for i = 1, 3 do
		local t = card(left, "Top" .. i, UDim2.fromOffset(0, 48 + (i - 1) * 116), UDim2.fromOffset(294, 104), WHITE, 14, 4, 3)
		t.ClipsDescendants = false
		SeasonArt.BuildBanner(t, "Banner", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 48), 14, true)
		local medal = new("TextLabel", { Name = "Medal", Position = UDim2.fromOffset(10, 30), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = medals[i], FontFace = HEAD, TextSize = 20, TextColor3 = INK, Text = tostring(i), ZIndex = 2 }, t)
		corner(medal, UDim.new(0.5, 0))
		stroke(medal, 3)
		local nm = chip(t, "PlayerName", UDim2.fromOffset(64, 36), 26, CREAM, "—", 15)
		nm.ZIndex = 2
		text(t, "SP", { Position = UDim2.fromOffset(66, 70), Size = UDim2.fromOffset(200, 20), TextSize = 14, Text = "" })
	end
	icon(left, "NoteIcon", "Billboard", UDim2.fromOffset(0, 398), 44)
	text(left, "Note", { Position = UDim2.fromOffset(52, 400), Size = UDim2.fromOffset(242, 40), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "Top 3 at season end get a billboard on the street for all of next season." })

	local right = new("Frame", { Name = "Right", Position = UDim2.fromOffset(320, 0), Size = UDim2.fromOffset(662, 519), BackgroundTransparency = 1 }, page)
	text(right, "Heading", { Size = UDim2.fromOffset(240, 30), FontFace = HEAD, TextSize = 20, Text = "Legend · Top 100" })
	chip(right, "Cutoff", UDim2.fromOffset(234, 3), 24, WHITE, "Top 100 cut-off: —", 13)
	local list = new("Frame", { Name = "Rows", Position = UDim2.fromOffset(0, 40), Size = UDim2.fromOffset(662, 392), BackgroundTransparency = 1 }, right)
	for i = 1, 7 do
		local r = new("Frame", { Name = "Row" .. i, Position = UDim2.fromOffset(0, (i - 1) * 56), Size = UDim2.fromOffset(662, 48), BackgroundColor3 = WHITE }, list)
		corner(r, 12)
		stroke(r, 3)
		text(r, "Rank", { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(46, 48), FontFace = HEAD, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Text = "#" .. (i + 3) })
		local strip = SeasonArt.BuildBanner(r, "Banner", UDim2.fromOffset(64, 10), UDim2.fromOffset(72, 28), 7, false)
		stroke(strip, 2)
		text(r, "PlayerName", { Position = UDim2.fromOffset(150, 0), Size = UDim2.fromOffset(280, 48), TextSize = 16, Text = "—" })
		SeasonArt.BuildChip(r, "Tier", UDim2.new(1, -112, 0.5, 0), 24, Vector2.new(1, 0.5))
		text(r, "SP", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(96, 48), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, Text = "0" })
	end
	text(list, "Empty", { Size = UDim2.fromOffset(662, 120), FontFace = BODY_BOLD, TextSize = 15, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = "The season board fills up as people play duels.", Visible = false })
	local you = card(right, "You", UDim2.fromOffset(0, 455), UDim2.fromOffset(656, 56), YELLOW, 12, 4, 4)
	text(you, "Rank", { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(58, 56), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "—" })
	local ys = SeasonArt.BuildBanner(you, "Banner", UDim2.fromOffset(76, 13), UDim2.fromOffset(72, 30), 7, false)
	stroke(ys, 2)
	text(you, "PlayerName", { Position = UDim2.fromOffset(162, 0), Size = UDim2.fromOffset(260, 56), TextSize = 16, Text = "YOU" })
	SeasonArt.BuildChip(you, "Tier", UDim2.new(1, -112, 0.5, 0), 26, Vector2.new(1, 0.5))
	text(you, "SP", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(96, 56), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, Text = "0" })
end

local function rewardsPage(page: Frame)
	text(page, "Heading", { Size = UDim2.fromOffset(400, 30), FontFace = HEAD, TextSize = 20, Text = "What each tier unlocks" })
	text(page, "Sub", { Position = UDim2.fromOffset(330, 4), Size = UDim2.fromOffset(500, 26), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "from your peak tier · rewards stack" })
	local grid = new("Frame", { Name = "Tiers", Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(982, 236), BackgroundTransparency = 1 }, page)
	local w = math.floor((982 - 5 * 14 - 6) / 6)
	for i, tier in SeasonConstants.TIERS do
		local t = card(grid, tier.Name, UDim2.fromOffset((i - 1) * (w + 14), 0), UDim2.fromOffset(w, 228), WHITE, 16, 5, 3)
		SeasonArt.BuildEmblem(t, "Emblem", UDim2.new(0.5, 0, 0, 12), 76, Vector2.new(0.5, 0))
		text(t, "TierName", { Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 24), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Text = string.upper(tier.Name) })
		text(t, "Range", { Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
		text(t, "Reward", { Position = UDim2.fromOffset(10, 146), Size = UDim2.new(1, -20, 0, 70), TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "" })
		local you = chip(t, "You", UDim2.new(0.5, 0, 0, -12), 22, INK, "YOU", 11, Vector2.new(0.5, 0))
		you.TextColor3 = YELLOW
		you.Visible = false
		you.ZIndex = 3
	end
	text(page, "PlaceHeading", { Position = UDim2.fromOffset(0, 296), Size = UDim2.fromOffset(400, 30), FontFace = HEAD, TextSize = 20, Text = "Placement · final standing" })
	local place = new("Frame", { Name = "Placement", Position = UDim2.fromOffset(0, 338), Size = UDim2.fromOffset(982, 170), BackgroundTransparency = 1 }, page)
	local pw = math.floor((982 - 3 * 14 - 6) / 4)
	for i, spec in {
		{ "Top100", "TOP 100", "Numbered title \"S0 #37\"", CREAM, "Title" },
		{ "Top10", "TOP 10", "Holo season photocard", C("D8C4FF"), "Photocard" },
		{ "Top3", "TOP 3", "Medal + a billboard on the street all next season", YELLOW, "Billboard" },
		{ "Champion", "#1", "Champion stage set: platform, stage skin + mics", PINK, "Stage" },
	} do
		local t = card(place, spec[1], UDim2.fromOffset((i - 1) * (pw + 14), 0), UDim2.fromOffset(pw, 156), WHITE, 16, 5, 3)
		local badge = new("TextLabel", { Name = "Badge", Position = UDim2.fromOffset(14, 16), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = spec[4], FontFace = HEAD, TextSize = 20, TextColor3 = INK, Text = spec[2] }, t)
		corner(badge, 10)
		stroke(badge, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, badge)
		icon(t, "Icon", spec[5], UDim2.new(1, -12, 0, 8), 56, Vector2.new(1, 0))
		text(t, "Reward", { Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -28, 0, 60), TextSize = 15, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = spec[3] })
	end
end

function Build.Season(frames: Instance)
	local root, panel = screen(frames, "Season", 1040, 620)
	local W = 1040
	local header = roundedHeader(panel, W, 64, PINK, 18)
	text(header, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(220, 64), FontFace = HEAD, TextSize = 24, Text = "PRE-DEBUT" })
	local tabs = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(212, 13), Size = UDim2.fromOffset(460, 38), BackgroundTransparency = 1 }, header)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, name in { "Track", "Ranks", "Rewards" } do
		local t = new("TextButton", { Name = name, LayoutOrder = i, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, BackgroundTransparency = 0.55, AutoButtonColor = false, FontFace = HEAD, TextSize = 14, TextColor3 = INK, Text = string.upper(name) }, tabs)
		corner(t, 10)
		stroke(t, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, t)
		chipIcon(t, ({ Track = "Stars", Ranks = "Ranks", Rewards = "Chest" })[name], 26)
		t:SetAttribute("NoButtonScale", true)
	end
	local days = chip(header, "Days", UDim2.new(1, -70, 0.5, 0), 26, INK, "Pre-season", 14, Vector2.new(1, 0.5))
	days.TextColor3 = YELLOW
	chipIcon(days, "Days", 22)

	local pages = new("Frame", { Name = "Pages", Position = UDim2.fromOffset(28, 67 + 16), Size = UDim2.fromOffset(982, 519), BackgroundTransparency = 1 }, panel)
	for _, spec in { { "Track", trackPage }, { "Ranks", ranksPage }, { "Rewards", rewardsPage } } do
		local page = new("Frame", { Name = spec[1], Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = spec[1] == "Track" }, pages)
		spec[2](page)
	end
	return root
end

-- [[ Banner picker ]]

function Build.Banners(frames: Instance)
	local root, panel = screen(frames, "Banners", 1000, 600)
	local W = 1000
	local header = roundedHeader(panel, W, 64, LILAC, 18)
	text(header, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(120, 64), FontFace = HEAD, TextSize = 26, Text = "STYLE" })
	-- SETS (banner + photocard) / BANNERS / CARDS
	local tabs = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(136, 13), Size = UDim2.fromOffset(380, 38), BackgroundTransparency = 1 }, header)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, spec in { { "Sets", "SETS" }, { "Banners", "BANNERS" }, { "Cards", "PHOTOCARDS" } } do
		local t = new("TextButton", { Name = spec[1], LayoutOrder = i, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, BackgroundTransparency = 0.55, AutoButtonColor = false, FontFace = HEAD, TextSize = 14, TextColor3 = INK, Text = spec[2] }, tabs)
		corner(t, 10)
		stroke(t, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, t)
		t:SetAttribute("NoButtonScale", true)
	end
	-- how many you own on the open tab: a quiet caption straight after the tabs
	text(tabs, "Owned", { LayoutOrder = 10, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "3 sets" })
	-- pager: ‹ 1 / 2 › left of Close; BannersController hides the arrows at either end
	local pager = new("Frame", { Name = "Pager", Position = UDim2.fromOffset(W - 14 - 42 - 18 - 150, 13), Size = UDim2.fromOffset(150, 38), BackgroundTransparency = 1 }, header)
	for i, spec in { { "Prev", 0 }, { "Next", 150 - 38 } } do
		local b = button(pager, spec[1], spec[2], 0, 38, 38, WHITE, if i == 1 then "‹" else "›", 22, 3)
		b.FontFace = HEAD
	end
	text(pager, "Page", { Position = UDim2.fromOffset(38, 0), Size = UDim2.fromOffset(150 - 76, 38), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })

	local left = new("Frame", { Name = "Preview", Position = UDim2.fromOffset(22, 67 + 18), Size = UDim2.fromOffset(300, 495), BackgroundTransparency = 1 }, panel)
	text(left, "Heading", { Size = UDim2.fromOffset(200, 24), FontFace = HEAD, TextSize = 18, Text = "Preview" })
	local pc = card(left, "Card", UDim2.fromOffset(0, 34), UDim2.fromOffset(294, 176), CREAM, 18, 6, 4)
	SeasonArt.BuildBanner(pc, "Banner", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 100), 18, true)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = INK, BorderSizePixel = 0 }, pc)
	local photo = card(pc, "Photo", UDim2.fromOffset(14, 52), UDim2.fromOffset(66, 82), WHITE, 10, 0, 3)
	photo.Rotation = -3
	P.Photo(photo, UDim2.fromOffset(5, 5), UDim2.new(1, -10, 1, -10), 2)
	SeasonArt.BuildCardSkin(photo, photo.Photo, 10, false)
	chip(pc, "PlayerName", UDim2.fromOffset(92, 74), 30, CREAM, "Player", 18)
	SeasonArt.BuildChip(pc, "Tier", UDim2.fromOffset(92, 116), 24)
	local info = card(left, "Info", UDim2.fromOffset(0, 232), UDim2.fromOffset(294, 110), WHITE, 12, 0, 3)
	text(info, "BannerName", { Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 24), FontFace = HEAD, TextSize = 18, Text = "Sky" })
	text(info, "Source", { Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -28, 0, 56), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "Default · pick any. Shows on your profile, inspect card, PreDuel and Results." })
	button(left, "Equip", 0, 437, 294, 56, MINT, "EQUIP", 20)

	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(346, 67 + 18), Size = UDim2.fromOffset(632, 495), BackgroundTransparency = 1 }, panel)
	-- 4 × 3 a page (BANNERS_PER_PAGE); BannersController places and pages them
	local cw, ch, g = math.floor((632 - 3 * 12) / 4), 150, 12
	local perPage = SeasonConstants.BANNERS_PER_PAGE
	for i, spec in SeasonConstants.BANNERS do
		local slot = (i - 1) % perPage
		local col, rowN = slot % 4, math.floor(slot / 4)
		local b = new("TextButton", { Name = spec.Id, Position = UDim2.fromOffset(col * (cw + g), rowN * (ch + 18)), Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "", Visible = i <= perPage }, grid)
		corner(b, 14)
		stroke(b, 3)
		b:SetAttribute("NoButtonScale", true)
		local art = SeasonArt.BuildBanner(b, "Banner", UDim2.fromOffset(9, 9), UDim2.new(1, -18, 0, 74), 10, false)
		stroke(art, 3)
		local lock = new("Frame", { Name = "Lock", Size = UDim2.fromScale(1, 1), BackgroundColor3 = CREAM, BackgroundTransparency = 0.4, Visible = false, ZIndex = 3 }, art)
		corner(lock, 10)
		local lk = new("TextLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = HEAD, TextSize = 11, TextColor3 = CREAM, Text = "LOCKED", ZIndex = 3 }, lock)
		corner(lk, 7)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, lk)
		local eq = chip(art, "Equipped", UDim2.new(1, -6, 0, 6), 18, INK, "EQUIPPED", 10, Vector2.new(1, 0))
		eq.TextColor3 = MINT
		eq.ZIndex = 4
		eq.Visible = false
		text(b, "BannerName", { Position = UDim2.fromOffset(10, 90), Size = UDim2.new(1, -20, 0, 22), FontFace = HEAD, TextSize = 14, Text = spec.Name })
		local tag = chip(art, "Tag", UDim2.fromOffset(6, 6), 18, WHITE, spec.Tag, 10)
		tag.ZIndex = 4
		text(b, "Source", { Position = UDim2.fromOffset(10, 114), Size = UDim2.new(1, -20, 0, 30), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = spec.Source })
	end

	-- a small photocard: card frame + photo window (+ skin) in the Profile card's proportions
	local function mini(parent: Instance, pos: UDim2, w: number, h: number, rot: number, withDeco: boolean): Frame
		local m = new("Frame", { Name = "Card", Position = pos, Size = UDim2.fromOffset(w, h), Rotation = rot, BackgroundColor3 = WHITE }, parent)
		corner(m, 8)
		stroke(m, 3)
		local ph = P.Photo(m, UDim2.fromScale(12 / 280, 12 / 334), UDim2.fromScale(256 / 280, 228 / 334), 2)
		ph:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 5)
		SeasonArt.BuildCardSkin(m, ph, 8, withDeco)
		return m
	end
	local function tile(parent: Instance, i: number, id: string): TextButton
		local slot = (i - 1) % perPage
		local col, rowN = slot % 4, math.floor(slot / 4)
		local b = new("TextButton", { Name = id, Position = UDim2.fromOffset(col * (cw + g), rowN * (ch + 18)), Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "", Visible = i <= perPage }, parent)
		corner(b, 14)
		stroke(b, 3)
		b:SetAttribute("NoButtonScale", true)
		return b
	end

	-- photocards: the card standing in the tile, name under it
	local cards = new("Frame", { Name = "Cards", Position = grid.Position, Size = grid.Size, BackgroundTransparency = 1, Visible = false }, panel)
	local n = 0
	for _, spec in SeasonConstants.BANNERS do
		if SeasonConstants.Photocard(spec.Id) then
			n += 1
			local b = tile(cards, n, spec.Id)
			mini(b, UDim2.new(0.5, -42, 0, 8), 84, 100, 0, true)
			text(b, "CardName", { Position = UDim2.fromOffset(8, 114), Size = UDim2.new(1, -16, 0, 22), FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = spec.Name })
			local tag = chip(b, "Tag", UDim2.fromOffset(6, 6), 18, WHITE, spec.Tag, 10)
			tag.ZIndex = 4
			local eq = chip(b, "Equipped", UDim2.new(1, -6, 0, 6), 18, INK, "ON", 10, Vector2.new(1, 0))
			eq.TextColor3 = MINT
			eq.ZIndex = 4
			eq.Visible = false
		end
	end

	-- sets: the banner with its photocard tucked over the corner
	local sets = new("Frame", { Name = "Sets", Position = grid.Position, Size = grid.Size, BackgroundTransparency = 1, Visible = false }, panel)
	n = 0
	for _, spec in SeasonConstants.BANNERS do
		if SeasonConstants.Photocard(spec.Id) then
			n += 1
			local b = tile(sets, n, spec.Id)
			local art = SeasonArt.BuildBanner(b, "Banner", UDim2.fromOffset(9, 9), UDim2.new(1, -18, 0, 62), 10, false)
			stroke(art, 3)
			mini(b, UDim2.fromOffset(12, 44), 50, 60, -5, false)
			-- two lines for the long names ("Chrome Dream", "S0 Comeback")
			text(b, "SetName", { Position = UDim2.fromOffset(70, 72), Size = UDim2.new(1, -76, 0, 30), FontFace = HEAD, TextSize = 12, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Bottom, LineHeight = 0.9, Text = spec.Name })
			text(b, "Kind", { Position = UDim2.fromOffset(70, 104), Size = UDim2.new(1, -76, 0, 18), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "banner + card" })
			local tag = chip(art, "Tag", UDim2.fromOffset(6, 6), 18, WHITE, spec.Tag, 10)
			tag.ZIndex = 4
			local eq = chip(art, "Equipped", UDim2.new(1, -6, 0, 6), 18, INK, "EQUIPPED", 10, Vector2.new(1, 0))
			eq.TextColor3 = MINT
			eq.ZIndex = 4
			eq.Visible = false
		end
	end
	return root
end

-- Photocards: the card skin (Skin + photo Bg + Deco stickers) on the Profile photocard and the
-- inspect card's small one
function Build.Photocards(frames: Instance)
	local face = frames.Profile.Panel.Content.Left.Photocard.Face
	SeasonArt.BuildCardSkin(face, face.Photo, 20, true)
	local pc = frames.PlayerCard.Panel.Top.Photocard
	SeasonArt.BuildCardSkin(pc, pc.Photo, 12, false)
end

-- Shop: "Banners + photocards" (StyleTitle + Style) after Stages + mics. Each card: the banner
-- strip with its photocard tilted in front (animated ones move), the name, the Set button
-- (+ a SAVE sticker) and the two halves' buttons (a small kind label over the price).
-- Made from the stage-set cards so it matches them.
function Build.ShopStyle(frames: Instance)
	local scroll = frames.Shop.Panel.Scroll
	local after = scroll.Pieces.LayoutOrder
	if not scroll:FindFirstChild("StyleTitle") then
		-- first build: make room for two more sections before Coins
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") and child.LayoutOrder > after then
				child.LayoutOrder += 2
			end
		end
	end
	clear(scroll, "StyleTitle")
	clear(scroll, "Style")
	local title = scroll.SetsTitle:Clone()
	title.Name = "StyleTitle"
	title.LayoutOrder = after + 1
	title.Title.Text = "Banners + photocards"
	title.Parent = scroll
	local hint = title.Chip:Clone()
	hint.Name = "Hint"
	hint.LayoutOrder = title.Chip.LayoutOrder + 1
	hint.BackgroundTransparency = 1
	hint.TextColor3 = MUTED
	hint.Text = "Equip them from STYLE on your profile"
	for _, d in hint:GetChildren() do
		if d:IsA("UIStroke") then
			d:Destroy()
		end
	end
	hint.Parent = title

	local W, H = 223, 318
	local section = new("Frame", { Name = "Style", LayoutOrder = after + 2, Size = UDim2.new(1, 0, 0, H + 5), BackgroundTransparency = 1 }, scroll)
	local template = scroll.Sets.Set1
	for i = 1, 4 do
		local x = (i - 1) * (W + 16)
		local sh = new("Frame", { Name = "Style" .. i .. "Shadow", Position = UDim2.fromOffset(x + 5, 5), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, BorderSizePixel = 0 }, section)
		corner(sh, 16)
		local c = new("Frame", { Name = "Style" .. i, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(W, H), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, section)
		corner(c, 16)
		stroke(c, 3)
		-- art: banner on top, the photocard standing in front of it
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(W - 20, 160), BackgroundColor3 = CREAM, ClipsDescendants = true }, c)
		corner(art, 10)
		stroke(art, 2)
		local banner = SeasonArt.BuildBanner(art, "Banner", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 64), 0, false)
		new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 2 }, art)
		banner.ZIndex = 1
		local pcShadow = new("Frame", { Name = "CardShadow", Position = UDim2.new(0.5, -46 + 3, 0, 42 + 3), Size = UDim2.fromOffset(92, 110), Rotation = -5, BackgroundColor3 = INK, ZIndex = 3 }, art)
		corner(pcShadow, 8)
		local m = new("Frame", { Name = "Card", Position = UDim2.new(0.5, -46, 0, 42), Size = UDim2.fromOffset(92, 110), Rotation = -5, BackgroundColor3 = WHITE, ZIndex = 3 }, art)
		corner(m, 8)
		stroke(m, 2)
		local ph = P.Photo(m, UDim2.fromScale(12 / 280, 12 / 334), UDim2.fromScale(256 / 280, 228 / 334), 2)
		ph:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 5)
		SeasonArt.BuildCardSkin(m, ph, 8, true)
		local anim = chip(art, "Animated", UDim2.new(1, -6, 0, 6), 18, PINK, "ANIMATED", 10, Vector2.new(1, 0))
		anim.ZIndex = 6
		local name = template.SetName:Clone()
		name.Position = UDim2.fromOffset(12, 178)
		name.Size = UDim2.fromOffset(W - 24, 22)
		name.Text = "Banner"
		name.Parent = c
		-- Set: the big button (Icon + Label, like the set cards' Action)
		local actSh = template.ActionShadow:Clone()
		actSh.Name = "SetBuyShadow"
		actSh.Size = UDim2.fromOffset(W - 20, 42)
		actSh.Position = UDim2.fromOffset(10 + 3 + actSh.AnchorPoint.X * (W - 20), 206 + 3 + actSh.AnchorPoint.Y * 42)
		actSh.Parent = c
		local act = template.Action:Clone()
		act.Name = "SetBuy"
		act.Position = UDim2.fromOffset(10 + act.AnchorPoint.X * (W - 20), 206 + act.AnchorPoint.Y * 42)
		act.Size = UDim2.fromOffset(W - 20, 42)
		act.Parent = c
		-- "Set" / "Finish set" before the coin + price
		local list = act:FindFirstChildOfClass("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		local pre = act.Label:Clone()
		pre.Name = "Pre"
		pre.LayoutOrder = 0
		pre.Text = "Set"
		pre.Parent = act
		act.Icon.LayoutOrder = 1
		act.Label.LayoutOrder = 2
		local save = chip(c, "Save", UDim2.fromOffset(W - 6, 196), 18, PINK, "SAVE 200", 10, Vector2.new(1, 0))
		save.FontFace = HEAD
		save.Rotation = 5
		save.ZIndex = 5
		-- the halves: a small kind label over coin + price ("Owned" once it's yours)
		for j, half in { "Banner", "Photocard" } do
			local bw = (W - 20 - 8) / 2
			local bx = 10 + (j - 1) * (bw + 8)
			local hs = new("Frame", { Name = half .. "BuyShadow", Position = UDim2.fromOffset(bx + 2, 260 + 2), Size = UDim2.fromOffset(bw, 44), BackgroundColor3 = INK }, c)
			corner(hs, 9)
			local b = new("TextButton", { Name = half .. "Buy", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(bx + bw / 2, 260 + 22), Size = UDim2.fromOffset(bw, 44), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "" }, c)
			corner(b, 9)
			stroke(b, 2)
			text(b, "Kind", { Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 13), FontFace = BODY, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = if half == "Banner" then "Banner" else "Card" })
			local row = new("Frame", { Name = "Row", Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }, b)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, row)
			new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit }, row)
			text(row, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 13, Text = "800" })
		end
	end
	return section
end

-- Season Track rewards on existing screens (board "Seasons 12"):
--   Roll  – Header.Tickets (a counter like Balance), Stage.TicketStrip (ticket icon, "2 roll
--           tickets", ROLL A GROUP) and Picker: a full-screen overlay with its own panel:
--           company tabs (Tabs.Tab1..8), 12 group tiles (Grid.Tile1..12: Art + Initials, GroupName,
--           Owned, Bar.Fill, Check), the pager, an Info line and the RollGroup button
--   Index – Header.Upgrade (UPGRADE ×n, beside ROLL SONGS), Header.UpgradeLeft ("1 left" next to
--           the title in upgrade mode) and Header.Confirm (UPGRADE THIS CARD, in ROLL SONGS' place);
--           Content.Playing: the Now Playing bar (board "Rainbow cards · background music") that
--           takes the footer's hint / title-progress spot left of the pager while a card plays:
--           Eq bars, Kicker, SongName, SetBg (SET AS / USE DEFAULT MUSIC), Note, Stop (✕)
-- RollController/Picker and IndexController fill them.
Build.PICKER_TABS = 8
Build.PICKER_TILES = 12
function Build.SeasonRewards(frames: Instance)
	-- [[ Roll ]]
	local roll = frames.Roll
	local rp = roll.Panel
	clear(rp.Header, "Tickets")
	local tickets = rp.Header.Balance:Clone()
	tickets.Name = "Tickets"
	tickets.Icon.Image = ICONS.Ticket
	tickets.Amount.Text = "0"
	tickets.Visible = false
	tickets.Parent = rp.Header

	local stage = rp.Pages.Roll.Stage
	clear(stage, "TicketStrip")
	local strip = new("Frame", { Name = "TicketStrip", Position = UDim2.fromOffset(18, 380), Size = UDim2.new(1, -36, 0, 122), BackgroundColor3 = C("FFF6D6"), Visible = false }, stage)
	corner(strip, 14)
	stroke(strip, 3)
	icon(strip, "Icon", "Ticket", UDim2.fromOffset(10, 6), 52)
	text(strip, "Heading", { Position = UDim2.fromOffset(68, 12), Size = UDim2.new(1, -80, 0, 22), FontFace = HEAD, TextSize = 17, Text = "2 roll tickets" })
	text(strip, "Sub", { Position = UDim2.fromOffset(68, 36), Size = UDim2.new(1, -80, 0, 16), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Free roll from a group you choose" })
	button(strip, "RollGroup", 12, 64, 430 - 24 - 4, 44, LILAC, "ROLL A GROUP · 1 TICKET", 16, 4)

	-- Pick a Group: over the whole Roll screen
	clear(roll, "Picker")
	local picker = new("Frame", { Name = "Picker", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 10 }, roll)
	new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = true }, picker)
	local W, H = 960, 620
	local x0, y0 = (1280 - W) / 2, (720 - H) / 2
	local psh = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(x0 + 8, y0 + 8), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, BorderSizePixel = 0 }, picker)
	corner(psh, 18)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(x0, y0), Size = UDim2.fromOffset(W, H), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, picker)
	corner(panel, 18)
	stroke(panel, 3)
	local header = roundedHeader(panel, W, 64, LILAC, 18)
	text(header, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(240, 64), FontFace = HEAD, TextSize = 24, Text = "PICK A GROUP" })
	local hc = tickets:Clone()
	hc.Name = "Tickets"
	hc.Visible = true
	hc.AnchorPoint = Vector2.new(0, 0.5)
	hc.Position = UDim2.fromOffset(262, 32)
	hc.Parent = header

	local tabs = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(22, 82), Size = UDim2.new(1, -44, 0, 34), BackgroundTransparency = 1 }, panel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, tabs)
	for i = 1, Build.PICKER_TABS do
		local t = new("TextButton", { Name = "Tab" .. i, LayoutOrder = i, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, AutoButtonColor = false, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = "All" }, tabs)
		corner(t, 17)
		stroke(t, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, t)
		t:SetAttribute("NoButtonScale", true)
	end

	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(22, 134), Size = UDim2.new(1, -44, 0, 330), BackgroundTransparency = 1 }, panel)
	local tw, th, gap = (W - 44 - 3 * 14) / 4, 96, 14
	for i = 1, Build.PICKER_TILES do
		local col, rowN = (i - 1) % 4, math.floor((i - 1) / 4)
		local sh = new("Frame", { Name = "Tile" .. i .. "Shadow", Position = UDim2.fromOffset(col * (tw + gap) + 3, rowN * (th + gap) + 3), Size = UDim2.fromOffset(tw, th), BackgroundColor3 = INK }, grid)
		corner(sh, 14)
		local t = new("TextButton", { Name = "Tile" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(col * (tw + gap) + tw / 2, rowN * (th + gap) + th / 2), Size = UDim2.fromOffset(tw, th), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "" }, grid)
		corner(t, 14)
		stroke(t, 3)
		t:SetAttribute("NoButtonScale", true)
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 18), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = BLUE }, t)
		corner(art, 12)
		stroke(art, 3)
		text(art, "Initials", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Text = "BT" })
		text(t, "GroupName", { Position = UDim2.fromOffset(76, 16), Size = UDim2.new(1, -86, 0, 20), FontFace = HEAD, TextSize = 14, Text = "Group" })
		text(t, "Owned", { Position = UDim2.fromOffset(76, 38), Size = UDim2.new(1, -86, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "0 / 0 owned" })
		local b = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(76, 60), Size = UDim2.new(1, -88, 0, 12), BackgroundColor3 = WHITE, ClipsDescendants = true }, t)
		corner(b, 6)
		stroke(b, 2)
		local f = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = MINT, BorderSizePixel = 0 }, b)
		corner(f, 6)
		local check = chip(t, "Check", UDim2.new(1, 8, 0, -10), 22, MINT, "✓", 12, Vector2.new(1, 0))
		check.FontFace = HEAD
		check.ZIndex = 3
		check.Visible = false
	end

	-- footer: pager · info · ROLL <GROUP> (uses 1 ticket)
	local fy = H - 18 - 60
	button(panel, "Prev", 22, fy + 10, 40, 40, WHITE, "‹", 22, 3)
	text(panel, "Page", { Position = UDim2.fromOffset(66, fy + 10), Size = UDim2.fromOffset(56, 40), FontFace = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })
	button(panel, "Next", 126, fy + 10, 40, 40, WHITE, "›", 22, 3)
	text(panel, "Info", { Position = UDim2.fromOffset(186, fy), Size = UDim2.fromOffset(W - 186 - 22 - 270 - 14, 60), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, RichText = true, Text = "Pick a group to roll." })
	local go = button(panel, "RollGroup", W - 22 - 270, fy, 270, 60, MINT, "", 18, 4)
	text(go, "Label", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 24), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Text = "ROLL" })
	local sub = new("Frame", { Name = "Sub", Position = UDim2.fromOffset(0, 33), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }, go)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sub)
	icon(sub, "Icon", "Ticket", UDim2.fromOffset(0, 0), 22).LayoutOrder = 1
	text(sub, "Text", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, FontFace = BODY, TextSize = 13, Text = "uses 1 ticket" })

	-- [[ Index ]]
	local ih = frames.Index.Panel.Header
	for _, name in { "Upgrade", "UpgradeShadow", "UpgradeLeft", "Confirm", "ConfirmShadow" } do
		clear(ih, name)
	end
	local rollB = ih.Roll
	local rw, rh = rollB.Size.X.Offset, rollB.Size.Y.Offset
	local rx, ry = rollB.Position.X.Offset - rw / 2, rollB.Position.Y.Offset - rh / 2
	-- UPGRADE ×n, left of ROLL SONGS (only while you have upgrades)
	local up = button(ih, "Upgrade", rx - 14 - 170, ry, 170, rh, BLUE, "", 16, 3)
	up.Visible = false
	ih.UpgradeShadow.Visible = false
	icon(up, "Icon", "Upgrade", UDim2.fromOffset(10, rh / 2), 28, Vector2.new(0, 0.5))
	text(up, "Label", { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -48, 1, 0), FontFace = HEAD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Text = "UPGRADE ×1" })
	-- upgrade mode: "1 left" by the title, UPGRADE THIS CARD where ROLL SONGS was
	local left = chip(ih, "UpgradeLeft", UDim2.fromOffset(380, 32), 30, WHITE, "1 left", 15, Vector2.new(0, 0.5))
	left.FontFace = HEAD
	chipIcon(left, "Upgrade", 22)
	left.Visible = false
	local confirm = button(ih, "Confirm", rx - 60, ry, rw + 60, rh, MINT, "UPGRADE THIS CARD", 15, 3)
	confirm.Visible = false
	ih.ConfirmShadow.Visible = false

	-- the Now Playing bar: footer, left of the pager (the pager never moves)
	local content = frames.Index.Panel.Content
	clear(content, "Playing")
	clear(content, "PlayingShadow")
	local cw = content.Size.X.Offset
	local bw, bh, by = cw - 212, 42, content.Hint.Position.Y.Offset - 4
	local psh = new("Frame", { Name = "PlayingShadow", Position = UDim2.fromOffset(4, by + 4), Size = UDim2.fromOffset(bw, bh), BackgroundColor3 = INK, Visible = false }, content)
	corner(psh, 12)
	local bar = new("Frame", { Name = "Playing", Position = UDim2.fromOffset(0, by), Size = UDim2.fromOffset(bw, bh), BackgroundColor3 = WHITE, Visible = false }, content)
	corner(bar, 12)
	stroke(bar, 3)
	new("UIGradient", { Name = "Level", Rotation = 35, Enabled = false }, bar)
	local eq = new("Frame", { Name = "Eq", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(26, 22), BackgroundTransparency = 1 }, bar)
	for b = 1, 3 do
		local f = new("Frame", { Name = "Bar" .. b, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, (b - 1) * 9, 1, 0), Size = UDim2.new(0, 6, 0.6, 0), BackgroundColor3 = WHITE }, eq)
		corner(f, 2)
		stroke(f, 1.5)
	end
	text(bar, "Kicker", { Position = UDim2.fromOffset(48, 4), Size = UDim2.fromOffset(160, 13), FontFace = BODY_BOLD, TextSize = 10, TextColor3 = MUTED, Text = "NOW PLAYING" })
	text(bar, "SongName", { Position = UDim2.fromOffset(48, 17), Size = UDim2.new(1, -48 - 290, 0, 20), FontFace = HEAD, TextSize = 14, Text = "Song · Artist" })
	local sw = 236
	local setBg = button(bar, "SetBg", bw - 8 - 32 - 8 - sw, 5, sw, 30, WHITE, "SET AS BACKGROUND MUSIC", 11, 3)
	-- breathing room inside the outline: FitText scales the text to fill the box, which on
	-- phones ran it right into the edges
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, setBg)
	text(bar, "Note", { Position = UDim2.fromOffset(bw - 8 - 32 - 8 - 260, 3), Size = UDim2.fromOffset(260, 36), FontFace = BODY_BOLD, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, RichText = true, Text = "Rainbow cards can be your background music", Visible = false })
	local stop = new("ImageButton", { Name = "Stop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(bw - 8 - 16, bh / 2), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, bar)
	corner(stop, 9)
	stroke(stop, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, Image = CLOSE }, stop)

	-- (the inspect card shows no background music: it crowded the Showcase heading)
	clear(frames.PlayerCard.Panel.Body, "BgMusic")
	return picker
end

-- Season titles: the rounded "S0" box (TitleChip.BuildBadge) in every chip that shows a player's
-- own title: the Profile, the inspect card and the two queue walk-on cards. Hidden until a season
-- title (SeasonConstants.SEASON_TITLES) is painted into the chip.
function Build.SeasonTitleReward(frames: Instance)
	local right = frames.Season.Panel.Pages.Track.Right
	for _, holder in right.Milestones:GetChildren() do
		local art = holder:FindFirstChild("Face") and holder.Face:FindFirstChild("Art")
		if art then
			titleArt(art, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 16, 26, 15, false)
		end
	end
	for i = 1, 2 do
		titleArt(right.ComingUp["Big" .. i], UDim2.fromOffset(10, 18), UDim2.fromOffset(120, 58), 13, 20, 12, true)
	end
end

function Build.SeasonTitleBadges(frames: Instance)
	local chips = {
		frames.Profile.Panel.Content.Left.Photocard.Face.Chips.Title,
		frames.PlayerCard.Panel.Top.Chips.Title,
		frames.Queue.WalkOn.ChipA.Badges.Title,
		frames.Queue.WalkOn.ChipB.Badges.Title,
	}
	for _, chip in chips do
		TitleChip.BuildBadge(chip, chip.TextSize, chip.FontFace)
	end
end

-- [[ Patches on existing screens ]]

-- Profile: the lilac title bar becomes a 128-tall banner band; the photocard rises over it
function Build.Profile(frames: Instance)
	local panel = frames.Profile.Panel
	local header = panel.Header
	local H = 128
	header.Size = UDim2.new(1, 0, 0, H)
	header.BackgroundTransparency = 1
	local sq = header:FindFirstChild("SquareBottom")
	if sq then
		sq.Visible = false
	end
	clear(header, "Banner")
	local banner = SeasonArt.BuildBanner(header, "Banner", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), 18, true)
	banner.ZIndex = 0
	for _, d in banner:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 0
		end
	end
	panel.Rule.Position = UDim2.fromOffset(0, H)
	-- title + season chips sit right of the photocard, on cream so any banner reads
	local title = header.Title
	title.Position = UDim2.fromOffset(340, 18)
	title.Size = UDim2.fromOffset(0, 32)
	title.AutomaticSize = Enum.AutomaticSize.X
	title.BackgroundTransparency = 0
	title.BackgroundColor3 = CREAM
	title.TextSize = 20
	if not title:FindFirstChildOfClass("UICorner") then
		corner(title, 10)
		stroke(title, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, title)
	end
	clear(header, "SeasonTag")
	local tag = chip(header, "SeasonTag", UDim2.fromOffset(340, 64), 24, INK, "PRE-DEBUT", 13)
	tag.TextColor3 = CREAM
	clear(header, "BannerButton")
	clear(header, "BannerButtonShadow")
	-- EDIT (opens STYLE): just wide enough for the pencil + word, 40 tall so it's an easy tap on
	-- phones, pinned to the band's bottom-right corner
	local BW, BH = 96, 40
	local bb = button(header, "BannerButton", 1040 - 14 - BW, H - 12 - BH, BW, BH, CREAM, "", 14, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, bb)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = P.ICONS.Pencil }, bb)
	text(bb, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, BH), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 15, TextTruncate = Enum.TextTruncate.None, Text = "EDIT" })
	header.CloseShadow.Position = UDim2.fromOffset(1040 - 14 - 42 + 3, 14 + 3)
	header.Close.Position = UDim2.fromOffset(1040 - 14 - 21, 14 + 21)

	-- content moves down; the photocard column rises into the band
	local content = panel.Content
	local top = H + 3 + 14
	content.Position = UDim2.fromOffset(22, top)
	content.Size = UDim2.fromOffset(990, 620 - top - 14)
	content.ZIndex = 2
	local left = content.Left
	left.Position = UDim2.fromOffset(0, -112)
	left.Size = UDim2.fromOffset(300, 620 - top - 14 + 112)
	-- left column, sized to the SeasonProfile board: a 268 × 320 photocard (photo, name, then
	-- title + tier chips side by side in a centred Chips row), XP under it, Change Title last.
	-- Everything is 268 wide and centred in the 300 column. ProfileController paints face.Chips.*
	local X, CW, CARD_H, PAD, GAP = 16, 268, 320, 12, 7
	local NAME_H, CHIP_H = 28, 27
	local PHOTO_H = CARD_H - PAD * 2 - NAME_H - CHIP_H - GAP * 2 -- the 4px UIStroke sits outside
	local pcard = left.Photocard
	pcard.Position = UDim2.fromOffset(X, 0)
	pcard.Size = UDim2.fromOffset(CW, CARD_H)
	local face = pcard.Face
	face.Photo.Position = UDim2.fromOffset(PAD, PAD)
	face.Photo.Size = UDim2.new(1, -PAD * 2, 0, PHOTO_H)
	local nameY = PAD + PHOTO_H + GAP
	face.PlayerName.Position = UDim2.fromOffset(PAD, nameY)
	face.PlayerName.Size = UDim2.new(1, -PAD * 2, 0, NAME_H)
	face.PlayerName.TextSize = 25
	-- level sticker hangs off the top-right corner (62, tilted the other way)
	local lv = face.LevelBadge
	lv.Size = UDim2.fromOffset(62, 62)
	lv.Position = UDim2.fromOffset(CW + 16 - 31, -16 + 31)
	lv.Rotation = 6
	local oldChips = face:FindFirstChild("Chips")
	local titleChip = face:FindFirstChild("Title") or (oldChips and oldChips:FindFirstChild("Title"))
	titleChip.Parent = face
	clear(face, "Tier")
	clear(face, "Chips")
	local chips = new("Frame", { Name = "Chips", Position = UDim2.fromOffset(PAD, nameY + NAME_H + GAP), Size = UDim2.new(1, -PAD * 2, 0, CHIP_H), BackgroundTransparency = 1, ZIndex = 3 }, face)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, chips) -- 12: the chips' 3px strokes sit outside, leaving a 6px gap
	titleChip.AnchorPoint = Vector2.zero
	titleChip.Position = UDim2.new()
	titleChip.Size = UDim2.fromOffset(0, CHIP_H)
	titleChip.TextSize = 16
	titleChip.LayoutOrder = 1
	titleChip.Parent = chips
	local tc = SeasonArt.BuildChip(chips, "Tier", UDim2.new(), CHIP_H)
	tc.LayoutOrder = 2
	tc.ZIndex = 3
	-- XP: 16 under the card (gap 10 + 6), label row then an 18-tall bar
	local xpY = CARD_H + 16
	local xp = left.XP
	xp.Position = UDim2.fromOffset(X, xpY)
	xp.Size = UDim2.fromOffset(CW, 42)
	xp.Track.Position = UDim2.fromOffset(0, 24)
	xp.Track.Size = UDim2.new(1, 0, 0, 18)
	-- Change Title: 268 × 52 under the XP (gap 10)
	local ctY, CT_H = xpY + 42 + 10, 52
	left.ChangeTitle.Size = UDim2.fromOffset(CW, CT_H)
	left.ChangeTitle.Position = UDim2.fromOffset(X + CW / 2, ctY + CT_H / 2)
	left.ChangeTitle.TextSize = 19
	left.ChangeTitleShadow.Size = UDim2.fromOffset(CW, CT_H)
	left.ChangeTitleShadow.Position = UDim2.fromOffset(X + 5, ctY + 5)

	-- right column: tighter tiles + cards so it all fits under the taller band
	local right = content.Right
	local stats = right.Stats
	local tw, th, gap = math.floor((664 - 2 * 14 - 4) / 3), 78, 12
	for i, spec in P.STATS do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local tile = stats:FindFirstChild(spec.Name)
		local shadow = stats:FindFirstChild(spec.Name .. "Shadow")
		if tile then
			tile.Position = UDim2.fromOffset(col * (tw + gap), row * (th + gap))
			tile.Size = UDim2.fromOffset(tw, th)
			tile.Label.Position = UDim2.fromOffset(16, 8)
			tile.Value.Position = UDim2.fromOffset(16, 24)
			tile.Value.Size = UDim2.new(1, -32, 0, 30)
			tile.Value.TextSize = 26
			tile.Sub.Position = UDim2.fromOffset(16, 54)
		end
		if shadow then
			shadow.Position = UDim2.fromOffset(col * (tw + gap) + 4, row * (th + gap) + 4)
			shadow.Size = UDim2.fromOffset(tw, th)
		end
	end
	stats.Size = UDim2.fromOffset(664, 2 * th + gap + 6)
	local y = 42 + 2 * th + gap + 14
	right.ShowcaseHeading.Position = UDim2.fromOffset(0, y)
	right.ShowcaseSub.Position = UDim2.fromOffset(142, y + 4)
	local edit = right.Edit
	edit.Position = UDim2.fromOffset(664 - 52 - 4, y + 18)
	local es = right:FindFirstChild("EditShadow")
	if es then
		es.Position = UDim2.fromOffset(664 - 104 - 4 + 3, y + 3)
	end
	local showcase = right.Showcase
	showcase.Position = UDim2.fromOffset(0, y + 44)
	for i = 1, P.SHOWCASE do
		local holder = showcase:FindFirstChild("Card" .. i)
		if holder then
			holder.Size = UDim2.fromOffset(108, 152)
		end
	end
	content.DimLeft.Position = UDim2.fromOffset(0, -112)
	content.DimLeft.Size = UDim2.fromOffset(300, content.Size.Y.Offset + 112)
	content.DimStats.Size = UDim2.fromOffset(672, 42 + stats.Size.Y.Offset)
end

-- PlayerCard (inspect): the top strip is the player's banner; name on a cream chip; tier chip
function Build.PlayerCard(frames: Instance)
	local panel = frames.PlayerCard.Panel
	local top = panel.Top
	top.BackgroundTransparency = 1
	local sq = top:FindFirstChild("SquareBottom")
	if sq then
		sq.Visible = false
	end
	clear(top, "Banner")
	local banner = SeasonArt.BuildBanner(top, "Banner", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), 24, true)
	banner.ZIndex = 0
	for _, d in banner:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 0
		end
	end
	local name = top.PlayerName
	name.AutomaticSize = Enum.AutomaticSize.X
	name.Size = UDim2.fromOffset(0, 32)
	name.BackgroundTransparency = 0
	name.BackgroundColor3 = CREAM
	if not name:FindFirstChildOfClass("UICorner") then
		corner(name, 10)
		stroke(name, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, name)
	end
	local chips = top.Chips
	clear(chips, "Tier")
	local tc = SeasonArt.BuildChip(chips, "Tier", UDim2.new(), 26)
	tc.LayoutOrder = 3
	local rank = top.Rank
	rank.BackgroundTransparency = 0
	rank.BackgroundColor3 = CREAM
	rank.AutomaticSize = Enum.AutomaticSize.X
	rank.Size = UDim2.fromOffset(0, 22)
	if not rank:FindFirstChildOfClass("UICorner") then
		corner(rank, 8)
		stroke(rank, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, rank)
	end
end

-- PreDuel: each player card gets a banner strip along its top and a tier chip on it
function Build.PreDuel(frames: Instance)
	local root = frames.PreDuel
	for _, side in { "You", "Rival" } do
		local c = root[side]
		local shadow = root[side .. "Shadow"]
		c.Position = UDim2.fromOffset(c.Position.X.Offset, 86)
		c.Size = UDim2.fromOffset(195, 100)
		shadow.Position = UDim2.fromOffset(shadow.Position.X.Offset, 90)
		shadow.Size = c.Size
		local r = c:FindFirstChildOfClass("UICorner")
		local radius = if r then r.CornerRadius.Offset else 14
		clear(c, "Banner")
		local b = SeasonArt.BuildBanner(c, "Banner", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 34), radius, true)
		b.ZIndex = 0
		for _, d in b:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 0
			end
		end
		clear(c, "BannerRule")
		new("Frame", { Name = "BannerRule", Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 0 }, c)
		local mirror = side == "Rival"
		c.Avatar.Position = UDim2.fromOffset(if mirror then 124 else 11, 22)
		c:FindFirstChild("Name").Position = UDim2.fromOffset(if mirror then 11 else 83, 44)
		c.Sub.Position = UDim2.fromOffset(if mirror then 11 else 83, 66)
		clear(c, "Tier")
		local tc = SeasonArt.BuildChip(c, "Tier", UDim2.new(if mirror then 0 else 1, if mirror then 8 else -8, 0, 6), 22, Vector2.new(if mirror then 0 else 1, 0))
		tc.ZIndex = 2
	end
	local vs = root.VS
	vs.Position = UDim2.fromOffset(vs.Position.X.Offset, 114)
end

-- Results: the Season bar under the table (duels: SP change; solo: Stars only)
function Build.Results(frames: Instance)
	local panel = frames.Results.Panel
	clear(panel, "Season")
	clear(panel, "SeasonShadow")
	local s = card(panel, "Season", UDim2.fromOffset(27, 566), UDim2.fromOffset(632, 40), WHITE, 12, 3, 3)
	SeasonArt.BuildChip(s, "Tier", UDim2.fromOffset(6, 7), 26)
	text(s, "Delta", { Position = UDim2.fromOffset(150, 0), Size = UDim2.fromOffset(70, 40), FontFace = HEAD, TextSize = 18, Text = "+29" })
	text(s, "Note", { Position = UDim2.fromOffset(150, 0), Size = UDim2.fromOffset(330, 40), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "Solo practice doesn't change SP", Visible = false })
	bar(s, "Bar", UDim2.fromOffset(222, 13), UDim2.fromOffset(170, 14), YELLOW, 2)
	text(s, "Range", { Position = UDim2.fromOffset(398, 0), Size = UDim2.fromOffset(120, 40), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "1,041 / 1,200" })
	local stars = new("TextLabel", { Name = "Stars", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = YELLOW, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = "+20" }, s)
	corner(stars, 9)
	stroke(stars, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, stars)
	chipIcon(stars, "Stars", 20)
	local promo = new("TextLabel", { Name = "Promoted", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 40, 0, 4), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Rotation = -3, BackgroundColor3 = LILAC, FontFace = HEAD, TextSize = 15, TextColor3 = INK, Text = "★ PROMOTED · IDOL I", Visible = false, ZIndex = 3 }, s)
	corner(promo, 10)
	stroke(promo, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, promo)
end

-- HUD: the season card under Roll / UGC ("HUD · Season button, no rank", option B): a star
-- tile, the season name, a bar for how much of the season has gone and the days left. No
-- tier or SP; it just opens the Season screen.
function Build.HUD(interface: Instance)
	local hud = interface:FindFirstChild("HUD") or interface.Parent:FindFirstChild("HUD")
	local topLeft = hud.TopLeft
	clear(topLeft, "Season")
	clear(topLeft, "SeasonShadow")
	local x, y, w, h = 20, 424, 178, 64
	local sh = new("Frame", { Name = "SeasonShadow", Position = UDim2.fromOffset(x + 4, y + 4), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, topLeft)
	corner(sh, 12)
	local b = new("TextButton", { Name = "Season", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2, y + h / 2), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "" }, topLeft)
	corner(b, 12)
	stroke(b, 3)
	local tile = new("Frame", { Name = "Tile", Position = UDim2.fromOffset(6, 7), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = LILAC }, b)
	corner(tile, 12)
	stroke(tile, 2)
	icon(tile, "Icon", "Stars", UDim2.fromScale(0.5, 0.5), 30, Vector2.new(0.5, 0.5))
	text(b, "SeasonName", { Position = UDim2.fromOffset(58, 9), Size = UDim2.fromOffset(108, 16), FontFace = HEAD, TextSize = 13, Text = "SEASON 1" })
	local track = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(58, 28), Size = UDim2.fromOffset(106, 10), BackgroundColor3 = CREAM, ClipsDescendants = true }, b)
	corner(track, 5)
	stroke(track, 2)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.62, 1), BackgroundColor3 = PINK, BorderSizePixel = 0 }, track)
	corner(fill, 5)
	text(b, "Days", { Position = UDim2.fromOffset(58, 41), Size = UDim2.fromOffset(108, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "12 days left" })
end

-- HUD: the coins wallet. While you hold roll tickets or card upgrades the coins card shows a
-- small lilac "+n" tab on its bottom edge; tapping it drops the Wallet card (over Roll / UGC)
-- with a row each: icon, count, name. Tap a row to use it (HUDController). Hidden at 0.
function Build.HUDExtras(interface: Instance)
	local hud = interface:FindFirstChild("HUD") or interface.Parent:FindFirstChild("HUD")
	local topLeft = hud.TopLeft
	local coins = topLeft.Coins
	coins.Icon.Position = UDim2.fromOffset(13, 11)
	coins.Icon.Size = UDim2.fromOffset(34, 34)
	for _, name in { "Divider", "Extras", "WalletTab" } do
		clear(coins, name)
	end
	clear(topLeft, "Wallet")
	clear(topLeft, "WalletShadow")

	-- the tab: "+3" and a chevron (flips while open), half over the card's bottom edge
	local tab = new("TextButton", { Name = "WalletTab", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.fromOffset(52, 22), BackgroundColor3 = C("DCD3FF"), AutoButtonColor = false, Text = "", ZIndex = 3, Visible = false }, coins)
	corner(tab, 8)
	stroke(tab, 2)
	text(tab, "Count", { Position = UDim2.fromOffset(7, 0), Size = UDim2.new(1, -24, 1, 0), FontFace = HEAD, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "+3", ZIndex = 3 })
	local chev = new("Frame", { Name = "Chevron", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -11, 0.5, 0), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 3 }, tab)
	for i, rot in { 45, -45 } do
		local leg = new("Frame", { Name = "Leg" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(if i == 1 then 3 else 7, 5), Size = UDim2.fromOffset(6, 2), Rotation = rot, BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 3 }, chev)
		corner(leg, 1)
	end

	-- the wallet card, under the coins card (coins sit at 20, 290, 178 × 56)
	local rowH, pad = 34, 8
	local h = pad + 12 + (4 + rowH) * #Currencies.Wallet + pad
	local wallet = card(topLeft, "Wallet", UDim2.fromOffset(17, 366), UDim2.fromOffset(200, h), WHITE, 12, 4, 3)
	wallet.ZIndex = 5
	wallet.Visible = false
	-- a Frame doesn't stop taps reaching Roll / UGC / Season under it: an empty button just
	-- below the card (above them) swallows them; the rows sit above it and still work
	clear(topLeft, "WalletSink")
	new("TextButton", { Name = "WalletSink", Position = wallet.Position, Size = wallet.Size + UDim2.fromOffset(4, 4), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 4, Visible = false }, topLeft):SetAttribute("NoButtonScale", true) -- no hover / click sound
	topLeft.WalletShadow.ZIndex = 5
	topLeft.WalletShadow.Visible = false
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, pad), PaddingBottom = UDim.new(0, pad) }, wallet)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, wallet)
	text(wallet, "Header", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 12), FontFace = BODY, TextSize = 10, TextColor3 = MUTED, Text = "YOUR WALLET", ZIndex = 6 })
	-- a row per wallet currency (Constants/Currencies), named by its Id
	for i, currency in Currencies.Wallet do
		local row = new("TextButton", { Name = currency.Id, LayoutOrder = i, Size = UDim2.new(1, 0, 0, rowH), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", ZIndex = 6 }, wallet)
		local ic = icon(row, "Icon", "", UDim2.new(0, 14, 0.5, 0), 30, Vector2.new(0.5, 0.5))
		ic.Image = currency.Icon
		ic.ZIndex = 6
		text(row, "Count", { Position = UDim2.fromOffset(38, 1), Size = UDim2.new(1, -38, 0, 18), FontFace = HEAD, TextSize = 16, Text = "2", ZIndex = 6 })
		text(row, "Label", { Position = UDim2.fromOffset(38, 19), Size = UDim2.new(1, -38, 0, 13), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = currency.Plural, ZIndex = 6 })
	end
end

function Build.BuildAll(interface: Instance)
	local frames = interface.Frames
	Build.Season(frames)
	Build.Banners(frames)
	Build.Profile(frames)
	Build.PlayerCard(frames)
	Build.PreDuel(frames)
	Build.Results(frames)
	Build.Photocards(frames)
	Build.ShopStyle(frames)
	Build.SeasonRewards(frames)
	Build.SeasonTitleBadges(frames)
	Build.SeasonTitleReward(frames)
	Build.HUD(interface)
	Build.HUDExtras(interface)
	return "built"
end

return Build
