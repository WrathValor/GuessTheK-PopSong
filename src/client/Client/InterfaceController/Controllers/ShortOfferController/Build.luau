--| "Not enough" offer UI builder
-- Builds Interface.Frames.ShortOffer from the design board "Money 3 · not enough coins / out
-- of roll tickets": a scrim and one card: a yellow header (NOT ENOUGH COINS / OUT OF ROLL
-- TICKETS), a line saying what's short, a coins bar (have → price; hidden for tickets), the
-- pack that covers it with its Robux price, and Not now / See all packs.
-- Run once in Studio (an existing one is replaced):
--   require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.ShortOfferController.Build).Build(game.StarterGui.Interface.Frames)
-- ShortOfferController finds everything by name, fills it in and lays out the tickets version.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local LILAC = C("DCD3FF")
local MUTED = C("4A4458")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local ROBUX = "rbxassetid://83637405007021"

local Build = {}
Build.W, Build.H = 480, 390
Build.TICKETS_UP = 70 -- the tickets version has no coins bar: everything under it moves up

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
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }
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
	stroke(b, 4)
	return b
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("ShortOffer")
	if old then
		old:Destroy()
	end
	local W, H = Build.W, Build.H
	-- (over the shop / roll screen it opens from, under the purchase reveal)
	local root = new("Frame", { Name = "ShortOffer", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 59 })
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, root)
	scrim.Active = true

	local x, y = 640 - W / 2, 360 - H / 2
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(x + 8, y + 8), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(shadow, 20)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(W, H), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, root)
	corner(panel, 20)
	stroke(panel, 4)

	local head = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = YELLOW, BorderSizePixel = 0 }, panel)
	corner(head, 18)
	new("Frame", { Name = "Square", Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = YELLOW, BorderSizePixel = 0, ZIndex = 0 }, head)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(head, "Title", { Size = UDim2.fromScale(1, 1), TextSize = 22, Text = "NOT ENOUGH COINS" })

	text(panel, "Line", { Position = UDim2.fromOffset(24, 80), Size = UDim2.fromOffset(W - 48, 46), FontFace = BODY, TextSize = 17, TextWrapped = true, Text = "You need 230 more coins for the Neon Set." })

	-- coins: what you have → the price
	local prog = new("Frame", { Name = "Progress", Position = UDim2.fromOffset(24, 140), Size = UDim2.fromOffset(W - 48, 52), BackgroundTransparency = 1 }, panel)
	local bar = new("Frame", { Name = "Bar", Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = WHITE, ClipsDescendants = true }, prog)
	corner(bar, UDim.new(0.5, 0))
	stroke(bar, 4)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.83, 1), BackgroundColor3 = YELLOW, BorderSizePixel = 0 }, bar)
	corner(fill, UDim.new(0.5, 0))
	-- never narrower than it is tall, so even a sliver of coins is a round pill
	new("UISizeConstraint", { MinSize = Vector2.new(30, 0) }, fill)
	text(prog, "Have", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(0.5, 0, 0, 18), FontFace = BODY, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "You have 1,120" })
	text(prog, "Price", { Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.new(0.5, 0, 0, 18), FontFace = BODY, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "Neon Set · 1,350" })

	-- the pack that covers it
	local ow, oh, oy = W - 48, 92, 208
	local offerShadow = new("Frame", { Name = "OfferShadow", Position = UDim2.fromOffset(24 + 5, oy + 5), Size = UDim2.fromOffset(ow, oh), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	corner(offerShadow, 16)
	local offer = new("Frame", { Name = "Offer", Position = UDim2.fromOffset(24, oy), Size = UDim2.fromOffset(ow, oh), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
	corner(offer, 16)
	stroke(offer, 4)
	local box = new("Frame", { Name = "IconBox", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(64, 64), Rotation = -5, BackgroundColor3 = C("FFF6D6") }, offer)
	corner(box, 12)
	stroke(box, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit }, box)
	text(offer, "Item", { Position = UDim2.fromOffset(92, 18), Size = UDim2.fromOffset(ow - 92 - 132, 28), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Text = "500 coins" })
	text(offer, "Sub", { Position = UDim2.fromOffset(92, 48), Size = UDim2.fromOffset(ow - 92 - 132, 20), FontFace = BODY, TextSize = 14, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "Covers it, with 270 left over" })
	local buy = button(offer, "Buy", ow - 14 - 112, (oh - 48) / 2, 112, 48, MINT, "")
	local inner = new("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, buy)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = ROBUX, ScaleType = Enum.ScaleType.Fit }, inner)
	text(inner, "Price", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), TextSize = 18, Text = "36", TextTruncate = Enum.TextTruncate.None })

	button(panel, "Later", 24, 320, 170, 48, WHITE, "Not now")
	button(panel, "Alt", 206, 320, W - 230, 48, LILAC, "See all packs")

	root.Parent = frames
	return root
end

return Build
