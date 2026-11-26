--| Albums UI builder
-- Builds Interface.Frames.Albums: the K-POPPED! photocard screens, all full-screen (design boards
-- "2 · Pick your bias", "16–20 · Pull v2" and "22–25 · Packs"). Run once in Studio Edit mode from the command bar,
-- then save the place:
--   require(game.StarterPlayer.StarterPlayerScripts.Client.InterfaceController.Controllers.AlbumsController.Build).Build(game.StarterGui.Interface.Frames)
-- Safe to run again: it replaces the old frame.
-- AlbumsController finds everything by name and fills lists by cloning the hidden Template rows.
--
-- One full-screen frame, four pages over a shared dark backdrop:
--   Bias   pick a group, then a member
--   Shop   the Packs page: free packs (pick a gen, Open / Open all, the refill clock), gen packs,
--          group packs (a row of group sleeves, photo when the group has PackArt), ×1/×5/×10,
--          the odds sheet
--   Pull   the stage: the sleeve, the fan of card backs, one card at a time with the tray and
--          the binder-page tag, the rare moment, the summary
--          (Build.RevealFx(Frames.Albums.Pull) adds just the rare reveals' pieces)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local PINK = C("FF9EC4")
local BLUE = C("9ED8F5")
local LILAC = C("DCD3FF")
local PURPLE = C("B9A6FF")
local MUTED = C("5C566B")
local NIGHT = C("2A2340")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local Currencies = require(game:GetService("ReplicatedStorage").Constants.Currencies)
local CardDecor = require(game:GetService("ReplicatedStorage").Modules.UI.CardDecor)
local COIN = Currencies.Coins.Icon
local TICKET = Currencies.Tickets.Icon

-- text on the dark backdrop
local DIM = 0.35 -- TextTransparency for quiet cream text

local Build = {}

-- [[ Helpers ]]

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
local function stroke(p: Instance, t: number, colour: Color3?, transparency: number?)
	new("UIStroke", { Color = colour or INK, Thickness = t, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function pad(p: Instance, l: number, r: number?, t: number?, b: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0) }, p)
end
local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
-- quiet cream text on the backdrop
local function soft(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { TextColor3 = CREAM, TextTransparency = DIM, FontFace = BODY_BOLD, TextSize = 14 }
	for k, v in props do
		base[k] = v
	end
	return text(parent, name, base)
end
local function chip(parent: Instance, name: string, label: string, colour: Color3, size: number, props: { [string]: any }?): TextLabel
	local base = {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 8),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		FontFace = BODY,
		TextSize = size,
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Center,
	}
	for k, v in props or {} do
		base[k] = v
	end
	local c = text(parent, name, base)
	corner(c, 7)
	stroke(c, 2)
	pad(c, 7)
	return c
end
-- a see-through pill on the backdrop ("Skip", "Sell 25", the coin balance)
local function ghost(parent: Instance, name: string, label: string, size: number, props: { [string]: any }?): TextButton
	local base = {
		Name = name,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 18),
		BackgroundColor3 = CREAM,
		BackgroundTransparency = 0.9,
		FontFace = BODY,
		TextSize = size,
		TextColor3 = CREAM,
		Text = label,
		AutoButtonColor = false,
	}
	for k, v in props or {} do
		base[k] = v
	end
	local b = new("TextButton", base, parent)
	corner(b, 12)
	stroke(b, 2, CREAM, 0.75)
	pad(b, 16)
	return b
end
-- a centre-anchored button with a hard shadow. With an icon: a row of Label + Icon + Amount.
local function button(parent: Instance, name: string, cx: number, cy: number, w: number, h: number, colour: Color3, label: string, size: number, icon: string?, drop: number?): TextButton
	local d = drop or 4
	if d > 0 then
		local s = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx + d, cy + d), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK }, parent)
		corner(s, 14)
	end
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		FontFace = HEAD,
		TextSize = size,
		TextColor3 = INK,
		Text = if icon then "" else label,
		AutoButtonColor = false,
		ZIndex = 2,
	}, parent)
	corner(b, 14)
	stroke(b, 4)
	if icon then
		local row = new("Frame", { Name = "Row", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, b)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		text(row, "Label", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), FontFace = HEAD, TextSize = size, Text = label, LayoutOrder = 1, ZIndex = 2 })
		new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(size + 6, size + 6), BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 2, ZIndex = 2 }, row)
		text(row, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h), FontFace = HEAD, TextSize = size, Text = "0", LayoutOrder = 3, ZIndex = 2 })
	end
	return b
end
-- the pink Bias button (design board "55 · Bias button"): left of ×1 / ×5 / ×10, opens the
-- Bias page, where you see your bias and can change it
local function biasButton(cluster: Instance): TextButton
	local b = new("TextButton", {
		Name = "Bias",
		LayoutOrder = -3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 38),
		BackgroundColor3 = PINK,
		FontFace = BODY,
		TextSize = 15,
		TextColor3 = INK,
		Text = "Bias",
		AutoButtonColor = false,
	}, cluster)
	corner(b, 12)
	stroke(b, 3, INK)
	pad(b, 18)
	return b
end

local function closeButton(parent: Instance, cx: number, cy: number): TextButton
	return button(parent, "Close", cx, cy, 46, 46, RED, "X", 20, nil, 3)
end
-- coins (and tickets) at the top right
local function balance(parent: Instance, rightX: number, y: number, withTickets: boolean)
	local row = new("Frame", { Name = "Balance", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(rightX, y), Size = UDim2.fromOffset(320, 38), BackgroundTransparency = 1 }, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i, spec in { { "Tickets", TICKET }, { "Coins", COIN } } do
		if spec[1] == "Tickets" and not withTickets then
			continue
		end
		local c = new("Frame", { Name = spec[1], AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), BackgroundColor3 = CREAM, BackgroundTransparency = 0.9, LayoutOrder = i }, row)
		corner(c, 12)
		stroke(c, 2, CREAM, 0.75)
		pad(c, 10, 14)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, c)
		new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = spec[2], ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, c)
		text(c, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38), TextSize = 16, TextColor3 = CREAM, Text = "0", LayoutOrder = 2 })
	end
end
-- the grey silhouette that stands in for idol art until the art batch lands
local function silhouette(parent: Instance, scale: number, z: number)
	local s = new("Frame", { Name = "Silhouette", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(200 * scale, 240 * scale), BackgroundTransparency = 1, ZIndex = z }, parent)
	local head = new("Frame", { Name = "Head", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44 * scale), Size = UDim2.fromOffset(96 * scale, 96 * scale), BackgroundColor3 = INK, BackgroundTransparency = 0.84, ZIndex = z }, s)
	corner(head, 999)
	local body = new("Frame", { Name = "Body", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 148 * scale), Size = UDim2.fromOffset(172 * scale, 92 * scale), BackgroundColor3 = INK, BackgroundTransparency = 0.84, ZIndex = z }, s)
	corner(body, math.floor(46 * scale))
end
local function setZ(root: Instance, z: number)
	if root:IsA("GuiObject") then
		root.ZIndex = z
	end
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = z
		end
	end
end

-- The Unopened box's rows (Shop.Side.Unopened): pack tickets (a 1-card free pack each) and
-- gen packs bought with Robux (a whole gen pack each, Currencies.GenPacks; 26 Nov 2026). Safe to
-- run again on a built frame: it rebuilds just the two rows.
function Build.UnopenedRows(unopened: Instance)
	for _, name in { "Tickets", "GenPacks" } do
		local old = unopened:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	for i, spec in { { "Tickets", "Pack tickets ×25", LILAC }, { "GenPacks", "Gen packs ×5", YELLOW } } do
		local r = new("Frame", { Name = spec[1], Position = UDim2.fromOffset(12, 68 + (i - 1) * 64), Size = UDim2.fromOffset(292, 56), BackgroundColor3 = CREAM, BackgroundTransparency = 0.94 }, unopened)
		corner(r, 14)
		stroke(r, 2, CREAM, 0.86)
		text(r, "Label", { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(180, 56), TextSize = 14, TextColor3 = CREAM, Text = spec[2] })
		button(r, "Open", 236, 28, 88, 34, spec[3], "OPEN", 13, nil, 3)
	end
end

-- [[ Shared art: the sleeve, the card face, the card back ]]

