--| Starter offer UI builder
-- Builds Interface.Frames.StarterOffer from the design board "Money 2 · starter offer": a
-- scrim and one card: a pink DEBUT PACK header, four reward cards (2,500 coins, the Debut
-- Stage + Mic tagged ONLY HERE, and the +3 roll tickets STARTER BONUS), the "Bonus ends in"
-- timer, and Maybe later / GET IT · R$ 64. Also the HUD chip it leaves behind
-- (HUD.Buttons.Starter + StarterShadow, under Invite on the right) while the bonus lasts.
-- Run once in Studio (existing ones are replaced):
--   local B = require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.StarterOfferController.Build)
--   B.Build(game.StarterGui.Interface.Frames); B.HUDChip(game.StarterGui.Interface.HUD)
-- StarterOfferController finds everything by name and fills in the numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local PINK = C("FF9EC4")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local MUTED = C("5C566B")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local ROBUX = "rbxassetid://83637405007021"

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
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a chunky button with a hard shadow (<name>Shadow); centre-anchored for ButtonScale
local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string): TextButton
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + 4, y + 4), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, 14)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2, y + h / 2), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, AutoButtonColor = false, FontFace = HEAD, TextSize = 17, TextColor3 = INK, Text = label }, parent)
	corner(b, 14)
	stroke(b, 4)
	return b
end

-- one reward card (124 × 180): Art on top (CosmeticView fills stage / mic ones), Big + Small
-- under it, a Tag sticker on the top edge
local function rewardCard(parent: Instance, name: string, x: number, y: number, face: Color3, artBg: Color3, big: string, small: string, tag: string?, tagBg: Color3?, tagText: Color3?, tilt: number)
	local holder = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(124, 180), BackgroundTransparency = 1, Rotation = tilt }, parent)
	local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
	corner(sh, 14)
	local f = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = face, BorderSizePixel = 0 }, holder)
	corner(f, 14)
	stroke(f, 3)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(108, 102), BackgroundColor3 = artBg, ClipsDescendants = true }, f)
	corner(art, 9)
	stroke(art, 2)
	text(f, "Big", { Position = UDim2.fromOffset(4, 116), Size = UDim2.fromOffset(116, 22), TextSize = 15, Text = big })
	text(f, "Small", { Position = UDim2.fromOffset(4, 138), Size = UDim2.fromOffset(116, 18), FontFace = BODY, TextSize = 13, TextColor3 = MUTED, Text = small })
	if tag then
		local t = text(holder, "Tag", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundTransparency = 0, BackgroundColor3 = tagBg, TextColor3 = tagText, TextSize = 11, Text = tag, TextTruncate = Enum.TextTruncate.None, ZIndex = 3 })
		corner(t, 8)
		stroke(t, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, t)
	end
	return art
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("StarterOffer")
	if old then
		old:Destroy()
	end
	local pack = ShopCatalog.DebutPack
	local root = new("Frame", { Name = "StarterOffer", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, root)
	scrim.Active = true

	local W, H = 620, 450
	local x, y = 640 - W / 2, 360 - H / 2
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(x + 9, y + 9), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(shadow, 22)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(W, H), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, root)
	corner(panel, 22)
	stroke(panel, 4)

	-- header: rounded top (follows the panel), square bottom on the rule
	local head = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = PINK, BorderSizePixel = 0 }, panel)
	corner(head, 20)
	new("Frame", { Name = "Square", Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = PINK, BorderSizePixel = 0, ZIndex = 0 }, head)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(head, "Title", { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 40), TextSize = 32, Text = "DEBUT PACK" })
	text(head, "Sub", { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 20), FontFace = BODY, TextSize = 15, Text = "NEW PLAYERS ONLY · ONE TIME" })

	-- the four rewards
	local cy = 114
	local cx = (W - (4 * 124 + 3 * 14)) / 2
	local coins = rewardCard(panel, "Coins", cx, cy, WHITE, C("FFF6D6"), "2,500", "Coins", nil, nil, nil, -3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(78, 78), BackgroundTransparency = 1, Image = pack.Items[1].Image or "", ScaleType = Enum.ScaleType.Fit }, coins)
	rewardCard(panel, "Stage", cx + 138, cy, WHITE, C("E4F4FF"), "Debut Stage", "Stage", "ONLY HERE", RED, WHITE, 1)
	rewardCard(panel, "Mic", cx + 276, cy, WHITE, C("E4F4FF"), "Debut Mic", "Mic", "ONLY HERE", RED, WHITE, 3)
	local bonus = rewardCard(panel, "Bonus", cx + 414, cy, YELLOW, WHITE, "+3 tickets", "Roll tickets", "STARTER BONUS", INK, YELLOW, -2)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(78, 78), BackgroundTransparency = 1, Image = Currencies.Tickets.Icon, ScaleType = Enum.ScaleType.Fit }, bonus)

	-- the bonus timer
	local timer = text(panel, "Timer", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, cy + 180 + 20), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = YELLOW, TextSize = 16, Text = "Bonus ends in 47:59:12", TextTruncate = Enum.TextTruncate.None })
	corner(timer, 12)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, timer)

	-- Maybe later · GET IT · R$ 64
	local by = cy + 180 + 20 + 34 + 20
	button(panel, "Later", 30, by, 206, 58, WHITE, "Maybe later")
	local buy = button(panel, "Buy", 250, by, W - 280, 58, MINT, "")
	local inner = new("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, buy)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	text(inner, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), TextSize = 20, Text = "GET IT ·", TextTruncate = Enum.TextTruncate.None })
	new("ImageLabel", { Name = "Icon", LayoutOrder = 2, Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = ROBUX, ScaleType = Enum.ScaleType.Fit }, inner)
	text(inner, "Price", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), TextSize = 20, Text = "64", TextTruncate = Enum.TextTruncate.None })

	root.Parent = frames
	return root
