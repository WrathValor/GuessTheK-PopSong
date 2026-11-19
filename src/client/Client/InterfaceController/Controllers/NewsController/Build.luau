--| News UI builder (the What's New card)
-- Builds Interface.Frames.News from the "What's New" design boards: a cream card with a
-- tilted yellow "What's New!" sticker on its corner. Left, the update's art (two photocards,
-- the front one holding an icon, a version tag), its name, date, and a Codes card; under
-- them ‹ › and dots to page through older updates. Right, a scrolling list: "Featuring"
-- rows (icon tile, title, one line) and "Also new" one-liners with a tag. A red close
-- button, and a big green "Let's go!" on the bottom edge (the pop-up on join only).
-- The rows and code chips are templates (FeatureTemplate, AlsoTemplate, CodeTemplate,
-- DotTemplate) that NewsController clones. Also adds the red unread Dot to the HUD's News
-- button. Run once in Studio (an existing frame is kept as ServerStorage.News_Legacy):
--   local B = require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.NewsController.Build)
--   B.Build(game.StarterGui.Interface.Frames, game.StarterGui.Interface.HUD)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local LILAC = C("B9A6FF")
local PINK = C("FF9EC4")
local BLUE_HEAD = C("2E8BC8")
local PINK_HEAD = C("D9468A")
local MUTED = C("5C566B")
local PAPER = C("F3EBDD")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local BODY_SEMI = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)

local CLOSE_ICON = "rbxassetid://118345756178429"

local Build = {}
Build.MAX_FEATURED = 4

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

local function stroke(p: Instance, t: number, colour: Color3?, contextual: boolean?)
	new("UIStroke", {
		Color = colour or INK,
		Thickness = t,
		ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, p)
end

local function pad(p: Instance, l: number, r: number?, t: number?, b: number?)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r or l),
		PaddingTop = UDim.new(0, t or 0),
		PaddingBottom = UDim.new(0, b or 0),
	}, p)
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

local function row(parent: Instance, gap: number, wraps: boolean?)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = wraps == true,
	}, parent)
end

-- a face with a hard ink shadow behind it (both rotate together when `rotation` is given)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number, rotation: number?): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = rotation or 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0, Rotation = rotation or 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function chip(parent: Instance, name: string, label: string, colour: Color3, props: { [string]: any }?): TextLabel
	local base = {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
	}
	for k, v in props or {} do
		base[k] = v
	end
	local c = text(parent, name, base)
	corner(c, 8)
	stroke(c, 2)
	pad(c, 8)
	return c
end

local function vertical(name: string): { [string]: any }
	return { Name = name, Rotation = 90, Color = ColorSequence.new(LILAC, PINK) }
end

-- Red unread dot on the HUD's News button.
function Build.AddHudDot(newsButton: GuiObject)
	local old = newsButton:FindFirstChild("Dot")
	if old then
		old:Destroy()
	end
	local dot = new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -3, 0, 3),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = RED,
		Visible = false,
		ZIndex = 3,
	}, newsButton)
	corner(dot, UDim.new(0.5, 0))
	stroke(dot, 2.5)
	return dot
end

-- [[ The art side: photocards, name, date, codes, pager ]]