-- A pack's record sleeve, 250×250 (scale it with the UIScale named Scale). The controller sets
-- Sleeve.BackgroundColor3, Sleeve.Band.Label.Text, Sleeve.Sticker.Count.Text and, for a group
-- with PackArt, Sleeve.Photo (Image + Visible).
local function sleeveArt(parent: Instance, name: string): Frame
	local root = new("Frame", { Name = name, Size = UDim2.fromOffset(250, 250), BackgroundTransparency = 1 }, parent)
	new("UIScale", { Name = "Scale" }, root)
	local glow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 44, 1, 44), BackgroundColor3 = WHITE, BackgroundTransparency = 1 }, root)
	corner(glow, 44)
	new("UIGradient", { Name = "Foil", Enabled = false, Rotation = 45 }, glow)
	local disc = new("Frame", { Name = "Disc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 30, 0.5, 0), Size = UDim2.fromOffset(210, 210), BackgroundColor3 = NIGHT }, root)
	corner(disc, 105)
	stroke(disc, 4)
	for k, r in { 84, 64 } do
		local groove = new("Frame", { Name = "Groove" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(r * 2, r * 2), BackgroundTransparency = 1 }, disc)
		corner(groove, r)
		stroke(groove, 2)
	end
	local discLabel = new("Frame", { Name = "Label", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(66, 66), BackgroundColor3 = YELLOW }, disc)
	corner(discLabel, 33)
	stroke(discLabel, 4)
	local shadow = new("Frame", { Name = "SleeveShadow", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, root)
	corner(shadow, 16)
	local sleeve = new("Frame", { Name = "Sleeve", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PINK }, root)
	corner(sleeve, 16)
	stroke(sleeve, 5)
	-- diagonal stripes from a gradient (a rotating sleeve can't clip its children)
	local stripes = new("Frame", { Name = "Stripes", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, sleeve)
	corner(stripes, 16)
	local keys = { NumberSequenceKeypoint.new(0, 0.7) }
	for k = 1, 9 do
		local x = k / 10
		table.insert(keys, NumberSequenceKeypoint.new(x - 0.001, if k % 2 == 1 then 0.7 else 1))
		table.insert(keys, NumberSequenceKeypoint.new(x, if k % 2 == 1 then 1 else 0.7))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 0.7))
	new("UIGradient", { Name = "Pattern", Rotation = 45, Transparency = NumberSequence.new(keys) }, stripes)
	-- the group photo (group packs, when the group has PackArt): covers the stripes
	local photo = new("ImageLabel", { Name = "Photo", Size = UDim2.fromScale(1, 1), BackgroundColor3 = CREAM, ScaleType = Enum.ScaleType.Crop, Image = "", Visible = false }, sleeve)
	corner(photo, 12)
	local shade = new("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, photo)
	corner(shade, 12)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 0.3) }) }, shade)
	-- the crimped tear strip along the top (flies off when it opens)
	-- (a row of thin ink teeth, like a heat-sealed edge)
	local tear = new("Frame", { Name = "Tear", Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, sleeve)
	for x = 8, 238, 8 do
		new("Frame", { Name = "Tooth", Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(3, 22), BackgroundColor3 = INK, BackgroundTransparency = 0.65, BorderSizePixel = 0 }, tear)
	end
	local band = new("Frame", { Name = "Band", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.new(1, -10, 0, 50), BackgroundColor3 = CREAM }, sleeve)
	stroke(band, 4)
	text(band, "Label", { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), FontFace = HEAD, TextSize = 24, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Text = "BTS" })
	new("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 12 }, band.Label)
	local sticker = new("Frame", { Name = "Sticker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -44, 1, -42), Size = UDim2.fromOffset(72, 72), Rotation = 12, BackgroundColor3 = RED }, sleeve)
	corner(sticker, 36)
	stroke(sticker, 3)
	-- (just "×5": big enough to read when the sleeve is drawn small, scaled to stay inside the circle)
	local count = text(sticker, "Count", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.56), FontFace = HEAD, TextSize = 30, TextScaled = true, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "×1" })
	new("UITextSizeConstraint", { MaxTextSize = 30 }, count)
	return root
end

-- A photocard face, 260×380. The controller fills Photo, Member, Album, Rarity, Bias, Level, New,
-- the serial (Photo.Serial) and the rarity look (Foil, Stamp, Signature, Shine).
local function cardFace(parent: Instance, name: string): Frame
	local root = new("Frame", { Name = name, Size = UDim2.fromOffset(260, 380), BackgroundTransparency = 1 }, parent)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(9, 9), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, root)
	corner(shadow, 18)
	local glow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 18, 1, 18), BackgroundColor3 = C("F2C94C"), Visible = false }, root)
	corner(glow, 24)
	new("UIGradient", { Name = "Rainbow", Enabled = false, Rotation = 45 }, glow)
	local c = new("Frame", { Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, root)
	corner(c, 18)
	stroke(c, 5)
	new("UIGradient", { Name = "Foil", Enabled = false, Rotation = 45 }, c)
	local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -96), BackgroundColor3 = C("FFD2E5"), ClipsDescendants = true }, c)
	corner(photo, 12)
	stroke(photo, 4)
	silhouette(photo, 1, 1)
	new("ImageLabel", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Image = "" }, photo)
	new("Frame", { Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(116, 96), Size = UDim2.fromOffset(200, 22), Rotation = -24, BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, Visible = false }, photo)
	chip(photo, "Stamp", "STORE", MINT, 10, { Position = UDim2.fromOffset(8, 8), Visible = false, Rotation = -8 })
	-- the serial number of a numbered card ("#12", "1 OF 1"; Albums.SerialText)
	chip(photo, "Serial", "#12", INK, 16, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), FontFace = HEAD, TextColor3 = YELLOW, Visible = false })
	text(photo, "Signature", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -8), Size = UDim2.fromOffset(150, 36), FontFace = Font.new("rbxasset://fonts/families/IndieFlower.json"), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Right, Text = "Jimin", Rotation = -8, Visible = false })
	text(c, "Member", { Position = UDim2.new(0, 14, 1, -76), Size = UDim2.new(1, -110, 0, 32), FontFace = HEAD, TextSize = 26, Text = "Jimin", TextTruncate = Enum.TextTruncate.AtEnd })
	chip(c, "Bias", "BIAS", PINK, 10, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -72), Visible = false })
	chip(c, "Level", "GOLD", INK, 10, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 1, -72), TextColor3 = C("F2C94C"), Visible = false })
	text(c, "Album", { Position = UDim2.new(0, 14, 1, -38), Size = UDim2.new(1, -120, 0, 22), TextSize = 12, Text = "BTS · Love Yourself", TextTruncate = Enum.TextTruncate.AtEnd })
	chip(c, "Rarity", "LUCKY DRAW", INK, 10, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -36), TextColor3 = CREAM })
	chip(root, "New", "NEW", MINT, 15, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 10, 0, -12), FontFace = HEAD, Rotation = 10, Visible = false })
	CardDecor.Build(root, c, photo) -- the v2 rarity looks + level stars
	return root
end

-- The back of every photocard (design board "15 · Card back options", A · Holo emblem), 260×380.
local function cardBack(parent: Instance, name: string): Frame
	local back = new("Frame", { Name = name, Size = UDim2.fromOffset(260, 380), BackgroundColor3 = PINK }, parent)
	corner(back, 18)
	stroke(back, 5)
	local dots = new("Frame", { Name = "Dots", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), BackgroundTransparency = 1 }, back)
	for row = 0, 13 do
		for col = 0, 9 do
			local lilac = (row + col) % 2 == 1
			local size = if lilac then 4 else 6
			local d = new("Frame", { Name = "Dot", Position = UDim2.fromOffset(col * 24 + (if row % 2 == 1 then 12 else 0), row * 26), Size = UDim2.fromOffset(size, size), BackgroundColor3 = if lilac then PURPLE else WHITE, BackgroundTransparency = if lilac then 0.3 else 0.45, BorderSizePixel = 0 }, dots)
			corner(d, 3)
		end
	end
	local sheen = new("Frame", { Name = "Sheen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, back)
	corner(sheen, 14)
	new("UIGradient", {
		Name = "Foil",
		Rotation = 35,
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.45, BLUE), ColorSequenceKeypoint.new(0.6, MINT), ColorSequenceKeypoint.new(1, YELLOW) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(0.45, 0.45), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(0.75, 1), NumberSequenceKeypoint.new(1, 1) }),
	}, sheen)
	local inner = new("Frame", { Name = "Inner", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), BackgroundTransparency = 1 }, back)
	corner(inner, 12)
	stroke(inner, 3, C("8E5A73"))
	local sealShadow = new("Frame", { Name = "SealShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 6, 0.44, 6), Size = UDim2.fromOffset(170, 170), BackgroundColor3 = INK }, back)
	corner(sealShadow, 85)
	local seal = new("Frame", { Name = "Seal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(170, 170), Rotation = -6, BackgroundColor3 = CREAM }, back)
	corner(seal, 85)
	stroke(seal, 5)
	local star = new("Frame", { Name = "Star", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(18, 18), Rotation = 45, BackgroundColor3 = YELLOW }, seal)
	corner(star, 4)
	stroke(star, 2)
	text(seal, "Shadow", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 3, 0.5, 5), Size = UDim2.fromOffset(160, 30), FontFace = HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Text = "K-POPPED!" })
	local word = text(seal, "Brand", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 2), Size = UDim2.fromOffset(160, 30), FontFace = HEAD, TextSize = 22, TextColor3 = PINK, TextXAlignment = Enum.TextXAlignment.Center, Text = "K-POPPED!" })
	new("UIStroke", { Color = INK, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, word)
	chip(seal, "Photocard", "PHOTOCARD", INK, 9, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 24), TextColor3 = CREAM })
	for k, spec in { { 24, 26, YELLOW, -12 }, { 222, 32, CREAM, 14 }, { 28, 284, BLUE, -8 }, { 220, 278, MINT, 18 } } do
		local deco = new("Frame", { Name = "Deco" .. k, Position = UDim2.fromOffset(spec[1], spec[2]), Size = UDim2.fromOffset(16, 16), Rotation = 45 + spec[4], BackgroundColor3 = spec[3] }, back)
		corner(deco, 3)
		stroke(deco, 2)
	end
	local ribbon = new("Frame", { Name = "Ribbon", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = INK, BorderSizePixel = 0 }, back)
	text(ribbon, "Label", { Size = UDim2.fromScale(1, 1), FontFace = BODY, TextSize = 11, TextColor3 = YELLOW, TextXAlignment = Enum.TextXAlignment.Center, Text = "O F F I C I A L   P H O T O C A R D" })
	return back
