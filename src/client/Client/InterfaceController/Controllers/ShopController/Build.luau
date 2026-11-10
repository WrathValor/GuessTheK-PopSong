--| Shop UI builder
-- Builds Interface.Frames.Shop from the "Shop A" design boards (tabs in the header, pages
-- that never scroll). Run once in Studio (it replaces any existing Shop frame, keeping the old
-- one as ServerStorage.Shop_Legacy); after that the frame lives in Studio and can be restyled
-- by hand. ShopController only fills it in, finding everything by name.

local RollPage = require(script.Parent.RollPage)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local LINE = C("CFC5B3")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Build = {}

Build.ICONS = {
	Coin = require(game:GetService("ReplicatedStorage").Constants.Currencies).Coins.Icon,
	CoinStack = "rbxassetid://83386580979392",
	Robux = "rbxassetid://83637405007021",
	Crown = "rbxassetid://131353192492921",
	Note = "rbxassetid://139417424771393",
	Clock = "rbxassetid://82578247239388",
	Close = "rbxassetid://118345756178429",
}
local ICONS = Build.ICONS

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
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function pad(p: Instance, l: number, r: number?, t: number?, b: number?)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r or l),
		PaddingTop = UDim.new(0, t or 0),
		PaddingBottom = UDim.new(0, b or 0),
	}, p)
end

local function row(p: Instance, gap: number, align: Enum.HorizontalAlignment?)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function icon(parent: Instance, name: string, image: string, size: number, order: number?): ImageLabel
	return new("ImageLabel", {
		Name = name,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Image = image,
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = order or 0,
	}, parent)
end

-- A face with a hard ink shadow: both are children of `parent`, the shadow named <name>Shadow.
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number)
	if drop > 0 then
		local shadow = new("Frame", {
			Name = name .. "Shadow",
			Position = pos + UDim2.fromOffset(drop, drop),
			Size = size,
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
		}, parent)
		corner(shadow, radius)
	end
	local face = new("Frame", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
	}, parent)
	corner(face, radius)
	if line > 0 then
		stroke(face, line)
	end
	return face
end

-- Green "price" button: [icon] 1,350  (icon = Coin or Robux)
local function priceButton(parent: Instance, name: string, pos: UDim2, size: UDim2, iconImage: string, textSize: number, colour: Color3?, line: number?, drop: number?)
	if (drop or 0) > 0 then
		local shadow = new("Frame", {
			Name = name .. "Shadow",
			Position = pos + UDim2.fromOffset(drop :: number, drop :: number),
			Size = size,
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
		}, parent)
		corner(shadow, 10)
	end
	local b = new("TextButton", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = colour or MINT,
		Text = "",
		AutoButtonColor = false,
	}, parent)
	corner(b, 10)
	stroke(b, line or 2)
	row(b, 6, Enum.HorizontalAlignment.Center)
	icon(b, "Icon", iconImage, textSize + 5, 1)
	text(b, "Old", {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, textSize),
		FontFace = BODY_BOLD,
		TextSize = textSize - 4,
		TextTransparency = 0.4,
		TextTruncate = Enum.TextTruncate.None,
		Visible = false,
		Text = "",
	})
	text(b, "Label", {
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, textSize + 4),
		FontFace = HEAD,
		TextSize = textSize,
		TextTruncate = Enum.TextTruncate.None,
		Text = "0",
	})
	return b
end

-- "—— Title [chip] ——" centred section heading
local function titleRow(parent: Instance, y: number, title: string, chip: string?)
	local f = new("Frame", {
		Name = "TitleRow",
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
	}, parent)
	row(f, 10, Enum.HorizontalAlignment.Center)
	local function bar(order)
		local l = new("Frame", { Name = "Line", Size = UDim2.fromOffset(40, 3), BackgroundColor3 = INK, BorderSizePixel = 0, LayoutOrder = order }, f)
		corner(l, 2)
	end
	bar(1)
	text(f, "Title", {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		FontFace = HEAD,
		TextSize = 20,
		TextTruncate = Enum.TextTruncate.None,
		Text = title,
	})
	if chip then
		local c = text(f, "Chip", {
			LayoutOrder = 3,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = YELLOW,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.None,
			Text = chip,
		})
		corner(c, 8)
		stroke(c, 2)
		pad(c, 8)
	end
	bar(4)
	return f
end

-- [[ Set card: art (stage, pad, mic, rarity), name, chips, action button, NEW badge ]]
local function setCard(parent: Instance, name: string, pos: UDim2, size: UDim2, compact: boolean)
	local holder = new("Frame", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundTransparency = 1,
	}, parent)
	local drop = if compact then 4 else 5
	local face = card(holder, "Face", UDim2.new(), UDim2.fromScale(1, 1), WHITE, if compact then 14 else 16, drop, 3)
	local p = if compact then 8 else 10
	local buttonH = if compact then 34 else 40
	local nameH = if compact then 18 else 22
	local chipsH = if compact then 0 else 18
	local gap = if compact then 6 else 8
	local bottom = p + buttonH + gap + chipsH + (if compact then 0 else gap) + nameH + gap

	local art = new("Frame", {
		Name = "Art",
		Position = UDim2.fromOffset(p, p),
		Size = UDim2.new(1, -2 * p, 1, -p - bottom),
		BackgroundColor3 = C("FFE4EF"),
		ClipsDescendants = true,
	}, face)
	corner(art, if compact then 8 else 10)
	stroke(art, 2)
	local stage = new("Frame", { Name = "Stage", Position = UDim2.fromScale(0.08, 0.22), Size = UDim2.fromScale(0.64, 0.38), BackgroundColor3 = C("FF9EC4") }, art)
	corner(stage, UDim.new(0.3, 0))
	stroke(stage, 3)
	local plat = new("Frame", { Name = "Platform", Position = UDim2.fromScale(0.16, 0.52), Size = UDim2.fromScale(0.48, 0.17), BackgroundColor3 = WHITE }, art)
	corner(plat, UDim.new(0.5, 0))
	stroke(plat, 3)
	local base = new("Frame", { Name = "MicBase", Position = UDim2.fromScale(0.76, 0.74), Size = UDim2.fromScale(0.16, 0.06), BackgroundColor3 = C("CFC8E6") }, art)
	corner(base, UDim.new(0.5, 0))
	stroke(base, 2)
	new("Frame", { Name = "MicPole", Position = UDim2.fromScale(0.83, 0.40), Size = UDim2.new(0, 4, 0.36, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, art)
	local head = new("Frame", { Name = "Mic", Position = UDim2.fromScale(0.78, 0.33), Size = UDim2.fromScale(0.15, 0.10), BackgroundColor3 = WHITE, Rotation = -28 }, art)
	corner(head, 8)
	stroke(head, 3)
	local rarity = text(art, "Rarity", {
		Position = UDim2.fromOffset(7, 7),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = MINT,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.None,
		Text = "Uncommon",
		ZIndex = 2,
	})
	corner(rarity, 6)
	stroke(rarity, 2)
	pad(rarity, 6)

	text(face, "SetName", {
		Position = UDim2.new(0, p, 1, -bottom + gap),
		Size = UDim2.new(1, -2 * p, 0, nameH),
		FontFace = if compact then BODY else HEAD,
		TextSize = if compact then 15 else 17,
		Text = "Set name",
	})
	if not compact then
		local chips = new("Frame", {
			Name = "Chips",
			Position = UDim2.new(0, p, 1, -p - buttonH - gap - chipsH),
			Size = UDim2.new(1, -2 * p, 0, chipsH),
			BackgroundTransparency = 1,
		}, face)
		row(chips, 5)
		for i, label in { "Stage skin", "Platform", "Mic" } do
			local c = text(chips, "Chip" .. i, {
				LayoutOrder = i,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 18),
				TextSize = 11,
				TextColor3 = C("4A4460"),
				TextTruncate = Enum.TextTruncate.None,
				Text = label,
			})
			corner(c, 7)
			stroke(c, 2, LINE)
			pad(c, 6)
		end
	end
	priceButton(face, "Action", UDim2.new(0, p, 1, -p - buttonH), UDim2.new(1, -2 * p, 0, buttonH), ICONS.Coin, if compact then 13 else 15)

	local badge = text(holder, "NewBadge", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -12),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundTransparency = 0,
		BackgroundColor3 = RED,
		FontFace = HEAD,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.None,
		Rotation = 7,
		Text = "NEW",
		Visible = false,
		ZIndex = 5,
	})
	corner(badge, 9)
	stroke(badge, 3)
	pad(badge, 8)
	return holder
