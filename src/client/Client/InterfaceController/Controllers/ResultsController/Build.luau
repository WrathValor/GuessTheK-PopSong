--| Results UI builder
-- Rebuilds Interface.Frames.Results to the "Match results · before seasons" board: a wider
-- panel with two columns.
--   left  – the round table and total bar (kept as they were), then Record: your all-time
--           record against this rival ("VS X · ALL TIME 6 – 3", a +1 WIN / LOSS sticker and the
--           last five as W / L tiles; hidden in solo, Party, the tutorial and draws)
--   right – Winner: the player's banner across the top (SeasonArt.BuildBanner) with their
--           photocard (SeasonArt.BuildCardSkin + their avatar in the window), name and title
--           chip; three tiles (Coins, XP, Streak – solo: Score); the Level card (level, XP bar,
--           the next level reward); the LEVEL UP banner; CONTINUE / REMATCH (solo: FIND RIVAL
--           and PLAY AGAIN too). Solo's rank stamp sits on the banner, its best + hint under
--           the level card.
-- The Season bar moves into the Level card's place; ResultsController shows one or the other
-- (SeasonConstants.ENABLED). Run once in Studio, Edit mode (safe to run again):
--   require(<this module>).Build(game.StarterGui.Interface.Frames.Results)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local Currencies = require(ReplicatedStorage.Constants.Currencies)

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local CREAM = C("FBF7F0")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local LILAC = C("B9A6FF")
local PALE_LILAC = C("DCD3FF")
local SALMON = C("FFD2CE")
local MUTED = C("4A4458")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local Build = {}
Build.PANEL_W, Build.PANEL_H = 1180, 640
Build.LEFT_W = 686 -- table column (27 + 632 + 27); the divider follows
Build.RIGHT_X, Build.RIGHT_W = 689, 491
Build.PAD = 20
Build.CARD_W = Build.RIGHT_W - 2 * Build.PAD -- 451

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

local function stroke(p: Instance, t: number)
	new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function pad(p: Instance, l: number, r: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l) }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

-- a face with a hard shadow under it (the shadow is a sibling: <name>Shadow)
local function card(parent: Instance, name: string, pos: Vector2, size: Vector2, colour: Color3, radius: number, line: number, drop: number?): Frame
	if drop then
		local sh = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(pos.X + drop, pos.Y + drop), Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
		corner(sh, radius)
	end
	local f = new("Frame", { Name = name, Position = UDim2.fromOffset(pos.X, pos.Y), Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(f, radius)
	stroke(f, line)
	return f
end

-- a button: centre anchor (ButtonScale), hard shadow behind
local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string): TextButton
	local sh = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2 + 4, y + h / 2 + 4), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(sh, 14)
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + w / 2, y + h / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		AutoButtonColor = false,
		FontFace = HEAD,
		TextSize = 18,
		TextColor3 = INK,
		Text = label,
	}, parent)
	corner(b, 14)
	stroke(b, 4)
	return b
end

-- a stat tile: icon + LABEL, then the value
local function tile(parent: Instance, name: string, x: number, w: number, colour: Color3, label: string, icon: string): Frame
	local t = card(parent, name, Vector2.new(x, 196), Vector2.new(w, 64), colour, 12, 3)
	new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit }, t)
	text(t, "Label", { Position = UDim2.fromOffset(31, 6), Size = UDim2.fromOffset(w - 40, 16), TextSize = 12, Text = label })
	text(t, "Value", { Position = UDim2.fromOffset(10, 22), Size = UDim2.fromOffset(w - 20, 26), FontFace = HEAD, TextSize = 22, Text = "+0", TextTruncate = Enum.TextTruncate.None })
	return t
end

