--| Tutorial UI builder
-- Builds Interface.Frames.Tutorial from the "Tutorial" design boards: the first-join Welcome
-- card and the "You're ready!" card after the practice round (Done: find a rival / keep
-- practising). Also adds the "Replay tutorial" button to Settings. Run once in Studio
-- (Build.Build(frames)); safe to run twice. (DoneRoll, "Tutorial 5", went with the song roll.)
-- TutorialController finds everything by name. The in-round tips are drawn by ./Tips.
-- Build.Onboarding (below) adds the K-POPPED! onboarding's cards and coach marks (boards 62–62e).

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local Currencies = require(game:GetService("ReplicatedStorage").Constants.Currencies)
local COIN = Currencies.Coins.Icon
local LILAC = C("B9A6FF")
local PINK = C("FF9EC4")
local BLUE = C("9ED8F5")

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
local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function card(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, r: number, drop: number, line: number): Frame
	if drop > 0 then
		local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + drop, y + drop), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK }, parent)
		corner(s, r)
	end
	local f = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour }, parent)
	corner(f, r)
	stroke(f, line)
	return f
end
-- a centre-anchored button with a hard shadow (ButtonScale grows it from the middle)
local function button(parent: Instance, name: string, cx: number, cy: number, w: number, h: number, colour: Color3, label: string, size: number, font: Font?, drop: number?): TextButton
	local d = drop or 5
	if d > 0 then
		local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(cx - w / 2 + d, cy - h / 2 + d), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK }, parent)
		corner(s, 14)
	end
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		FontFace = font or HEAD,
		TextSize = size,
		TextColor3 = INK,
		Text = label,
		AutoButtonColor = false,
	}, parent)
	corner(b, 14)
	stroke(b, 3)
	return b
end
local function badge(parent: Instance, label: string, colour: Color3)
	local b = text(parent, "Badge", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		FontFace = HEAD,
		TextSize = 18,
		Text = label,
		Rotation = -2,
		ZIndex = 3,
	})
	corner(b, 12)
	stroke(b, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, b)
end

-- one "how it works" photocard: art on top, a step title, one line
local function stepCard(parent: Instance, name: string, x: number, colour: Color3, title: string, line: string): Frame
	local c = card(parent, name, x, 150, 220, 250, WHITE, 16, 5, 3)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 156), BackgroundColor3 = colour }, c)
	corner(art, 10)
	stroke(art, 2)
	text(c, "Title", { Position = UDim2.fromOffset(12, 172), Size = UDim2.new(1, -24, 0, 26), FontFace = HEAD, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Text = title })
	text(c, "Line", { Position = UDim2.fromOffset(12, 200), Size = UDim2.new(1, -24, 0, 36), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = line })
	return art
end

local function welcome(root: Frame)
	local w = card(root, "Welcome", 230, 70, 820, 580, CREAM, 20, 8, 3)
	w.Visible = false
	root.WelcomeShadow.Visible = false
	badge(w, "WELCOME!", YELLOW)
	text(w, "Title", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 46), FontFace = HEAD, TextSize = 40, Text = "K-POPPED!" })
	text(w, "Sub", { Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 24), FontFace = BODY_BOLD, TextSize = 18, TextColor3 = MUTED, Text = "Hear a snippet. Guess the song. Beat your rival." })

	local listen = stepCard(w, "Listen", 59, C("FFD2CE"), "1 · Listen", "A tiny clip plays. 0.5 seconds!")
	local play = new("Frame", { Name = "Play", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(74, 74), BackgroundColor3 = RED }, listen)
	corner(play, 37)
	stroke(play, 3)
	text(play, "Icon", { Position = UDim2.fromOffset(3, 0), Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 44, Text = "▶" })

	local pick = stepCard(w, "Pick", 300, C("DCD3FF"), "2 · Pick", "Choose 1 of 4 songs. Faster = more points.")
	for i = 1, 3 do
		local bar = new("Frame", { Name = "Option" .. i, Position = UDim2.new(0, 16, 0, 22 + (i - 1) * 40), Size = UDim2.new(1, -32, 0, 30), BackgroundColor3 = if i == 2 then YELLOW else WHITE }, pick)
		corner(bar, 8)
		stroke(bar, 2)
	end

	local win = stepCard(w, "Win", 541, MINT, "3 · Win", "Most points after 7 rounds takes the coins.")
	local chip = text(win, "Chip", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(140, 40), BackgroundTransparency = 0, BackgroundColor3 = RED, FontFace = HEAD, TextSize = 20, Text = "YOU WIN!", Rotation = -4 })
	corner(chip, 10)
	stroke(chip, 3)

	button(w, "Play", 410, 470, 420, 70, MINT, "PLAY A PRACTICE ROUND", 24, HEAD, 6)
	button(w, "Skip", 410, 540, 100, 40, RED, "SKIP", 14, HEAD, 3)