end

-- --------------------------------- Pages ---------------------------------- --
local PAGE_W, PAGE_H = 956, 531

local function featuredPage(pages: Instance)
	local page = new("Frame", { Name = "Featured", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = true }, pages)

	-- featured set (dark card)
	local fw = 580
	local f = card(page, "FeaturedSet", UDim2.new(), UDim2.fromOffset(fw, 150), C("2B2346"), 16, 5, 3)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(18, 24), Size = UDim2.fromOffset(130, 96), BackgroundColor3 = C("3B2F63") }, f)
	corner(art, 10)
	stroke(art, 2, WHITE)
	local st = new("Frame", { Name = "Stage", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(98, 44), BackgroundColor3 = RED }, art)
	corner(st, 8)
	stroke(st, 2)
	local pl = new("Frame", { Name = "Platform", Position = UDim2.fromOffset(34, 54), Size = UDim2.fromOffset(62, 24), BackgroundColor3 = YELLOW }, art)
	corner(pl, UDim.new(0.5, 0))
	stroke(pl, 2)
	local tag = text(f, "Tag", {
		Position = UDim2.fromOffset(166, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.None,
		Text = "FEATURED · LEAVES IN 6D",
	})
	corner(tag, 8)
	stroke(tag, 2)
	pad(tag, 9)
	text(f, "SetName", { Position = UDim2.fromOffset(166, 50), Size = UDim2.fromOffset(270, 32), FontFace = HEAD, TextSize = 24, TextColor3 = WHITE, Text = "Encore Stage Set" })
	text(f, "Blurb", {
		Position = UDim2.fromOffset(166, 84),
		Size = UDim2.fromOffset(270, 50), -- 2 lines with room to spare on phones
		FontFace = BODY_BOLD,
		TextSize = 13,
		TextColor3 = C("D9D3F0"),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.None,
		Text = "Legendary stage skin, gold spotlight platform + mic",
	})
	priceButton(f, "Action", UDim2.fromOffset(fw - 18 - 130, 49), UDim2.fromOffset(124, 52), ICONS.Coin, 18, MINT, 3, 4)
	local newb = text(page, "FeaturedNew", {
		Position = UDim2.fromOffset(fw - 90, -14),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		FontFace = HEAD,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.None,
		Rotation = 6,
		Text = "NEW!",
		ZIndex = 5,
	})
	corner(newb, 10)
	stroke(newb, 3)
	pad(newb, 10)

	-- VIP pass
	local vx = fw + 14
	local vip = card(page, "Vip", UDim2.fromOffset(vx, 0), UDim2.fromOffset(PAGE_W - vx, 150), YELLOW, 16, 5, 3)
	local circle = new("Frame", { Name = "IconCircle", Position = UDim2.fromOffset(18, 22), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = WHITE }, vip)
	corner(circle, UDim.new(0.5, 0))
	stroke(circle, 3)
	local crown = icon(circle, "Icon", ICONS.Crown, 30)
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.Position = UDim2.fromScale(0.5, 0.5)
	text(vip, "PassName", { Position = UDim2.fromOffset(82, 32), Size = UDim2.fromOffset(140, 32), FontFace = HEAD, TextSize = 22, Text = "VIP Pass" })
	priceButton(vip, "Action", UDim2.fromOffset(PAGE_W - vx - 18 - 96, 26), UDim2.fromOffset(96, 44), ICONS.Robux, 16, MINT, 3, 3)
	local perks = new("Frame", { Name = "Perks", Position = UDim2.fromOffset(18, 92), Size = UDim2.new(1, -36, 0, 22), BackgroundTransparency = 1 }, vip)
	row(perks, 4)
	for i = 1, 3 do
		local c = text(perks, "Perk" .. i, {
			LayoutOrder = i,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.None,
			Text = "Perk",
		})
		corner(c, 8)
		stroke(c, 2)
		pad(c, 6)
	end

	titleRow(page, 164, "Sets", "Restocks in 1h 42m")
	local cw = (PAGE_W - 3 * 14) / 4
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(0, 206), Size = UDim2.fromOffset(PAGE_W, PAGE_H - 206), BackgroundTransparency = 1 }, page)
	for i = 1, 4 do
		setCard(grid, "Card" .. i, UDim2.fromOffset((i - 1) * (cw + 14), 0), UDim2.new(0, cw, 1, -6), true)
	end
end

