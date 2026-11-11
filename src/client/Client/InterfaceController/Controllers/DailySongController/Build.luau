--| DailySong UI builder
-- Builds Interface.Frames.DailySong from the "Daily Song" boards on the design canvas (Daily
-- Song 1 · playing, 2 · solved). It opens from the listening booth on the plaza
-- (Map.DailySongBooth, wired in Client/StreetScreens); there's no HUD button. One frame, two
-- views: Body.Play (the mystery card, the clip ladder, your guesses + the search
-- box) and Body.Result (the revealed song, your squares, how everyone did, coins + streak).
-- Run once in Studio from the command bar (Edit mode):
--   local B = require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.DailySongController.Build)
--   B.Build(game.StarterGui.Interface.Frames)
-- An existing frame is kept as ServerStorage.DailySong_Legacy. DailySongController finds
-- everything by name. Primary buttons are yellow with a plain dark shadow (no coloured shadows).

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local PAPER = C("FFF6D6")
local WHITE = C("FFFFFF")
local LILAC = C("B9A6FF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local PEACH = C("FFB38A")
local RED = C("FF5A4E")
local BLUE = C("9ED8F5")
local MUTED = C("5C566B")
local LINE = C("CFC5B3")
local SAND = C("EDE4D4")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CLOSE_ICON = "rbxassetid://118345756178429"

local Build = {}
Build.TRIES = 5
Build.STAT_ROWS = 6 -- tries 1–5 + Missed
Build.SUGGESTIONS = 4

-- [[ Helpers (same shapes as the other builders) ]]

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

local function stroke(p: Instance, t: number, colour: Color3?)
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
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

-- a face with a hard offset shadow behind it (Name + Name.."Shadow", siblings)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number, className: string?): any
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0, Visible = drop > 0 }, parent)
	corner(shadow, radius)
	local props = { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }
	if className == "TextButton" then
		props.AutoButtonColor = false
		props.Text = ""
	end
	local face = new(className or "Frame", props, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function button(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, label: string, font: Font, textSize: number): TextButton
	local b = card(parent, name, pos, size, colour, 12, 4, 3, "TextButton")
	b.Text = label
	b.FontFace = font
	b.TextSize = textSize
	b.TextColor3 = INK
	return b
end

local function chip(parent: Instance, name: string, label: string, colour: Color3, pos: UDim2?, size: number?): TextLabel
	local c = text(parent, name, {
		Position = pos or UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = size or 13,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
	})
	corner(c, 15)
	stroke(c, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, c)
	return c
end

local function rowLayout(parent: Instance, gap: number)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

-- the wrong / skip / right mark: a circle (or rounded square) with a glyph. Gotham has no ✕
-- or », so the controller writes "X" / ">>" in HEAD and "✓" in BODY (Builder Sans has it).
local function mark(parent: Instance, name: string, pos: UDim2, size: number, radius: UDim): Frame
	local m = new("Frame", { Name = name, Position = pos, Size = UDim2.fromOffset(size, size), BackgroundColor3 = WHITE }, parent)
	corner(m, radius)
	stroke(m, if size > 30 then 3 else 2)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.6), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ImageColor3 = INK, Image = "" }, m)
	return m
end

-- [[ Play view ]]

