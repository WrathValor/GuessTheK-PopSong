--| Shop UI builder
-- Builds Interface.Frames.Shop from the "Shop A" design boards (tabs in the header, pages
-- that never scroll). Run once in Studio (it replaces any existing Shop frame, keeping the old
-- one as ServerStorage.Shop_Legacy); after that the frame lives in Studio and can be restyled
-- by hand. ShopController only fills it in, finding everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local LINE = C("CFC5B3")
local PAPER = C("F3EBDD")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Build = {}

Build.ICONS = {
	Coin = "rbxassetid://105055420801588",
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
		Size = UDim2.fromOffset(270, 36),
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
	row(perks, 6)
	for i = 1, 3 do
		local c = text(perks, "Perk" .. i, {
			LayoutOrder = i,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = WHITE,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.None,
			Text = "Perk",
		})
		corner(c, 8)
		stroke(c, 2)
		pad(c, 8)
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

local function packsPage(pages: Instance)
	local page = new("Frame", { Name = "Packs", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, pages)
	local head = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, page)
	row(head, 10)
	text(head, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), FontFace = HEAD, TextSize = 20, TextTruncate = Enum.TextTruncate.None, Text = "Song packs" })
	text(page, "Note", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.fromOffset(420, 20),
		FontFace = BODY_BOLD,
		TextSize = 12,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "Songs you own go into My Pack for solo practice.",
	})

	-- pack picker (5 slots)
	local pw = (PAGE_W - 4 * 12) / 5
	local picker = new("Frame", { Name = "Picker", Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(PAGE_W, 64), BackgroundTransparency = 1 }, page)
	for i = 1, 5 do
		local x = (i - 1) * (pw + 12)
		local sh = new("Frame", { Name = "Pack" .. i .. "Shadow", Position = UDim2.fromOffset(x + 3, 3), Size = UDim2.fromOffset(pw, 64), BackgroundColor3 = INK }, picker)
		corner(sh, 12)
		local b = new("TextButton", { Name = "Pack" .. i, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(pw, 64), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, picker)
		corner(b, 12)
		stroke(b, 3)
		local cover = new("Frame", { Name = "Cover", Position = UDim2.fromOffset(9, 11), Size = UDim2.fromOffset(36, 42), BackgroundColor3 = C("B9A6FF"), Rotation = -4 }, b)
		corner(cover, 7)
		stroke(cover, 2)
		local n = icon(cover, "Icon", ICONS.Note, 20)
		n.AnchorPoint = Vector2.new(0.5, 0.5)
		n.Position = UDim2.fromScale(0.5, 0.5)
		text(b, "PackName", { Position = UDim2.fromOffset(54, 13), Size = UDim2.new(1, -60, 0, 20), FontFace = HEAD, TextSize = 15, Text = "HYBE" })
		text(b, "Sub", { Position = UDim2.fromOffset(54, 34), Size = UDim2.new(1, -60, 0, 16), FontFace = BODY_BOLD, TextSize = 11, Text = "5 / 12 owned" })
		local chip = text(b, "Chip", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 15),
			BackgroundTransparency = 0,
			BackgroundColor3 = MINT,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.None,
			Text = "DONE",
			Visible = false,
		})
		corner(chip, 6)
		stroke(chip, 2)
		pad(chip, 5)
	end

	-- selected pack
	local sel = card(page, "Selected", UDim2.fromOffset(0, 120), UDim2.fromOffset(PAGE_W - 5, PAGE_H - 120 - 5), WHITE, 16, 5, 3)
	local top = new("Frame", { Name = "Top", Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -32, 0, 28), BackgroundTransparency = 1 }, sel)
	row(top, 12)
	text(top, "PackName", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), FontFace = HEAD, TextSize = 22, TextTruncate = Enum.TextTruncate.None, Text = "HYBE" })
	text(top, "Count", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "12 songs · you own 5" })
	local reward = text(sel, "Reward", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 17),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.None,
		Rotation = 2,
		Text = "Own all 12 → title: HYBE Expert",
	})
	corner(reward, 8)
	stroke(reward, 2)
	pad(reward, 9)

	local innerW = PAGE_W - 5 - 32
	local sw = (innerW - 2 * 10) / 3
	local songs = new("Frame", { Name = "Songs", Position = UDim2.fromOffset(16, 54), Size = UDim2.fromOffset(innerW, 4 * 44 + 3 * 8), BackgroundTransparency = 1 }, sel)
	for i = 1, 12 do
		local col, r = (i - 1) % 3, (i - 1) // 3
		local s = new("Frame", { Name = "Song" .. i, Position = UDim2.fromOffset(col * (sw + 10), r * 52), Size = UDim2.fromOffset(sw, 44), BackgroundColor3 = WHITE }, songs)
		corner(s, 9)
		stroke(s, 2)
		text(s, "SongTitle", { Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -96, 0, 18), TextSize = 13, Text = "Song" })
		text(s, "Artist", { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -96, 0, 15), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "Artist" })
		local owned = text(s, "Owned", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = MINT,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.None,
			Text = "OWNED",
			Visible = false,
		})
		corner(owned, 6)
		stroke(owned, 2)
		pad(owned, 6)
		local buy = priceButton(s, "Buy", UDim2.new(1, -78, 0.5, -14), UDim2.fromOffset(72, 28), ICONS.Coin, 12, YELLOW, 2)
		buy:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 8)
	end

	-- bottom: buy everything missing
	local bottomY = PAGE_H - 120 - 5 - 14 - 46
	new("Frame", { Name = "Divider", Position = UDim2.fromOffset(16, bottomY - 12), Size = UDim2.new(1, -32, 0, 2), BackgroundColor3 = LINE, BorderSizePixel = 0 }, sel)
	text(sel, "BuyAllTitle", { Position = UDim2.fromOffset(16, bottomY + 2), Size = UDim2.new(1, -260, 0, 20), Text = "Buy the 7 HYBE songs you're missing" })
	text(sel, "BuyAllSub", { Position = UDim2.fromOffset(16, bottomY + 23), Size = UDim2.new(1, -260, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "You only pay for songs you don't own · 25% off" })
	priceButton(sel, "BuyAll", UDim2.new(1, -16 - 190 - 3, 0, bottomY), UDim2.fromOffset(190, 46), ICONS.Coin, 18, MINT, 3, 3)
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

-- Companies | Groups switch in the Packs header, plus ‹ › to page through more than 5 packs.
local function packsKindSwitch(page: Instance)
	local head = page.Header
	local switch = new("Frame", { Name = "Kind", LayoutOrder = 2, Size = UDim2.fromOffset(196, 28), BackgroundColor3 = WHITE }, head)
	corner(switch, 9)
	stroke(switch, 3)
	for i, label in { "Companies", "Groups" } do
		local b = new("TextButton", {
			Name = label,
			Position = UDim2.fromOffset((i - 1) * 98, 0),
			Size = UDim2.fromOffset(98, 28),
			BackgroundColor3 = if i == 1 then INK else WHITE,
			FontFace = BODY,
			TextSize = 13,
			TextColor3 = if i == 1 then YELLOW else MUTED,
			Text = label,
			AutoButtonColor = false,
		}, switch)
		corner(b, 7)
	end
	local chip = text(head, "Chip", {
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.None,
		Text = "Restocks in 3h 42m",
	})
	corner(chip, 8)
	stroke(chip, 2)
	pad(chip, 8)
	local note = page:FindFirstChild("Note")
	if note then
		note.Position = UDim2.new(1, -80, 0, 4)
		note.Size = UDim2.fromOffset(360, 20)
	end
	for i, n in { "PickerPrev", "PickerNext" } do
		local b = new("TextButton", {
			Name = n,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -52 + (i - 1) * 38, 0, 14),
			Size = UDim2.fromOffset(32, 28),
			BackgroundColor3 = WHITE,
			FontFace = BODY,
			TextSize = 20,
			TextColor3 = INK,
			Text = if i == 1 then "‹" else "›",
			AutoButtonColor = false,
		}, page)
		corner(b, 8)
		stroke(b, 2)
	end
end

-- Adds the Items tab + page and the packs switch to an existing Shop frame (so hand edits to
-- the rest of the shop are kept). Safe to run twice.
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
	local packs = pages.Packs
	if not packs.Header:FindFirstChild("Kind") or not packs.Header:FindFirstChild("Chip") then
		local old = packs.Header:FindFirstChild("Kind")
		if old then
			old:Destroy()
		end
		for _, n in { "PickerPrev", "PickerNext" } do
			if packs:FindFirstChild(n) then
				packs[n]:Destroy()
			end
		end
		packsKindSwitch(packs)
		require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(packs)
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
	local tabs = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(112, 0), Size = UDim2.fromOffset(640, 68), BackgroundTransparency = 1 }, header)
	row(tabs, 10)
	for i, t in { { "Featured", "FFE07A" }, { "Sets", "B9A6FF" }, { "Items", "FF9EC4" }, { "Packs", "9ED8F5" }, { "Coins", "FFD2CE" } } do
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
	packsPage(pages)
	packsKindSwitch(pages.Packs)
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

return Build
