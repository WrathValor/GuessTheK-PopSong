--| Photocard
-- A K-POPPED! photocard at any size, for screens other than the binder and the packs (the
-- profile showcase and its card picker; the binder and packs have their own builders).
--   Photocard.Build(parent, name, w, h, rotation?)   -- in Studio, from a screen's Build module
--   Photocard.Paint(card, cardId, copies, serial?, date?)   -- at runtime; hides the card for a bad id
-- The card is a holder (transparent) with Glow (Gold / Rainbow halo), Shadow and Face. Face
-- has the rarity's colour and Foil gradient; Photo (Art, Silhouette, Shine, Stamp, Serial,
-- Signature); Member; Level (GOLD / RAINBOW chip). The rarity looks are the same ladder as the
-- binder and packs (design board "5 · Rarity ladder").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Albums = require(ReplicatedStorage.Modules.Library.Albums)
local CardDecor = require(ReplicatedStorage.Modules.UI.CardDecor)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local GOLD = C("F2C94C")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local HOLO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("C9D3E3")),
	ColorSequenceKeypoint.new(0.3, C("EEF3FA")),
	ColorSequenceKeypoint.new(0.5, C("9ED8F5")),
	ColorSequenceKeypoint.new(0.7, C("F6F8FC")),
	ColorSequenceKeypoint.new(1, C("AEB9CC")),
})
local GLITTER = ColorSequence.new(C("FF9EC4"), C("B9A6FF"))
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FF5A4E")),
	ColorSequenceKeypoint.new(0.2, C("FFE07A")),
	ColorSequenceKeypoint.new(0.4, C("A7E9B8")),
	ColorSequenceKeypoint.new(0.6, C("9ED8F5")),
	ColorSequenceKeypoint.new(0.8, C("B9A6FF")),
	ColorSequenceKeypoint.new(1, C("FF9EC4")),
})

local STYLE = {
	standard = { Colour = WHITE },
	selca = { Colour = C("FFD2E5") },
	store = { Colour = MINT, Stamp = "STORE" },
	luckydraw = { Colour = WHITE, Foil = HOLO, Shine = true, Stamp = "LUCKY DRAW" },
	fansign = { Colour = WHITE, Foil = GLITTER, Shine = true, Stamp = "♡ FANSIGN" },
	polaroid = { Colour = CREAM, Signature = true },
	oneofone = { Colour = WHITE, Foil = RAINBOW, Shine = true },
}

local Photocard = {}

Photocard.RAINBOW = RAINBOW

-- [[ Build (Studio) ]]

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
local function label(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
local function chip(parent: Instance, name: string, size: number, props: { [string]: any }): TextLabel
	local base = { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size + 6), BackgroundTransparency = 0, TextSize = size, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None }
	for k, v in props do
		base[k] = v
	end
	local c = label(parent, name, base)
	corner(c, math.max(3, math.floor(size / 2)))
	stroke(c, 1.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, c)
	return c
end

