--| Events UI builder
-- Builds Interface.Frames.Events from design boards "79a · Events · Winter Special missions" and
-- "79b · Events · Winter Special shop" (79c, the pass, isn't built yet). Run once in Studio Edit
-- mode (an existing one is replaced), then save the place:
--   local m = game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.EventsController.Build
--   local c = m:Clone(); c.Parent = m.Parent; require(c).Build(game.StarterGui.Interface.Frames); c:Destroy()
-- Full screen like the Shop, over a dark winter scrim with Snow drifting down it:
--   Header      Title "Events", Sub, Balance (the event currency: Icon + Amount), Close
--   List        the events down the left: LimitedHead, Live (the live event: Thumb.Icon, Title,
--               Chip), Soon (the next one), AlwaysHead, FanClub (opens Quests)
--   Panel       Banner (Title, Blurb, Chips: Ends + Balance, two winter cards), Tabs (Missions, Shop),
--               and the two pages:
--     Missions  a ScrollingFrame: HeadTemplate (a section line) and RowTemplate (Text, Hint, Bar.Fill,
--               Count, Reward: Icon + Amount, Action: Label), cloned by EventsController
--     Shop      a ScrollingFrame grid of ItemTemplate (Tag, Art: Pic + TitleChip, OpenPack, Title,
--               Hint, Stock, Buy: Icon + Price), then the Note
--   Toast
-- EventsController finds everything by name and fills it from Constants/LiveEvents.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local ICE = C("DFF3FF")
local BLUE = C("9ED8F5")
local RED = C("FF5A4E")
local MUTED = C("6B6480")
local PAPER = C("EFE7D4")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local SNOWFLAKE = "rbxassetid://119208551988683" -- assets/ui/Events/Snowflake.png
local CLOSE_ICON = "rbxassetid://118345756178429"

local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 300, 112, 940, 590
local BANNER_H = 112
local PAGE_Y = BANNER_H + 4 + 62 -- under the tabs
local LIST_X, LIST_W = 40, 236

local Build = {}

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
	return new("UIStroke", { Color = colour or INK, Thickness = t, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function pad(p: Instance, l: number, r: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l) }, p)
end
local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function icon(parent: Instance, name: string, image: string, size: number, props: { [string]: any }?): ImageLabel
	local base = { Name = name, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit }
	for k, v in props or {} do
		base[k] = v
	end
	return new("ImageLabel", base, parent)
end
-- a hard ink shadow behind `of` (same parent), grown by its outline
local function shadowOf(of: GuiObject, offset: number, radius: number, line: number): Frame
	local a = of.AnchorPoint
	local s = new("Frame", {
		Name = of.Name .. "Shadow",
		AnchorPoint = a,
		Position = of.Position + UDim2.fromOffset(offset + line * (2 * a.X - 1), offset + line * (2 * a.Y - 1)),
		Size = of.Size + UDim2.fromOffset(2 * line, 2 * line),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = of.ZIndex - 1,
	}, of.Parent)
	corner(s, radius)
	return s
end
-- an ink-outlined button, centred (ButtonScale grows it from the middle), with its shadow
local function button(parent: Instance, name: string, cx: number, cy: number, w: number, h: number, colour: Color3, label: string, size: number): TextButton
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, Text = "", AutoButtonColor = false, ZIndex = 3 }, parent)
	corner(b, 11)
	stroke(b, 3)
	text(b, "Label", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = size, Text = label, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	shadowOf(b, 3, 11, 3)
	return b
end
-- an icon + label pill that grows with its text
local function chip(parent: Instance, name: string, label: string, colour: Color3, withIcon: boolean, order: number?): Frame
	local c = new("Frame", { Name = name, LayoutOrder = order or 0, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = colour }, parent)
	corner(c, 8)
	stroke(c, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 9) }, c)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, c)
	if withIcon then
		icon(c, "Icon", SNOWFLAKE, 16, { LayoutOrder = 1 })
	end
	local t = text(c, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, Text = label, TextTruncate = Enum.TextTruncate.None })
	t:SetAttribute("FitTextSkip", true)
	return c
end

-- [[ Header + list ]]