end

-- a small card in a wrapper of size w (the face shrunk with a UIScale), for the tray and summary
local function miniFace(parent: Instance, name: string, w: number): Frame
	local scale = w / 260
	local wrap = new("Frame", { Name = name, Size = UDim2.fromOffset(w, math.floor(380 * scale)), BackgroundTransparency = 1 }, parent)
	local face = cardFace(wrap, "Face")
	new("UIScale", { Scale = scale }, face)
	return wrap
end

-- [[ Backdrop ]]

local function backdrop(root: Frame)
	local bg = new("Frame", { Name = "Backdrop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, root)
	bg.Active = true
	new("UIGradient", {
		Color = ColorSequence.new(C("3B2F66"), C("221C36")),
		Rotation = 90,
		Offset = Vector2.new(0, 0.05),
	}, bg)
	for k, spec in { { 980, 0.975 }, { 720, 0.97 }, { 470, 0.965 } } do
		local ring = new("Frame", { Name = "Ring" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 330), Size = UDim2.fromOffset(spec[1], spec[1]), BackgroundColor3 = CREAM, BackgroundTransparency = spec[2], BorderSizePixel = 0 }, root)
		corner(ring, spec[1] / 2)
	end
end

-- [[ 2 · Pick your bias ]]

local function bias(root: Frame)
	local page = new("Frame", { Name = "Bias", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, root)
	-- (headings sit below Roblox's top bar buttons, like the Packs page)
	text(page, "Title", { Position = UDim2.fromOffset(40, 60), Size = UDim2.fromOffset(500, 34), FontFace = HEAD, TextSize = 28, TextColor3 = CREAM, Text = "Pick your bias" })
	soft(page, "Sub", { Position = UDim2.fromOffset(40, 98), Size = UDim2.fromOffset(700, 20), Text = "Your bias is twice as likely in their group's pulls and earns more in your binder." })
	closeButton(page, 1214, 79)

	chip(page, "GroupStep", "1 · Group", CREAM, 13, { Position = UDim2.fromOffset(40, 136) })
	soft(page, "GroupsLabel", { Position = UDim2.fromOffset(132, 136), Size = UDim2.fromOffset(220, 22), Text = "Which group do you stan?" })

	-- the group list, like the binder's: search, All / Girls / Boys, then a row per group
	local side = new("Frame", { Name = "Groups", Position = UDim2.fromOffset(40, 170), Size = UDim2.fromOffset(306, 526), BackgroundTransparency = 1 }, page)
	local search = new("Frame", { Name = "Search", Size = UDim2.fromOffset(296, 38), BackgroundColor3 = CREAM, BackgroundTransparency = 0.92 }, side)
	corner(search, 11)
	stroke(search, 2, CREAM, 0.8)
	local glass = new("Frame", { Name = "Glass", Position = UDim2.fromOffset(12, 11), Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 1 }, search)
	corner(glass, 6)
	stroke(glass, 2, CREAM, 0.25)
	new("Frame", { Name = "Handle", Position = UDim2.fromOffset(9, 11), Size = UDim2.fromOffset(6, 2), Rotation = 45, BackgroundColor3 = CREAM, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, glass)
	new("TextBox", {
		Name = "Box",
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		FontFace = BODY_BOLD,
		TextSize = 15,
		TextColor3 = CREAM,
		PlaceholderText = "Find a group",
		PlaceholderColor3 = C("BDB6CF"),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, search)

	local filters = new("Frame", { Name = "Filters", Position = UDim2.fromOffset(0, 46), Size = UDim2.fromOffset(296, 28), BackgroundTransparency = 1 }, side)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, filters)
	for i, spec in { { "All", "All" }, { "Girl", "Girls" }, { "Boy", "Boys" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundColor3 = CREAM, BackgroundTransparency = if i == 1 then 0 else 0.9, FontFace = BODY, TextSize = 14, TextColor3 = if i == 1 then INK else CREAM, Text = spec[2], AutoButtonColor = false }, filters)
		corner(b, 10)
		stroke(b, 2, if i == 1 then INK else CREAM, if i == 1 then 0 else 0.75)
		pad(b, 13)
	end

	local groups = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.fromOffset(306, 442),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = CREAM,
		ScrollBarImageTransparency = 0.6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, side)
	pad(groups, 0, 10, 2, 8)
	new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, groups)
	text(groups, "Empty", { Size = UDim2.fromOffset(286, 40), TextColor3 = CREAM, TextTransparency = DIM, FontFace = BODY_BOLD, TextSize = 14, Text = "No groups match that", TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 9999, Visible = false })

	-- a group row (cloned per group; the picked one is yellow with a shadow)
	local row = new("Frame", { Name = "Template", Size = UDim2.fromOffset(288, 52), BackgroundTransparency = 1, Visible = false }, groups)
	local rowShadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, Visible = false }, row)
	corner(rowShadow, 12)
	local g = new("TextButton", { Name = "Button", Size = UDim2.fromScale(1, 1), BackgroundColor3 = CREAM, BackgroundTransparency = 0.95, Text = "", AutoButtonColor = false }, row)
	corner(g, 12)
	stroke(g, 2, CREAM, 0.9)
	local icon = new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = PINK, ScaleType = Enum.ScaleType.Crop, Image = "" }, g)
	corner(icon, 8)
	stroke(icon, 2)
	text(icon, "Initial", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 16, Text = "B", TextXAlignment = Enum.TextXAlignment.Center })
	text(g, "Label", { Position = UDim2.fromOffset(54, 7), Size = UDim2.fromOffset(170, 20), TextSize = 15, TextColor3 = CREAM, Text = "BLACKPINK", RichText = true, TextTruncate = Enum.TextTruncate.AtEnd })
	text(g, "Members", { Position = UDim2.fromOffset(54, 27), Size = UDim2.fromOffset(170, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = CREAM, TextTransparency = DIM, Text = "4 members" })
	text(g, "Gen", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(60, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = CREAM, TextTransparency = DIM, Text = "3rd gen", TextXAlignment = Enum.TextXAlignment.Right })

	chip(page, "MemberStep", "2 · Member", PINK, 13, { Position = UDim2.fromOffset(420, 136) })
	soft(page, "MembersLabel", { Position = UDim2.fromOffset(530, 136), Size = UDim2.fromOffset(600, 22), Text = "BTS · tap your bias" })
	local members = new("ScrollingFrame", {
		Name = "Members",
		Position = UDim2.fromOffset(414, 160),
		Size = UDim2.fromOffset(830, 230),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = CREAM,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
	}, page)
	pad(members, 6, 10, 26, 10)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, members)
	local m = new("TextButton", { Name = "Template", Visible = false, Size = UDim2.fromOffset(98, 160), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, members)
	corner(m, 12)
	stroke(m, 3)
	local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(7, 7), Size = UDim2.new(1, -14, 1, -40), BackgroundColor3 = BLUE, ClipsDescendants = true }, m)
	corner(photo, 8)
	stroke(photo, 3)
	silhouette(photo, 0.42, 1)
	new("ImageLabel", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Image = "" }, photo)
	text(m, "Label", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -6), Size = UDim2.new(1, -12, 0, 22), FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	chip(m, "MyBias", "MY BIAS", RED, 11, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -18), TextColor3 = CREAM, Visible = false, ZIndex = 3 })

	local perksShadow = new("Frame", { Name = "PerksShadow", Position = UDim2.fromOffset(426, 416), Size = UDim2.fromOffset(812, 172), BackgroundColor3 = INK }, page)
	corner(perksShadow, 16)
	local perks = new("Frame", { Name = "Perks", Position = UDim2.fromOffset(420, 410), Size = UDim2.fromOffset(812, 172), BackgroundColor3 = CREAM }, page)
	corner(perks, 16)
	stroke(perks, 4)
	text(perks, "YourBias", { Position = UDim2.fromOffset(24, 20), Size = UDim2.fromOffset(240, 18), TextSize = 13, TextColor3 = MUTED, Text = "Your bias" })
	text(perks, "BiasName", { Position = UDim2.fromOffset(24, 44), Size = UDim2.fromOffset(250, 40), FontFace = HEAD, TextSize = 32, Text = "Jimin", TextTruncate = Enum.TextTruncate.AtEnd })
	text(perks, "Group", { Position = UDim2.fromOffset(24, 90), Size = UDim2.fromOffset(250, 20), TextSize = 14, TextColor3 = C("4A4458"), Text = "BTS · ARMY" })
	for i, spec in { { "Weight", YELLOW, "2×" }, { "Earn", MINT, "+50%" }, { "Tag", BLUE, "TAG" } } do
		local row = new("Frame", { Name = "Perk" .. spec[1], Position = UDim2.fromOffset(300, 22 + (i - 1) * 44), Size = UDim2.fromOffset(490, 34), BackgroundTransparency = 1 }, perks)
		chip(row, "Tag", spec[3], spec[2], 13, { Position = UDim2.fromOffset(0, 5), Size = UDim2.fromOffset(62, 24), AutomaticSize = Enum.AutomaticSize.None })
		text(row, "Line", { Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -76, 1, 0), TextSize = 15, Text = "" })
	end
	soft(page, "Note", { Position = UDim2.fromOffset(420, 626), Size = UDim2.fromOffset(500, 26), Text = "You can change your bias once a week." })
	button(page, "Confirm", 1104, 642, 256, 58, PINK, "THIS IS MY BIAS", 18)
	soft(page, "GroupsNote", { Position = UDim2.fromOffset(420, 664), Size = UDim2.fromOffset(500, 22), TextSize = 12, Text = "More groups and albums arrive with updates." })