function Photocard.Build(parent: Instance, name: string, w: number, h: number, rotation: number?): Frame
	local k = w / 120 -- sizes below are for a 120-wide card
	local function n(v: number): number
		return math.max(1, math.floor(v * k + 0.5))
	end
	local root = new("Frame", { Name = name, Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1, Rotation = rotation or 0 }, parent)
	local glow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, n(10), 1, n(10)), BackgroundColor3 = GOLD, Visible = false }, root)
	corner(glow, n(14))
	stroke(glow, n(3))
	new("UIGradient", { Name = "Rainbow", Color = RAINBOW, Rotation = 45, Enabled = false }, glow)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(n(4), n(4)), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK }, root)
	corner(shadow, n(10))
	local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, root)
	corner(face, n(10))
	stroke(face, math.max(2, n(3)))
	new("UIGradient", { Name = "Foil", Rotation = 45, Enabled = false }, face)

	local pad, bottom = n(6), n(22)
	local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(pad, pad), Size = UDim2.new(1, -pad * 2, 1, -pad - bottom), BackgroundColor3 = C("FFD2E5"), ClipsDescendants = true }, face)
	corner(photo, n(7))
	stroke(photo, math.max(1.5, n(2)))
	label(photo, "Silhouette", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = n(30), TextColor3 = INK, TextTransparency = 0.75, TextXAlignment = Enum.TextXAlignment.Center, Text = "?" })
	local art = new("ImageLabel", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, Image = "" }, photo)
	corner(art, n(7))
	new("Frame", { Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.new(1.6, 0, 0, n(10)), Rotation = -24, BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false }, photo)
	chip(photo, "Stamp", n(8), { Position = UDim2.fromOffset(n(3), n(3)), BackgroundColor3 = MINT, Text = "STORE", Rotation = -8, Visible = false })
	chip(photo, "Serial", n(9), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -n(3), 0, n(3)), BackgroundColor3 = INK, TextColor3 = YELLOW, FontFace = HEAD, Text = "#4", Visible = false })
	label(photo, "Signature", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, n(6), 1, -n(4)), Size = UDim2.new(1, -n(12), 0, n(20)), FontFace = HEAD, TextSize = n(15), TextColor3 = C("5B45D6"), Rotation = -6, Text = "", Visible = false })

	label(face, "Member", { Position = UDim2.new(0, pad, 1, -bottom + n(3)), Size = UDim2.new(1, -pad * 2 - n(40), 0, n(16)), FontFace = HEAD, TextSize = n(11), Text = "MEMBER" })
	local level = chip(face, "Level", n(8), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -pad, 1, -bottom + n(4)), BackgroundColor3 = GOLD, Text = "GOLD", Visible = false })
	new("UIGradient", { Name = "Rainbow", Color = RAINBOW, Enabled = false }, level)
	CardDecor.Build(root, face, photo) -- the v2 rarity looks + level stars
	return root
end

-- [[ Paint (runtime) ]]

function Photocard.Paint(card: Instance, cardId: string?, copies: number, serial: number?, date: number?): any
	local info = cardId and cardId ~= "" and Albums.Card(cardId)
	if not info then
		card.Visible = false
		return nil
	end
	local rarity, album, member = info.Rarity, info.Album, info.Member
	local style = STYLE[rarity.Key] or STYLE.standard
	local face = card.Face
	face.BackgroundColor3 = style.Colour
	face.Foil.Enabled = style.Foil ~= nil
	if style.Foil then
		face.Foil.Color = style.Foil
	end
	local photo = face.Photo
	local ok, colour = pcall(Color3.fromHex, album.Colour or "FFD2E5")
	photo.BackgroundColor3 = if ok then colour else C("FFD2E5")
	photo.Art.Image = member.Art or ""
	photo.Silhouette.Visible = (member.Art or "") == ""
	photo.Shine.Visible = style.Shine == true
	photo.Stamp.Visible = style.Stamp ~= nil
	photo.Stamp.Text = style.Stamp or ""
	photo.Stamp.BackgroundColor3 = if rarity.Key == "store" then MINT else CREAM
	photo.Signature.Visible = style.Signature == true
	photo.Signature.Text = `{member.Name} ♡`
	local serialText = Albums.SerialText(info.Id, serial)
	photo.Serial.Visible = serialText ~= nil
	photo.Serial.Text = serialText or ""
	face.Member.Text = string.upper(member.Name)
	local level = Albums.Level(copies) or "Normal"
	face.Level.Visible = level ~= "Normal"
	face.Level.Text = string.upper(level)
	face.Level.BackgroundColor3 = if level == "Gold" then GOLD else WHITE
	face.Level.Rainbow.Enabled = level == "Rainbow"
	card.Glow.Visible = level ~= "Normal"
	card.Glow.BackgroundColor3 = if level == "Gold" then GOLD else WHITE
	card.Glow.Rainbow.Enabled = level == "Rainbow"
	CardDecor.Paint(card, face, info.Id, copies, { Serial = serial, Date = date }) -- the v2 looks over the base
	card.Visible = true
	return info
end

return Photocard