local function header(root: Frame)
	local h = new("Frame", { Name = "Header", Size = UDim2.fromOffset(1280, PANEL_Y), BackgroundTransparency = 1, ZIndex = 2 }, root)
	text(h, "Title", { Position = UDim2.fromOffset(40, 38), Size = UDim2.fromOffset(400, 36), FontFace = HEAD, TextSize = 30, TextColor3 = CREAM, Text = "Events" })
	text(h, "Sub", { Position = UDim2.fromOffset(40, 74), Size = UDim2.fromOffset(500, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = CREAM, TextTransparency = 0.35, Text = "Limited-time missions and a shop to spend what you earn" })

	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(1216, 62), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = RED, Image = "", AutoButtonColor = false, ZIndex = 3 }, h)
	corner(close, 12)
	stroke(close, 3)
	icon(close, "Icon", CLOSE_ICON, 16, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 4 })
	shadowOf(close, 3, 12, 3)

	local bal = new("Frame", { Name = "Balance", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(1216 - 22 - 22, 62), Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, BackgroundTransparency = 0.9 }, h)
	corner(bal, 12)
	stroke(bal, 2, CREAM, 0.75)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 14) }, bal)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, bal)
	icon(bal, "Icon", SNOWFLAKE, 22, { LayoutOrder = 1 })
	local amount = text(bal, "Amount", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, TextSize = 16, TextColor3 = CREAM, Text = "1,240", TextTruncate = Enum.TextTruncate.None })
	amount:SetAttribute("FitTextSkip", true)
end