-- [[ Left column: the record strip under the total bar ]]
local function record(panel: Instance)
	local r = card(panel, "Record", Vector2.new(27, 574), Vector2.new(632, 50), WHITE, 14, 3)
	text(r, "Label", { Position = UDim2.fromOffset(14, 7), Size = UDim2.fromOffset(330, 13), TextSize = 11, TextColor3 = MUTED, Text = "VS RIVAL · ALL TIME" })
	text(r, "Score", { Position = UDim2.fromOffset(14, 20), Size = UDim2.fromOffset(110, 24), FontFace = HEAD, TextSize = 20, RichText = true, Text = '6 <font color="#8A8497">–</font> 3' })
	local delta = text(r, "Delta", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(126, 33),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		Rotation = 6,
		BackgroundTransparency = 0,
		BackgroundColor3 = MINT,
		FontFace = HEAD,
		TextSize = 12,
		Text = "+1 WIN",
		TextTruncate = Enum.TextTruncate.None,
	})
	corner(delta, 7)
	stroke(delta, 2)
	pad(delta, 6)
	text(r, "LastLabel", { Position = UDim2.fromOffset(426, 17), Size = UDim2.fromOffset(60, 16), TextSize = 11, TextColor3 = MUTED, Text = "LAST 5", TextXAlignment = Enum.TextXAlignment.Right })
	local pips = new("Frame", { Name = "Pips", Position = UDim2.fromOffset(494, 13), Size = UDim2.fromOffset(124, 24), BackgroundTransparency = 1 }, r)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, pips)
	for k = 1, 5 do
		local pip = text(pips, "P" .. k, {
			LayoutOrder = k,
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = MINT,
			FontFace = HEAD,
			TextSize = 11,
			Text = "W",
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
		})
		corner(pip, 6)
		stroke(pip, 2)
	end
	return r
end