end

-- [[ 22 · Packs: free, gen and group packs ]]

local ODDS_ROWS = 7 -- every rarity, One of One included

-- a pack price: a coin and the amount, for the gen and group tiles
local function priceRow(parent: Instance, name: string, x: number, y: number, w: number, colour: Color3?)
	local row = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 20), BackgroundTransparency = 1 }, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	new("ImageLabel", { Name = "Icon", Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 }, row)
	text(row, "Amount", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextSize = 15, TextColor3 = colour or CREAM, Text = "400", LayoutOrder = 2 })
	return row
end

-- a small underlined "Odds" link: hover (or tap) shows that pack's odds popover
local function oddsLink(parent: Instance, x: number, y: number, colour: Color3?): TextButton
	local link = new("TextButton", { Name = "Odds", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, FontFace = BODY, TextSize = 13, TextColor3 = colour or CREAM, TextTransparency = 0.2, Text = "Odds", AutoButtonColor = false }, parent)
	new("Frame", { Name = "Underline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = colour or CREAM, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, link)
	return link
end

local function shop(root: Frame)
	local page = new("Frame", { Name = "Shop", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, root)
	-- (everything sits below y 56 on the left: Roblox's own buttons are in the top-left corner)
	text(page, "Title", { Position = UDim2.fromOffset(40, 60), Size = UDim2.fromOffset(500, 34), FontFace = HEAD, TextSize = 28, TextColor3 = CREAM, Text = "Packs" })
	soft(page, "Sub", { Position = UDim2.fromOffset(40, 98), Size = UDim2.fromOffset(600, 20), Text = "5 cards a pack. The best one is always last." })
	closeButton(page, 1214, 79)
	balance(page, 1176, 60, true)
	soft(page, "Blocked", { Position = UDim2.fromOffset(420, 98), Size = UDim2.fromOffset(500, 20), Text = "Photocard packs aren't available for your account.", Visible = false })

	-- ×1 / ×5 / ×10 (paid packs) and Rarities, centred at the top
	local cluster = new("Frame", { Name = "Controls", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 60), Size = UDim2.fromOffset(480, 38), BackgroundTransparency = 1 }, page)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, cluster)
	local counts = new("Frame", { Name = "Counts", LayoutOrder = -2, Size = UDim2.fromOffset(186, 38), BackgroundColor3 = CREAM, BackgroundTransparency = 0.9 }, cluster)
	corner(counts, 12)
	stroke(counts, 2, CREAM, 0.75)
	pad(counts, 3, 3, 3, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, counts)
	for i, n in { 1, 5, 10 } do
		local b = new("TextButton", { Name = "X" .. n, Size = UDim2.fromOffset(58, 32), BackgroundColor3 = CREAM, BackgroundTransparency = if i == 1 then 0 else 1, FontFace = BODY, TextSize = 15, TextColor3 = if i == 1 then INK else CREAM, Text = "×" .. n, AutoButtonColor = false, LayoutOrder = i }, counts)
		corner(b, 9)
	end
	ghost(cluster, "Odds", "Rarities", 14, { LayoutOrder = -1, Size = UDim2.fromOffset(0, 38) })
	biasButton(cluster)

	-- the main column scrolls (design board "26 · Packs v3"); the premium sidebar beside it
	local main = new("ScrollingFrame", {
		Name = "Main",
		Position = UDim2.fromOffset(30, 126),
		Size = UDim2.fromOffset(874, 594),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollBarImageTransparency = 1,
		CanvasSize = UDim2.fromOffset(0, 1070),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)

	-- free packs: a banner across the top
	local freeShadow = new("Frame", { Name = "FreeShadow", Position = UDim2.fromOffset(17, 17), Size = UDim2.fromOffset(836, 150), BackgroundColor3 = INK }, main)
	corner(freeShadow, 20)
	local free = new("Frame", { Name = "Free", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(836, 150), BackgroundColor3 = CREAM }, main)
	corner(free, 20)
	stroke(free, 4)
	local stack = new("Frame", { Name = "Stack", Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(130, 130), BackgroundTransparency = 1 }, free)
	for k = 1, 3 do
		local sl = sleeveArt(stack, "Sleeve" .. k)
		sl.Position = UDim2.fromOffset((k - 1) * 12, (3 - k) * 8)
		sl.Scale.Scale = 0.42
		sl.Disc.Visible = false
		sl.Sleeve.BackgroundColor3 = MINT
		sl.Sleeve.Band.Label.Text = "FREE"
		sl.Sleeve.Sticker.Count.Text = "×1"
	end
	chip(free, "Badge", "FREE", MINT, 13, { Position = UDim2.fromOffset(170, 16), FontFace = HEAD })
	text(free, "Count", { Position = UDim2.fromOffset(234, 14), Size = UDim2.fromOffset(260, 28), FontFace = HEAD, TextSize = 22, Text = "4 free packs" })
	text(free, "Line", { Position = UDim2.fromOffset(170, 48), Size = UDim2.fromOffset(330, 20), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "1 card each. Any rarity can turn up. Pick a gen:" })
	local gens = new("Frame", { Name = "Gens", Position = UDim2.fromOffset(170, 78), Size = UDim2.fromOffset(330, 30), BackgroundTransparency = 1 }, free)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, gens)
	for i, g in { "Any", "2nd", "3rd", "4th", "5th" } do
		local b = new("TextButton", { Name = g, Size = UDim2.fromOffset(54, 30), BackgroundColor3 = if i == 1 then INK else CREAM, FontFace = BODY, TextSize = 13, TextColor3 = if i == 1 then CREAM else INK, Text = g, AutoButtonColor = false, LayoutOrder = i }, gens)
		corner(b, 9)
		stroke(b, 2)
	end
	button(free, "Open", 604, 40, 168, 46, MINT, "OPEN", 16)
	local all = new("TextButton", { Name = "OpenAll", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(756, 40), Size = UDim2.fromOffset(116, 46), BackgroundColor3 = CREAM, FontFace = BODY, TextSize = 14, TextColor3 = INK, Text = "Open all 4", AutoButtonColor = false }, free)
	corner(all, 12)
	stroke(all, 3)
	text(free, "Timer", { Position = UDim2.fromOffset(520, 82), Size = UDim2.fromOffset(200, 18), TextSize = 12, Text = "Next free pack in 1h 12m" })
	text(free, "Cap", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(764, 82), Size = UDim2.fromOffset(110, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "holds up to 3" })
	oddsLink(free, 816, 81, INK)
	local ftrack = new("Frame", { Name = "Track", Position = UDim2.fromOffset(520, 108), Size = UDim2.fromOffset(296, 10), BackgroundColor3 = C("EDE5D6") }, free)
	corner(ftrack, 5)
	stroke(ftrack, 2)
	local ffill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = MINT, BorderSizePixel = 0 }, ftrack)
	corner(ffill, 5)

	local function sectionHead(name: string, y: number, title: string, line: string): Frame
		local h = new("Frame", { Name = name, Position = UDim2.fromOffset(10, y), Size = UDim2.fromOffset(836, 30), BackgroundTransparency = 1 }, main)
		text(h, "Title", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), FontFace = HEAD, TextSize = 19, TextColor3 = CREAM, Text = title })
		soft(h, "Line", { Position = UDim2.fromOffset(200, 0), Size = UDim2.fromOffset(560, 30), TextSize = 13, Text = line })
		return h
	end
	-- a pack tile: sleeve, a row (label + Odds), the price, Buy
	local function packTile(parent: Instance, name: string, w: number, h: number): Frame
		local tile = new("TextButton", { Name = name, Size = UDim2.fromOffset(w, h), BackgroundColor3 = CREAM, BackgroundTransparency = 0.94, Text = "", AutoButtonColor = false }, parent)
		corner(tile, 16)
		stroke(tile, 2, CREAM, 0.86)
		local sl = sleeveArt(tile, "Pack")
		local scale = (w - 20) / 250
		sl.Position = UDim2.fromOffset(10, 10)
		sl.Scale.Scale = scale
		sl.Disc.Visible = false
		sl.Sleeve.Sticker.Count.Text = "×5"
		local y = 10 + math.floor(250 * scale) + 8
		text(tile, "Label", { Position = UDim2.fromOffset(10, y), Size = UDim2.fromOffset(w - 64, 18), TextSize = 12, TextColor3 = CREAM, TextTruncate = Enum.TextTruncate.AtEnd, Text = "9 groups" })
		oddsLink(tile, w - 10, y)
		priceRow(tile, "Price", 10, y + 22, w - 20).UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		button(tile, "Buy", w / 2 + 1, h - 26, w - 22, 34, YELLOW, "BUY", 13)
		return tile
	end

	-- mixes & gens (gen packs, and the girl / boy / every-group mixes)
	sectionHead("MixHead", 186, "Mixes & gens", "Cards from lots of groups in one pack")
	local genRow = new("Frame", { Name = "GenPacks", Position = UDim2.fromOffset(10, 222), Size = UDim2.fromOffset(836, 214), BackgroundTransparency = 1 }, main)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, genRow)
	for i, g in { "2nd", "3rd", "4th", "5th", "Girl", "Boy", "All" } do
		local tile = packTile(genRow, g, 112, 214)
		tile.LayoutOrder = i
		tile.Pack.Sleeve.Band.Label.Text = if i <= 4 then string.upper(g) .. " GEN" elseif g == "All" then "SHUFFLE" else string.upper(g) .. "S"
	end

	-- your favourites: your bias's group and the groups you star, always on sale
	sectionHead("FavHead", 458, "Your favourites", "Your bias and up to 2 starred groups, always on sale")
	local favs = new("Frame", { Name = "Favs", Position = UDim2.fromOffset(10, 496), Size = UDim2.fromOffset(836, 250), BackgroundTransparency = 1 }, main)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, favs)
	local function groupTemplate(parent: Instance, w: number, h: number)
		local tile = packTile(parent, "Template", w, h)
		tile.Visible = false
		-- the group's name (the sleeve shows its art, with no name band)
		tile.Label.Text = "BLACKPINK"
		tile.Label.FontFace = HEAD
		tile.Label.TextScaled = true
		new("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8 }, tile.Label)
		local pin = new("TextButton", { Name = "Pin", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(w - 14, 16), Size = UDim2.fromOffset(46, 22), BackgroundColor3 = INK, FontFace = BODY, TextSize = 11, TextColor3 = CREAM, Text = "+ PIN", AutoButtonColor = false, ZIndex = 3 }, tile)
		corner(pin, 8)
		stroke(pin, 2, CREAM, 0.6)
		chip(tile, "Bias", "YOUR BIAS", PINK, 10, { Position = UDim2.fromOffset(-6, -12), Rotation = -4, Visible = false, ZIndex = 3 })
		return tile
	end
	groupTemplate(favs, 150, 250)
	local empty = new("Frame", { Name = "Empty", Size = UDim2.fromOffset(150, 250), BackgroundTransparency = 1, LayoutOrder = 99 }, favs)
	corner(empty, 16)
	stroke(empty, 2, CREAM, 0.7)
	soft(empty, "Hint", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Text = "Pin a group from Today's groups to keep its pack here" })

	-- today's groups: the rotation
	local th = sectionHead("TodayHead", 770, "Today's groups", "6 groups a day. Pick exactly who you get.")
	local rot = new("Frame", { Name = "NewGroups", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = CREAM, BackgroundTransparency = 0.9 }, th)
	corner(rot, 10)
	stroke(rot, 2, CREAM, 0.75)
	pad(rot, 12)
	text(rot, "Label", { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), TextSize = 13, TextColor3 = CREAM, Text = "New groups in 5h 12m" })
	local today = new("Frame", { Name = "Today", Position = UDim2.fromOffset(10, 808), Size = UDim2.fromOffset(836, 236), BackgroundTransparency = 1 }, main)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, today)
	groupTemplate(today, 134, 236)

	-- the sidebar: premium packs, the guarantee, unopened packs
	local side = new("ScrollingFrame", {
		Name = "Side",
		Position = UDim2.fromOffset(920, 126),
		Size = UDim2.fromOffset(334, 594),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollBarImageTransparency = 1,
		CanvasSize = UDim2.fromOffset(0, 934),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)
	local prem = new("Frame", { Name = "Premium", Position = UDim2.fromOffset(4, 10), Size = UDim2.fromOffset(316, 690), BackgroundColor3 = INK, BackgroundTransparency = 0.6 }, side)
	corner(prem, 20)
	stroke(prem, 2, PURPLE, 0.4)
	text(prem, "Title", { Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(280, 26), FontFace = HEAD, TextSize = 19, TextColor3 = CREAM, Text = "Premium packs" })
	soft(prem, "Line", { Position = UDim2.fromOffset(16, 40), Size = UDim2.fromOffset(280, 18), TextSize = 12, Text = "Much better odds. 5 cards each." })
	for i, spec in { { "photobook", "PHOTOBOOK", YELLOW }, { "limited", "LIMITED", LILAC }, { "fansign", "FANSIGN", CREAM } } do
		local card = new("Frame", { Name = spec[1], Position = UDim2.fromOffset(12, 68 + (i - 1) * 168), Size = UDim2.fromOffset(292, 156), BackgroundColor3 = CREAM, BackgroundTransparency = 0.94 }, prem)
		corner(card, 16)
		stroke(card, 2, CREAM, 0.86)
		local sl = sleeveArt(card, "Pack")
		sl.Position = UDim2.fromOffset(12, 12)
		sl.Scale.Scale = 0.28
		sl.Disc.Visible = false
		sl.Sleeve.BackgroundColor3 = spec[3]
		sl.Sleeve.Band.Label.Text = spec[2]
		sl.Sleeve.Sticker.Count.Text = "×5"
		text(card, "Title", { Position = UDim2.fromOffset(96, 12), Size = UDim2.fromOffset(186, 22), FontFace = HEAD, TextSize = 16, TextColor3 = CREAM, Text = "Photobook Pack" })
		text(card, "Line", { Position = UDim2.fromOffset(96, 36), Size = UDim2.fromOffset(186, 32), TextSize = 12, TextColor3 = YELLOW, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "Last card is Store Benefit or better" })
		oddsLink(card, 140, 70)
		button(card, "Buy", 96, 124, 170, 38, MINT, "", 14, COIN)
		button(card, "Robux", 236, 124, 96, 38, CREAM, "R$ 24", 14)
	end
	text(prem, "Guarantee", { Position = UDim2.fromOffset(16, 580), Size = UDim2.fromOffset(200, 18), TextSize = 13, TextColor3 = CREAM, Text = "Polaroid guarantee" })
	text(prem, "GuaranteeCount", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(300, 580), Size = UDim2.fromOffset(80, 18), TextSize = 13, TextColor3 = BLUE, TextXAlignment = Enum.TextXAlignment.Right, Text = "0 / 100" })
	local gtrack = new("Frame", { Name = "GuaranteeTrack", Position = UDim2.fromOffset(16, 604), Size = UDim2.fromOffset(284, 8), BackgroundColor3 = CREAM, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, prem)
	corner(gtrack, 4)
	local gfill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = BLUE, BorderSizePixel = 0 }, gtrack)
	corner(gfill, 4)
	soft(prem, "GuaranteeNote", { Position = UDim2.fromOffset(16, 618), Size = UDim2.fromOffset(284, 60), TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "Go 99 premium packs without a Signed Polaroid and the next one ends with one." })

	local unopened = new("Frame", { Name = "Unopened", Position = UDim2.fromOffset(4, 716), Size = UDim2.fromOffset(316, 204), BackgroundColor3 = INK, BackgroundTransparency = 0.6 }, side)
	corner(unopened, 20)
	stroke(unopened, 2, PURPLE, 0.4)
	text(unopened, "Title", { Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(280, 26), FontFace = HEAD, TextSize = 19, TextColor3 = CREAM, Text = "Unopened" })
	soft(unopened, "Line", { Position = UDim2.fromOffset(16, 40), Size = UDim2.fromOffset(280, 18), TextSize = 12, Text = "Tickets open 1 card · gen packs open 5" })
	Build.UnopenedRows(unopened)

	-- one pack's odds, shown by hovering (or tapping) its Odds link: each card, and the last one
	local pop = new("Frame", { Name = "Popover", Size = UDim2.fromOffset(330, 326), BackgroundColor3 = INK, Visible = false, ZIndex = 20 }, page)
	corner(pop, 16)
	stroke(pop, 3, CREAM, 0.7)
	pad(pop, 16, 16, 14, 12)
	text(pop, "Title", { Size = UDim2.fromOffset(298, 22), FontFace = HEAD, TextSize = 16, TextColor3 = CREAM, Text = "BTS pack", TextTruncate = Enum.TextTruncate.AtEnd })
	local ph = new("Frame", { Name = "Header", Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(298, 16), BackgroundTransparency = 1 }, pop)
	soft(ph, "Each", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 0), Size = UDim2.fromOffset(90, 16), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, Text = "CARDS 1-4" })
	text(ph, "Last", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(80, 16), TextSize = 11, TextColor3 = YELLOW, TextXAlignment = Enum.TextXAlignment.Right, Text = "LAST" })
	for i = 1, ODDS_ROWS do
		local r = new("Frame", { Name = "Row" .. i, Position = UDim2.fromOffset(0, 50 + (i - 1) * 26), Size = UDim2.fromOffset(298, 24), BackgroundTransparency = 1 }, pop)
		local dot = new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = WHITE }, r)
		corner(dot, 6)
		stroke(dot, 2, CREAM, 0.6)
		new("UIGradient", { Name = "Foil", Enabled = false, Rotation = 45 }, dot)
		text(r, "Label", { Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(120, 24), TextSize = 14, TextColor3 = CREAM, Text = "Standard" })
		soft(r, "Each", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 0), Size = UDim2.fromOffset(90, 24), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Text = "55%" })
		text(r, "Last", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(80, 24), TextSize = 14, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Right, Text = "50%" })
	end
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 236), Size = UDim2.fromOffset(298, 1), BackgroundColor3 = CREAM, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, pop)
	soft(pop, "Note", { Position = UDim2.fromOffset(0, 244), Size = UDim2.fromOffset(298, 54), TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	setZ(pop, 20)

	-- the odds sheet (a paid random item: the odds are one tap away before you pay)
	local sheet = new("Frame", { Name = "OddsSheet", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 10 }, page)
	local dim = new("TextButton", { Name = "Dim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.35, Text = "", AutoButtonColor = false, ZIndex = 10 }, sheet)
	dim.BorderSizePixel = 0
	-- the Rarities sheet: every rarity, rarest first, explained (design: SHUFFLED's Rarities)
	local panelShadow = new("Frame", { Name = "PanelShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(648, 378), Size = UDim2.fromOffset(680, 620), BackgroundColor3 = INK, ZIndex = 10 }, sheet)
	corner(panelShadow, 20)
	local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 370), Size = UDim2.fromOffset(680, 620), BackgroundColor3 = CREAM, ZIndex = 10 }, sheet)
	corner(panel, 20)
	stroke(panel, 4)
	text(panel, "Title", { Position = UDim2.fromOffset(24, 18), Size = UDim2.fromOffset(400, 30), FontFace = HEAD, TextSize = 24, Text = "Rarities" })
	text(panel, "Line", { Position = UDim2.fromOffset(24, 50), Size = UDim2.fromOffset(520, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "From rarest to most common. The same odds in every pack." })
	local close = button(panel, "Close", 640, 40, 40, 40, RED, "X", 18, nil, 0)
	close.ZIndex = 11
	local list = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(16, 80),
		Size = UDim2.fromOffset(648, 446),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	pad(list, 4, 12, 4, 8)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local row = new("Frame", { Name = "Template", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = WHITE, Visible = false }, list)
	corner(row, 14)
	stroke(row, 3)
	pad(row, 92, 14, 12, 12)
	-- the card's look, as a little card frame with its rank
	local swatch = new("Frame", { Name = "Swatch", Position = UDim2.new(0, -78, 0, 0), Size = UDim2.fromOffset(60, 84), BackgroundColor3 = WHITE }, row)
	corner(swatch, 10)
	stroke(swatch, 4)
	new("UIGradient", { Name = "Foil", Enabled = false, Rotation = 45 }, swatch)
	text(swatch, "Rank", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "#1" })
	local body = new("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, row)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	text(body, "Heading", { Size = UDim2.new(1, 0, 0, 22), FontFace = HEAD, TextSize = 18, Text = "Signed Polaroid", LayoutOrder = 1 })
	text(body, "Blurb", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, Text = "", LayoutOrder = 2 })
	local chips = new("Frame", { Name = "Chips", Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 3 }, body)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	for k, colour in { LILAC, YELLOW, MINT, PINK } do
		local c = chip(chips, "Chip" .. k, "", colour, 11, { LayoutOrder = k })
		c.Size = UDim2.fromOffset(0, 24)
	end
	-- your bias: a boost on top, not odds of its own
	local boost = new("Frame", { Name = "Boost", Position = UDim2.fromOffset(20, 538), Size = UDim2.fromOffset(640, 64), BackgroundColor3 = PINK }, panel)
	corner(boost, 12)
	stroke(boost, 3)
	text(boost, "Tag", { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(50, 64), FontFace = HEAD, TextSize = 22, Text = "2×" })
	text(boost, "Line", { Position = UDim2.fromOffset(70, 0), Size = UDim2.fromOffset(560, 64), TextSize = 13, TextWrapped = true, Text = "Bias boost: Jimin is 2× as likely as the rest of BTS in BTS packs. Copies level a card up: 3 copies make it Gold (2× earnings), 5 make it Rainbow (4×)." })
	setZ(panel, 11)
	setZ(panelShadow, 10)
end

-- [[ The rare reveals (design board "42 · Rare reveals") ]]
-- Lucky Draw and up each get their own moment (AlbumsController plays them). Everything sits
-- in Pull.Fx (behind the card) and Pull.FxTop (over it), hidden; the card is at (640, 300),
-- 260×380.
--   Night      One of One: the stage goes dark, star dots fade in
--   Glow       a soft glow behind the card back (gold / pink-silver / rainbow by rarity)
--   Charge     Polaroid: a white ring round the back that blinks like a flash charging, + Ready
--   Coins      Lucky Draw: gold coins that burst out and fall
--   Spot       Fansign: a soft pink spotlight; Hearts float up past the card; Leaks puff
--              out of the back's edges; Scribble: a white marker signature across the stage
--   Shock      One of One: the shockwave ring; Big: ONE OF ONE in gold; Dust: rising gold
--   Holder.Back.Cracks  One of One: rainbow light cracking through the back
local SCRIBBLE = "rbxassetid://110658120687997" -- a white marker squiggle (assets/UI/Cards/Scribble.png)
local GLOW = "rbxassetid://80565779904016" -- soft rounded glow, 9-slice (assets/UI/Cards/Glow.png)
local RADIAL = "rbxassetid://97414923574122" -- soft round falloff (assets/UI/Cards/Radial.png)
local TextService = game:GetService("TextService")

-- a straight line from (x1, y1) to (x2, y2) in its parent's px
local function line(parent: Instance, x1: number, y1: number, x2: number, y2: number, colour: Color3, width: number)
	local dx, dy = x2 - x1, y2 - y1
	local bar = new("Frame", { Name = "Line", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2), Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + width, width), Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(bar, width // 2)
end

function Build.RevealFx(page: Frame)
	local old = page:FindFirstChild("Fx")
	if old then
		old:Destroy()
	end
	local oldTop = page:FindFirstChild("FxTop")
	if oldTop then
		oldTop:Destroy()
	end
	-- (behind the card: Night, Glow, Spot, Hearts; the rest goes over it, in FxTop)
	local fx = new("Frame", { Name = "Fx", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 0 }, page)
	local top = new("Frame", { Name = "FxTop", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 9 }, page)

	local night = new("Frame", { Name = "Night", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = C("07060C"), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0, Visible = false }, fx)
	-- a violet haze round the card (the mock-up's radial night), then 44 single stars that
	-- fade in and twinkle one by one (Reveal)
	new("ImageLabel", { Name = "Haze", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1500, 1100), BackgroundTransparency = 1, Image = RADIAL, ImageColor3 = C("1D1636"), ImageTransparency = 1, ZIndex = 0 }, night)
	local stars = new("Frame", { Name = "Stars", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1400, 800), BackgroundTransparency = 1, ZIndex = 0 }, night)
	local seed = Random.new(11)
	for i = 1, 44 do
		local size = if i % 5 == 0 then 4 elseif i % 2 == 0 then 3 else 2
		local star = new("Frame", { Name = "Star" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(seed:NextInteger(10, 1390), seed:NextInteger(10, 790)), Size = UDim2.fromOffset(size, size), BackgroundColor3 = if i % 6 == 0 then C("FFE7A0") else WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 0 }, stars)
		corner(star, 2)
		star:SetAttribute("Phase", seed:NextNumber(0, math.pi * 2))
	end

	local glow = new("ImageLabel", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(260 + 200, 380 + 200), BackgroundTransparency = 1, Image = GLOW, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(48, 48, 80, 80), SliceScale = 1.6, ImageTransparency = 1, ZIndex = 0, Visible = false }, fx)
	new("UIGradient", { Name = "Colour", Rotation = 45 }, glow)

	local spot = new("ImageLabel", { Name = "Spot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 320), Size = UDim2.fromOffset(820, 980), BackgroundTransparency = 1, Image = RADIAL, ImageColor3 = PINK, ImageTransparency = 1, ZIndex = 0, Visible = false }, fx)
	spot:SetAttribute("Shown", 0.45)

	local hearts = new("Frame", { Name = "Hearts", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, ZIndex = 0, Visible = false }, fx)
	for i, spec in { { 420, 26 }, { 480, 18 }, { 545, 32 }, { 600, 20 }, { 690, 28 }, { 745, 18 }, { 810, 30 }, { 870, 22 }, { 515, 16 }, { 770, 24 } } do
		local h = text(hearts, "Heart" .. i, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(spec[1], 760), Size = UDim2.fromOffset(spec[2] * 2, spec[2] * 2), FontFace = HEAD, TextSize = spec[2] * 1.4, TextColor3 = PINK, TextXAlignment = Enum.TextXAlignment.Center, Text = "♥", ZIndex = 0 })
		new("UIStroke", { Color = INK, Thickness = 2 }, h)
		h:SetAttribute("Delay", (i - 1) * 0.09)
	end
	local leaks = new("Frame", { Name = "Leaks", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, ZIndex = 4, Visible = false }, top)
	for i, at in { { 512, 200 }, { 770, 270 }, { 600, 110 }, { 520, 400 }, { 760, 420 } } do
		local h = text(leaks, "Leak" .. i, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(at[1], at[2]), Size = UDim2.fromOffset(30, 30), FontFace = HEAD, TextSize = 22, TextColor3 = PINK, TextXAlignment = Enum.TextXAlignment.Center, Text = "♥", TextTransparency = 1, ZIndex = 4 })
		new("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 1 }, h)
		h:SetAttribute("Home", h.Position)
	end
	local scribble = new("ImageLabel", { Name = "Scribble", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 330), Size = UDim2.fromOffset(560, 205), Rotation = -6, BackgroundTransparency = 1, Image = SCRIBBLE, ZIndex = 9, Visible = false }, top)
	-- (drawn on by sliding a hard edge across: Offset.X from -1 to 1)
	new("UIGradient", { Name = "Reveal", Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.499, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1) }), Offset = Vector2.new(-1, 0) }, scribble)

	local charge = new("Frame", { Name = "Charge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(272, 392), BackgroundTransparency = 1, ZIndex = 5, Visible = false }, top)
	corner(charge, 22)
	stroke(charge, 7, WHITE, 1)
	text(top, "ChargeText", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 506), Size = UDim2.fromOffset(300, 22), FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold), TextSize = 16, TextColor3 = C("FF8A3D"), TextXAlignment = Enum.TextXAlignment.Center, Text = "●  ●  ●   READY", ZIndex = 5, Visible = false })

	local coins = new("Frame", { Name = "Coins", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, ZIndex = 8, Visible = false }, top)
	for k = 1, 16 do
		local coin = new("Frame", { Name = "Coin" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = WHITE, ZIndex = 8 }, coins)
		corner(coin, 13)
		stroke(coin, 3)
		new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C("FFF1B8")), ColorSequenceKeypoint.new(0.5, C("E8C15A")), ColorSequenceKeypoint.new(1, C("A87A1E")) }), Rotation = 45 }, coin)
		local inner = new("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, ZIndex = 8 }, coin)
		corner(inner, 6)
		stroke(inner, 2, C("A87A1E"), 0.2)
	end

	local shock = new("Frame", { Name = "Shock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, ZIndex = 9, Visible = false }, top)
	corner(shock, 300)
	stroke(shock, 10, WHITE, 0)
	-- ONE OF ONE, a label per letter so they can fly in wide apart and close up (the mock-up's
	-- letter-spacing): Reveal tweens Big.Letters.Layout.Padding and pops Big.Scale
	local big = new("Frame", { Name = "Big", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 58), Size = UDim2.fromOffset(1200, 56), BackgroundTransparency = 1, ZIndex = 10, Visible = false }, top)
	new("UIScale", { Name = "Scale" }, big)
	local letters = new("Frame", { Name = "Letters", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 }, big)
	new("UIListLayout", { Name = "Layout", FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, letters)
	local gold = ColorSequence.new({ ColorSequenceKeypoint.new(0, C("A87A1E")), ColorSequenceKeypoint.new(0.25, C("FFF1B8")), ColorSequenceKeypoint.new(0.5, C("E8C15A")), ColorSequenceKeypoint.new(0.75, C("FFF1B8")), ColorSequenceKeypoint.new(1, C("A87A1E")) })
	for i, ch in string.split("ONE OF ONE", "") do
		if ch == " " then
			new("Frame", { Name = "Gap" .. i, LayoutOrder = i, Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1 }, letters)
			continue
		end
		local width = TextService:GetTextSize(ch, 44, Enum.Font.GothamBlack, Vector2.new(200, 200)).X + 6
		local l = text(letters, "Letter" .. i, { LayoutOrder = i, Size = UDim2.fromOffset(width, 56), FontFace = HEAD, TextSize = 44, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Center, Text = ch, ZIndex = 10 })
		l:SetAttribute("FitTextSkip", true)
		new("UIStroke", { Color = INK, Thickness = 4 }, l)
		new("UIGradient", { Name = "Gold", Color = gold }, l)
	end

	local dust = new("Frame", { Name = "Dust", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(260, 380), BackgroundTransparency = 1, ZIndex = 9, Visible = false }, top)
	for i = 1, 10 do
		local mote = new("ImageLabel", { Name = "Mote" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((i - 0.5) / 10, 1), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = RADIAL, ImageColor3 = C("FFD36B"), ZIndex = 9 }, dust)
		mote:SetAttribute("Delay", (i * 0.37) % 3.2)
		local dot = new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C("FFE7A0"), BorderSizePixel = 0, ZIndex = 9 }, mote)
		corner(dot, 3)
	end

	-- the cracks of rainbow light through the card back (a 150×216 drawing, scaled up)
	local back = page:FindFirstChild("Holder") and page.Holder:FindFirstChild("Back")
	if back then
		local oldCracks = back:FindFirstChild("Cracks")
		if oldCracks then
			oldCracks:Destroy()
		end
		local cracks = new("Frame", { Name = "Cracks", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = back.ZIndex + 1, Visible = false }, back)
		local k = 260 / 150
		for _, path in {
			{ C("FFE07A"), { 75, 20, 68, 60, 82, 80, 70, 120 } },
			{ C("9ED8F5"), { 20, 120, 52, 108, 60, 132, 96, 126 } },
			{ PINK, { 120, 40, 104, 78, 126, 100, 112, 150, 130, 196 } },
			{ MINT, { 30, 190, 56, 170, 50, 150 } },
		} do
			local pts = path[2]
			for i = 1, #pts - 2, 2 do
				line(cracks, pts[i] * k, pts[i + 1] * k, pts[i + 2] * k, pts[i + 3] * k, path[1], 5)
			end
		end
		for _, bar in cracks:GetChildren() do
			bar.ZIndex = back.ZIndex + 1
		end
	end
	return fx, top
end

-- [[ 16–20 · The pull stage ]]

local function pull(root: Frame)
	local page = new("Frame", { Name = "Pull", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, root)
	-- tap anywhere on the stage (opens the sleeve, flips the card, moves on)
	local tap = new("TextButton", { Name = "Tap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, page)
	tap.Selectable = false

	-- (below Roblox's top bar buttons)
	text(page, "Group", { Position = UDim2.fromOffset(40, 60), Size = UDim2.fromOffset(500, 30), FontFace = HEAD, TextSize = 24, TextColor3 = CREAM, Text = "BTS" })
	soft(page, "Sub", { Position = UDim2.fromOffset(40, 94), Size = UDim2.fromOffset(600, 20), TextSize = 13, Text = "Group pack ×5 · pack 2 of 5 · card 3 of 5" })
	balance(page, 1232, 60, false)
	ghost(page, "Skip", "Skip", 14, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromOffset(1232, 688) })
	soft(page, "Hint", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 676), Size = UDim2.fromOffset(700, 22), TextXAlignment = Enum.TextXAlignment.Center, Text = "Tap for the next card · hold to go fast" })

	-- rare moment: rays turning behind the card, a ring, sparkles, the rarity's name
	local rays = new("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Visible = false }, page)
	for i = 1, 8 do
		local ray = new("Frame", { Name = "Ray" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1300, 64), Rotation = (i - 1) * 22.5, BackgroundColor3 = YELLOW, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, rays)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, ray)
	end
	local ring = new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(440, 440), BackgroundColor3 = PURPLE, BackgroundTransparency = 0.88, Visible = false }, page)
	corner(ring, 220)
	stroke(ring, 4, CREAM, 0.25)
	local sparkles = new("Frame", { Name = "Sparkles", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, page)
	for k, spec in { { 460, 150, YELLOW }, { 840, 130, CREAM }, { 880, 400, BLUE }, { 420, 440, PINK }, { 800, 500, YELLOW }, { 500, 80, MINT }, { 360, 280, CREAM }, { 930, 260, PINK } } do
		local s = new("Frame", { Name = "Sparkle" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(spec[1], spec[2]), Size = UDim2.fromOffset(14, 14), Rotation = 45, BackgroundColor3 = spec[3] }, sparkles)
		corner(s, 3)
		stroke(s, 2)
	end

	-- 16 · the sleeve
	local pack = sleeveArt(page, "Pack")
	pack.AnchorPoint = Vector2.new(0.5, 0.5)
	pack.Position = UDim2.fromOffset(640, 320)
	pack.Scale.Scale = 1.2
	pack.Visible = false
	-- the strip that tears off
	local strip = new("Frame", { Name = "Strip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 178), Size = UDim2.fromOffset(300, 24), BackgroundColor3 = PINK, Visible = false }, page)
	corner(strip, 6)
	stroke(strip, 4)

	-- 17 · the fan of backs (five: one pack)
	local fan = new("Frame", { Name = "Fan", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, page)
	for i = 1, 5 do
		local slot = new("Frame", { Name = "Back" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 320), Size = UDim2.fromOffset(260, 380), BackgroundTransparency = 1 }, fan)
		new("UIScale", { Name = "Scale", Scale = 0.72 }, slot)
		local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(9, 9), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, slot)
		corner(shadow, 18)
		cardBack(slot, "Art")
	end

	-- 18 · one card at a time: the card (back or face), the binder-page tag, the tray
	local holder = new("Frame", { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(260, 380), BackgroundTransparency = 1, Visible = false }, page)
	new("UIScale", { Name = "Scale" }, holder)
	local face = cardFace(holder, "Face")
	face.Size = UDim2.fromScale(1, 1)
	local back = cardBack(holder, "Back")
	back.Size = UDim2.fromScale(1, 1)
	back.Visible = false
	setZ(back, 3)

	local rarity = text(page, "Rarity", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(640, 64),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		BackgroundTransparency = 0,
		BackgroundColor3 = WHITE,
		FontFace = HEAD,
		TextSize = 26,
		Text = "LUCKY DRAW!",
		Rotation = -2,
		Visible = false,
		ZIndex = 4,
	})
	corner(rarity, 12)
	stroke(rarity, 4)
	pad(rarity, 18)
	new("UIGradient", { Name = "Foil", Enabled = false }, rarity)

	local tag = new("Frame", { Name = "Page", Position = UDim2.fromOffset(1000, 150), Size = UDim2.fromOffset(250, 66), BackgroundColor3 = CREAM, BackgroundTransparency = 0.92, Visible = false }, page)
	corner(tag, 14)
	stroke(tag, 2, CREAM, 0.8)
	local tsw = new("Frame", { Name = "Swatch", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = PINK }, tag)
	corner(tsw, 8)
	stroke(tsw, 3)
	text(tag, "Album", { Position = UDim2.fromOffset(54, 10), Size = UDim2.fromOffset(140, 18), TextSize = 14, TextColor3 = CREAM, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Love Yourself" })
	soft(tag, "Line", { Position = UDim2.fromOffset(54, 28), Size = UDim2.fromOffset(140, 16), TextSize = 12, Text = "binder page" })
	text(tag, "Count", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(60, 20), TextSize = 14, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Right, Text = "5 / 7" })
	local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 0, 8), BackgroundColor3 = CREAM, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, tag)
	corner(track, 4)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.7, 1), BackgroundColor3 = MINT, BorderSizePixel = 0 }, track)
	corner(fill, 4)

	local tray = new("Frame", { Name = "Tray", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 540), Size = UDim2.fromOffset(1000, 112), BackgroundTransparency = 1, Visible = false }, page)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tray)
	local mini = miniFace(tray, "Template", 70)
	mini.Visible = false
	local left = new("TextLabel", { Name = "Left", Size = UDim2.fromOffset(70, 102), BackgroundTransparency = 1, FontFace = BODY, TextSize = 14, TextColor3 = CREAM, TextTransparency = DIM, Text = "+6", LayoutOrder = 999 }, tray)
	corner(left, 10)
	stroke(left, 3, CREAM, 0.65)

	-- 20 · the summary
	local summary = new("Frame", { Name = "Summary", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 5 }, page)
	soft(summary, "Kicker", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 78), Size = UDim2.fromOffset(600, 16), TextSize = 12, FontFace = BODY, TextXAlignment = Enum.TextXAlignment.Center, Text = "P A C K   O P E N E D" })
	text(summary, "Best", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 96), Size = UDim2.fromOffset(900, 32), FontFace = HEAD, TextSize = 24, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Center, Text = "Best card: Jimin · Lucky Draw" })
	local chips = new("Frame", { Name = "Chips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 138), Size = UDim2.fromOffset(1100, 32), BackgroundTransparency = 1 }, summary)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	for i = 1, 3 do
		local c = text(chips, "Chip" .. i, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), BackgroundTransparency = 0.9, BackgroundColor3 = CREAM, TextColor3 = CREAM, TextSize = 13, Text = "", LayoutOrder = i })
		corner(c, 10)
		stroke(c, 2, CREAM, 0.75)
		pad(c, 12)
	end
	local cards = new("Frame", { Name = "Cards", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 196), Size = UDim2.fromOffset(1200, 390), BackgroundTransparency = 1 }, summary)
	local slot = new("Frame", { Name = "Template", Size = UDim2.fromOffset(150, 270), BackgroundTransparency = 1, Visible = false }, cards)
	new("UIScale", { Name = "Scale" }, slot)
	local sface = miniFace(slot, "Card", 150)
	sface.Position = UDim2.fromOffset(0, 0)
	ghost(slot, "Sell", "Sell 25", 13, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 236) })
	soft(slot, "Kept", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 240), Size = UDim2.fromOffset(150, 20), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Text = "your bias · kept", Visible = false })
	soft(summary, "SellAll", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(500, 628), Size = UDim2.fromOffset(300, 30), FontFace = BODY, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
	local sellAll = new("TextButton", { Name = "SellAllButton", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(500, 628), Size = UDim2.fromOffset(300, 30), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, summary)
	sellAll.ZIndex = 6
	button(summary, "Done", 610, 628, 150, 56, MINT, "DONE", 18)
	button(summary, "Again", 830, 628, 260, 56, YELLOW, "OPEN AGAIN", 17, COIN)
	setZ(summary, 5)

	-- confetti for rare pulls
	local confetti = new("Frame", { Name = "Confetti", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 300), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Visible = false, ZIndex = 8 }, page)
	local colours = { PINK, YELLOW, MINT, BLUE, PURPLE }
	for k = 1, 22 do
		local bit = new("Frame", { Name = "Bit" .. k, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 18), BackgroundColor3 = colours[(k - 1) % 5 + 1], ZIndex = 8 }, confetti)
		corner(bit, 3)
		stroke(bit, 2)
	end
	new("Frame", { Name = "Flash", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20 }, page)
	Build.RevealFx(page)
end

-- Adds just the Bias button to an Albums frame built before it existed (Edit mode, then save):
--   require(<this>).BiasButton(game.StarterGui.Interface.Frames)
function Build.BiasButton(frames: Instance)
	local cluster = frames.Albums.Shop.Controls
	local old = cluster:FindFirstChild("Bias")
	if old then
		old:Destroy()
	end
	cluster.Size = UDim2.fromOffset(480, 38)
	return biasButton(cluster)
end

function Build.Build(frames: Instance): Frame
	local old = frames:FindFirstChild("Albums")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Albums", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 1 })
	backdrop(root)
	bias(root)
	shop(root)
	pull(root)
	local toast = text(root, "Toast", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 20), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = CREAM, TextSize = 16, Text = "", Visible = false, ZIndex = 30 })
	corner(toast, 10)
	pad(toast, 16)
	stroke(toast, 2, CREAM, 0.6)
	root.Parent = frames
	return root
end

return Build