local function setsPage(pages: Instance)
	local page = new("Frame", { Name = "Sets", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, pages)
	titleRow(page, 0, "Stage sets", "Restocks in 1h 42m")
	local cw = (PAGE_W - 3 * 16) / 4
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(PAGE_W, PAGE_H - 42 - 54 - 18), BackgroundTransparency = 1 }, page)
	for i = 1, 4 do
		setCard(grid, "Card" .. i, UDim2.fromOffset((i - 1) * (cw + 16), 0), UDim2.new(0, cw, 1, -6), false)
	end
	-- footer: restock info + VIP note
	local foot = card(page, "Footer", UDim2.fromOffset(0, PAGE_H - 54 - 4), UDim2.fromOffset(PAGE_W - 4, 54), WHITE, 14, 4, 3)
	pad(foot, 16)
	row(foot, 12)
	icon(foot, "Clock", ICONS.Clock, 20, 1)
	text(foot, "Headline", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextTruncate = Enum.TextTruncate.None, Text = "4 new sets every 2 hours" })
	text(foot, "Sub", {
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		FontFace = BODY_BOLD,
		TextSize = 13,
		TextColor3 = MUTED,
		TextTruncate = Enum.TextTruncate.None,
		Text = "Every set comes with a stage skin, a spot platform and a mic.",
	})
end

-- [[ Item card (Items tab): art (stage + pad, or a mic stand), rarity, name, price ]]
local function itemCard(parent: Instance, name: string, pos: UDim2, size: UDim2, kind: string)
	local holder = new("Frame", { Name = name, Position = pos, Size = size, BackgroundTransparency = 1 }, parent)
	local face = card(holder, "Face", UDim2.new(), UDim2.fromScale(1, 1), WHITE, 14, 4, 3)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -8 - 6 - 18 - 6 - 34 - 8), BackgroundColor3 = C("F3F7FF"), ClipsDescendants = true }, face)
	corner(art, 8)
	stroke(art, 2)
	if kind == "Stage" then
		local stage = new("Frame", { Name = "Stage", Position = UDim2.fromScale(0.18, 0.14), Size = UDim2.fromScale(0.64, 0.44), BackgroundColor3 = C("9ED8F5") }, art)
		corner(stage, UDim.new(0.3, 0))
		stroke(stage, 3)
		local plat = new("Frame", { Name = "Platform", Position = UDim2.fromScale(0.26, 0.5), Size = UDim2.fromScale(0.48, 0.22), BackgroundColor3 = WHITE }, art)
		corner(plat, UDim.new(0.5, 0))
		stroke(plat, 3)
	else
		local base = new("Frame", { Name = "MicBase", Position = UDim2.fromScale(0.38, 0.82), Size = UDim2.fromScale(0.24, 0.09), BackgroundColor3 = C("CFC8E6") }, art)
		corner(base, UDim.new(0.5, 0))
		stroke(base, 2)
		new("Frame", { Name = "MicPole", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.new(0, 4, 0.54, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, art)
		local head = new("Frame", { Name = "Mic", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromScale(0.16, 0.2), BackgroundColor3 = WHITE, Rotation = -24 }, art)
		head.SizeConstraint = Enum.SizeConstraint.RelativeYY
		head.Size = UDim2.fromScale(0.24, 0.24)
		corner(head, 9)
		stroke(head, 3)
	end
	local rarity = text(art, "Rarity", {
		Position = UDim2.fromOffset(5, 5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 16),
		BackgroundTransparency = 0,
		BackgroundColor3 = MINT,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.None,
		Text = "Common",
		ZIndex = 2,
	})
	corner(rarity, 6)
	stroke(rarity, 2)
	pad(rarity, 5)
	text(face, "ItemName", { Position = UDim2.new(0, 8, 1, -8 - 34 - 6 - 18), Size = UDim2.new(1, -16, 0, 18), Text = "Item" })
	local action = priceButton(face, "Action", UDim2.new(0, 8, 1, -8 - 34), UDim2.new(1, -16, 0, 34), ICONS.Coin, 13)
	action:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 9)
	return holder
end

-- Items tab: 4 rotating stages + 4 rotating mic stands. Set pieces are never sold here.
local function itemsPage(pages: Instance)
	local page = new("Frame", { Name = "Items", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, pages)
	local cw = (PAGE_W - 3 * 14) / 4
	-- two header rows (26 + 8 gap each) and a gap between the sections; the cards take the rest
	local gridH = math.floor((PAGE_H - 2 * 34 - 8) / 2)
	local function section(kind: string, y: number, title: string, sub: string)
		local head = new("Frame", { Name = kind .. "Row", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, page)
		row(head, 10)
		text(head, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), FontFace = HEAD, TextSize = 19, TextTruncate = Enum.TextTruncate.None, Text = title })
		text(head, "Sub", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = sub })
		local grid = new("Frame", { Name = kind .. "Grid", Position = UDim2.fromOffset(0, y + 34), Size = UDim2.fromOffset(PAGE_W, gridH), BackgroundTransparency = 1 }, page)
		for i = 1, 4 do
			itemCard(grid, "Card" .. i, UDim2.fromOffset((i - 1) * (cw + 14), 0), UDim2.new(0, cw - 4, 1, -4), kind)
		end
	end
	section("Stage", 0, "Stages", "Platform + stage skin for your spot")
	local micY = 34 + gridH + 8
	section("Mic", micY, "Mic stands", "Stands at the front of your spot")
	local chip = text(page, "Chip", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 3),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.None,
		Text = "Restocks in 1h 42m",
	})
	corner(chip, 8)
	stroke(chip, 2)
	pad(chip, 8)
	-- sits at the right end of the "Mic stands" row (like the restock chip on "Stages")
	text(page, "Footnote", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, micY + 4),
		Size = UDim2.fromOffset(560, 18),
		FontFace = BODY_BOLD,
		TextSize = 12,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "Set pieces are never sold here. Buy the set to unlock them, then mix them with anything.",
	})
	return page
end

-- Adds the Items tab + page to an existing Shop frame (so hand edits to the rest of the shop
-- are kept). Safe to run twice.
function Build.AddItemsAndGroups(shop: Instance)
	local panel = shop.Panel
	local tabs = panel.Header.Tabs
	tabs.Size = UDim2.fromOffset(640, 68)
	if not tabs:FindFirstChild("Items") then
		local order = { Featured = 1, Sets = 2, Items = 3, Packs = 4, Coins = 5 }
		local items = tabs.Sets:Clone()
		items.Name = "Items"
		items.Parent = tabs
		items.Button.Label.Text = "Items"
		items.Button.Dot.BackgroundColor3 = C("FF9EC4")
		items.Size = UDim2.fromOffset(80, 43)
		items.Button.Size = UDim2.fromOffset(77, 40)
		items.Button.Position = UDim2.fromOffset(38, 20)
		items.Button:SetAttribute("BaseY", nil)
		for name, n in order do
			tabs[name].LayoutOrder = n
		end
	end
	local pages = panel.Pages
	if not pages:FindFirstChild("Items") then
		local page = itemsPage(pages)
		require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(page)
	end
end

