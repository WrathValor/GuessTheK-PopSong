--| StreetScreens UI builder (the big screen's photocard flex)
-- Adds to the Jumbotron (Map.Landmarks.BigScreen.SurfaceGui.Jumbotron.Content, 600 × 272 under
-- its UIScale) the pieces Client/StreetScreens fills in:
--   SlideShowcase  (design board "69b") Slot1–4: Card (a Modules/UI/Photocard), Head (headshot
--                  bubble), PlayerName, Line (member · album), Chip (the rarity)
--   Takeover       (design board "69c") over the panel for a big pull: Bg, Bits (confetti),
--                  Kicker, Head, PlayerName, Headline, Line, Serial, Card (a big Photocard)
-- Run once in Edit (again = replaced), then save:
--   local m = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("StreetScreensBuild", true)
--   local c = m:Clone(); c.Parent = m.Parent
--   require(c).Flex(workspace.Map.Landmarks.BigScreen.SurfaceGui.Jumbotron.Content); c:Destroy()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Photocard = require(ReplicatedStorage.Modules.UI.Photocard)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("F1ECF4")
local YELLOW = C("FFE07A")
local MUTED = C("6B6480")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local TAKEOVER_Z = 20

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
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function chip(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = YELLOW, FontFace = BODY, TextSize = 9, Text = "LUCKY DRAW" }
	for k, v in props do
		base[k] = v
	end
	local c = text(parent, name, base)
	corner(c, 4)
	stroke(c, 1.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, c)
	return c
end

local function head(parent: Instance, name: string, x: number, y: number, d: number, z: number): ImageLabel
	local h = new("ImageLabel", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(d, d), BackgroundColor3 = C("DCD3FF"), Image = "", ZIndex = z }, parent)
	corner(h, d // 2)
	stroke(h, 2)
	return h
end

local function raise(root: Instance, by: number)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += by
		end
	end
	if root:IsA("GuiObject") then
		root.ZIndex += by
	end
end

function Build.Flex(content: Instance)
	for _, n in { "SlideShowcase", "Takeover" } do
		local old = content:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end

	-- SHOWCASE: four flex cards
	local slide = new("Frame", { Name = "SlideShowcase", Size = UDim2.fromOffset(600, 272), BackgroundTransparency = 1, Visible = false }, content)
	local SLOT_W = 130
	for i = 1, 4 do
		local slot = new("Frame", { Name = "Slot" .. i, Position = UDim2.fromOffset(40 + (i - 1) * SLOT_W, 94), Size = UDim2.fromOffset(SLOT_W, 168), BackgroundTransparency = 1 }, slide)
		local pc = Photocard.Build(slot, "Card", 74, 98, ({ -3, 1, -1, 3 })[i])
		pc.Position = UDim2.fromOffset((SLOT_W - 74) / 2, 4)
		head(slot, "Head", (SLOT_W - 74) / 2 - 10, -4, 24, 8)
		text(slot, "PlayerName", { Position = UDim2.fromOffset(0, 106), Size = UDim2.fromOffset(SLOT_W, 15), FontFace = HEAD, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Player" })
		text(slot, "Line", { Position = UDim2.fromOffset(0, 121), Size = UDim2.fromOffset(SLOT_W, 12), TextSize = 9, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Member · Album" })
		chip(slot, "Chip", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(SLOT_W / 2, 136), Size = UDim2.fromOffset(0, 14) })
	end

	-- the big-pull takeover, over the panel (the Tag stays on top)
	local t = new("Frame", { Name = "Takeover", Size = UDim2.fromOffset(600, 272), BackgroundTransparency = 1, Visible = false }, content)
	local bg = new("Frame", { Name = "Bg", Position = UDim2.fromOffset(14, 24), Size = UDim2.fromOffset(576, 240), BackgroundColor3 = C("FFFFFF") }, t)
	corner(bg, 18)
	stroke(bg, 3)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, CREAM),
			ColorSequenceKeypoint.new(0.45, C("FFF3B8")),
			ColorSequenceKeypoint.new(0.7, YELLOW),
			ColorSequenceKeypoint.new(1, CREAM),
		}),
	}, bg)
	local bits = new("Frame", { Name = "Bits", Size = UDim2.fromOffset(600, 272), BackgroundTransparency = 1 }, t)
	-- (round the edges, clear of the text and the card)
	for k, spec in { { 28, 40, "FF9EC4", 20 }, { 24, 130, "A7E9B8", -30 }, { 30, 228, "9ED8F5", 40 }, { 360, 38, "B9A6FF", -15 }, { 372, 214, "FF9EC4", 35 }, { 540, 48, "FFE07A", -40 }, { 556, 150, "B9A6FF", 10 }, { 540, 234, "A7E9B8", 25 } } do
		local b = new("Frame", { Name = "Bit" .. k, Position = UDim2.fromOffset(spec[1], spec[2]), Size = UDim2.fromOffset(7, 10), Rotation = spec[4], BackgroundColor3 = C(spec[3]) }, bits)
		corner(b, 2)
		stroke(b, 1.5)
	end
	text(t, "Kicker", { Position = UDim2.fromOffset(44, 60), Size = UDim2.fromOffset(280, 14), FontFace = HEAD, TextSize = 10, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "JUST NOW ON THIS SERVER" })
	head(t, "Head", 44, 78, 34, 1)
	text(t, "PlayerName", { Position = UDim2.fromOffset(86, 78), Size = UDim2.fromOffset(250, 34), FontFace = HEAD, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Player" })
	text(t, "Headline", { Position = UDim2.fromOffset(44, 120), Size = UDim2.fromOffset(300, 64), FontFace = HEAD, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = "PULLED A SIGNED POLAROID!" })
	text(t, "Line", { Position = UDim2.fromOffset(44, 192), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Text = "V · BTS · Proof" })
	chip(t, "Serial", { Position = UDim2.fromOffset(44, 214), Size = UDim2.fromOffset(0, 18), BackgroundColor3 = INK, TextColor3 = YELLOW, TextSize = 11, Text = "#7" })
	local card = Photocard.Build(t, "Card", 126, 168, 4)
	card.Position = UDim2.fromOffset(392, 58)
	raise(t, TAKEOVER_Z)
	local tag = content:FindFirstChild("Tag")
	if tag then
		raise(tag, TAKEOVER_Z + 20 - tag.ZIndex)
	end
	return slide, t
end

return Build