local function buildArt(panel: Frame)
	local W, H = 330, 500
	-- a rounded panel with a square right edge: the rounded half on the left, a square one on
	-- the right, both with the same top-to-bottom gradient (Rotation 90) so they line up
	local art = new("Frame", { Name = "Art", Size = UDim2.fromOffset(W, H), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	corner(art, 19)
	new("UIGradient", vertical("Tint"), art)
	local square = new("Frame", { Name = "Square", Position = UDim2.fromOffset(40, 0), Size = UDim2.fromOffset(W - 40, H), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0 }, art)
	new("UIGradient", vertical("Tint"), square)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(W, 0), Size = UDim2.fromOffset(3, H), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)

	-- two photocards, the front one holding this update's icon
	local cards = new("Frame", { Name = "Cards", Position = UDim2.fromOffset(47, 30), Size = UDim2.fromOffset(236, 200), BackgroundTransparency = 1 }, art)
	card(cards, "Back", UDim2.fromOffset(12, 16), UDim2.fromOffset(130, 172), YELLOW, 12, 4, 3, -9)
	local front = card(cards, "Front", UDim2.fromOffset(84, 6), UDim2.fromOffset(140, 186), C("FAF6E9"), 12, 5, 3, 5)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(104, 104), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "" }, front)
	chip(cards, "Version", "v1.0", MINT, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(242, -8), Size = UDim2.fromOffset(0, 24), TextSize = 14, Rotation = 8, ZIndex = 3 })

	local name = text(art, "UpdateName", {
		Position = UDim2.fromOffset(12, 234),
		Size = UDim2.fromOffset(W - 24, 40),
		FontFace = HEAD,
		TextSize = 30,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = false,
		Text = "Ghost Rivals!",
	})
	stroke(name, 3.5, INK, true)
	local date = chip(art, "Date", "Nov 20th, 2026", WHITE, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(W / 2, 276),
		Size = UDim2.fromOffset(0, 26),
		TextSize = 15,
	})
	date.UICorner.CornerRadius = UDim.new(1, 0)
	date.UIPadding.PaddingLeft = UDim.new(0, 12)
	date.UIPadding.PaddingRight = UDim.new(0, 12)

	-- this update's codes, one a line (CodeTemplate chips, cloned into List)
	local codes = card(art, "Codes", UDim2.fromOffset(18, 314), UDim2.fromOffset(W - 40, 120), WHITE, 14, 4, 3)
	text(codes, "Title", { Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(70, 20), FontFace = HEAD, TextSize = 15, Text = "Codes" })
	text(codes, "Hint", { Position = UDim2.fromOffset(76, 8), Size = UDim2.fromOffset(196, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Redeem in Shop › Codes" })
	local list = new("Frame", { Name = "List", Position = UDim2.fromOffset(10, 32), Size = UDim2.fromOffset(W - 60, 80), BackgroundTransparency = 1 }, codes)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local template = new("Frame", { Name = "CodeTemplate", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundColor3 = PAPER, BorderSizePixel = 0, Visible = false }, list)
	corner(template, 9)
	stroke(template, 2)
	row(template, 0)
	local code = text(template, "Code", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundTransparency = 0, BackgroundColor3 = YELLOW, FontFace = HEAD, TextSize = 13, TextTruncate = Enum.TextTruncate.None, Text = "CODE" })
	corner(code, 8)
	pad(code, 8)
	local reward = text(template, "Reward", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), FontFace = BODY, TextSize = 12, TextTruncate = Enum.TextTruncate.None, Text = "reward" })
	pad(reward, 7)

	-- older / newer (from the News button only)
	local pager = new("Frame", { Name = "Pager", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(W / 2, H - 10), Size = UDim2.fromOffset(220, 46), BackgroundTransparency = 1, Visible = false }, art)
	local function arrow(nm: string, x: number, label: string): TextButton
		local sh = new("Frame", { Name = nm .. "Shadow", Position = UDim2.fromOffset(x + 3, 3), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = INK, BorderSizePixel = 0 }, pager)
		corner(sh, 12)
		local b = new("TextButton", { Name = nm, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + 23, 23), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = 24, TextColor3 = INK, Text = label, AutoButtonColor = false }, pager)
		corner(b, 12)
		stroke(b, 3)
		return b
	end
	arrow("Prev", 0, "‹")
	arrow("Next", 220 - 46, "›")
	local dots = new("Frame", { Name = "Dots", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(110, 23), Size = UDim2.fromOffset(110, 16), BackgroundTransparency = 1 }, pager)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, dots)
	local dot = new("Frame", { Name = "DotTemplate", Size = UDim2.fromOffset(10, 10), BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false }, dots)
	corner(dot, UDim.new(1, 0))
	stroke(dot, 2)
end

-- [[ The list side: Featuring rows + Also new ]]