end

-- the HUD card under the Invite button ("HUD right · Invite + Debut Pack buttons", style B)
-- while the bonus lasts: yellow, a tilted white tile with the roll ticket, "Debut Pack" /
-- "Bonus ends 47:59:12" with a thin countdown bar under it as wide as that line (Info.Timer,
-- Info.Bar.Fill: the controller fills them in), and a red +3 FREE sticker
function Build.HUDChip(hud: Instance)
	local tl = hud:FindFirstChild("Buttons") -- the right-hand group, with Invite
	for _, n in { "Starter", "StarterShadow" } do
		local old = tl:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local w, h = 176, 52
	local x, y = 1260 - w / 2, 162 + h / 2 -- centre; 22 under the Invite card (room for the sticker)
	local shadow = new("Frame", { Name = "StarterShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + 4, y + 4), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0, Visible = false }, tl)
	corner(shadow, 13)
	local chip = new("TextButton", { Name = "Starter", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = YELLOW, AutoButtonColor = false, Text = "", Visible = false }, tl)
	corner(chip, 13)
	stroke(chip, 3)
	local icon = new("Frame", { Name = "IconBox", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(34, 34), Rotation = -6, BackgroundColor3 = WHITE }, chip)
	corner(icon, 9)
	stroke(icon, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(25, 25), BackgroundTransparency = 1, Image = Currencies.Tickets.Icon, ScaleType = Enum.ScaleType.Fit }, icon)
	text(chip, "Title", { Position = UDim2.fromOffset(52, 6), Size = UDim2.fromOffset(w - 58, 18), TextSize = 15, Text = "Debut Pack", TextXAlignment = Enum.TextXAlignment.Left })
	-- the timer line and the countdown bar under it; the controller sizes the bar to the line's
	-- width each tick (so they always match); the fill never gets narrower than it is tall
	local info = new("Frame", { Name = "Info", Position = UDim2.fromOffset(52, 24), Size = UDim2.fromOffset(w - 58, 23), BackgroundTransparency = 1 }, chip)
	text(info, "Timer", { Size = UDim2.fromOffset(0, 15), AutomaticSize = Enum.AutomaticSize.X, FontFace = BODY, TextSize = 12, Text = "Bonus ends 47:59:12", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.None })
	local bar = new("Frame", { Name = "Bar", Position = UDim2.fromOffset(0, 18), Size = UDim2.fromOffset(100, 5), BackgroundColor3 = INK, BorderSizePixel = 0 }, info)
	corner(bar, UDim.new(0.5, 0))
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.92, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, bar)
	corner(fill, UDim.new(0.5, 0))
	new("UISizeConstraint", { MinSize = Vector2.new(5, 0) }, fill)
	local sticker = text(chip, "Sticker", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, -12), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), Rotation = 6, BackgroundTransparency = 0, BackgroundColor3 = RED, TextColor3 = WHITE, TextSize = 12, Text = "+3 FREE", TextTruncate = Enum.TextTruncate.None, ZIndex = 3 })
	corner(sticker, 9)
	stroke(sticker, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, sticker)
	return chip
end

return Build