-- [[ UGC tab: the group's own avatar items, for Robux (ShopController/Emotes fills it) ]]

-- small chip label: [DANCE]
local function chip(parent: Instance, name: string, pos: UDim2, colour: Color3, label: string)
	local c = text(parent, name, {
		Position = pos,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 16),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
		ZIndex = 6,
	})
	corner(c, 6)
	stroke(c, 2)
	pad(c, 5)
	return c
end

local function ugcArt(parent: Instance, pos: UDim2, size: UDim2)
	local art = new("Frame", { Name = "Art", Position = pos, Size = size, BackgroundColor3 = C("4A3F78"), ClipsDescendants = true }, parent)
	corner(art, 8)
	stroke(art, 2)
	chip(art, "Kind", UDim2.fromOffset(6, 6), YELLOW, "DANCE")
	return art
end

-- one grid card: art (click to preview), name, artist, Robux button
local function ugcCard(parent: Instance, name: string, pos: UDim2, size: UDim2)
	local holder = new("Frame", { Name = name, Position = pos, Size = size, BackgroundTransparency = 1 }, parent)
	local face = card(holder, "Face", UDim2.new(), UDim2.fromScale(1, 1), WHITE, 14, 4, 3)
	local art = ugcArt(face, UDim2.fromOffset(8, 8), UDim2.new(1, -16, 1, -8 - 6 - 18 - 14 - 6 - 30 - 8))
	new("TextButton", { Name = "Select", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, art)
	text(face, "ItemName", { Position = UDim2.new(0, 8, 1, -8 - 30 - 6 - 14 - 18), Size = UDim2.new(1, -16, 0, 18), Text = "Item" })
	text(face, "Sub", { Position = UDim2.new(0, 8, 1, -8 - 30 - 6 - 14), Size = UDim2.new(1, -16, 0, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "Artist" })
	local action = priceButton(face, "Action", UDim2.new(0, 8, 1, -8 - 30), UDim2.new(1, -16, 0, 30), ICONS.Robux, 13)
	action:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 9)
	return holder
end

local EMOTE_FILTERS = { "All", "Dances", "Accessories" }

local function emotesPage(pages: Instance)
	local page = new("Frame", { Name = "UGC", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, pages)

	-- left: the selected item, big, on your own avatar
	local pw = 296
	local preview = card(page, "Preview", UDim2.new(), UDim2.fromOffset(pw, PAGE_H - 5), WHITE, 16, 5, 3)
	local bottom = 10 + 52 + 12 + 16 + 4 + 28 + 8
	local art = ugcArt(preview, UDim2.fromOffset(10, 10), UDim2.new(1, -20, 1, -10 - bottom))
	art.Kind.Position = UDim2.fromOffset(8, 8)
	-- drag catcher: CosmeticView.EnableSpin turns the model when you drag here
	new("TextButton", { Name = "Spin", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, art)
	local hint = text(art, "Hint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0.08,
		BackgroundColor3 = WHITE,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.None,
		Text = "Drag to spin",
		ZIndex = 6,
	})
	corner(hint, 8)
	stroke(hint, 2)
	pad(hint, 10)
	text(preview, "ItemName", { Position = UDim2.new(0, 14, 1, -bottom + 8), Size = UDim2.new(1, -28, 0, 28), FontFace = HEAD, TextSize = 22, Text = "Item" })
	text(preview, "Sub", { Position = UDim2.new(0, 14, 1, -bottom + 8 + 28 + 4), Size = UDim2.new(1, -28, 0, 16), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Item - by Group" })
	priceButton(preview, "Action", UDim2.new(0, 10, 1, -10 - 52), UDim2.new(1, -24, 0, 50), ICONS.Robux, 18, MINT, 3, 4)

	-- right: filters, 3×2 grid, pager
	local rx = pw + 22
	local rw = PAGE_W - rx
	local filters = new("Frame", { Name = "Filters", Position = UDim2.fromOffset(rx, 0), Size = UDim2.fromOffset(rw, 32), BackgroundTransparency = 1 }, page)
	row(filters, 8)
	for i, label in EMOTE_FILTERS do
		local b = new("TextButton", {
			Name = label,
			LayoutOrder = i,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 32),
			BackgroundColor3 = if i == 1 then INK else WHITE,
			FontFace = BODY,
			TextSize = 13,
			TextColor3 = if i == 1 then YELLOW else INK,
			Text = label,
			AutoButtonColor = false,
		}, filters)
		corner(b, 16)
		stroke(b, 2)
		pad(b, 14)
	end
	text(page, "Source", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 7),
		Size = UDim2.fromOffset(220, 18),
		FontFace = BODY_BOLD,
		TextSize = 12,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "From our group · Robux",
	})

	local gridY, pagerH = 44, 36
	local gridH = PAGE_H - gridY - pagerH - 12
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(rx, gridY), Size = UDim2.fromOffset(rw, gridH), BackgroundTransparency = 1 }, page)
	local cw = (rw - 2 * 14) / 3
	local ch = (gridH - 14) / 2
	for i = 1, 6 do
		local col, r = (i - 1) % 3, math.floor((i - 1) / 3)
		ugcCard(grid, "Card" .. i, UDim2.fromOffset(col * (cw + 14), r * (ch + 14)), UDim2.fromOffset(cw - 4, ch - 4))
	end
	text(grid, "Empty", {
		Size = UDim2.fromScale(1, 1),
		FontFace = BODY_BOLD,
		TextSize = 15,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Loading the group's items…",
		Visible = false,
	})

	local pager = new("Frame", { Name = "Pager", Position = UDim2.fromOffset(rx, PAGE_H - pagerH), Size = UDim2.fromOffset(rw, pagerH), BackgroundTransparency = 1 }, page)
	row(pager, 14, Enum.HorizontalAlignment.Center)
	for i, n in { "Prev", "PageLabel", "Next" } do
		if n == "PageLabel" then
			text(pager, n, { LayoutOrder = i, Size = UDim2.fromOffset(70, 24), FontFace = HEAD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })
		else
			local b = new("TextButton", {
				Name = n,
				LayoutOrder = i,
				Size = UDim2.fromOffset(40, 34),
				BackgroundColor3 = if n == "Next" then YELLOW else WHITE,
				FontFace = BODY,
				TextSize = 22,
				TextColor3 = INK,
				Text = if n == "Prev" then "‹" else "›",
				AutoButtonColor = false,
			}, pager)
			corner(b, 10)
			stroke(b, 3)
		end
	end
	return page
end