-- [[ Right column ]]
local function winner(panel: Instance)
	local P, W = Build.PAD, Build.CARD_W
	local w = new("Frame", {
		Name = "Winner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Build.RIGHT_X + Build.RIGHT_W / 2, Build.PANEL_H / 2),
		Size = UDim2.fromOffset(Build.RIGHT_W, Build.PANEL_H),
		BackgroundTransparency = 1,
	}, panel)

	-- their banner across the top, on a rule
	SeasonArt.BuildBanner(w, "Banner", UDim2.fromOffset(0, 0), UDim2.fromOffset(Build.RIGHT_W - 2, 140), 15, true)
	new("Frame", { Name = "BannerRule", Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, w)

	local ribbon = new("Frame", { Name = "Ribbon", Position = UDim2.fromOffset(P, 16), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), BackgroundColor3 = INK }, w)
	corner(ribbon, 9)
	pad(ribbon, 10)
	text(ribbon, "Label", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), FontFace = HEAD, TextSize = 16, TextColor3 = YELLOW, Text = "WINNER", TextTruncate = Enum.TextTruncate.None })

	-- solo: the rank stamp, top right of the banner
	local rank = card(w, "Rank", Vector2.new(Build.RIGHT_W - P - 62, 14), Vector2.new(62, 62), C("FF9EC4"), 31, 3, 3)
	text(rank, "Grade", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 30, Text = "S", TextXAlignment = Enum.TextXAlignment.Center })
	rank.Visible, w.RankShadow.Visible = false, false

	-- their photocard, tilted, half over the rule
	local photoW, photoH = 88, 105
	local CARD_TOP = 80 -- sits 12px higher than the name row: the -3° tilt + shadow would touch the tiles at 196
	local cardShadow = new("Frame", { Name = "CardShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(P + photoW / 2 + 5, CARD_TOP + photoH / 2 + 5), Size = UDim2.fromOffset(photoW, photoH), Rotation = -3, BackgroundColor3 = INK, BorderSizePixel = 0 }, w)
	corner(cardShadow, 10)
	local pc = new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(P + photoW / 2, CARD_TOP + photoH / 2), Size = UDim2.fromOffset(photoW, photoH), Rotation = -3, BackgroundColor3 = WHITE, BorderSizePixel = 0 }, w)
	corner(pc, 10)
	stroke(pc, 3)
	local photo = new("Frame", { Name = "Photo", Position = UDim2.fromScale(12 / 280, 12 / 334), Size = UDim2.fromScale(256 / 280, 228 / 334), BackgroundColor3 = C("CDEBFA"), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 1 }, pc)
	corner(photo, 6)
	new("ImageLabel", { Name = "Thumbnail", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop, ZIndex = 1 }, photo)
	SeasonArt.BuildCardSkin(pc, photo, 10, true)

	-- name + title chip, right of the photocard
	local name = text(w, "Name", {
		Position = UDim2.fromOffset(P + photoW + 16, 92),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 0,
		BackgroundColor3 = CREAM,
		FontFace = HEAD,
		TextSize = 22,
		Text = "mujtabah",
		TextTruncate = Enum.TextTruncate.None,
	})
	corner(name, 10)
	stroke(name, 3)
	pad(name, 10)
	local title = text(w, "Title", {
		Position = UDim2.fromOffset(P + photoW + 16, 152),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = MINT,
		FontFace = HEAD,
		TextSize = 12,
		Text = "Rookie",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	corner(title, 7)
	stroke(title, 2)
	pad(title, 8)
	new("UIGradient", { Name = "Rainbow", Enabled = false }, title)

	-- what you earned
	local coins = tile(w, "Coins", P, 200, YELLOW, "COINS", Currencies.Coins.Icon)
	text(coins, "Detail", { Position = UDim2.fromOffset(10, 45), Size = UDim2.fromOffset(180, 14), TextSize = 12, Text = "70 × 1.2 streak" })
	coins.Value.Size = UDim2.fromOffset(180, 24)
	tile(w, "XP", P + 210, 115, PALE_LILAC, "XP", SeasonConstants.ICONS.XP)
	tile(w, "Streak", P + 335, W - 335, SALMON, "STREAK", SeasonConstants.ICONS.Streak)

	-- the level card (the Season bar takes this spot once seasons are on)
	local lv = card(w, "Level", Vector2.new(P, 274), Vector2.new(W, 124), WHITE, 16, 4, 5)
	text(lv, "Label", { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(120, 16), TextSize = 13, TextColor3 = MUTED, Text = "LEVEL" })
	text(lv, "Source", { Position = UDim2.fromOffset(140, 10), Size = UDim2.fromOffset(W - 156, 16), TextSize = 13, TextColor3 = MUTED, Text = "+46 XP this match", TextXAlignment = Enum.TextXAlignment.Right })
	text(lv, "Value", { Position = UDim2.fromOffset(14, 28), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), FontFace = HEAD, TextSize = 30, Text = "Lv 7", TextTruncate = Enum.TextTruncate.None })
	text(lv, "Progress", { Position = UDim2.fromOffset(120, 36), Size = UDim2.fromOffset(220, 22), TextSize = 16, Text = "20 / 220 XP" })
	local bar = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(14, 68), Size = UDim2.fromOffset(W - 36, 20), BackgroundColor3 = CREAM, ClipsDescendants = true }, lv)
	corner(bar, UDim.new(1, 0))
	stroke(bar, 3)
	local gain = new("Frame", { Name = "Gain", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = YELLOW, BorderSizePixel = 0, ZIndex = 1 }, bar)
	corner(gain, UDim.new(1, 0))
	local old = new("Frame", { Name = "Old", Size = UDim2.fromScale(0.2, 1), BackgroundColor3 = LILAC, BorderSizePixel = 0, ZIndex = 2 }, bar)
	corner(old, UDim.new(1, 0))
	text(lv, "Now", { Position = UDim2.fromOffset(14, 94), Size = UDim2.fromOffset(120, 18), TextSize = 13, Text = "LEVEL 7" })
	text(lv, "Next", { Position = UDim2.fromOffset(140, 94), Size = UDim2.fromOffset(W - 176, 18), TextSize = 13, Text = "NEXT REWARD · LV 8 · 100 coins", TextXAlignment = Enum.TextXAlignment.Right })

	-- LEVEL UP (only when this match levelled you)
	local up = card(w, "LevelUp", Vector2.new(P, 412), Vector2.new(W, 54), LILAC, 14, 4)
	up.Rotation = -1
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, Image = SeasonConstants.ICONS.Stars, ScaleType = Enum.ScaleType.Fit }, up)
	text(up, "Label", { Position = UDim2.fromOffset(50, 0), Size = UDim2.fromOffset(230, 54), FontFace = HEAD, TextSize = 20, Text = "LEVEL UP · LV 7" })
	text(up, "Note", { Position = UDim2.fromOffset(280, 0), Size = UDim2.fromOffset(W - 294, 54), TextSize = 13, Text = "Reward ready in Rewards", TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right })
	up.Visible = false

	-- solo: personal best + how far the next rank is
	local best = new("Frame", { Name = "Best", Position = UDim2.fromOffset(P, 478), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundTransparency = 1, Visible = false }, w)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, best)
	local newBest = text(best, "New", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundTransparency = 0, BackgroundColor3 = YELLOW, FontFace = HEAD, TextSize = 13, Text = "NEW BEST!", TextTruncate = Enum.TextTruncate.None })
	corner(newBest, 8)
	stroke(newBest, 2)
	pad(newBest, 8)
	text(best, "Old", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), TextSize = 13, TextColor3 = MUTED, Text = "old best 40", TextTruncate = Enum.TextTruncate.None })
	text(w, "RankHint", { Position = UDim2.fromOffset(P, 508), Size = UDim2.fromOffset(W, 18), TextSize = 13, TextColor3 = MUTED, Text = "6 more points for S rank", Visible = false })

	text(w, "RematchNote", { Position = UDim2.fromOffset(0, 536), Size = UDim2.fromOffset(Build.RIGHT_W, 18), TextSize = 13, Text = "Waiting for your rival…", TextXAlignment = Enum.TextXAlignment.Center, Visible = false })

	-- CONTINUE · REMATCH (solo: CONTINUE · FIND RIVAL · PLAY AGAIN; the controller lays them out)
	button(w, "Leave", P, 564, 220, 52, WHITE, "CONTINUE")
	local find = button(w, "FindRival", P + 150, 564, 140, 52, WHITE, "FIND RIVAL")
	find.TextSize = 15
	find.Visible, w.FindRivalShadow.Visible = false, false
	local rematch = button(w, "Rematch", P + 231, 564, 220, 52, MINT, "")
	text(rematch, "Label", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 18, Text = "REMATCH", TextXAlignment = Enum.TextXAlignment.Center })
	text(rematch, "SoloLabel", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 18, Text = "PLAY AGAIN", TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	local count = new("Frame", { Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 8, 0, -12), Size = UDim2.fromOffset(40, 22), Rotation = 6, BackgroundColor3 = WHITE }, rematch)
	corner(count, 8)
	stroke(count, 2)
	text(count, "Value", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 12, Text = "0/2", TextXAlignment = Enum.TextXAlignment.Center })
	return w