-- one event in the list (a TextButton: Thumb.Icon / Thumb.Big, Title, Line or Chip)
local function listCard(list: Instance, name: string, y: number, on: boolean): TextButton
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(LIST_W / 2, y + 39), Size = UDim2.fromOffset(LIST_W, 78), BackgroundColor3 = CREAM, BackgroundTransparency = if on then 0 else 1, Text = "", AutoButtonColor = false, ZIndex = 3 }, list)
	corner(b, 14)
	stroke(b, 3, if on then INK else CREAM, if on then 0 else 0.82)
	if on then
		shadowOf(b, 4, 14, 3)
	end
	local thumb = new("Frame", { Name = "Thumb", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = ICE, ZIndex = 4 }, b)
	corner(thumb, 12)
	stroke(thumb, 3)
	icon(thumb, "Icon", SNOWFLAKE, 34, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5 })
	text(thumb, "Big", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 22, Text = "?", TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 5 })
	local txt = if on then INK else CREAM
	text(b, "Title", { Position = UDim2.fromOffset(76, 14), Size = UDim2.fromOffset(LIST_W - 86, 22), FontFace = HEAD, TextSize = 16, TextColor3 = txt, Text = "Winter Special", ZIndex = 4 })
	text(b, "Line", { Position = UDim2.fromOffset(76, 40), Size = UDim2.fromOffset(LIST_W - 86, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = txt, TextTransparency = if on then 0.2 else 0.3, Text = "A new album drops · soon", ZIndex = 4 })
	local c = chip(b, "Chip", "LIVE · 23d left", MINT, false)
	c.Position = UDim2.fromOffset(76, 40)
	c.Size = UDim2.fromOffset(0, 22)
	c.ZIndex = 4
	c.Label.Size = UDim2.fromOffset(0, 22)
	c.Label.TextSize = 11
	c.Visible = on
	b.Line.Visible = not on
	return b
end

local function eventList(root: Frame)
	local list = new("Frame", { Name = "List", Position = UDim2.fromOffset(LIST_X, PANEL_Y), Size = UDim2.fromOffset(LIST_W, PANEL_H), BackgroundTransparency = 1, ZIndex = 2 }, root)
	local function head(name: string, y: number, label: string)
		text(list, name, { Position = UDim2.fromOffset(2, y), Size = UDim2.fromOffset(LIST_W, 16), TextSize = 12, TextColor3 = CREAM, TextTransparency = 0.4, Text = label, ZIndex = 3 })
	end
	head("LimitedHead", 0, "LIMITED")
	listCard(list, "Live", 24, true)
	local soon = listCard(list, "Soon", 114, false)
	soon.Title.Text = "Comeback Week"
	soon.Thumb.BackgroundColor3 = C("FFE4EF")
	soon.Thumb.Icon.Visible = false
	soon.Thumb.Big.Visible = true
	head("AlwaysHead", 208, "ALWAYS ON")
	local fan = listCard(list, "FanClub", 232, false)
	fan.Title.Text = "Fan Club"
	fan.Line.Text = "Daily + weekly quests"
	fan.Thumb.BackgroundColor3 = C("FFE07A")
	fan.Thumb.Icon.Visible = false
	fan.Thumb.Big.Visible = true
	fan.Thumb.Big.Text = "Q"
	text(list, "Note", { Position = UDim2.fromOffset(2, 340), Size = UDim2.fromOffset(LIST_W, 120), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = CREAM, TextTransparency = 0.35, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "Missions pay Snowflakes. Spend them in the event's shop before it ends: left-overs turn into coins.", ZIndex = 3 })
end

-- [[ Panel: banner + tabs ]]

local function banner(panel: Frame)
	local b = new("Frame", { Name = "Banner", Size = UDim2.new(1, 0, 0, BANNER_H), BackgroundColor3 = WHITE, ClipsDescendants = true, ZIndex = 2 }, panel)
	corner(b, 18)
	new("UIGradient", { Name = "Theme", Rotation = 0, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C("CFEFFF")), ColorSequenceKeypoint.new(0.45, C("EAF7FF")), ColorSequenceKeypoint.new(1, C("FFE4EF")) }) }, b)
	-- (squares off the bottom corners: the same gradient across the same width)
	local square = new("Frame", { Name = "Square", Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2 }, b)
	b.Theme:Clone().Parent = square
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, BANNER_H), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 3 }, panel)
	text(b, "Title", { Position = UDim2.fromOffset(24, 16), Size = UDim2.fromOffset(560, 34), FontFace = HEAD, TextSize = 28, Text = "Winter Special", ZIndex = 3 })
	text(b, "Blurb", { Position = UDim2.fromOffset(24, 50), Size = UDim2.fromOffset(600, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = C("4A4460"), Text = "Do missions for Snowflakes, spend them on winter photocards you can only get this month.", ZIndex = 3 })
	local chips = new("Frame", { Name = "Chips", Position = UDim2.fromOffset(24, 74), Size = UDim2.fromOffset(600, 26), BackgroundTransparency = 1, ZIndex = 3 }, b)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	chip(chips, "Ends", "Ends 7 Jan · 23d 4h", WHITE, false, 1)
	chip(chips, "Balance", "1,240 Snowflakes", ICE, true, 2)
	-- two little winter photocards, leaning
	local cards = new("Frame", { Name = "Cards", Position = UDim2.fromOffset(PANEL_W - 180, 10), Size = UDim2.fromOffset(170, 100), BackgroundTransparency = 1, ZIndex = 3 }, b)
	for i, spec in { { 26, 14, -8, "B9E4FA" }, { 92, 18, 7, "FFC9DD" } } do
		local c = new("Frame", { Name = "Card" .. i, Position = UDim2.fromOffset(spec[1], spec[2]), Size = UDim2.fromOffset(60, 82), BackgroundColor3 = WHITE, Rotation = spec[3], ZIndex = 4 }, cards)
		corner(c, 8)
		stroke(c, 3)
		local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(48, 54), BackgroundColor3 = C(spec[4]), ZIndex = 5 }, c)
		corner(photo, 5)
		icon(photo, "Flake", SNOWFLAKE, 22, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6, ImageTransparency = 0.15 })
		text(c, "Word", { Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(60, 16), TextSize = 9, Text = "WINTER", TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	end
end

local function tabs(panel: Frame)
	local t = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(24, BANNER_H + 4 + 14), Size = UDim2.fromOffset(400, 38), BackgroundTransparency = 1, ZIndex = 2 }, panel)
	for i, name in { "Missions", "Shop" } do
		local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((i - 1) * 132 + 60, 19), Size = UDim2.fromOffset(120, 38), BackgroundColor3 = if i == 1 then INK else PAPER, Text = "", AutoButtonColor = false, ZIndex = 3 }, t)
		corner(b, 11)
		stroke(b, 3)
		text(b, "Label", { Size = UDim2.fromScale(1, 1), TextSize = 15, Text = name, TextColor3 = if i == 1 then CREAM else INK, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		-- the red count: missions ready to claim
		local count = text(b, "Count", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0, BackgroundColor3 = RED, TextColor3 = WHITE, TextSize = 12, Text = "2", TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 5 })
		corner(count, 11)
		stroke(count, 2)
	end
end

local function scroll(panel: Frame, name: string): ScrollingFrame
	local s = new("ScrollingFrame", {
		Name = name,
		Position = UDim2.fromOffset(20, PAGE_Y),
		Size = UDim2.fromOffset(PANEL_W - 30, PANEL_H - PAGE_Y - 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = INK,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 2,
	}, panel)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 16), PaddingBottom = UDim.new(0, 10) }, s)
	return s
end

-- [[ Missions ]]

