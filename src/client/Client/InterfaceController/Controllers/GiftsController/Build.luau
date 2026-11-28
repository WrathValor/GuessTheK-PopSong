--| Gifts UI builder
-- Builds Interface.Frames.Gifts from design board "56 · Gifts inbox + send to anyone". Run once
-- in Studio Edit mode (an existing one is replaced), then save the place:
--   local m = game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.GiftsController.Build
--   local c = m:Clone(); c.Parent = m.Parent; require(c).Build(game.StarterGui.Interface.Frames); c:Destroy()
-- One panel over a scrim:
--   Panel.Header   the gift icon, GIFTS, "n waiting · gifts last 30 days", the Inbox / Send a gift
--                  tabs, Close
--   Panel.Inbox    List (a ScrollingFrame; rows cloned from List.Template: the item square, its
--                  name + DEVELOPER chip, From, the note and when, CLAIM), Empty, the footer note
--                  and CLAIM ALL
--   Panel.Send     the username search (Box + Find), People (a ScrollingFrame: section heads from
--                  HeadTemplate, people from PersonTemplate: headshot, name, line under it), the
--                  note box and SHOP FOR <NAME>
-- GiftsController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local PINK = C("FF9EC4")
local PINK_LIGHT = C("FFE4EF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local GIFT_ICON = "rbxassetid://119916041465663" -- the HUD's Gifts icon (assets/UI/HUD/v3/Gifts.png)
local CLOSE_ICON = "rbxassetid://118345756178429"

local W, H = 900, 600 -- the panel
local HEADER = 84

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
local function stroke(p: Instance, t: number)
	new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
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
-- an ink-outlined button with a hard shadow (centre cx, cy)
local function button(parent: Instance, name: string, cx: number, cy: number, w: number, h: number, colour: Color3, label: string, size: number): TextButton
	local s = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + 3, cy + 3), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK }, parent)
	corner(s, 12)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, FontFace = BODY, TextSize = size, TextColor3 = INK, Text = label, AutoButtonColor = false, ZIndex = 2 }, parent)
	corner(b, 12)
	stroke(b, 3)
	return b
