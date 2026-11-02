--| Tutorial UI builder
-- Builds Interface.Frames.Tutorial from the "Tutorial" design boards: the first-join Welcome
-- card and the "You're ready!" card after the practice round. Also adds the "Replay
-- tutorial" button to Settings. Run once in Studio (Build.Build(frames)); safe to run twice.
-- TutorialController finds everything by name. The in-round tips are drawn by ./Tips.

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
local COIN = "rbxassetid://105055420801588"

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
	text(w, "Title", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 46), FontFace = HEAD, TextSize = 40, Text = "Guess the K-pop Song" })
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
