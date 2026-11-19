--| Daily login UI builder
-- Builds Interface.Frames.DailyLogin from the "Daily login 1–3" design boards: a cream card
-- with a tilted yellow "DAILY LOGIN!" sticker on its corner and a red close button, the
-- streak chip centred at the top with the "miss a day" line under it, days 1–6 in a 3 × 2
-- grid of photocards and day 7 as the tall card on the right, then CLAIM DAY n on the
-- bottom (or, once claimed, the "Next one in …" pill and tomorrow's prize).
-- Every day card is the same build (holder → Shadow, Face → DayLabel, Art → Icon1/Icon2,
-- Big, Sub; Stamp, Today + TodayShadow; day 7 also Big1 sticker) that DailyLoginController
-- paints for its state (done / today / next) and the week on show.
-- Run once in Studio (an existing frame is replaced):
--   local B = require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.DailyLoginController.Build)
--   B.Build(game.StarterGui.Interface.Frames)

local SeasonConstants = require(game:GetService("ReplicatedStorage").Constants.SeasonConstants)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local LILAC = C("B9A6FF")
local PINK = C("FFD2E6")
local PEACH = C("FFE3CC")
local MUTED = C("6B6478")
local SUB = C("4A4458")
local SAND = C("E9E3D3")
local BLUE = C("9ED8F5")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local CLOSE_ICON = "rbxassetid://118345756178429"
local CLOCK_ICON = "rbxassetid://82578247239388" -- the shop's timer clock

local Build = {}

-- the layout (1280 × 720 canvas), shared with the controller
Build.CARD_W, Build.CARD_H, Build.GAP, Build.BIG_W = 136, 156, 14, 230
Build.PANEL = { X = 266, Y = 46, W = 748, H = 548 }
Build.GRID_X, Build.GRID_Y = 298, 168
Build.BIG_X = Build.GRID_X + 3 * Build.CARD_W + 2 * Build.GAP + 18
Build.COLOURS = { Done = C("E4F7E9"), Today = YELLOW, Next = WHITE }

-- --------------------------------- Helpers -------------------------------- --

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
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round }, p)
end

local function pad(p: Instance, l: number, r: number?, t: number?, b: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0) }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a face with a hard ink shadow behind it (both rotate together when `rotation` is given).
-- A Border stroke is drawn outside the frame, so the shadow covers the stroked face (`line`
-- bigger all round) and shows `drop` px past it, like the boards' CSS shadows.
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number, rotation: number?): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop - line, drop - line), Size = size + UDim2.fromOffset(2 * line, 2 * line), BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = rotation or 0 }, parent)
	corner(shadow, radius + line)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0, Rotation = rotation or 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

-- a tilted sticker (TODAY / BIG ONE) with its shadow, both anchored at their centre
local function sticker(parent: Instance, name: string, label: string, colour: Color3, centre: Vector2, size: Vector2, rotation: number, textColour: Color3?, textSize: number?)
	local sh = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X + 3, centre.Y + 3), Size = UDim2.fromOffset(size.X + 6, size.Y + 6), BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = rotation, ZIndex = 4 }, parent)
	corner(sh, 12)
	local face = text(parent, name, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(centre.X, centre.Y), Size = UDim2.fromOffset(size.X, size.Y), BackgroundTransparency = 0, BackgroundColor3 = colour, FontFace = HEAD, TextSize = textSize or 11, TextColor3 = textColour or INK, Text = label, Rotation = rotation, ZIndex = 5 })
	corner(face, 9)
	stroke(face, 3)
	return face, sh
end