end

function Build.Build(results: Instance)
	local panel = results.Panel
	local shadow = results:FindFirstChild("PanelShadow")
	local dx, dy = (shadow and shadow.Position.X.Offset - panel.Position.X.Offset) or 8, (shadow and shadow.Position.Y.Offset - panel.Position.Y.Offset) or 8
	panel.Position = UDim2.fromOffset((1280 - Build.PANEL_W) / 2, (720 - Build.PANEL_H) / 2)
	panel.Size = UDim2.fromOffset(Build.PANEL_W, Build.PANEL_H)
	if shadow then
		shadow.Position = panel.Position + UDim2.fromOffset(dx, dy)
		shadow.Size = panel.Size
	end

	for _, n in { "Winner", "Record", "RecordShadow", "Divider" } do
		local old = panel:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	-- the title tag stays centred over the table
	local tag, tagShadow = panel.TitleTag, panel:FindFirstChild("TitleTagShadow")
	local tagX = 27 + 316 - tag.Size.X.Offset / 2
	if tagShadow then
		tagShadow.Position = UDim2.fromOffset(tagX + (tagShadow.Position.X.Offset - tag.Position.X.Offset), tagShadow.Position.Y.Offset)
	end
	tag.Position = UDim2.fromOffset(tagX, tag.Position.Y.Offset)
	-- the table's total bar shadow (the scale plugin knocked it out of place once)
	local total = panel.Table.Total
	local totalShadow = panel.Table:FindFirstChild("TotalShadow")
	if totalShadow then
		totalShadow.AnchorPoint = total.AnchorPoint
		totalShadow.Size = total.Size
		totalShadow.Position = total.Position + UDim2.fromOffset(4, 4)
	end

	new("Frame", { Name = "Divider", Position = UDim2.fromOffset(Build.LEFT_W, 0), Size = UDim2.fromOffset(3, Build.PANEL_H), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	record(panel)
	local w = winner(panel)

	-- the Season bar: into the Level card's place (shown instead of it once seasons are on)
	local season, seasonShadow = panel:FindFirstChild("Season"), panel:FindFirstChild("SeasonShadow")
	if season then
		season.Position = UDim2.fromOffset(Build.RIGHT_X + Build.PAD, 274)
		season.Size = UDim2.fromOffset(Build.CARD_W, 40)
		if seasonShadow then
			seasonShadow.Position = season.Position + UDim2.fromOffset(3, 3)
			seasonShadow.Size = season.Size
		end
	end
	return w
end

return Build