local function buildPlay(body: Frame)
	local view = new("Frame", { Name = "Play", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)

	-- LEFT: the clip
	local lx, lw = 24, 420
	local mystery = card(view, "Mystery", UDim2.fromOffset(lx, 22), UDim2.fromOffset(lw, 250), INK, 16, 5, 3)
	local inner = new("Frame", { Name = "Inner", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -28), BackgroundTransparency = 1 }, mystery)
	corner(inner, 10)
	stroke(inner, 2, MUTED)
	text(mystery, "Label", { Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(200, 18), FontFace = HEAD, TextSize = 13, TextColor3 = LILAC, Text = "TODAY'S SONG" })
	text(mystery, "Question", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(160, 130), FontFace = HEAD, TextSize = 110, TextColor3 = YELLOW, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "?" })
	local playShadow = new("Frame", { Name = "PlayShadow", Position = UDim2.new(1, -18 - 74 + 4, 1, -18 - 74 + 4), Size = UDim2.fromOffset(74, 74), BackgroundColor3 = CREAM }, mystery)
	corner(playShadow, UDim.new(0.5, 0))
	local play = new("TextButton", { Name = "PlayClip", Position = UDim2.new(1, -18 - 74, 1, -18 - 74), Size = UDim2.fromOffset(74, 74), BackgroundColor3 = YELLOW, AutoButtonColor = false, FontFace = HEAD, TextSize = 30, TextColor3 = INK, Text = "▶" }, mystery)
	corner(play, UDim.new(0.5, 0))
	stroke(play, 3)
	local plays = chip(mystery, "Plays", "Plays 0.1 s", WHITE, UDim2.new(0, 18, 1, -22 - 30), 14)
	plays.TextSize = 14

	text(view, "TryLabel", { Position = UDim2.fromOffset(lx, 288), Size = UDim2.fromOffset(200, 22), FontFace = HEAD, TextSize = 16, Text = "Try 1 of 5" })
	text(view, "TryHint", { Position = UDim2.fromOffset(lx + lw - 220, 288), Size = UDim2.fromOffset(220, 22), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "Each miss or skip plays more" })
	local ladder = new("Frame", { Name = "Ladder", Position = UDim2.fromOffset(lx, 318), Size = UDim2.fromOffset(lw, 62), BackgroundTransparency = 1 }, view)
	local tw = math.floor((lw - 4 * 8 - 3) / 5)
	for i = 1, Build.TRIES do
		local t = card(ladder, "Tier" .. i, UDim2.fromOffset((i - 1) * (tw + 8), 0), UDim2.fromOffset(tw, 58), WHITE, 12, 3, 3)
		text(t, "Len", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 22), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "0.1 s" })
		text(t, "Coins", { Position = UDim2.fromOffset(0, 31), Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "100 coins" })
	end

	local note = card(view, "Note", UDim2.fromOffset(lx, 396), UDim2.fromOffset(lw, 58), PAPER, 14, 0, 3)
	text(note, "Text", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -130, 1, 0), TextSize = 14, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = "Get it now for 100 coins" })
	local streak = chip(note, "Streak", "Streak 0", PEACH, UDim2.new(1, -14, 0.5, 0))
	streak.AnchorPoint = Vector2.new(1, 0.5)
	streak.Size = UDim2.fromOffset(0, 26)

	-- RIGHT: guesses
	local rx = lx + lw + 26
	local rw = 1040 - 6 - rx - 24
	local right = new("Frame", { Name = "Guesses", Position = UDim2.fromOffset(rx, 22), Size = UDim2.fromOffset(rw, 470), BackgroundTransparency = 1 }, view)
	text(right, "Heading", { Size = UDim2.fromOffset(200, 24), FontFace = HEAD, TextSize = 18, Text = "Your guesses" })
	for i = 1, Build.TRIES do
		local r = new("Frame", { Name = "Guess" .. i, Position = UDim2.fromOffset(0, 34 + (i - 1) * 58), Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = WHITE }, right)
		corner(r, 12)
		stroke(r, 3, LINE)
		mark(r, "Mark", UDim2.fromOffset(14, 12), 26, UDim.new(0.5, 0))
		text(r, "Title", { Position = UDim2.fromOffset(52, 0), Size = UDim2.new(0.5, -40, 1, 0), FontFace = BODY, TextSize = 16, Text = "" })
		text(r, "Artist", { Position = UDim2.new(0.5, 16, 0, 0), Size = UDim2.new(0.5, -90, 1, 0), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "" })
		text(r, "Len", { Position = UDim2.new(1, -70, 0, 0), Size = UDim2.fromOffset(56, 50), FontFace = BODY, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
	end

	-- the search box, with its suggestions opening upward over the guess rows
	local boxY = 34 + Build.TRIES * 58 + 6
	local box = new("Frame", { Name = "SearchBox", Position = UDim2.fromOffset(0, boxY), Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = WHITE }, right)
	corner(box, 12)
	stroke(box, 3)
	new("TextBox", {
		Name = "Input",
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -122, 1, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		FontFace = BODY,
		TextSize = 18,
		TextColor3 = INK,
		PlaceholderText = "Type a song or artist…",
		PlaceholderColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, box)
	text(box, "Count", { Position = UDim2.new(1, -100, 0, 0), Size = UDim2.fromOffset(88, 54), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "416 songs" })

	-- the rows sit in a rounded CanvasGroup (List): ClipsDescendants ignores rounded corners,
	-- so the highlighted row poked out of the card's corners. The card itself stays a Frame so
	-- its outline isn't clipped.
	local sugg = card(right, "Suggestions", UDim2.fromOffset(0, boxY - 8 - Build.SUGGESTIONS * 46), UDim2.new(1, 0, 0, Build.SUGGESTIONS * 46), WHITE, 12, 4, 3)
	sugg.ZIndex = 5
	local list = new("CanvasGroup", { Name = "List", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, sugg)
	corner(list, 12)
	right.SuggestionsShadow.ZIndex = 4
	sugg.Visible = false
	right.SuggestionsShadow.Visible = false
	for i = 1, Build.SUGGESTIONS do
		local s = new("TextButton", { Name = "Option" .. i, Position = UDim2.fromOffset(0, (i - 1) * 46), Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "", ZIndex = 6 }, list)
		s:SetAttribute("NoButtonScale", true) -- rows in a list don't zoom on hover (it shifted the row)
		if i < Build.SUGGESTIONS then
			new("Frame", { Name = "Rule", Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = SAND, BorderSizePixel = 0, ZIndex = 6 }, s)
		end
		text(s, "Title", { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0.55, -16, 1, 0), FontFace = BODY, TextSize = 15, ZIndex = 7, Text = "" })
		text(s, "Artist", { Position = UDim2.new(0.55, 8, 0, 0), Size = UDim2.new(0.45, -24, 1, 0), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, ZIndex = 7, Text = "" })
	end

	button(right, "Skip", UDim2.fromOffset(0, 470 - 54 + 46), UDim2.fromOffset(180, 54), WHITE, "Skip · hear 0.5 s", BODY, 15)
	button(right, "Guess", UDim2.fromOffset(196, 470 - 54 + 46), UDim2.new(1, -200, 0, 54), YELLOW, "GUESS", HEAD, 18)
	return view
end

-- [[ Result view ]]

local function buildResult(body: Frame)
	local view = new("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, body)

	-- LEFT: the revealed song card
	local lx, lw = 24, 330
	local holder = new("Frame", { Name = "SongHolder", Position = UDim2.fromOffset(lx, 22), Size = UDim2.fromOffset(lw, 380), BackgroundTransparency = 1, Rotation = -2 }, view)
	local songCard = card(holder, "Song", UDim2.new(), UDim2.fromScale(1, 1), WHITE, 16, 5, 3)
	-- the song's art as the Index draws it: the group's colours (GroupArt.Paint adds the
	-- gradient) with the song's initials. Nothing pokes outside it, so the tilt can't clip.
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -100), BackgroundColor3 = BLUE }, songCard)
	corner(art, 10)
	stroke(art, 2)
	text(art, "Initials", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 110, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "?" })
	text(songCard, "Title", { Position = UDim2.new(0, 14, 1, -84), Size = UDim2.new(1, -28, 0, 36), FontFace = HEAD, TextSize = 26, Text = "Song" })
	text(songCard, "Artist", { Position = UDim2.new(0, 14, 1, -46), Size = UDim2.new(1, -28, 0, 22), FontFace = BODY_BOLD, TextSize = 16, TextColor3 = MUTED, Text = "Artist · 2023" })
	local sticker = text(holder, "Sticker", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -20, 0, 2), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), Rotation = 8, BackgroundTransparency = 0, BackgroundColor3 = PEACH, FontFace = HEAD, TextSize = 15, TextTruncate = Enum.TextTruncate.None, Text = "DAY 7", ZIndex = 3 })
	corner(sticker, 10)
	stroke(sticker, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, sticker)
	button(view, "Chorus", UDim2.fromOffset(lx, 22 + 380 + 18), UDim2.fromOffset(lw, 46), WHITE, "▶  Play the chorus", BODY, 14)

	-- RIGHT
	local rx = lx + lw + 28
	local rw = 1040 - 6 - rx - 24
	local right = new("Frame", { Name = "Summary", Position = UDim2.fromOffset(rx, 22), Size = UDim2.fromOffset(rw, 500), BackgroundTransparency = 1 }, view)
	text(right, "Headline", { Size = UDim2.new(1, 0, 0, 44), FontFace = HEAD, TextSize = 38, Text = "GOT IT IN 3!" })
	text(right, "Sub", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 20), FontFace = BODY_BOLD, TextSize = 15, TextColor3 = MUTED, Text = "From a 2 s clip." })

	local squares = new("Frame", { Name = "Squares", Position = UDim2.fromOffset(0, 82), Size = UDim2.fromOffset(5 * 60, 54), BackgroundTransparency = 1 }, right)
	for i = 1, Build.TRIES do
		local sh = new("Frame", { Name = "Square" .. i .. "Shadow", Position = UDim2.fromOffset((i - 1) * 60 + 3, 3), Size = UDim2.fromOffset(50, 50), BackgroundColor3 = INK }, squares)
		corner(sh, 10)
		mark(squares, "Square" .. i, UDim2.fromOffset((i - 1) * 60, 0), 50, UDim.new(0, 10))
	end
	button(right, "Share", UDim2.fromOffset(5 * 60 + 10, 82), UDim2.fromOffset(190, 50), YELLOW, "SHARE IN CHAT", HEAD, 15)

	local chart = card(right, "Chart", UDim2.fromOffset(0, 156), UDim2.new(1, -4, 0, 206), WHITE, 14, 4, 3)
	text(chart, "Title", { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(240, 20), FontFace = HEAD, TextSize = 15, Text = "How everyone did" })
	text(chart, "Players", { Position = UDim2.new(1, -236, 0, 10), Size = UDim2.fromOffset(220, 20), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "0 players today" })
	for i = 1, Build.STAT_ROWS do
		local r = new("Frame", { Name = "Row" .. i, Position = UDim2.fromOffset(16, 38 + (i - 1) * 26), Size = UDim2.new(1, -32, 0, 20), BackgroundTransparency = 1 }, chart)
		text(r, "Label", { Size = UDim2.fromOffset(60, 20), TextSize = 12, Text = if i <= Build.TRIES then `Try {i}` else "Missed" })
		local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(66, 2), Size = UDim2.new(1, -116, 0, 16), BackgroundTransparency = 1 }, r)
		local bar = new("Frame", { Name = "Bar", Size = UDim2.fromScale(0.05, 1), BackgroundColor3 = if i <= Build.TRIES then BLUE else SAND }, track)
		corner(bar, 5)
		stroke(bar, 2)
		text(r, "Pct", { Position = UDim2.new(1, -44, 0, 0), Size = UDim2.fromOffset(44, 20), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Text = "0%" })
	end

	local coins = card(right, "Coins", UDim2.fromOffset(0, 384), UDim2.new(0.5, -8, 0, 64), YELLOW, 14, 0, 3)
	text(coins, "Amount", { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -100, 1, 0), FontFace = HEAD, TextSize = 22, Text = "+50 coins" })
	text(coins, "XP", { Position = UDim2.new(1, -86, 0, 0), Size = UDim2.fromOffset(72, 64), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Text = "+25 XP" })
	local streak = card(right, "Streak", UDim2.new(0.5, 4, 0, 384), UDim2.new(0.5, -8, 0, 64), PEACH, 14, 0, 3)
	text(streak, "Days", { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 26), FontFace = HEAD, TextSize = 19, Text = "7-day streak" })
	text(streak, "Best", { Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -32, 0, 16), FontFace = BODY_BOLD, TextSize = 12, Text = "Best: 12 days" })
	return view
