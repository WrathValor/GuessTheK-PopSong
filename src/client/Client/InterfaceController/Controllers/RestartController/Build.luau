--| Server restart UI builder
-- Builds the three pieces of the "Server restart 1–3" design boards:
--   • HUD.TopCenter.Restart: the lobby banner under the top bar. Face (yellow for an update,
--     blue for maintenance; tapping it shrinks the banner) → IconBox.Icon (rocket / wrench),
--     Title, Message, Time (clock + Label) and the HOP OVER NOW button (Hop + HopShadow).
--     HUD.TopCenter.RestartMini (+ Shadow): the shrunk clock pill (tap to open it again).
--     (HUD.TopCenter is a 1280 × 720 group AutoScale pins to the top of the screen, just under
--     Roblox's top bar.)
--   • Frames.Game.RestartPill (+ Shadow): the small "UPDATE IN 3:10 · this duel finishes
--     first" pill under the duel scoreboard.
--   • Frames.Restart: the hand-over card for the last seconds (scrim, "BACK IN A SEC!" sticker,
--     countdown Ring with a spinning gradient, heading, line and two chips).
-- RestartController fills them in. Run once in Studio (existing pieces are replaced):
--   local B = require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.RestartController.Build)
--   B.Build(game.StarterGui.Interface)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local LILAC = C("B9A6FF")
local SUB = C("4A4458")
local MUTED = C("6B6478")
local TRACK = C("EDE6D6")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local CLOCK_ICON = "rbxassetid://82578247239388" -- the shop's timer clock
local Build = {}
Build.ROCKET = "rbxassetid://116896639567244" -- assets/ui/RestartRocket.png
Build.WRENCH = "rbxassetid://81560057862771" -- assets/ui/RestartWrench.png
Build.UPDATE = YELLOW
Build.MAINTENANCE = C("9ED8F5")

local BANNER_W, BANNER_H = 720, 82

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
	return new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round }, p)
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

-- a hard ink shadow for a centre-anchored face: a Border stroke is drawn outside the frame,
-- so the shadow covers the stroked face (`line` bigger all round) and shows `drop` px past it
local function shadowFor(parent: Instance, name: string, centre: Vector2, size: Vector2, radius: number, drop: number, line: number, anchorY: number?, z: number?): Frame
	local sh = new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, anchorY or 0.5), Position = UDim2.fromOffset(centre.X + drop, centre.Y + drop + (if anchorY == 0 then -line else 0)), Size = UDim2.fromOffset(size.X + 2 * line, size.Y + 2 * line), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = z or 1 }, parent)
	corner(sh, radius + line)
	return sh
end

local function replace(parent: Instance, name: string)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- ---------------------------------- Pieces --------------------------------- --

local function topCenter(hud: Instance): Frame
	local group = hud:FindFirstChild("TopCenter")
	if not group then
		group = new("Frame", { Name = "TopCenter", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1 }, hud)
	end
	return group
end