local function buildList(panel: Frame)
	local X, W, H = 333, 880 - 333 - 3, 500 - 6
	local scroll = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(X, 3),
		Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = INK,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, panel)
	pad(scroll, 26, 22, 24, 64)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	text(scroll, "FeaturedHeader", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), FontFace = HEAD, TextSize = 20, TextColor3 = BLUE_HEAD, Text = "Featuring" })

	-- one Featuring row (cloned per feature, LayoutOrder 10 + i)
	local feature = new("Frame", { Name = "FeatureTemplate", LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Visible = false }, scroll)
	local fs = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = INK, BorderSizePixel = 0 }, feature)
	corner(fs, 14)
	local face = new("Frame", { Name = "Face", Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, feature)
	corner(face, 14)
	stroke(face, 3)
	local tile = new("Frame", { Name = "IconBox", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = LILAC, BorderSizePixel = 0 }, face)
	corner(tile, 11)
	stroke(tile, 2)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "" }, tile)
	text(face, "Title", { Position = UDim2.fromOffset(68, 9), Size = UDim2.new(1, -80, 0, 22), TextSize = 18, Text = "Feature" })
	text(face, "Body", { Position = UDim2.fromOffset(68, 31), Size = UDim2.new(1, -80, 0, 30), FontFace = BODY_SEMI, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd, Text = "One line about it." })

	text(scroll, "AlsoHeader", { LayoutOrder = 50, Size = UDim2.new(1, 0, 0, 30), FontFace = HEAD, TextSize = 20, TextColor3 = PINK_HEAD, TextYAlignment = Enum.TextYAlignment.Bottom, Text = "Also new" })

	-- one "Also new" line (cloned, LayoutOrder 60 + i)
	local also = new("Frame", { Name = "AlsoTemplate", LayoutOrder = 60, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Visible = false }, scroll)
	row(also, 10)
	chip(also, "Tag", "NEW", YELLOW, { LayoutOrder = 1, TextSize = 11 })
	text(also, "Text", { LayoutOrder = 2, Size = UDim2.new(1, -70, 0, 22), FontFace = BODY_BOLD, TextSize = 15, Text = "Also new line" })
end

function Build.Build(frames: Instance, hud: Instance?)
	local old = frames:FindFirstChild("News")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("News_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "News_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "News", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, root)
	scrim.Active = true

	local panel = card(root, "Panel", UDim2.fromOffset(200, 112), UDim2.fromOffset(880, 500), CREAM, 22, 9, 3)
	buildArt(panel)
	buildList(panel)

	-- "What's New!" sticker on the top-left corner
	local sticker = card(root, "Sticker", UDim2.fromOffset(172, 70), UDim2.fromOffset(252, 58), YELLOW, 14, 5, 3, -4)
	text(sticker, "Label", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 32, TextXAlignment = Enum.TextXAlignment.Center, Text = "What's New!" })
	-- "Update 1 of 2" beside it (from the News button only)
	chip(root, "Count", "Update 1 of 2", WHITE, { Position = UDim2.fromOffset(440, 86), Size = UDim2.fromOffset(0, 24), TextSize = 13, Rotation = -4, Visible = false })

	-- close
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(1040 + 4, 90 + 4), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(cs, 14)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(1040 + 26, 90 + 26), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, root)
	corner(close, 14)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- the big button on the bottom edge (the pop-up on join only)
	local okShadow = new("Frame", { Name = "OkShadow", Position = UDim2.fromOffset(640 + 5, 580 + 5), Size = UDim2.fromOffset(250, 64), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(okShadow, 16)
	local ok = new("TextButton", { Name = "Ok", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640 + 125, 580 + 32), Size = UDim2.fromOffset(250, 64), BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 28, TextColor3 = INK, Text = "Let's go!", AutoButtonColor = false }, root)
	corner(ok, 16)
	stroke(ok, 3)

	root.Parent = frames

	if hud then
		local buttons = hud:FindFirstChild("Buttons")
		local news = buttons and buttons:FindFirstChild("News")
		if news and not news:FindFirstChild("Dot") then
			Build.AddHudDot(news)
		end
	end
	return root
end

return Build
