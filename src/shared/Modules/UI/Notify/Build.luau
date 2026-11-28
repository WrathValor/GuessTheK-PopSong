--| Notify UI builder
-- Builds Interface.Notify from design board "57 · Notifications": the stack top centre under the
-- Roblox bar, and the two hidden templates Modules/UI/Notify clones. Run once in Studio Edit
-- mode (an existing one is replaced), then save the place:
--   local m = game.ReplicatedStorage.Modules.UI.Notify.Build
--   local c = m:Clone(); c.Parent = m.Parent; require(c).Build(game.StarterGui.Interface); c:Destroy()
--   Notify            full-screen, transparent, over everything (ZIndex 60)
--     Stack           top centre: a UIListLayout (newest on top) + UIScale "Scale"
--     Templates       a hidden Frame
--       Card          a slot Frame holding Group (a CanvasGroup, slides inside the slot):
--                     Shadow, Face (Tint gradient, Disc + Icon, Title, Body, Action, Timer.Fill)
--       Pill          the same, one line: Group > Shadow, Face (Tint, Disc + Icon, Text)

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MUTED = C("4A4560")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CARD_W, CARD_H = 460, 72
local PILL_H = 40
local SHADOW = 4
local LINE = 3 -- the face's outline (a Border UIStroke draws outside the face)
-- the face sits LINE in from the slot so its outline isn't clipped by the CanvasGroup, and the
-- hard shadow is grown by the outline (LINE bigger all round, its corner LINE rounder) so its
-- corners don't poke out past the outline's: the slot is the face + 2 × LINE + SHADOW
local PAD = LINE * 2 + SHADOW

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
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
-- the coloured square with the icon (size s)
local function disc(parent: Instance, s: number, x: number, r: number, line: number, icon: number): Frame
	local d = new("Frame", { Name = "Disc", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, x, 0.5, 0), Size = UDim2.fromOffset(s, s), BackgroundColor3 = C("A7E9B8") }, parent)
	corner(d, r)
	stroke(d, line)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(icon, icon), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit }, d)
	return d
end

local function card(templates: Instance)
	local slot = new("Frame", { Name = "Card", Size = UDim2.fromOffset(CARD_W + PAD, CARD_H + PAD), BackgroundTransparency = 1 }, templates)
	local g = new("CanvasGroup", { Name = "Group", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, slot)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(SHADOW, SHADOW), Size = UDim2.fromOffset(CARD_W + LINE * 2, CARD_H + LINE * 2), BackgroundColor3 = INK }, g)
	corner(shadow, 16 + LINE)
	local face = new("TextButton", { Name = "Face", Position = UDim2.fromOffset(LINE, LINE), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false, ZIndex = 2 }, g)
	corner(face, 16)
	stroke(face, LINE)
	new("UIGradient", { Name = "Tint", Color = ColorSequence.new(C("E8FBEE"), C("C8F2D3")) }, face)
	disc(face, 44, 10, 12, 3, 26)
	text(face, "Title", { Position = UDim2.fromOffset(66, 11), Size = UDim2.new(1, -82, 0, 22), FontFace = HEAD, TextSize = 17, Text = "Gift claimed!" })
	text(face, "Body", { Position = UDim2.fromOffset(66, 33), Size = UDim2.new(1, -82, 0, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "+5,000 coins added to your wallet" })
	-- one action ("Get coins"), right side; hidden unless asked for
	local action = new("TextButton", { Name = "Action", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, -2), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = YELLOW, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = "Get coins", AutoButtonColor = false, Visible = false, ZIndex = 3 }, face)
	corner(action, 10)
	stroke(action, 2.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, action)
	-- the countdown along the bottom
	local timer = new("Frame", { Name = "Timer", Position = UDim2.new(0, 66, 1, -11), Size = UDim2.new(1, -82, 0, 4), BackgroundColor3 = INK, BackgroundTransparency = 0.88, BorderSizePixel = 0 }, face)
	corner(timer, 2)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C("3CB371"), BorderSizePixel = 0 }, timer)
	corner(fill, 2)
end

local function pill(templates: Instance)
	local slot = new("Frame", { Name = "Pill", Size = UDim2.fromOffset(300, PILL_H + PAD), BackgroundTransparency = 1 }, templates)
	local g = new("CanvasGroup", { Name = "Group", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, slot)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(SHADOW, SHADOW), Size = UDim2.new(1, -SHADOW, 0, PILL_H + LINE * 2), BackgroundColor3 = INK }, g)
	corner(shadow, 12 + LINE)
	local face = new("TextButton", { Name = "Face", Position = UDim2.fromOffset(LINE, LINE), Size = UDim2.new(1, -PAD, 0, PILL_H), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false, ZIndex = 2 }, g)
	corner(face, 12)
	stroke(face, LINE)
	new("UIGradient", { Name = "Tint", Color = ColorSequence.new(C("E8FBEE"), C("C8F2D3")) }, face)
	disc(face, 26, 8, 8, 2.5, 17)
	text(face, "Text", { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -54, 1, 0), FontFace = BODY, TextSize = 15, Text = "+1,240 coins collected" })
end

function Build.Build(interface: Instance): Frame
	local old = interface:FindFirstChild("Notify")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Notify", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 60, Active = false })
	local stack = new("Frame", { Name = "Stack", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.fromOffset(CARD_W + 20, 300), BackgroundTransparency = 1 }, root)
	new("UIScale", { Name = "Scale", Scale = 1 }, stack)
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, stack)
	local templates = new("Frame", { Name = "Templates", Visible = false, BackgroundTransparency = 1 }, root)
	card(templates)
	pill(templates)
	-- (the templates are never shown: their holder is hidden)
	root.Parent = interface
	return root
end

return Build
