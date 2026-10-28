--| Rewards UI builder
-- Builds Interface.Frames.Rewards from the "Rewards" design board: salmon header with a
-- "n ready to claim" chip, then one scrolling body with three sections:
--   Daily login  – streak chip, progress track with 7 dots, 7 day cards (coin stack, amount, button)
--   Daily quests – reset countdown, 3 quest cards (progress bar, reward, button), bonus bar
--   Group reward – the one-time group card
-- Run once in Studio (an existing frame is kept as ServerStorage.Rewards_Legacy);
-- RewardsController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local SALMON = C("FFD2CE")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local PALE = C("FFF6D6")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CLOSE_ICON = "rbxassetid://118345756178429"
local COIN = "rbxassetid://105055420801588" -- same coin as the HUD + shop
local COIN_STACK = "rbxassetid://83386580979392" -- one thick coin, side-on (the shop's bundle art)
local ATLAS = "rbxassetid://87950570350196" -- gtks_atlas0

local Build = {}
Build.DAYS = 7
Build.QUESTS = 3
-- each day card shows one pile of coins, one coin taller per day (2 on day 1 … 8 on day 7),
-- each coin nudged a little left/right like the original design
Build.MAX_STACKS = 8
Build.DAY_STACKS = { 2, 3, 4, 5, 6, 7, 8 }
Build.COIN_W, Build.COIN_H, Build.COIN_STEP = 58, 35, 12

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

local function pad(p: Instance, l: number, r: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l) }, p)
end

local function row(parent: Instance, gap: number)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
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

local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function pill(parent: Instance, name: string, label: string, colour: Color3, order: number?): TextLabel
	local c = text(parent, name, {
		LayoutOrder = order or 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
	})
	corner(c, UDim.new(0.5, 0))
	stroke(c, 2)
	pad(c, 12)
	return c
end

-- a coin icon tucked into a reward chip's left padding
local function coinChip(chip: TextLabel)
	local p = chip:FindFirstChildOfClass("UIPadding")
	if p then
		p.PaddingLeft = UDim.new(0, 32)
	end
	new("ImageLabel", { Name = "Coin", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -24, 0.5, 0), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = COIN }, chip)
end

local function button(parent: Instance, name: string, pos: UDim2, size: UDim2, label: string): TextButton
	local b = new("TextButton", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = INK,
		FontFace = HEAD,
		TextSize = 14,
		TextColor3 = YELLOW,
		Text = label,
		AutoButtonColor = false,
	}, parent)
	corner(b, 10)
	stroke(b, 2)
	return b
end