-- Adds the UGC tab (between Roll and Coins) + page to an existing Shop frame, keeping hand
-- edits to the rest. Safe to run twice.
function Build.AddUGC(shop: Instance)
	local panel = shop.Panel
	local tabs = panel.Header.Tabs
	if not tabs:FindFirstChild("UGC") then
		local emotes = (tabs:FindFirstChild("Roll") or tabs.Packs):Clone()
		emotes.Name = "UGC"
		emotes.Button.Label.Text = "UGC"
		emotes.Button.Dot.BackgroundColor3 = MINT
		emotes.Button:SetAttribute("BaseY", nil)
		emotes.Size = UDim2.fromOffset(78, 43)
		emotes.Button.Size = UDim2.fromOffset(75, 40)
		emotes.Button.Position = UDim2.fromOffset(37, 20)
		emotes.Parent = tabs
		local order = { Featured = 1, Sets = 2, Items = 3, Packs = 4, Roll = 4, UGC = 5, Coins = 6 }
		for name, n in order do
			if tabs:FindFirstChild(name) then
				tabs[name].LayoutOrder = n
			end
		end
		tabs.Size = UDim2.fromOffset(740, 68)
	end
	local pages = panel.Pages
	if not pages:FindFirstChild("UGC") then
		local page = emotesPage(pages)
		require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(page)
	end
end

local function coinsPage(pages: Instance)
	local page = new("Frame", { Name = "Coins", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, pages)
	titleRow(page, 0, "Coins")
	local bw = (PAGE_W - 2 * 16) / 3
	local bundles = new("Frame", { Name = "Bundles", Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(PAGE_W, 330), BackgroundTransparency = 1 }, page)
	for i = 1, 3 do
		local holder = new("Frame", { Name = "Bundle" .. i, Position = UDim2.fromOffset((i - 1) * (bw + 16), 0), Size = UDim2.fromOffset(bw - 5, 325), BackgroundTransparency = 1 }, bundles)
		local face = card(holder, "Face", UDim2.new(), UDim2.fromScale(1, 1), WHITE, 16, 5, 3)
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 1, -10 - 12 - 44 - 6 - 18 - 6 - 26 - 6), BackgroundColor3 = C("FFF6D6") }, face)
		corner(art, 10)
		stroke(art, 2)
		for c = 1, 6 do
			local im = icon(art, "Coin" .. c, ICONS.CoinStack, 0, c)
			im.Size = UDim2.fromScale(0.34, 0.34 * 0.6 * 1.6)
			im.SizeConstraint = Enum.SizeConstraint.RelativeXX
			im.Size = UDim2.fromScale(0.34, 0.34 * 0.6)
			im.Visible = false
		end
		text(face, "Amount", { Position = UDim2.new(0, 12, 1, -12 - 44 - 6 - 18 - 6 - 26), Size = UDim2.new(1, -24, 0, 26), FontFace = HEAD, TextSize = 24, Text = "2,500 coins" })
		text(face, "Sub", { Position = UDim2.new(0, 12, 1, -12 - 44 - 6 - 18), Size = UDim2.new(1, -24, 0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Most popular" })
		priceButton(face, "Action", UDim2.new(0, 12, 1, -12 - 44), UDim2.new(1, -24 - 3, 0, 44 - 3), ICONS.Robux, 17, MINT, 3, 3)
		local best = text(holder, "Best", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 8, 0, -13),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			BackgroundTransparency = 0,
			BackgroundColor3 = RED,
			FontFace = HEAD,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.None,
			Rotation = 6,
			Text = "BEST VALUE",
			Visible = false,
			ZIndex = 5,
		})
		corner(best, 10)
		stroke(best, 3)
		pad(best, 10)
	end

	titleRow(page, 386, "Passes")
	local passW = (PAGE_W - 16) / 2
	for i = 1, 2 do
		local x = (i - 1) * (passW + 16)
		local p = card(page, "Pass" .. i, UDim2.fromOffset(x, PAGE_H - 96 - 5), UDim2.fromOffset(passW - 5, 96), C("9ED8F5"), 16, 5, 3)
		local circle = new("Frame", { Name = "IconCircle", Position = UDim2.fromOffset(16, 19), Size = UDim2.fromOffset(58, 58), BackgroundColor3 = WHITE }, p)
		corner(circle, UDim.new(0.5, 0))
		stroke(circle, 3)
		text(circle, "IconText", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "2×" })
		local crown = icon(circle, "IconImage", ICONS.Crown, 32)
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Position = UDim2.fromScale(0.5, 0.5)
		crown.Visible = false
		text(p, "PassName", { Position = UDim2.fromOffset(88, 22), Size = UDim2.new(1, -88 - 130, 0, 26), FontFace = HEAD, TextSize = 20, Text = "2× Coins" })
		text(p, "Sub", { Position = UDim2.fromOffset(88, 50), Size = UDim2.new(1, -88 - 130, 0, 18), TextSize = 12, Text = "Double coins from every match, forever" })
		priceButton(p, "Action", UDim2.new(1, -16 - 104, 0.5, -23), UDim2.fromOffset(104, 46), ICONS.Robux, 16, MINT, 3, 3)
	end
end

-- --------------------------------- Build ---------------------------------- --
function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Shop")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("Shop_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "Shop_Legacy"
		old.Parent = storage
	end

	local shop = new("Frame", { Name = "Shop", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 1 })
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, shop)
	scrim.Active = true -- swallow clicks behind the shop

	local panel = card(shop, "Panel", UDim2.fromOffset(140, 40), UDim2.fromOffset(1000, 640), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true

	-- header
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 68), BackgroundColor3 = MINT, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(header, "Title", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(90, 68), FontFace = HEAD, TextSize = 26, Text = "SHOP" })
	local tabs = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(112, 0), Size = UDim2.fromOffset(740, 68), BackgroundTransparency = 1 }, header)
	row(tabs, 10)
	for i, t in { { "Featured", "FFE07A" }, { "Sets", "B9A6FF" }, { "Items", "FF9EC4" }, { "Roll", "FF9EC4" }, { "UGC", "A7E9B8" }, { "Coins", "FFD2CE" } } do
		local holder = new("Frame", { Name = t[1], LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 43), BackgroundTransparency = 1 }, tabs)
		local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -3, 1, -3), BackgroundColor3 = INK, BorderSizePixel = 0 }, holder)
		corner(shadow, 11)
		local b = new("TextButton", {
			Name = "Button",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			BackgroundColor3 = WHITE,
			Text = "",
			AutoButtonColor = false,
		}, holder)
		corner(b, 11)
		stroke(b, 3)
		pad(b, 12)
		row(b, 7)
		local dot = new("Frame", { Name = "Dot", LayoutOrder = 1, Size = UDim2.fromOffset(12, 12), BackgroundColor3 = C(t[2]) }, b)
		corner(dot, UDim.new(0.5, 0))
		stroke(dot, 2)
		text(b, "Label", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextTruncate = Enum.TextTruncate.None, Text = t[1] })
	end
	-- balance + close
	local close = card(header, "Close", UDim2.fromOffset(1000 - 14 - 42, 13), UDim2.fromOffset(42, 42), RED, 12, 3, 3)
	close:Destroy()
	header:FindFirstChild("CloseShadow"):Destroy()
	local closeShadow = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(1000 - 14 - 42 + 3, 16), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(closeShadow, 12)
	local closeBtn = new("ImageButton", {
		Name = "Close",
		Position = UDim2.fromOffset(1000 - 14 - 42, 13),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = RED,
		Image = "",
		AutoButtonColor = false,
	}, header)
	corner(closeBtn, 12)
	stroke(closeBtn, 3)
	local x = icon(closeBtn, "Icon", ICONS.Close, 16)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)

	local bal = new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(1000 - 14 - 42 - 12, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		BackgroundColor3 = WHITE,
	}, header)
	corner(bal, 10)
	stroke(bal, 3)
	pad(bal, 10)
	row(bal, 8)
	icon(bal, "Icon", ICONS.Coin, 25, 1)
	text(bal, "Amount", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = HEAD, TextSize = 15, TextTruncate = Enum.TextTruncate.None, Text = "0" })

	-- pages
	local pages = new("Frame", { Name = "Pages", Position = UDim2.fromOffset(22, 89), Size = UDim2.fromOffset(PAGE_W, PAGE_H), BackgroundTransparency = 1 }, panel)
	featuredPage(pages)
	setsPage(pages)
	itemsPage(pages)
	RollPage.Build(pages, shop) -- the song roll (./RollPage), which replaced buying packs
	emotesPage(pages)
	coinsPage(pages)

	-- toast for purchase results
	local toast = text(shop, "Toast", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(640, 700),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 0,
		BackgroundColor3 = INK,
		TextColor3 = YELLOW,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Text = "",
		Visible = false,
		ZIndex = 10,
	})
	corner(toast, 10)
	pad(toast, 16)

	shop.Parent = frames
	-- centre every button's AnchorPoint so the ButtonScale tween grows from the middle
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(shop)
	return shop
