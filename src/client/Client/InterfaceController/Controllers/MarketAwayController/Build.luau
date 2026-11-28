--| Market away pop-up UI builder
-- Builds Interface.Frames.MarketAway from the design board "67b · Market · Away pop-up + ended
-- toast": a scrim and one card: WHILE YOU WERE AWAY and its line, up to 3 cards (Slot1–3: the
-- card, its Name and a SOLD · +coins / ENDED · in binder Tag) and a "+N more" line, the yellow
-- Collect bar (coin + "12,240 to collect"), then SEE MY LISTINGS / COLLECT ALL.
-- Run once in Edit (an existing one is replaced):
--   local m = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("MarketAwayController", true).Build
--   local c = m:Clone(); c.Parent = m.Parent; require(c).Build(game.StarterGui.Interface.Frames); c:Destroy()
-- MarketAwayController finds everything by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local Photocard = require(ReplicatedStorage.Modules.UI.Photocard)
local CardDecor = require(ReplicatedStorage.Modules.UI.CardDecor)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local PINK = C("FF9EC4")
local MUTED = C("6B6480")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Build = {}
Build.SLOTS = 3

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
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a chunky button with a hard shadow (<name>Shadow); centre-anchored for ButtonScale
local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string): TextButton
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + 3, y + 3), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, 12)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2, y + h / 2), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, AutoButtonColor = false, FontFace = HEAD, TextSize = 16, TextColor3 = INK, Text = label }, parent)
	corner(b, 12)
	stroke(b, 3)
	return b
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("MarketAway")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "MarketAway", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", { Name = "Scrim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundColor3 = INK, BackgroundTransparency = 0.4, BorderSizePixel = 0 }, root)
	scrim.Active = true

	local W, H = 620, 440
	local x, y = 640 - W / 2, 360 - H / 2
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(x + 8, y + 8), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK, BorderSizePixel = 0 }, root)
	corner(shadow, 24)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(W, H), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, root)
	corner(panel, 22)
	stroke(panel, 4)

	text(panel, "Title", { Position = UDim2.fromOffset(0, 24), Size = UDim2.fromOffset(W, 32), TextSize = 26, Text = "WHILE YOU WERE AWAY" })
	text(panel, "Sub", { Position = UDim2.fromOffset(0, 56), Size = UDim2.fromOffset(W, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "Your Market listings since you last played" })

	-- up to 3 cards, centred by the controller (each slot 114 wide)
	local cards = new("Frame", { Name = "Cards", Position = UDim2.fromOffset(0, 88), Size = UDim2.fromOffset(W, 186), BackgroundTransparency = 1 }, panel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, cards)
	for i = 1, Build.SLOTS do
		local slot = new("Frame", { Name = `Slot{i}`, LayoutOrder = i, Size = UDim2.fromOffset(124, 186), BackgroundTransparency = 1 }, cards)
		local pc = Photocard.Build(slot, "Card", 100, 134)
		pc.Position = UDim2.fromOffset(12, 0)
		pc:SetAttribute("CardFx", "Tile")
		CardDecor.Build(pc, pc.Face, pc.Face.Photo)
		text(slot, "Name", { Position = UDim2.fromOffset(0, 138), Size = UDim2.fromOffset(124, 18), TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Member" })
		local t = text(slot, "Tag", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(62, 160), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = PINK, FontFace = BODY, TextSize = 12, Text = "SOLD · +5,850" })
		corner(t, 8)
		stroke(t, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, t)
	end
	text(panel, "More", { Position = UDim2.fromOffset(0, 276), Size = UDim2.fromOffset(W, 16), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "+2 more in My listings", Visible = false })

	-- the coins waiting
	local bar = new("Frame", { Name = "Collect", Position = UDim2.fromOffset(28, 298), Size = UDim2.fromOffset(W - 56, 52), BackgroundColor3 = YELLOW }, panel)
	corner(bar, 14)
	stroke(bar, 3)
	local inner = new("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, bar)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	new("ImageLabel", { Name = "Coin", LayoutOrder = 1, Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1, Image = Currencies.Coins.Icon, ScaleType = Enum.ScaleType.Fit }, inner)
	text(inner, "Amount", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextSize = 22, Text = "12,240 to collect" })

	local bw = (W - 56 - 14) / 2
	button(panel, "SeeListings", 28, H - 28 - 52, bw, 52, WHITE, "SEE MY LISTINGS")
	button(panel, "CollectAll", 28 + bw + 14, H - 28 - 52, bw, 52, MINT, "COLLECT ALL")

	root.Parent = frames
	return root
end

return Build