end

-- [[ Frame ]]

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("DailySong")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("DailySong_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "DailySong_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "DailySong", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
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

	local W, H = 1040, 620
	local panel = card(root, "Panel", UDim2.fromOffset(120, 50), UDim2.fromOffset(W, H), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true

	-- rounded like the panel (ClipsDescendants doesn't follow rounded corners, so a square
	-- header poked out of them); Fill squares off its bottom edge, behind everything else
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = LILAC, BorderSizePixel = 0 }, panel)
	corner(header, 18)
	new("Frame", { Name = "Fill", Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = LILAC, BorderSizePixel = 0, ZIndex = 0 }, header)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	local titleRow = new("Frame", { Name = "TitleRow", Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(700, 64), BackgroundTransparency = 1 }, header)
	rowLayout(titleRow, 12)
	text(titleRow, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), FontFace = HEAD, TextSize = 26, TextTruncate = Enum.TextTruncate.None, Text = "DAILY SONG" })
	chip(titleRow, "Chip", "#1 · Wed 11 Nov", WHITE).LayoutOrder = 2
	text(titleRow, "Sub", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = BODY_BOLD, TextSize = 13, TextTruncate = Enum.TextTruncate.None, Text = "Same song for everyone today" })
	local nextIn = chip(header, "NextIn", "Next song in 4h 42m", WHITE, UDim2.new(1, -14 - 42 - 12, 0.5, 0))
	nextIn.AnchorPoint = Vector2.new(1, 0.5)
	nextIn.Size = UDim2.fromOffset(0, 28)
	nextIn.Visible = false
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(W - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W - 14 - 21, 32), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 67), Size = UDim2.new(1, 0, 1, -67), BackgroundTransparency = 1 }, panel)
	buildPlay(body)
	buildResult(body)

	root.Parent = frames
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(root)
	return root
end

return Build