local function banner(group: Instance)
	replace(group, "Restart")
	local root = new("Frame", { Name = "Restart", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 0), Size = UDim2.fromOffset(BANNER_W + 12, BANNER_H + 12), BackgroundTransparency = 1, Visible = false }, group)
	new("UIScale", { Name = "Pop" }, root)
	local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(6 - 4 + 4, 6 - 4 + 4), Size = UDim2.fromOffset(BANNER_W + 8, BANNER_H + 8), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(sh, 22)
	-- tapping the banner (anywhere but HOP) shrinks it to the clock pill
	local face = new("TextButton", { Name = "Face", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(BANNER_W, BANNER_H), BackgroundColor3 = Build.UPDATE, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 2 }, root)
	corner(face, 18)
	stroke(face, 4)
	face:SetAttribute("NoButtonScale", true) -- (the HUD's hover grow would push it under HOP)

	local box = new("Frame", { Name = "IconBox", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(14, BANNER_H / 2), Size = UDim2.fromOffset(58, 58), BackgroundColor3 = WHITE, Rotation = -4, ZIndex = 3 }, face)
	corner(box, 14)
	stroke(box, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1, Image = Build.ROCKET, ScaleType = Enum.ScaleType.Fit, ZIndex = 4 }, box)

	local textX = 14 + 58 + 14
	local hopW, timeW = 160, 112 -- (room for HOP to grow on hover without touching the timer)
	local textW = BANNER_W - textX - 14 - hopW - 12 - timeW - 14
	text(face, "Title", { Position = UDim2.fromOffset(textX, 13), Size = UDim2.fromOffset(textW, 24), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Text = "UPDATE INCOMING!", ZIndex = 3 })
	text(face, "Message", { Position = UDim2.fromOffset(textX, 39), Size = UDim2.fromOffset(textW, 32), TextSize = 13, TextColor3 = SUB, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "New stuff is ready · this server restarts soon", ZIndex = 3 })

	local time = new("Frame", { Name = "Time", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(textX + textW + 14, BANNER_H / 2), Size = UDim2.fromOffset(timeW, 48), BackgroundColor3 = WHITE, ZIndex = 3 }, face)
	corner(time, 12)
	stroke(time, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, time)
	new("ImageLabel", { Name = "Clock", LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = CLOCK_ICON, ImageColor3 = INK, ScaleType = Enum.ScaleType.Fit, ZIndex = 4 }, time)
	text(time, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(64, 28), FontFace = HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Text = "4:32", ZIndex = 4 })

	local hx = BANNER_W - 14 - hopW / 2 + 4
	local hopSh = new("Frame", { Name = "HopShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(hx + 3, BANNER_H / 2 + 4 + 3), Size = UDim2.fromOffset(hopW + 6, 44 + 6), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 4 }, root)
	corner(hopSh, 15)
	local hop = new("TextButton", { Name = "Hop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(hx, BANNER_H / 2 + 4), Size = UDim2.fromOffset(hopW, 44), BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 15, TextColor3 = INK, Text = "HOP OVER NOW", AutoButtonColor = false, ZIndex = 5 }, root)
	corner(hop, 12)
	stroke(hop, 3)

	-- the shrunk banner: a clock pill (tap to open the banner again)
	replace(group, "RestartMini")
	replace(group, "RestartMiniShadow")
	local miniSh = shadowFor(group, "RestartMiniShadow", Vector2.new(640, 4), Vector2.new(132, 40), 12, 3, 3, 0)
	miniSh.Visible = false
	local mini = new("TextButton", { Name = "RestartMini", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 24), Size = UDim2.fromOffset(132, 40), BackgroundColor3 = Build.UPDATE, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 2 }, group)
	corner(mini, 12)
	stroke(mini, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, mini)
	new("ImageLabel", { Name = "Clock", LayoutOrder = 1, Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = CLOCK_ICON, ImageColor3 = INK, ScaleType = Enum.ScaleType.Fit, ZIndex = 3 }, mini)
	text(mini, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(62, 24), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Text = "4:32", ZIndex = 3 })
end

local function duelPill(gameFrame: Instance)
	replace(gameFrame, "RestartPill")
	replace(gameFrame, "RestartPillShadow")
	local w, h = 372, 32
	local sh = shadowFor(gameFrame, "RestartPillShadow", Vector2.new(640, 118), Vector2.new(w, h), 11, 3, 3, 0)
	sh.Visible = false
	local pill = new("Frame", { Name = "RestartPill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 118), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Build.UPDATE, Visible = false, ZIndex = 2 }, gameFrame)
	corner(pill, 11)
	stroke(pill, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, pill)
	new("ImageLabel", { Name = "Clock", LayoutOrder = 1, Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = CLOCK_ICON, ImageColor3 = INK, ScaleType = Enum.ScaleType.Fit, ZIndex = 3 }, pill)
	text(pill, "Label", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = HEAD, TextSize = 13, Text = "UPDATE IN 3:10", ZIndex = 3 })
	text(pill, "Sub", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextSize = 13, TextColor3 = SUB, Text = "· this duel finishes first", ZIndex = 3 })
end

local function handOver(frames: Instance)
	replace(frames, "Restart")
	local root = new("Frame", { Name = "Restart", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 40 }, frames)
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, root)
	scrim.Active = true

	local cw, ch = 560, 340
	shadowFor(root, "CardShadow", Vector2.new(640, 372), Vector2.new(cw, ch), 24, 9, 4)
	local card = new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 372), Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = CREAM, ZIndex = 2 }, root)
	corner(card, 24)
	stroke(card, 4)
	new("UIScale", { Name = "Pop" }, card)

	-- "BACK IN A SEC!" sticker on the top edge
	local stSh = new("Frame", { Name = "StickerShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cw / 2 + 5, 5), Size = UDim2.fromOffset(300 + 8, 54 + 8), BackgroundColor3 = INK, BorderSizePixel = 0, Rotation = -2, ZIndex = 3 }, card)
	corner(stSh, 16)
	local st = text(card, "Sticker", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cw / 2, 0), Size = UDim2.fromOffset(300, 54), BackgroundTransparency = 0, BackgroundColor3 = YELLOW, FontFace = HEAD, TextSize = 28, Text = "BACK IN A SEC!", Rotation = -2, ZIndex = 4 })
	corner(st, 12)
	stroke(st, 4)

	-- countdown ring: a white disc, a pale track and a lilac arc that spins (its gradient)
	local ring = new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cw / 2, 50), Size = UDim2.fromOffset(112, 112), BackgroundColor3 = WHITE, ZIndex = 3 }, card)
	corner(ring, UDim.new(0.5, 0))
	stroke(ring, 5)
	local track = new("Frame", { Name = "Track", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, ZIndex = 4 }, ring)
	corner(track, UDim.new(0.5, 0))
	stroke(track, 11, TRACK)
	local arc = new("Frame", { Name = "Arc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, ZIndex = 5 }, ring)
	corner(arc, UDim.new(0.5, 0))
	local arcStroke = stroke(arc, 11, LILAC)
	-- (half the stroke see-through, softening into it: reads as a moving arc when it rotates)
	new("UIGradient", { Name = "Spin", Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.62, 1), NumberSequenceKeypoint.new(1, 1) }) }, arcStroke)
	text(ring, "Count", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 40, Text = "8", ZIndex = 6 })

	text(card, "Heading", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cw / 2, 180), Size = UDim2.fromOffset(cw - 60, 28), FontFace = HEAD, TextSize = 22, Text = "Moving you to an updated server", ZIndex = 3 })
	text(card, "Line", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cw / 2, 214), Size = UDim2.fromOffset(cw - 60, 40), TextSize = 15, TextColor3 = MUTED, TextWrapped = true, Text = "Your coins, cards and streak are all saved.\nFriends here land on the same server.", ZIndex = 3 })

	local chips = new("Frame", { Name = "Chips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cw / 2, 274), Size = UDim2.fromOffset(cw - 60, 30), BackgroundTransparency = 1, ZIndex = 3 }, card)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	for i, spec in { { "Saved", "✓ Progress saved", MINT }, { "Finding", "Finding a server…", WHITE } } do
		local chip = text(chips, spec[1], { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundTransparency = 0, BackgroundColor3 = spec[3], TextSize = 13, Text = spec[2], ZIndex = 4 })
		corner(chip, 9)
		stroke(chip, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, chip)
	end
	return root
end

-- ---------------------------------- Build --------------------------------- --

function Build.Build(interface: Instance)
	local hud = interface:FindFirstChild("HUD")
	local frames = interface:FindFirstChild("Frames")
	banner(topCenter(hud))
	duelPill(frames:FindFirstChild("Game"))
	handOver(frames)
end

return Build