end

-- [[ Rolls + upgrades ]]
-- The scrolling shop's "Rolls + upgrades" section (design board "Shop v3 · roll tickets + card
-- upgrades"): RollsTitle + Rolls, between Banners + photocards and Coins. Two cards side by
-- side, Tickets (pink) and Upgrades (lilac): the currency's icon, name, a line on what it
-- does, a "You have n" chip and three bundles (Count, Unit, a Robux Buy button cloned from
-- the coin bundles, a POPULAR / BEST VALUE Tag). ShopController fills them from
-- ShopCatalog.RollBundles. Run once in Studio, Edit mode (safe to run again):
--   require(<this module>).AddRolls(game.StarterGui.Interface.Frames)
function Build.AddRolls(frames: Instance)
	local Currencies = require(game:GetService("ReplicatedStorage").Constants.Currencies)
	local scroll = frames.Shop.Panel.Scroll
	local after = (scroll:FindFirstChild("Style") or scroll.Pieces).LayoutOrder
	if not scroll:FindFirstChild("RollsTitle") then
		-- first build: make room for two more sections before Coins
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") and child.LayoutOrder > after then
				child.LayoutOrder += 2
			end
		end
	end
	for _, name in { "RollsTitle", "Rolls" } do
		local old = scroll:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	-- heading: "—— Rolls + upgrades  never expire ——", like the other section titles
	local title = scroll.SetsTitle:Clone()
	title.Name = "RollsTitle"
	title.LayoutOrder = after + 1
	title.Title.Text = "Rolls + upgrades"
	local hint = title.Chip
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.TextColor3 = MUTED
	hint.Text = "Never expire · stack with the ones from codes"
	for _, d in hint:GetChildren() do
		if d:IsA("UIStroke") then
			d:Destroy()
		end
	end
	title.Parent = scroll

	local coinFace = scroll.Coins.Face
	local buyTemplate, buyShadowTemplate = coinFace.Bundle1.Buy, coinFace.Bundle1.BuyShadow
	local tagTemplate = coinFace:FindFirstChild("Tag", true)

	local W, GAP, CH = 941, 18, 236
	local CW = math.floor((W - GAP) / 2)
	local section = new("Frame", { Name = "Rolls", LayoutOrder = after + 2, Size = UDim2.new(1, 0, 0, CH + 5), BackgroundTransparency = 1 }, scroll)
	for i, spec in {
		{ Id = "Tickets", Colour = C("FFE4EF"), Title = "Roll tickets", Body = "A free song roll from any group you pick", Unit = "tickets" },
		{ Id = "Upgrades", Colour = C("EFEAFF"), Title = "Card upgrades", Body = "+1 copy on any song you own. Gold at 3, Rainbow at 5", Unit = "upgrades" },
	} do
		local x = (i - 1) * (CW + GAP)
		local face = card(section, spec.Id, UDim2.fromOffset(x, 0), UDim2.fromOffset(CW, CH), spec.Colour, 16, 5, 3)
		-- head: icon tile, name + line, "You have n"
		local tile = new("Frame", { Name = "IconTile", Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(78, 78), BackgroundColor3 = WHITE }, face)
		corner(tile, 14)
		stroke(tile, 3)
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(62, 62), BackgroundTransparency = 1, Image = Currencies.Get(spec.Id).Icon, ScaleType = Enum.ScaleType.Fit }, tile)
		text(face, "CardTitle", { Position = UDim2.fromOffset(108, 22), Size = UDim2.new(1, -230, 0, 28), FontFace = HEAD, TextSize = 21, Text = spec.Title })
		text(face, "Body", { Position = UDim2.fromOffset(108, 52), Size = UDim2.new(1, -124, 0, 38), FontFace = BODY_BOLD, TextSize = 13, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, Text = spec.Body })
		local have = text(face, "Have", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 18), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = WHITE, TextSize = 12, TextTruncate = Enum.TextTruncate.None, Text = "You have 0" })
		corner(have, 8)
		stroke(have, 2)
		pad(have, 8)
		-- three bundles
		local bw = math.floor((CW - 32 - 2 * 10) / 3)
		for b = 1, 3 do
			local bx = 16 + (b - 1) * (bw + 10)
			local holder = new("Frame", { Name = "Bundle" .. b, Position = UDim2.fromOffset(bx, 110), Size = UDim2.fromOffset(bw, 108), BackgroundColor3 = WHITE }, face)
			corner(holder, 12)
			stroke(holder, 2)
			text(holder, "Count", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 30), FontFace = HEAD, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Text = `×{({ 1, 5, 12 })[b]}` })
			text(holder, "Unit", { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = C("4A4460"), TextXAlignment = Enum.TextXAlignment.Center, Text = spec.Unit })
			local bwBtn, bh, by = bw - 18, 40, 58
			local sh = buyShadowTemplate:Clone()
			sh.Size = UDim2.fromOffset(bwBtn, bh)
			sh.Position = UDim2.fromOffset(9 + bwBtn / 2 + 3, by + bh / 2 + 3)
			sh.Parent = holder
			local buy = buyTemplate:Clone()
			buy.Size = UDim2.fromOffset(bwBtn, bh)
			buy.Position = UDim2.fromOffset(9 + bwBtn / 2, by + bh / 2)
			buy.Parent = holder
			buy.Icon.Size = UDim2.fromOffset(18, 18)
			buy.Label.TextSize = math.min(buy.Label.TextSize, 16)
			buy.Label.Size = UDim2.fromOffset(0, bh - 8)
			if tagTemplate then
				local tag = tagTemplate:Clone()
				tag.Name = "Tag"
				tag.AnchorPoint = Vector2.new(1, 0)
				tag.Position = UDim2.new(1, 6, 0, -10)
				tag.Visible = b > 1
				tag.Text = if b == 3 then "BEST VALUE" else "POPULAR"
				tag.BackgroundColor3 = if b == 3 then RED else C("FF9EC4")
				tag.ZIndex = 3
				tag.Parent = holder
			end
		end
	end
	return section