end

local function done(root: Frame)
	local d = card(root, "Done", 340, 140, 600, 440, CREAM, 20, 8, 3)
	d.Visible = false
	root.DoneShadow.Visible = false
	badge(d, "PRACTICE DONE", MINT)
	text(d, "Title", { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 46), FontFace = HEAD, TextSize = 40, Text = "You're ready!" })
	text(d, "Score", { Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 22), FontFace = BODY_BOLD, TextSize = 17, TextColor3 = MUTED, Text = "3 of 3 right · you know how it works" })
	local gift = card(d, "Gift", 150, 140, 300, 84, YELLOW, 16, 5, 3)
	new("ImageLabel", { Name = "Coin", Position = UDim2.fromOffset(18, 17), Size = UDim2.fromOffset(50, 50), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit }, gift)
	text(gift, "Amount", { Position = UDim2.fromOffset(82, 14), Size = UDim2.new(1, -96, 0, 32), FontFace = HEAD, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Text = "+100 coins" })
	text(gift, "Line", { Position = UDim2.fromOffset(82, 48), Size = UDim2.new(1, -96, 0, 20), FontFace = BODY_BOLD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = "a welcome gift" })
	button(d, "FindRival", 300, 296, 520, 66, MINT, "FIND A RIVAL", 22, HEAD, 6)
	button(d, "KeepPractising", 300, 374, 520, 52, WHITE, "Keep practising (solo)", 16, BODY, 0)
end

-- "Replay tutorial" at the bottom-left of Settings, next to "Reset to default"
function Build.AddSettingsButton(frames: Instance)
	local settings = frames:FindFirstChild("Settings")
	local content = settings and settings:FindFirstChild("Panel") and settings.Panel:FindFirstChild("Content")
	local reset = content and content:FindFirstChild("Reset")
	if not reset or content:FindFirstChild("ReplayTutorial") then
		return
	end
	local shadow = content:FindFirstChild("ResetShadow")
	if shadow then
		local s = shadow:Clone()
		s.Name = "ReplayTutorialShadow"
		s.Position = UDim2.new(0, 3, 1, -38)
		s.Size = UDim2.fromOffset(170, 38)
		s.Parent = content
	end
	local b = reset:Clone()
	b.Name = "ReplayTutorial"
	b.Text = "Replay tutorial"
	b.Position = UDim2.new(0, 85, 1, -22)
	b.Size = UDim2.fromOffset(170, 38)
	b.Parent = content
end

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
--                       Bubble (Tag, Title, Body, Skip, Next + NextShadow), Arrow,
--                       Skip (top right: only while no bubble is up)

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
	-- Skip tutorial inside the bubble, on the tag's line (the corner Skip is only for steps with no bubble)
	local bubbleSkip = new("TextButton", { Name = "Skip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(bw - 18, 16), Size = UDim2.fromOffset(110, 22), BackgroundTransparency = 1, FontFace = BODY, TextSize = 13, TextColor3 = C("6B6480"), TextXAlignment = Enum.TextXAlignment.Right, RichText = true, Text = "<u>Skip tutorial</u>", AutoButtonColor = false, ZIndex = COACH_Z + 5 }, bubble)
	bubbleSkip:SetAttribute("NoButtonScale", true)
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

function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Tutorial")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Tutorial", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 1 })
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
	welcome(root)
	done(root)
	root.Parent = frames
	Build.AddSettingsButton(frames)
	return root
end

return Build