local ROW_W = PANEL_W - 30 - 20 -- (the scroll's width less its padding)

local function missions(panel: Frame)
	local s = scroll(panel, "Missions")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, s)

	local head = new("Frame", { Name = "HeadTemplate", Size = UDim2.fromOffset(ROW_W, 28), BackgroundTransparency = 1, Visible = false, ZIndex = 2 }, s)
	text(head, "Label", { Position = UDim2.fromOffset(2, 4), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextColor3 = MUTED, Text = "DAILY · RESETS IN 6h 12m", TextTruncate = Enum.TextTruncate.None, ZIndex = 3 }):SetAttribute("FitTextSkip", true)
	new("Frame", { Name = "Line", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0, 15), Size = UDim2.new(1, -260, 0, 3), BackgroundColor3 = C("E6DECB"), BorderSizePixel = 0, ZIndex = 3 }, head)

	local row = new("Frame", { Name = "RowTemplate", Size = UDim2.fromOffset(ROW_W, 62), BackgroundColor3 = WHITE, Visible = false, ZIndex = 2 }, s)
	corner(row, 13)
	stroke(row, 3)
	text(row, "Text", { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(ROW_W - 470, 22), FontFace = BODY, TextSize = 17, Text = "Win 3 duels", ZIndex = 3 })
	text(row, "Hint", { Position = UDim2.fromOffset(16, 33), Size = UDim2.fromOffset(ROW_W - 470, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "In any mode, solo too", ZIndex = 3 })
	local right = ROW_W - 16
	-- the action button (Claim / Go / Done), the reward, then the progress bar
	local action = button(row, "Action", right - 54, 31, 108, 40, MINT, "Claim", 15)
	action.Label.FontFace = HEAD
	local reward = new("Frame", { Name = "Reward", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(right - 108 - 16 - 44, 31), Size = UDim2.fromOffset(88, 36), BackgroundColor3 = ICE, ZIndex = 3 }, row)
	corner(reward, 10)
	stroke(reward, 2.5)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, reward)
	icon(reward, "Icon", SNOWFLAKE, 20, { LayoutOrder = 1, ZIndex = 4 })
	local amount = text(reward, "Amount", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 15, Text = "40", TextTruncate = Enum.TextTruncate.None, ZIndex = 4 })
	amount:SetAttribute("FitTextSkip", true)
	local barX = right - 108 - 16 - 88 - 16 - 180
	local bar = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(barX, 16), Size = UDim2.fromOffset(180, 14), BackgroundColor3 = PAPER, ClipsDescendants = true, ZIndex = 3 }, row)
	corner(bar, 7)
	stroke(bar, 2.5)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = BLUE, BorderSizePixel = 0, ZIndex = 4 }, bar)
	corner(fill, 7)
	text(row, "Count", { Position = UDim2.fromOffset(barX, 33), Size = UDim2.fromOffset(180, 16), TextSize = 12, Text = "2 / 5", TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
end

-- [[ Shop ]]

local ITEM_W, ITEM_H = 206, 270

local function shop(panel: Frame)
	local s = scroll(panel, "Shop")
	s.Visible = false
	new("UIGridLayout", { CellSize = UDim2.fromOffset(ITEM_W, ITEM_H), CellPadding = UDim2.fromOffset(16, 18), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	s.UIPadding.PaddingTop = UDim.new(0, 14)

	local cell = new("Frame", { Name = "ItemTemplate", BackgroundTransparency = 1, Visible = false, ZIndex = 2 }, s)
	local card = new("Frame", { Name = "Card", Size = UDim2.fromOffset(ITEM_W - 6, ITEM_H - 6), BackgroundColor3 = WHITE, ZIndex = 3 }, cell)
	corner(card, 14)
	stroke(card, 3)
	shadowOf(card, 4, 14, 3)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(ITEM_W - 26, 108), BackgroundColor3 = ICE, ClipsDescendants = true, ZIndex = 4 }, card)
	corner(art, 10)
	stroke(art, 3)
	icon(art, "Pic", SNOWFLAKE, 88, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5 })
	local title = text(art, "TitleChip", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = ICE, TextSize = 16, Text = "Snow Bias", TextTruncate = Enum.TextTruncate.None, Visible = false, ZIndex = 5 })
	corner(title, 9)
	stroke(title, 2.5)
	pad(title, 12)
	title:SetAttribute("FitTextSkip", true)
	-- the pack's "Open" (you have some unopened)
	local openPack = new("TextButton", { Name = "OpenPack", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = MINT, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 6 }, art)
	corner(openPack, 8)
	stroke(openPack, 2.5)
	pad(openPack, 9)
	local ol = text(openPack, "Label", { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, Text = "Open ×2", TextTruncate = Enum.TextTruncate.None, ZIndex = 7 })
	ol:SetAttribute("FitTextSkip", true)

	local tag = text(card, "Tag", { Position = UDim2.fromOffset(12, -12), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = C("FF9EC4"), TextSize = 11, Text = "EXCLUSIVE", TextTruncate = Enum.TextTruncate.None, ZIndex = 8 })
	corner(tag, 7)
	stroke(tag, 2)
	pad(tag, 8)
	tag:SetAttribute("FitTextSkip", true)

	text(card, "Title", { Position = UDim2.fromOffset(12, 126), Size = UDim2.fromOffset(ITEM_W - 30, 20), FontFace = BODY, TextSize = 16, Text = "Winter pack", ZIndex = 4 })
	text(card, "Hint", { Position = UDim2.fromOffset(12, 148), Size = UDim2.fromOffset(ITEM_W - 30, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "5 cards · 1 winter card", ZIndex = 4 })
	text(card, "Stock", { Position = UDim2.fromOffset(12, 166), Size = UDim2.fromOffset(ITEM_W - 30, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "10 left today", ZIndex = 4 })
	local buy = new("TextButton", { Name = "Buy", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((ITEM_W - 6) / 2, 222), Size = UDim2.fromOffset(ITEM_W - 30, 42), BackgroundColor3 = ICE, Text = "", AutoButtonColor = false, ZIndex = 5 }, card)
	corner(buy, 11)
	stroke(buy, 3)
	shadowOf(buy, 3, 11, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, buy)
	icon(buy, "Icon", SNOWFLAKE, 20, { LayoutOrder = 1, ZIndex = 6 })
	local price = text(buy, "Price", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 16, Text = "150", TextTruncate = Enum.TextTruncate.None, ZIndex = 6 })
	price:SetAttribute("FitTextSkip", true)

	-- the note at the end of the grid
	local note = new("Frame", { Name = "Note", LayoutOrder = 999, BackgroundTransparency = 1, ZIndex = 2 }, s)
	local box = new("Frame", { Name = "Box", Size = UDim2.fromOffset(ITEM_W - 6, ITEM_H - 6), BackgroundTransparency = 1, ZIndex = 3 }, note)
	corner(box, 14)
	stroke(box, 3, C("CFC3A6"))
	text(box, "Label", { Position = UDim2.fromOffset(16, 16), Size = UDim2.new(1, -32, 1, -32), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "Left-over Snowflakes turn into coins when the event ends (1 = 5 coins), so nothing is wasted. Unopened Winter packs become gen packs.", ZIndex = 4 })
end

-- [[ Snow ]]

-- soft dots over the scrim; EventsController drifts them down
local function snow(root: Frame)
	local s = new("Frame", { Name = "Snow", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, ClipsDescendants = false, ZIndex = 1 }, root)
	local rng = Random.new(1225)
	for i = 1, 46 do
		local size = rng:NextInteger(3, 7)
		local f = new("Frame", { Name = "Flake" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rng:NextInteger(0, 1280), rng:NextInteger(0, 720)), Size = UDim2.fromOffset(size, size), BackgroundColor3 = WHITE, BackgroundTransparency = rng:NextNumber(0.25, 0.65), BorderSizePixel = 0, ZIndex = 1 }, s)
		corner(f, 4)
		f:SetAttribute("Speed", rng:NextNumber(14, 34))
	end