end

-- [[ Debut Pack banner ("Shop v3 · Debut Pack · A with a plain title", A1) ]]
-- The title on the left ("Debut / Pack", a line under it, an "n ITEMS" chip), then the items
-- as tilted photocards with "+" between (Item1–4: Shadow + Card with Art / Label / Sub and an
-- "ONLY HERE" Only tag), then the Robux button with "One time only" under it. Rebuilds the
-- inside of Scroll.Debut (keeps its place in the page). Run once in Studio, Edit mode:
--   require(<this module>).DebutPack(game.StarterGui.Interface.Frames)
Build.DEBUT_CARD_W, Build.DEBUT_CARD_H = 132, 166
function Build.DebutPack(frames: Instance)
	local section = frames.Shop.Panel.Scroll.Debut
	local W, H = 941, 214
	for _, child in section:GetChildren() do
		child:Destroy()
	end
	section.Size = UDim2.new(1, 0, 0, 14 + H + 8)
	local face = card(section, "Face", UDim2.fromOffset(0, 14), UDim2.fromOffset(W, H), WHITE, 16, 6, 3)
	new("UIGradient", { Rotation = 10, Color = ColorSequence.new(C("FFE4EF"), C("FFF1B8")) }, face)

	local tag = text(face, "Tag", {
		Position = UDim2.fromOffset(16, -14),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = C("FF9EC4"),
		FontFace = HEAD,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.None,
		Rotation = -3,
		ZIndex = 5,
		Text = "ONE TIME · NEW PLAYERS",
	})
	corner(tag, 7)
	stroke(tag, 3)
	pad(tag, 10)

	-- title block
	text(face, "Title", { Position = UDim2.fromOffset(22, 40), Size = UDim2.fromOffset(190, 64), FontFace = HEAD, TextSize = 30, LineHeight = 0.95, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "Debut\nPack" })
	text(face, "Sub", { Position = UDim2.fromOffset(22, 110), Size = UDim2.fromOffset(180, 32), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "Everything to start your first duels" })
	local count = text(face, "Count", {
		Position = UDim2.fromOffset(22, 148),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundTransparency = 0,
		BackgroundColor3 = CREAM,
		FontFace = HEAD,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.None,
		Text = "3 ITEMS",
	})
	corner(count, 7)
	stroke(count, 2)
	pad(count, 9)

	-- the items: photocards with a "+" between
	local cw, ch = Build.DEBUT_CARD_W, Build.DEBUT_CARD_H
	local items = new("Frame", { Name = "Items", Position = UDim2.fromOffset(224, 0), Size = UDim2.fromOffset(470, H), BackgroundTransparency = 1 }, face)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, items)
	for i = 1, 4 do
		if i > 1 then
			text(items, "Plus" .. (i - 1), { LayoutOrder = i * 2 - 1, Size = UDim2.fromOffset(18, 30), FontFace = HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Text = "+" })
		end
		local slot = new("Frame", { Name = "Item" .. i, LayoutOrder = i * 2, Size = UDim2.fromOffset(cw + 4, ch + 4), BackgroundTransparency = 1, Rotation = ({ -3, 1.5, 3, -1.5 })[i] }, items)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = INK, BorderSizePixel = 0 }, slot)
		corner(sh, 12)
		local c = new("Frame", { Name = "Card", Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = WHITE }, slot)
		corner(c, 12)
		stroke(c, 3)
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(cw - 14, 100), BackgroundColor3 = YELLOW, ClipsDescendants = true }, c)
		corner(art, 8)
		stroke(art, 3)
		-- coins: the pile drawn big, anchored on the coins (CosmeticView fills stage / mic)
		new("ImageLabel", { Name = "Pic", AnchorPoint = Vector2.new(0.5, 0.56), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.1, 1.1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "" }, art)
		text(c, "Label", { Position = UDim2.fromOffset(4, 112), Size = UDim2.new(1, -8, 0, 24), FontFace = HEAD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Text = "2,500" })
		text(c, "Sub", { Position = UDim2.fromOffset(4, 136), Size = UDim2.new(1, -8, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Coins" })
		local only = text(slot, "Only", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromOffset(cw + 8, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = YELLOW,
			FontFace = HEAD,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.None,
			ZIndex = 4,
			Visible = false,
			Text = "ONLY HERE",
		})
		corner(only, 6)
		stroke(only, 2)
		pad(only, 7)
	end

	-- price + note
	local bw, bh = 180, 56
	priceButton(face, "Buy", UDim2.fromOffset(W - 24 - bw, H / 2 - bh / 2 - 12), UDim2.fromOffset(bw, bh), ICONS.Robux, 22, MINT, 3, 4)
	text(face, "Note", { Position = UDim2.fromOffset(W - 24 - bw, H / 2 + bh / 2 - 4), Size = UDim2.fromOffset(bw, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "One time only" })
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(section)
	return section
end

-- [[ Bundles ("Shop v3 · Bundles") ]]
-- One banner: Face (+ FaceShadow) with Tag, Title, Sub, Count?, Items (Item1–n photocard slots
-- with "+" between: Shadow + Card with Art / Label / Sub, and an Only tag), Buy (+ BuyShadow)
-- and Note. Big = the Debut Pack's size (two-line title + count chip); otherwise the short one.
local function bundleBanner(parent: Instance, name: string, order: number, big: boolean, slots: number): Frame
	local W = 941
	local H = if big then 214 else 118
	local holder = new("Frame", { Name = name, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 14 + H + 8), BackgroundTransparency = 1 }, parent)
	local face = card(holder, "Face", UDim2.fromOffset(0, 14), UDim2.fromOffset(W, H), WHITE, 16, if big then 6 else 5, 3)
	new("UIGradient", { Name = "Tint", Rotation = 10, Color = ColorSequence.new(C("FFF1B8"), C("FFE4EF")) }, face)

	local tag = text(face, "Tag", {
		Position = UDim2.fromOffset(16, -14),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = C("FF9EC4"),
		FontFace = HEAD,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.None,
		Rotation = -3,
		ZIndex = 5,
		Text = "BEST VALUE",
	})
	corner(tag, 7)
	stroke(tag, 3)
	pad(tag, 10)

	local titleW = if big then 160 else 196
	if big then
		text(face, "Title", { Position = UDim2.fromOffset(22, 40), Size = UDim2.fromOffset(titleW, 64), FontFace = HEAD, TextSize = 30, LineHeight = 0.95, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, TextWrapped = true, Text = "Headliner" })
		text(face, "Sub", { Position = UDim2.fromOffset(22, 110), Size = UDim2.fromOffset(titleW - 6, 32), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
		local count = text(face, "Count", {
			Position = UDim2.fromOffset(22, 148),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			BackgroundTransparency = 0,
			BackgroundColor3 = CREAM,
			FontFace = HEAD,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.None,
			Text = "5 ITEMS",
		})
		corner(count, 7)
		stroke(count, 2)
		pad(count, 9)
	else
		text(face, "Title", { Position = UDim2.fromOffset(22, 34), Size = UDim2.fromOffset(titleW, 28), FontFace = HEAD, TextSize = 22, Text = "Bundle" })
		text(face, "Sub", { Position = UDim2.fromOffset(22, 64), Size = UDim2.fromOffset(titleW, 32), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "" })
	end

	-- the contents
	-- (big: five cards, as wide as they fit, so the art boxes stay near square)
	local cw, ch = if big then 98 else 82, if big then 132 else 96
	local bw, bh = if big then 150 else 160, if big then 56 else 48
	local x0 = 22 + titleW + 6
	local items = new("Frame", { Name = "Items", Position = UDim2.fromOffset(x0, 0), Size = UDim2.fromOffset(W - 24 - bw - 10 - x0, H), BackgroundTransparency = 1 }, face)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, if big then 3 else 4), SortOrder = Enum.SortOrder.LayoutOrder }, items)
	for i = 1, slots do
		if i > 1 then
			text(items, "Plus" .. (i - 1), { LayoutOrder = i * 2 - 1, Size = UDim2.fromOffset(if big then 10 else 12, 24), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Text = "+" })
		end
		local slot = new("Frame", { Name = "Item" .. i, LayoutOrder = i * 2, Size = UDim2.fromOffset(cw + 3, ch + 3), BackgroundTransparency = 1 }, items)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = INK, BorderSizePixel = 0 }, slot)
		corner(sh, 10)
		local c = new("Frame", { Name = "Card", Size = UDim2.fromOffset(cw, ch), BackgroundColor3 = WHITE }, slot)
		corner(c, 10)
		stroke(c, if big then 3 else 2.5)
		local artH = ch - (if big then 46 else 40)
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(cw - 10, artH), BackgroundColor3 = YELLOW, ClipsDescendants = true }, c)
		corner(art, 7)
		stroke(art, 2.5)
		new("ImageLabel", { Name = "Pic", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "" }, art)
		text(c, "Label", { Position = UDim2.fromOffset(3, artH + 7), Size = UDim2.new(1, -6, 0, if big then 19 else 17), FontFace = HEAD, TextSize = if big then 15 else 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "×10" })
		text(c, "Sub", { Position = UDim2.fromOffset(3, artH + (if big then 26 else 24)), Size = UDim2.new(1, -6, 0, 13), FontFace = BODY_BOLD, TextSize = if big then 11 else 10, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Roll tickets" })
		local only = text(slot, "Only", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromOffset(cw + 6, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			BackgroundTransparency = 0,
			BackgroundColor3 = YELLOW,
			FontFace = HEAD,
			TextSize = 9,
			TextTruncate = Enum.TextTruncate.None,
			ZIndex = 4,
			Visible = false,
			Text = "ONLY HERE",
		})
		corner(only, 6)
		stroke(only, 2)
		pad(only, 6)
	end

	priceButton(face, "Buy", UDim2.fromOffset(W - 24 - bw, H / 2 - bh / 2 - (if big then 12 else 9)), UDim2.fromOffset(bw, bh), ICONS.Robux, if big then 22 else 19, MINT, 3, 4)
	text(face, "Note", { Position = UDim2.fromOffset(W - 24 - bw, H / 2 + bh / 2 - (if big then 4 else 2)), Size = UDim2.fromOffset(bw, 16), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "" })
	return holder
end

-- Adds the bundles to the shop page. Top of the page, in order: the weekly Featured set,
-- Scroll.Headliner (the big featured bundle), a "Bundles" heading, the Debut Pack, then
-- Scroll.Bundles (Bundle1–3, the short banners). ShopController fills them from
-- ShopCatalog.Bundles. Run once in Studio, Edit mode (safe to run again):
--   require(<this module>).AddBundles(game.StarterGui.Interface.Frames)
function Build.AddBundles(frames: Instance)
	local scroll = frames.Shop.Panel.Scroll
	local featured, debut = scroll.Featured, scroll.Debut
	local old = scroll:FindFirstChild("Headliner")
	local f = math.min(featured.LayoutOrder, if old then old.LayoutOrder else math.huge)
	for _, n in { "Headliner", "BundlesTitle", "Bundles" } do
		local x = scroll:FindFirstChild(n)
		if x then
			x:Destroy()
		end
	end

	featured.LayoutOrder = f
	local headliner = bundleBanner(scroll, "Headliner", f + 1, true, 5)
	local title = scroll.SetsTitle:Clone()
	title.Name = "BundlesTitle"
	title.LayoutOrder = f + 2
	title.Parent = scroll
	title.Title.Text = "Bundles"
	title.Chip.Visible = false
	debut.LayoutOrder = f + 3
	local list = new("Frame", { Name = "Bundles", LayoutOrder = f + 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, scroll)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i = 1, 3 do
		bundleBanner(list, "Bundle" .. i, i, false, 3)
	end

	-- everything else keeps its order, after these five
	local mine = { [headliner] = true, [featured] = true, [title] = true, [debut] = true, [list] = true }
	local low = math.huge
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") and not mine[child] and child.LayoutOrder > f then
			low = math.min(low, child.LayoutOrder)
		end
	end
	if low < f + 5 then
		for _, child in scroll:GetChildren() do
			if child:IsA("GuiObject") and not mine[child] and child.LayoutOrder > f then
				child.LayoutOrder += f + 5 - low
			end
		end
	end
	-- (centre the buttons inside each banner; the banner holders keep their size)
	local CenterButtons = require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons)
	CenterButtons.Apply(headliner.Face)
	for _, b in list:GetChildren() do
		if b:IsA("Frame") then
			CenterButtons.Apply(b.Face)
		end
	end
	return list
end

return Build
