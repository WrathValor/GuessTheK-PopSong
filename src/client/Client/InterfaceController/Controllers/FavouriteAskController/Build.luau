--| Favourite ask UI builder
-- Builds Interface.Frames.FavouriteAsk from the design board "Fans 1 · second (last) favourite
-- ask": a scrim and one card: a yellow header naming the moment (3 WINS IN A ROW! / FIRST
-- RAINBOW CARD!), a star badge, "Add the game to your favourites?", a line on why, and
-- Not now / FAVOURITE (FAVOURITE opens Roblox's own favourite pop-up).
-- Run once in Studio (an existing one is replaced):
--   require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.FavouriteAskController.Build).Build(game.StarterGui.Interface.Frames)
-- FavouriteAskController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MUTED = C("4A4458")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local STAR = "rbxassetid://92448810394913" -- the HUD Season tile's star

local Build = {}

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

local function stroke(p: Instance, t: number)
	new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a chunky button with a hard shadow (<name>Shadow); centre-anchored for ButtonScale
local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string): TextButton
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + 3, y + 3), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, 12)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2, y + h / 2), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, AutoButtonColor = false, FontFace = HEAD, TextSize = 15, TextColor3 = INK, Text = label }, parent)
	corner(b, 12)
	stroke(b, 3)
	return b
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("FavouriteAsk")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "FavouriteAsk", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, root)
	scrim.Active = true

	local W, H = 420, 352
	local x, y = 640 - W / 2, 360 - H / 2
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(x + 8, y + 8), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(shadow, 18)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(W, H), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, root)
	corner(panel, 18)
	stroke(panel, 3)

	-- header: rounded top (follows the panel), square bottom on the rule
	local head = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = YELLOW, BorderSizePixel = 0 }, panel)
	corner(head, 16)
	new("Frame", { Name = "Square", Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = YELLOW, BorderSizePixel = 0, ZIndex = 0 }, head)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(head, "Moment", { Size = UDim2.fromScale(1, 1), TextSize = 20, Text = "3 WINS IN A ROW!" })

	-- the star badge
	local badge = new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, 74), Size = UDim2.fromOffset(74, 74), BackgroundColor3 = WHITE, Rotation = -6 }, panel)
	corner(badge, UDim.new(0.5, 0))
	stroke(badge, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1, Image = STAR }, badge)

	text(panel, "Title", { Position = UDim2.fromOffset(22, 160), Size = UDim2.fromOffset(W - 44, 54), TextSize = 22, Text = "Add the game to your favourites?" })
	text(panel, "Body", { Position = UDim2.fromOffset(28, 218), Size = UDim2.fromOffset(W - 56, 40), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "It stays one tap away on your home page, so you can keep the streak going next time." })

	local by, gap = H - 22 - 50, 12
	local nw = math.floor((W - 44 - gap) * 0.42)
	button(panel, "NotNow", 22, by, nw, 50, WHITE, "Not now")
	local fav = button(panel, "Favourite", 22 + nw + gap, by, W - 44 - gap - nw, 50, YELLOW, "")
	local inner = new("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, fav)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = STAR }, inner)
	text(inner, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, TextSize = 15, TextWrapped = false, Text = "FAVOURITE" })

	root.Parent = frames
	return root
end

return Build