-- One day: holder (the lift / tilt moves it as one) → Shadow, Face, Stamp, Today sticker.
local function dayCard(parent: Instance, day: number, x: number, y: number, w: number, h: number)
	local seven = day == 7
	-- centre-anchored, so Juice's pop-in (which re-centres anchors) and the lift agree
	local holder = new("Frame", { Name = "Day" .. day, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w // 2, y + h // 2), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1 }, parent)
	-- (under the 4 px stroke: Position = drop - 4, Size = the face + 8)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, 8, 1, 8), BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(shadow, 20)
	local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2 }, holder)
	corner(face, 16)
	stroke(face, 4)
	-- day 7's lilac → pink wash while it's still to come (DailyLoginController turns it on)
	new("UIGradient", { Name = "Wash", Rotation = 70, Color = ColorSequence.new(C("E7DEFF"), PINK), Enabled = seven }, face)

	text(face, "DayLabel", { Position = UDim2.fromOffset(0, if seven then 10 else 6), Size = UDim2.new(1, 0, 0, if seven then 24 else 16), FontFace = HEAD, TextSize = if seven then 20 else 13, Text = "DAY " .. day, ZIndex = 3 })
	local artH = if seven then 186 else 74
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, if seven then 40 else 26), Size = UDim2.new(1, -16, 0, artH), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 }, face)
	corner(art, 11)
	stroke(art, 3)
	-- one reward: Icon1 centred; two: Icon1 on the left, Icon2 on the right
	local one = if seven then 150 else 72
	new("ImageLabel", { Name = "Icon1", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(one, one), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "", ZIndex = 4 }, art)
	local two = if seven then 110 else 60
	new("ImageLabel", { Name = "Icon2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.72, 0.5), Size = UDim2.fromOffset(two, two), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "", Visible = false, ZIndex = 5 }, art)

	local bt = (if seven then 40 else 26) + artH
	text(face, "Big", { Position = UDim2.fromOffset(4, bt + (if seven then 14 else 6)), Size = UDim2.new(1, -8, 0, if seven then 28 else 18), FontFace = HEAD, TextSize = if seven then 24 else 15, TextScaled = false, Text = "100", ZIndex = 3 })
	text(face, "Sub", { Position = UDim2.fromOffset(6, bt + (if seven then 46 else 26)), Size = UDim2.new(1, -12, 0, if seven then 34 else 26), TextSize = if seven then 14 else 11, TextColor3 = SUB, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "coins", ZIndex = 3 })

	-- the ✓ stamp over a claimed day's art
	local stampY = (if seven then 40 else 26) + artH // 2
	local stamp = new("Frame", { Name = "Stamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w // 2, stampY), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = MINT, BorderSizePixel = 0, Rotation = -12, Visible = false, ZIndex = 6 }, holder)
	corner(stamp, UDim.new(0.5, 0))
	stroke(stamp, 4)
	new("UIScale", { Name = "Pop" }, stamp) -- the claim drops it in from bigger
	-- the tick: two rounded ink bars (the ✓ glyph draws as a thin √)
	local tick = new("Frame", { Name = "Tick", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, ZIndex = 7 }, stamp)
	for _, bar in { { "Short", 7.6, 16.2, 12, 45 }, { "Long", 15.6, 13.2, 19, -50 } } do
		local b = new("Frame", { Name = bar[1], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(bar[2], bar[3]), Size = UDim2.fromOffset(bar[4], 4.5), Rotation = bar[5], BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 7 }, tick)
		corner(b, UDim.new(0.5, 0))
	end

	local today, todayShadow = sticker(holder, "Today", "TODAY", RED, Vector2.new(w - 22, -2), Vector2.new(62, 22), 8, WHITE, 11)
	today.Visible = false
	todayShadow.Visible = false
	if seven then
		sticker(holder, "BigOne", "BIG ONE", LILAC, Vector2.new(w - 32, -4), Vector2.new(88, 26), 6, INK, 13)
	end
	return holder
end

-- ---------------------------------- Build --------------------------------- --

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("DailyLogin")
	if old then
		old:Destroy()
	end
	local P = Build.PANEL
	local root = new("Frame", { Name = "DailyLogin", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, root)
	scrim.Active = true

	card(root, "Panel", UDim2.fromOffset(P.X, P.Y), UDim2.fromOffset(P.W, P.H), CREAM, 22, 8, 4)

	-- "DAILY LOGIN!" on the top-left corner
	local title = card(root, "Sticker", UDim2.fromOffset(P.X + 22, P.Y - 26), UDim2.fromOffset(262, 56), YELLOW, 12, 5, 4, -2)
	text(title, "Label", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 30, Text = "DAILY LOGIN!" })

	-- close
	local cx, cy = P.X + P.W - 30, P.Y - 16
	local cs = new("Frame", { Name = "CloseShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + 24 + 3, cy + 24 + 3), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(cs, 16)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + 24, cy + 24), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, root)
	corner(close, 12)
	stroke(close, 4)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- the streak chip, centred at the top, with the rule under it
	-- (DailyLoginController sizes the chip to its words, and this to the chip + 6)
	local streakShadow = new("Frame", { Name = "StreakShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640 + 3, P.Y + 40), Size = UDim2.fromOffset(176, 38), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(streakShadow, 14)
	local streak = new("Frame", { Name = "Streak", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, P.Y + 40), Size = UDim2.fromOffset(170, 32), BackgroundColor3 = PEACH, BorderSizePixel = 0 }, root)
	corner(streak, 11)
	stroke(streak, 3)
	local srow = new("Frame", { Name = "Row", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, streak)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, srow)
	new("ImageLabel", { Name = "Flame", LayoutOrder = 1, Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = SeasonConstants.ICONS.Streak }, srow)
	text(srow, "Days", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), FontFace = HEAD, TextSize = 16, Text = "3 DAY STREAK" })
	text(root, "Rule", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, P.Y + 78), Size = UDim2.fromOffset(400, 16), TextSize = 12, TextColor3 = MUTED, Text = "Miss a day and it starts over at day 1" })

	-- the days
	local days = new("Frame", { Name = "Days", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1 }, root)
	for day = 1, 6 do
		local r, c = (day - 1) // 3, (day - 1) % 3
		dayCard(days, day, Build.GRID_X + c * (Build.CARD_W + Build.GAP), Build.GRID_Y + r * (Build.CARD_H + Build.GAP), Build.CARD_W, Build.CARD_H)
	end
	dayCard(days, 7, Build.BIG_X, Build.GRID_Y, Build.BIG_W, 2 * Build.CARD_H + Build.GAP)

	-- CLAIM DAY n
	local by = Build.GRID_Y + 2 * Build.CARD_H + Build.GAP + 24
	local claimShadow = new("Frame", { Name = "ClaimShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640 + 5, by + 31 + 5), Size = UDim2.fromOffset(278, 70), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(claimShadow, 18)
	local claim = new("TextButton", { Name = "Claim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, by + 31), Size = UDim2.fromOffset(270, 62), BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 22, TextColor3 = INK, Text = "CLAIM DAY 3", AutoButtonColor = false }, root)
	corner(claim, 14)
	stroke(claim, 4)

	-- once claimed: "⏱ Next one in 6h 12m" + "Tomorrow: <prize>"
	local nextRow = new("Frame", { Name = "Next", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, by + 3), Size = UDim2.fromOffset(560, 56), BackgroundTransparency = 1, Visible = false }, root)
	new("UIScale", { Name = "Pop" }, nextRow) -- eases in after a claim
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, nextRow)
	local timer = new("Frame", { Name = "Timer", LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 56), BackgroundColor3 = SAND, BorderSizePixel = 0 }, nextRow)
	corner(timer, 14)
	stroke(timer, 4)
	pad(timer, 22, 24)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, timer)
	new("ImageLabel", { Name = "Clock", LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = CLOCK_ICON, ImageColor3 = MUTED }, timer)
	text(timer, "Label", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), FontFace = HEAD, TextSize = 18, TextColor3 = MUTED, Text = "Next one in 6h 12m" })
	local tomorrow = new("Frame", { Name = "Tomorrow", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundTransparency = 1 }, nextRow)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tomorrow)
	text(tomorrow, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), TextSize = 15, Text = "Tomorrow:" })
	local prize = text(tomorrow, "Prize", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundTransparency = 0, BackgroundColor3 = BLUE, TextSize = 15, Text = "1 card upgrade" })
	corner(prize, 7)
	stroke(prize, 2)
	pad(prize, 7)

	root.Parent = frames
	return root
end

return Build