end

function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Events")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Events", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 1 })
	local scrim = new("TextButton", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = WHITE, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 0 }, root)
	scrim.Active = true
	-- (the scrim is 4000 tall, centred: the canvas spans about 0.41 to 0.59)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C("2E3C6E")),
			ColorSequenceKeypoint.new(0.41, C("2E3C6E")),
			ColorSequenceKeypoint.new(0.5, C("2A2346")),
			ColorSequenceKeypoint.new(0.59, C("221C36")),
			ColorSequenceKeypoint.new(1, C("221C36")),
		}),
	}, scrim)
	snow(root)
	header(root)
	eventList(root)
	local panelShadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(PANEL_X + 8 - 4, PANEL_Y + 8 - 4), Size = UDim2.fromOffset(PANEL_W + 8, PANEL_H + 8), BackgroundColor3 = INK, ZIndex = 1 }, root)
	corner(panelShadow, 22)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(PANEL_X, PANEL_Y), Size = UDim2.fromOffset(PANEL_W, PANEL_H), BackgroundColor3 = CREAM, ClipsDescendants = true, ZIndex = 2 }, root)
	corner(panel, 22)
	stroke(panel, 4)
	banner(panel)
	tabs(panel)
	missions(panel)
	shop(panel)
	local toast = text(root, "Toast", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(770, 24), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = CREAM, TextSize = 16, Text = "", TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Visible = false, ZIndex = 30 })
	corner(toast, 10)
	pad(toast, 16)
	root.Parent = frames
	return root
end

return Build
