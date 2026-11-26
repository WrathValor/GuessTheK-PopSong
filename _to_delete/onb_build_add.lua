-- ------------------------------- Onboarding ------------------------------- --
-- The K-POPPED! onboarding (design boards 62–62e, ./Flow): two new cards on the Tutorial frame
-- and the coach marks, all instances. Run once in Edit (again = rebuilt):
--   local m = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("TutorialController", true).Build
--   local c = m:Clone(); c.Parent = m.Parent; require(c).Onboarding(game.StarterGui.Interface.Frames); c:Destroy()
--   • Tutorial.Hello  – board 62b: WELCOME TO / K-POPPED!, the line, four step tiles (Step1–4:
--                       Num, Title, Line; Step4 hides for returning players), Go, Skip
--   • Tutorial.AllSet – board 62e: YOU'RE ALL SET!, the rewards (Coins / Ticket / XP: Amount),
--                       three live lines (Line1–3), QuickPlay + Lobby
--   • Frames.Coach    – boards 62c / 62d: Dim (Top / Bottom / Left / Right), Ring, BubbleShadow,
--                       Bubble (Tag, Title, Body, Next + NextShadow), Arrow, Skip (top right)

-- a card whose hard shadow is grown by its outline (UIStroke draws outside the frame)
local function slab(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, r: number, drop: number, line: number): Frame
	local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + drop - line, y + drop - line), Size = UDim2.fromOffset(w + line * 2, h + line * 2), BackgroundColor3 = INK }, parent)
	corner(s, r + line)
	local f = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour }, parent)
	corner(f, r)
	stroke(f, line)
	return f
end

local function tag(parent: Instance, name: string, label: string, colour: Color3, size: number)
	local b = text(parent, name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		FontFace = HEAD,
		TextSize = size,
		Text = label,
		Rotation = -2,
		ZIndex = 3,
	})
	corner(b, 12)
	stroke(b, 4)
	new("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, b)
	return b
end

local function hello(root: Frame)
	local w = slab(root, "Hello", 220, 110, 840, 500, CREAM, 24, 8, 4)
	w.Visible = false
	root.HelloShadow.Visible = false
	tag(w, "Badge", "WELCOME TO", YELLOW, 20)
	local title = text(w, "Title", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 76), FontFace = HEAD, TextSize = 64, TextColor3 = PINK, Rotation = -2, Text = "K-POPPED!" })
	new("UIStroke", { Color = INK, Thickness = 3 }, title)
	text(w, "Sub", { Position = UDim2.fromOffset(0, 124), Size = UDim2.new(1, 0, 0, 24), FontFace = BODY, TextSize = 18, TextColor3 = MUTED, Text = "Collect K-pop photocards. Guess the songs. Build your binder." })
	local row = new("Frame", { Name = "Steps", Position = UDim2.fromOffset(40, 172), Size = UDim2.fromOffset(760, 150), BackgroundTransparency = 1 }, w)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i, spec in { { "Pick your bias", "Your favourite member", PINK }, { "Open a pack", "Free, from their group", LILAC }, { "Pin & earn", "Coins every hour", MINT }, { "Guess songs", "Beat your rivals", BLUE } } do
		local holder = new("Frame", { Name = "Step" .. i, LayoutOrder = i, Size = UDim2.fromOffset(176, 146), BackgroundTransparency = 1 }, row)
		local t = slab(holder, "Card", 0, 0, 172, 142, spec[3], 16, 4, 3)
		text(t, "Num", { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(40, 34), FontFace = HEAD, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(i) })
		text(t, "Title", { Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -24, 0, 22), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Text = spec[1] })
		text(t, "Line", { Position = UDim2.fromOffset(14, 82), Size = UDim2.new(1, -24, 0, 36), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = spec[2] })
	end
	button(w, "Go", 420, 382, 360, 62, MINT, "LET'S GO", 24, HEAD, 6)
	local skip = new("TextButton", { Name = "Skip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(420, 446), Size = UDim2.fromOffset(160, 28), BackgroundTransparency = 1, FontFace = BODY, TextSize = 14, TextColor3 = C("6B6480"), RichText = true, Text = "<u>Skip tutorial</u>", AutoButtonColor = false }, w)
	skip:SetAttribute("NoButtonScale", true)
end

local function allSet(root: Frame)
	local d = slab(root, "AllSet", 300, 120, 680, 476, CREAM, 24, 8, 4)
	d.Visible = false
	root.AllSetShadow.Visible = false
	tag(d, "Badge", "YOU'RE ALL SET!", MINT, 20)
	text(d, "Sub", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 24), FontFace = BODY, TextSize = 17, TextColor3 = MUTED, Text = "Your binder is earning. Here's something for the road:" })
	for i, spec in { { "Coins", "+250", "coins", YELLOW }, { "Ticket", "×1", "pack ticket", C("DCD3FF") }, { "XP", "+50", "XP", MINT } } do
		local t = slab(d, spec[1], 40 + (i - 1) * 206, 86, 186, 116, spec[4], 16, 4, 3)
		text(t, "Amount", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 40), FontFace = HEAD, TextSize = 32, Text = spec[2] })
		text(t, "Label", { Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 18), FontFace = BODY, TextSize = 14, Text = spec[3] })
	end
	for i = 1, 3 do
		local l = new("Frame", { Name = "Line" .. i, Position = UDim2.fromOffset(40, 222 + (i - 1) * 44), Size = UDim2.fromOffset(600, 36), BackgroundColor3 = WHITE }, d)
		corner(l, 12)
		new("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, l)
		text(l, "Text", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), FontFace = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Text = "Next free pack in <b>1 h 58 min</b>" })
	end
	local qp = button(d, "QuickPlay", 188, 416, 296, 56, RED, "QUICK PLAY", 20, HEAD, 5)
	qp.TextColor3 = WHITE
	button(d, "Lobby", 492, 416, 296, 56, CREAM, "TO THE LOBBY", 20, HEAD, 5)