end
local function list(parent: Instance, gap: number)
	new("UIListLayout", { Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

-- [[ Header ]]

local function header(panel: Frame)
	local h = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, HEADER), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	corner(h, 18)
	new("UIGradient", { Color = ColorSequence.new(PINK_LIGHT, PINK) }, h)
	-- (squares off the header's bottom corners)
	local square = new("Frame", { Name = "Square", Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0 }, h)
	new("UIGradient", { Color = ColorSequence.new(PINK_LIGHT, PINK) }, square)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, HEADER), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)

	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.fromOffset(52, 52), BackgroundTransparency = 1, Image = GIFT_ICON }, h)
	text(h, "Title", { Position = UDim2.fromOffset(84, 16), Size = UDim2.fromOffset(300, 30), FontFace = HEAD, TextSize = 26, Text = "GIFTS" })
	text(h, "Sub", { Position = UDim2.fromOffset(84, 48), Size = UDim2.fromOffset(360, 18), TextSize = 14, Text = "3 waiting · gifts last 30 days" })

	-- Inbox / Send a gift
	local tabs = new("Frame", { Name = "Tabs", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -78, 0.5, 0), Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, BackgroundTransparency = 0.85 }, h)
	corner(tabs, 12)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, tabs)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, spec in { { "Inbox", "Inbox" }, { "Send", "Send a gift" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, BackgroundTransparency = if i == 1 then 0 else 1, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = spec[2], AutoButtonColor = false }, tabs)
		corner(b, 9)
		pad(b, 16)
	end

	local cs = new("Frame", { Name = "CloseShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -38 + 3, 0.5, 3), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = INK }, h)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -38, 0.5, 0), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = RED, Image = "", AutoButtonColor = false, ZIndex = 2 }, h)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON, ZIndex = 3 }, close)
end

-- [[ Inbox ]]

local function inbox(panel: Frame)
	local page = new("Frame", { Name = "Inbox", Position = UDim2.fromOffset(0, HEADER + 4), Size = UDim2.new(1, 0, 1, -(HEADER + 4)), BackgroundTransparency = 1 }, panel)
	local scroll = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(22, 16),
		Size = UDim2.new(1, -44, 1, -96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = INK,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)
	list(scroll, 12)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 6) }, scroll)

	-- a gift row (the template)
	local row = new("Frame", { Name = "Template", Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = WHITE, Visible = false }, scroll)
	corner(row, 16)
	stroke(row, 3)
	local item = new("Frame", { Name = "Item", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(58, 58), BackgroundColor3 = C("FFF0B8") }, row)
	corner(item, 12)
	stroke(item, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(42, 42), BackgroundTransparency = 1, Image = GIFT_ICON, ScaleType = Enum.ScaleType.Fit }, item)
	text(item, "Big", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 20, Text = "", TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	local top = new("Frame", { Name = "Top", Position = UDim2.fromOffset(88, 12), Size = UDim2.new(1, -230, 0, 22), BackgroundTransparency = 1 }, row)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, top)
	text(top, "Item", { LayoutOrder = 1, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 17, Text = "5,000 Coins", TextTruncate = Enum.TextTruncate.None })
	local dev = new("TextLabel", { Name = "Dev", LayoutOrder = 2, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = YELLOW, FontFace = BODY, TextSize = 11, TextColor3 = INK, Text = "DEVELOPER", Visible = false }, top)
	corner(dev, 6)
	stroke(dev, 2)
	pad(dev, 6)
	text(row, "From", { Position = UDim2.fromOffset(88, 35), Size = UDim2.new(1, -230, 0, 18), TextSize = 14, Text = "From mujta" })
	text(row, "Note", { Position = UDim2.fromOffset(88, 54), Size = UDim2.new(1, -230, 0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "“Thanks for testing!” · 2 h ago" })
	button(row, "Claim", 0, 0, 116, 46, MINT, "CLAIM", 16)
	for _, n in { "Claim", "ClaimShadow" } do
		local b = row[n]
		-- (Claim centred so ButtonScale grows it from the middle; the shadow stays right-anchored)
		b.AnchorPoint = if n == "Claim" then Vector2.new(0.5, 0.5) else Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, if n == "Claim" then -16 - b.Size.X.Offset / 2 else -13, 0.5, if n == "Claim" then 0 else 3)
	end

	text(page, "Empty", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -40), Size = UDim2.fromOffset(560, 60), TextSize = 16, TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Text = "No gifts yet. Gifts from friends land here, even when you're offline.", Visible = false })
	text(page, "Footer", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 24, 1, -40), Size = UDim2.fromOffset(520, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Unclaimed gifts go after 30 days. Up to 30 can wait." })
	button(page, "ClaimAll", W - 24 - 90, H - HEADER - 4 - 40, 180, 50, YELLOW, "CLAIM ALL", 17)
end

-- [[ Send a gift ]]

local function send(panel: Frame)
	local page = new("Frame", { Name = "Send", Position = UDim2.fromOffset(0, HEADER + 4), Size = UDim2.new(1, 0, 1, -(HEADER + 4)), BackgroundTransparency = 1, Visible = false }, panel)
	text(page, "Hint", { Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(600, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "To anyone, in any server, even offline. Search a username or pick a friend." })

	-- the search: @ + box, Find
	local search = new("Frame", { Name = "Search", Position = UDim2.fromOffset(24, 42), Size = UDim2.fromOffset(W - 48 - 130, 48), BackgroundColor3 = WHITE }, page)
	corner(search, 12)
	stroke(search, 3)
	text(search, "At", { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(20, 48), TextSize = 16, TextColor3 = MUTED, Text = "@" })
	new("TextBox", { Name = "Box", Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -48, 1, 0), BackgroundTransparency = 1, FontFace = BODY, TextSize = 16, TextColor3 = INK, PlaceholderText = "Username", PlaceholderColor3 = C("A9A2B8"), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false }, search)
	button(page, "Find", W - 24 - 57, 66, 114, 48, YELLOW, "FIND", 16)

	-- people: found + friends
	local scroll = new("ScrollingFrame", {
		Name = "People",
		Position = UDim2.fromOffset(24, 104),
		Size = UDim2.new(1, -48, 0, 236),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = INK,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)
	list(scroll, 6)
	new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 4) }, scroll)
	text(scroll, "HeadTemplate", { Size = UDim2.new(1, 0, 0, 22), FontFace = BODY, TextSize = 12, TextColor3 = MUTED, Text = "FRIENDS", Visible = false })
	local person = new("TextButton", { Name = "PersonTemplate", Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = YELLOW, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false }, scroll)
	corner(person, 12)
	new("UIStroke", { Color = INK, Thickness = 3, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, person)
	local av = new("ImageLabel", { Name = "Avatar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = C("E5DCFF"), Image = "" }, person)
	corner(av, 21)
	stroke(av, 3)
	text(person, "PersonName", { Position = UDim2.fromOffset(64, 9), Size = UDim2.new(1, -80, 0, 20), TextSize = 16, Text = "lunaa" })
	text(person, "Line", { Position = UDim2.fromOffset(64, 29), Size = UDim2.new(1, -80, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Friend · online" })
	text(scroll, "Loading", { Size = UDim2.new(1, 0, 0, 40), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "Loading your friends…", Visible = false })

	-- note + SHOP FOR
	text(page, "NoteLabel", { Position = UDim2.fromOffset(24, 352), Size = UDim2.fromOffset(400, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Add a note (optional)" })
	local note = new("Frame", { Name = "Note", Position = UDim2.fromOffset(24, 374), Size = UDim2.fromOffset(W - 48, 44), BackgroundColor3 = WHITE }, page)
	corner(note, 12)
	stroke(note, 3)
	new("TextBox", { Name = "Box", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), BackgroundTransparency = 1, FontFace = BODY, TextSize = 15, TextColor3 = INK, PlaceholderText = "gg from the duel!", PlaceholderColor3 = C("A9A2B8"), Text = "", TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false }, note)
	button(page, "ShopFor", W / 2, H - HEADER - 4 - 44, W - 48, 54, PINK, "PICK SOMEONE", 18)
end

function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Gifts")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Gifts", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 1 })
	local scrim = new("TextButton", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0, Text = "", AutoButtonColor = false }, root)
	scrim.Active = true
	local shadow = new("Frame", { Name = "PanelShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640 + 6, 370 + 6), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK }, root)
	corner(shadow, 22)
	local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 370), Size = UDim2.fromOffset(W, H), BackgroundColor3 = CREAM, ClipsDescendants = false }, root)
	corner(panel, 22)
	stroke(panel, 4)
	header(panel)
	inbox(panel)
	send(panel)
	local toast = text(root, "Toast", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 22), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = CREAM, TextSize = 16, Text = "", TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 30 })
	corner(toast, 10)
	pad(toast, 16)
	root.Parent = frames
	return root
end

return Build