local function heading(parent: Instance, name: string, y: number, title: string): Frame
	local h = new("Frame", { Name = name, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, parent)
	row(h, 10)
	text(h, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), FontFace = HEAD, TextSize = 22, TextTruncate = Enum.TextTruncate.None, Text = title })
	return h
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Rewards")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("Rewards_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "Rewards_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "Rewards", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
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

	local PW, PH = 1040, 620
	local panel = card(root, "Panel", UDim2.fromOffset(120, 50), UDim2.fromOffset(PW, PH), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true

	-- header
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = SALMON, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	local titleRow = new("Frame", { Name = "TitleRow", Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(500, 64), BackgroundTransparency = 1 }, header)
	row(titleRow, 12)
	text(titleRow, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), FontFace = HEAD, TextSize = 26, TextTruncate = Enum.TextTruncate.None, Text = "REWARDS" })
	pill(titleRow, "Ready", "3 ready to claim", MINT, 2)
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(PW - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(PW - 14 - 21, 32), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- scrolling body
	local CANVAS_H = 910
	local body = new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 67),
		Size = UDim2.new(1, 0, 1, -67),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, CANVAS_H),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = INK,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
	}, panel)
	local W = PW - 6 - 44 - 10
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(W, CANVAS_H), BackgroundTransparency = 1 }, body)

	-- [[ Daily login ]]
	local dh = heading(content, "DailyHeading", 18, "Daily login")
	local streak = pill(dh, "Streak", "Streak: day 3", WHITE, 2)
	streak.Size = UDim2.fromOffset(0, 30)
	text(dh, "Note", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "Miss a day and it resets." })

	local dayW = (W - 6 * 12) / Build.DAYS
	local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(dayW / 2, 62 + 9), Size = UDim2.fromOffset(W - dayW, 12), BackgroundColor3 = WHITE, ClipsDescendants = true }, content)
	corner(track, 6)
	stroke(track, 2)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.33, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, track)
	corner(fill, 4)
	local dots = new("Frame", { Name = "Dots", Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(W, 30), BackgroundTransparency = 1 }, content)
	for i = 1, Build.DAYS do
		local d = new("Frame", { Name = "Dot" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((i - 1) * (dayW + 12) + dayW / 2, 15), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = WHITE }, dots)
		corner(d, UDim.new(0.5, 0))
		stroke(d, 3)
	end

	local days = new("Frame", { Name = "Days", Position = UDim2.fromOffset(0, 112), Size = UDim2.fromOffset(W, 300), BackgroundTransparency = 1 }, content)
	for i = 1, Build.DAYS do
		local x = (i - 1) * (dayW + 12)
		local holder = new("Frame", { Name = "Day" .. i, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(dayW - 4, 292), BackgroundTransparency = 1 }, days)
		local glow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 12, 1, 12), BackgroundColor3 = YELLOW, Visible = false }, holder)
		corner(glow, 20)
		local face = card(holder, "Face", UDim2.new(), UDim2.fromScale(1, 1), C("EDE4D4"), 16, 4, 3)
		text(face, "DayLabel", { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 20), FontFace = HEAD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Text = `DAY {i}` })
		local coins = new("Frame", { Name = "Coins", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(80, 128), BackgroundTransparency = 1 }, face)
		for k = 1, Build.MAX_STACKS do
			-- same wobble as the design's ovals: alternate 4px, every third coin back 4px
			local x = 11 + ((k - 1) % 2) * 4 - (if (k - 1) % 3 == 2 then 4 else 0)
			new("ImageLabel", {
				Name = "Stack" .. k,
				Position = UDim2.new(0, x, 1, -Build.COIN_H - (k - 1) * Build.COIN_STEP),
				Size = UDim2.fromOffset(Build.COIN_W, Build.COIN_H),
				BackgroundTransparency = 1,
				Image = COIN_STACK, -- one thick coin, side-on
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = k, -- higher coins draw on top
				Visible = k <= Build.DAY_STACKS[i],
			}, coins)
		end
		text(face, "Amount", { Position = UDim2.fromOffset(0, 172), Size = UDim2.new(1, 0, 0, 28), FontFace = HEAD, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Text = "50" })
		local unit = new("Frame", { Name = "Unit", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 200), Size = UDim2.fromOffset(60, 16), BackgroundTransparency = 1 }, face)
		new("ImageLabel", { Name = "Coin", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = COIN }, unit)
		text(unit, "Label", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(40, 16), TextSize = 12, Text = "coins" })
		button(face, "Claim", UDim2.new(0, 10, 1, -12 - 40), UDim2.new(1, -20, 0, 40), "CLAIM!")
		if i == Build.DAYS then
			local big = text(holder, "Big", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 10, 0, -14),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 22),
				BackgroundTransparency = 0,
				BackgroundColor3 = RED,
				TextSize = 11,
				TextTruncate = Enum.TextTruncate.None,
				Rotation = 8,
				Text = "BIG!",
				ZIndex = 10,
			})
			corner(big, 8)
			stroke(big, 2)
			pad(big, 7)
		end
	end

	-- [[ Daily quests ]]
	local qy = 112 + 300 + 30
	local qh = heading(content, "QuestHeading", qy, "Daily quests")
	local reset = pill(qh, "Reset", "Resets in 5h 18m", WHITE, 2)
	corner(reset, 8)
	local qW = (W - 2 * 14) / Build.QUESTS
	local QH = 124 -- quest card height
	local quests = new("Frame", { Name = "Quests", Position = UDim2.fromOffset(0, qy + 42), Size = UDim2.fromOffset(W, QH + 4), BackgroundTransparency = 1 }, content)
	for i = 1, Build.QUESTS do
		local q = card(quests, "Quest" .. i, UDim2.fromOffset((i - 1) * (qW + 14), 0), UDim2.fromOffset(qW - 4, QH), C("9ED8F5"), 16, 4, 3)
		-- title / progress bar / reward chip + a compact button on the right
		-- progress count sits on the title row so the bar can run the full width (same right
		-- edge as the button below)
		text(q, "QuestTitle", { Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -32 - 56, 0, 22), TextSize = 16, Text = "Quest" })
		local bar = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(16, 48), Size = UDim2.new(1, -32, 0, 14), BackgroundColor3 = WHITE, ClipsDescendants = true }, q)
		corner(bar, 7)
		stroke(bar, 2)
		local f = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, bar)
		corner(f, 5)
		text(q, "Progress", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 15), Size = UDim2.fromOffset(52, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Text = "1 / 2" })
		local reward = text(q, "Reward", {
			Position = UDim2.fromOffset(16, 76),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 32),
			BackgroundTransparency = 0,
			BackgroundColor3 = YELLOW,
			FontFace = HEAD,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.None,
			Text = "+100",
		})
		corner(reward, 10)
		stroke(reward, 2)
		pad(reward, 10)
		coinChip(reward)
		local qb = button(q, "Claim", UDim2.new(1, -16 - 116, 0, 76), UDim2.fromOffset(116, 32), "CLAIM!")
		qb.TextSize = 13
	end
	local bonus = new("Frame", { Name = "Bonus", Position = UDim2.fromOffset(0, qy + 42 + QH + 4 + 12), Size = UDim2.fromOffset(W - 4, 66), BackgroundColor3 = PALE }, content)
	corner(bonus, 14)
	stroke(bonus, 3)
	text(bonus, "BonusTitle", { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(500, 20), FontFace = HEAD, TextSize = 15, Text = "BONUS · finish all 3 quests" })
	text(bonus, "Sub", { Position = UDim2.fromOffset(16, 34), Size = UDim2.fromOffset(500, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "1 of 3 done" })
	local br = text(bonus, "Reward", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16 - 116 - 12, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		FontFace = HEAD,
		TextSize = 15,
		TextTruncate = Enum.TextTruncate.None,
		Text = "+150",
	})
	corner(br, 10)
	stroke(br, 2)
	pad(br, 10)
	coinChip(br)
	local bb = button(bonus, "Claim", UDim2.new(1, -16 - 116, 0.5, -16), UDim2.fromOffset(116, 32), "CLAIM!")
	bb.TextSize = 13

	-- [[ Group reward ]]
	local gy = qy + 42 + QH + 4 + 12 + 66 + 30
	heading(content, "GroupHeading", gy, "Group reward")
	local group = card(content, "Group", UDim2.fromOffset(0, gy + 42), UDim2.fromOffset(W - 4, 120), MINT, 16, 4, 3)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(20, 18), Size = UDim2.fromOffset(120, 84), BackgroundColor3 = C("E8FFF0") }, group)
	corner(art, 10)
	stroke(art, 2)
	local st = new("Frame", { Name = "Stage", Position = UDim2.fromScale(0.18, 0.14), Size = UDim2.fromScale(0.64, 0.44), BackgroundColor3 = MINT }, art)
	corner(st, UDim.new(0.3, 0))
	stroke(st, 2)
	local pl = new("Frame", { Name = "Platform", Position = UDim2.fromScale(0.26, 0.5), Size = UDim2.fromScale(0.48, 0.26), BackgroundColor3 = WHITE }, art)
	corner(pl, UDim.new(0.5, 0))
	stroke(pl, 2)
	text(group, "GroupTitle", { Position = UDim2.fromOffset(160, 32), Size = UDim2.new(1, -160 - 180, 0, 24), TextSize = 18, Text = "500 coins + Group Exclusive stage + \"Supporter\" title" })
	text(group, "Sub", { Position = UDim2.fromOffset(160, 60), Size = UDim2.new(1, -160 - 180, 0, 18), FontFace = BODY_BOLD, TextSize = 13, Text = "Join our Roblox group, then come back and claim. One time only." })
	local gs = new("Frame", { Name = "ClaimShadow", Position = UDim2.new(1, -20 - 140 + 4, 0.5, -25 + 4), Size = UDim2.fromOffset(140, 50), BackgroundColor3 = RED }, group)
	corner(gs, 12)
	local gb = button(group, "Claim", UDim2.new(1, -20 - 140, 0.5, -25), UDim2.fromOffset(140, 50), "CLAIM")
	gb.TextSize = 16
	gb:FindFirstChildOfClass("UIStroke").Thickness = 3

	-- toast
	local toast = text(root, "Toast", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(640, 700),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		TextColor3 = YELLOW,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Text = "",
		Visible = false,
		ZIndex = 20,
	})
	corner(toast, 10)
	pad(toast, 16)

	root.Parent = frames
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(root)
	return root
end

Build.ATLAS = ATLAS
return Build