end

local COACH_Z = 300
Build.COACH_BUBBLE = Vector2.new(440, 186) -- the bubble's size (./Flow places it beside the spot)

local function coach(frames: Instance)
	local old = frames:FindFirstChild("Coach")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Coach", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = COACH_Z })
	local dim = new("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = COACH_Z }, root)
	for _, n in { "Top", "Bottom", "Left", "Right" } do
		new("Frame", { Name = n, BackgroundColor3 = C("141028"), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = COACH_Z }, dim)
	end
	local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, ZIndex = COACH_Z + 1 }, root)
	corner(ring, 18)
	new("UIStroke", { Color = YELLOW, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	local bw, bh = Build.COACH_BUBBLE.X, Build.COACH_BUBBLE.Y
	local shadow = new("Frame", { Name = "BubbleShadow", Size = UDim2.fromOffset(bw + 8, bh + 8), BackgroundColor3 = INK, ZIndex = COACH_Z + 2 }, root)
	corner(shadow, 22)
	local bubble = new("Frame", { Name = "Bubble", Size = UDim2.fromOffset(bw, bh), BackgroundColor3 = CREAM, ZIndex = COACH_Z + 3, Active = true }, root)
	corner(bubble, 18)
	stroke(bubble, 4)
	local stepTag = text(bubble, "Tag", { Position = UDim2.fromOffset(18, 16), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = YELLOW, FontFace = BODY, TextSize = 12, Text = "STEP 4 OF 9", ZIndex = COACH_Z + 4 })
	corner(stepTag, 7)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, stepTag)
	text(bubble, "Title", { Position = UDim2.fromOffset(18, 44), Size = UDim2.new(1, -36, 0, 26), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Text = "Pin your best card", ZIndex = COACH_Z + 4 })
	text(bubble, "Body", { Position = UDim2.fromOffset(18, 74), Size = UDim2.new(1, -36, 0, 58), FontFace = BODY_BOLD, TextSize = 15, TextColor3 = C("4A4458"), TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "Pinned cards earn coins every hour, even while you're away.", ZIndex = COACH_Z + 4 })
	local nb = button(bubble, "Next", bw / 2, bh - 30, bw - 36, 40, MINT, "NEXT", 16, HEAD, 4)
	nb.ZIndex = COACH_Z + 5
	bubble.NextShadow.ZIndex = COACH_Z + 4
	-- the pointer: a cream square turned 45°, half under the bubble's edge (./Flow moves it)
	local arrow = new("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), Rotation = 45, BackgroundColor3 = CREAM, ZIndex = COACH_Z + 2 }, root)
	stroke(arrow, 4)
	local skipShadow = new("Frame", { Name = "SkipShadow", Position = UDim2.fromOffset(1092 + 3 - 2, 18 + 3 - 2), Size = UDim2.fromOffset(160 + 4, 36 + 4), BackgroundColor3 = INK, ZIndex = COACH_Z + 4 }, root)
	corner(skipShadow, 12)
	local skip = new("TextButton", { Name = "Skip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(1092 + 80, 18 + 18), Size = UDim2.fromOffset(160, 36), BackgroundColor3 = CREAM, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = "Skip tutorial", AutoButtonColor = false, ZIndex = COACH_Z + 5 }, root)
	corner(skip, 10)
	new("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, skip)
	root.Parent = frames
end

function Build.Onboarding(frames: Instance)
	local root = frames:FindFirstChild("Tutorial") or Build.Build(frames)
	for _, n in { "Hello", "HelloShadow", "AllSet", "AllSetShadow" } do
		local old = root:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	hello(root)
	allSet(root)
	coach(frames)
	local center = require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons)
	center.Apply(root)
	center.Apply(frames.Coach)
end

