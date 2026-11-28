--| Market UI builder
-- Builds Interface.Frames.Market from the design boards "60 · Market · Browse", "60b · Sell a
-- card" and "60c · Card detail + buy": a full-screen screen like the Shop and Quests. "Market"
-- top left with its line, Browse · Sell · My listings tabs top centre (each with a red Badge),
-- the balance and ✕ top right, then one page a tab:
--   Pages.Browse   – Filters (search, rarity chips, group dropdown + GroupList, sort chips,
--                    two toggles) and Grid (ON SALE + info, ‹ page ›, Tile1–8: the card, its
--                    name + NEW TO YOU, group · album · seller, price, VIEW)
--   Pages.Sell     – Cards (your cards, any rarity: List grid, an Item template) and
--                    Form (the card, pricing help, − price +, fee, LISTED FOR chips, LIST CARD)
--   Pages.Listings – Panel (board 67: MY LISTINGS + count; Stats: OnSale, Week, ToCollect,
--                    AllTime + COLLECT ALL; List of Row templates: the card, chips (Status, Who,
--                    time Bar, Rank), price, Cancel / COLLECT; Activity: All · Sold · Ended
--                    Filters and the Feed's Item template). Build.MyListings rebuilds just this.
--   Detail         – the card detail over everything (dim, the big card, last 5 sales, this
--                    copy's story, other copies, PRICE and BUY FOR)
-- Photocards are Modules/UI/Photocard builds (MarketController paints them). Run once in Edit
-- (again = rebuilt; an old frame is replaced):
--   local m = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("MarketController", true).Build
--   local c = m:Clone(); c.Parent = m.Parent; require(c).Build(game.StarterGui.Interface.Frames); c:Destroy()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local MarketConstants = require(ReplicatedStorage.Constants.MarketConstants)
local Photocard = require(ReplicatedStorage.Modules.UI.Photocard)
local CardDecor = require(ReplicatedStorage.Modules.UI.CardDecor)

local C = Color3.fromHex

-- a grid or list card: a tile (CardDecor CardFx "Tile"), so it keeps still with Low effects on;
-- the decor is built again now it knows. (The Detail's big card always moves, as the binder's.)
local function asTile(pc: Frame): Frame
	pc:SetAttribute("CardFx", "Tile")
	CardDecor.Build(pc, pc.Face, pc.Face.Photo)
	return pc
end
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local SAND = C("F3EEE0")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local PINK = C("FF9EC4")
local RED = C("FF5A4E")
local MUTED = C("6B6480")
local TRACK = C("EDE4D4")
local DARK_TOP, DARK_MID, DARK_LOW = C("3B2F66"), C("2A2340"), C("221C36")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local CLOSE_ICON = "rbxassetid://118345756178429"
local COIN = Currencies.Coins.Icon

local Build = {}
Build.TABS = { "Browse", "Sell", "Listings" }
Build.TAB_NAMES = { Browse = "Browse", Sell = "Sell", Listings = "My listings" }
Build.RARITY_NAMES = { standard = "Standard", selca = "Selca", store = "Store", luckydraw = "Lucky Draw", fansign = "Fansign", polaroid = "Signed Polaroid", oneofone = "One of One" }
Build.SORT_NAMES = { Price = "Lowest price", Newest = "Newest", Rarest = "Rarest", Serial = "Low serial" }
Build.HOUR_NAMES = { [24] = "24 h", [48] = "48 h", [168] = "7 days" }
Build.BARS = 5
Build.FEED_FILTERS = { "All", "Sold", "Ended" }

-- [[ Helpers ]]

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
	return new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function pad(p: Instance, l: number, r: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l) }, p)
end

local function row(parent: Instance, gap: number, align: Enum.HorizontalAlignment?)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
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
	return new("ImageLabel", { Name = name, LayoutOrder = order or 0, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit }, parent)
end

-- a label over the controls ("RARITY")
local function lab(parent: Instance, name: string, x: number, y: number, label: string): TextLabel
	return text(parent, name, { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(240, 14), FontFace = BODY, TextSize = 12, TextColor3 = MUTED, Text = label })
end

-- a hard-shadowed card: shadow `drop` down-right of the face's outside edge (the stroke is drawn
-- outside, so the shadow grows by it)
local function card(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, radius: number, drop: number, line: number): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + drop - line, y + drop - line), Size = UDim2.fromOffset(w + line * 2, h + line * 2), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius + line)
	local face = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string, size: number?, drop: number?): TextButton
	local line = 3
	local d = drop or 3
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + d - line, y + d - line), Size = UDim2.fromOffset(w + line * 2, h + line * 2), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, 12 + line)
	local b = new("TextButton", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		AutoButtonColor = false,
		FontFace = HEAD,
		TextSize = size or 14,
		TextColor3 = INK,
		Text = label,
	}, parent)
	corner(b, 12)
	stroke(b, line)
	return b
end

-- a round filter chip (TextButton): its Dot (rarity chips) and Label
local function chip(parent: Instance, name: string, x: number, y: number, w: number, label: string, dot: Color3?): TextButton
	local b = new("TextButton", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, 28),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
	}, parent)
	corner(b, UDim.new(0.5, 0))
	stroke(b, 2.5)
	if dot then
		local d = new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = dot }, b)
		corner(d, UDim.new(0.5, 0))
		stroke(d, 2)
		local foil = CardDecor.FOILS[name]
		if foil then
			-- the rarity's foil, like the Odds sheet's dots: always on the dot, on the chip while picked
			new("UIGradient", { Name = "Foil", Rotation = 45, Color = foil }, d)
			new("UIGradient", { Name = "Foil", Rotation = 45, Color = foil, Enabled = false }, b)
		end
	end
	text(b, "Label", { Position = UDim2.fromOffset(if dot then 26 else 0, 0), Size = UDim2.new(1, if dot then -30 else 0, 1, 0), TextSize = 13, TextXAlignment = if dot then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center, Text = label })
	return b
end

-- a pill tag (auto width) in a row
local function tag(parent: Instance, name: string, order: number, colour: Color3, label: string, h: number?): TextLabel
	local t = text(parent, name, {
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h or 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
	})
	corner(t, 9)
	stroke(t, 2.5)
	pad(t, 10)
	if name == "Rarity" then
		new("UIGradient", { Name = "Foil", Rotation = 45, Enabled = false }, t) -- (the rarity's foil, set when shown)
	end
	return t
end

-- a heading with a muted line after it
local function titleRow(parent: Instance, x: number, y: number, title: string, info: string): Frame
	local r = new("Frame", { Name = "TitleRow", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(700, 30), BackgroundTransparency = 1 }, parent)
	row(r, 12)
	text(r, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), FontFace = HEAD, TextSize = 22, TextTruncate = Enum.TextTruncate.None, Text = title })
	text(r, "Info", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = info })
	return r
end

local function toggle(parent: Instance, name: string, x: number, y: number, label: string): TextButton
	local b = new("TextButton", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(236, 26), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, parent)
	local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(40, 24), BackgroundColor3 = TRACK }, b)
	corner(track, UDim.new(0.5, 0))
	stroke(track, 2.5)
	local knob = new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(15, 15), BackgroundColor3 = WHITE }, track)
	corner(knob, UDim.new(0.5, 0))
	stroke(knob, 2)
	text(b, "Label", { Position = UDim2.fromOffset(50, 0), Size = UDim2.fromOffset(186, 26), TextSize = 14, Text = label })
	return b
end

-- the coin + amount, in a row
local function price(parent: Instance, name: string, order: number, coin: number, size: number, font: Font?): Frame
	local f = new("Frame", { Name = name, LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, coin), BackgroundTransparency = 1 }, parent)
	row(f, math.max(4, coin // 4))
	icon(f, "Coin", COIN, coin, 1)
	text(f, "Amount", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, coin), FontFace = font or HEAD, TextSize = size, TextTruncate = Enum.TextTruncate.None, Text = "0" })
	return f
end

-- [[ Header ]]

local function header(root: Instance)
	local h = new("Frame", { Name = "Header", Size = UDim2.fromOffset(1280, 120), BackgroundTransparency = 1, ZIndex = 2 }, root)
	text(h, "Title", { Position = UDim2.fromOffset(40, 54), Size = UDim2.fromOffset(400, 36), FontFace = HEAD, TextSize = 30, TextColor3 = CREAM, Text = "Market" })
	text(h, "Sub", { Position = UDim2.fromOffset(40, 90), Size = UDim2.fromOffset(400, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = CREAM, TextTransparency = 0.4, Text = "Buy and sell photocards with other players" })

	local tabs = new("Frame", {
		Name = "Tabs",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(640, 58),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = CREAM,
		BackgroundTransparency = 0.9,
	}, h)
	corner(tabs, 14)
	new("UIStroke", { Color = CREAM, Transparency = 0.8, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tabs)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, tabs)
	row(tabs, 4)
	for i, name in Build.TABS do
		local b = new("TextButton", {
			Name = name,
			LayoutOrder = i,
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = CREAM,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
		}, tabs)
		corner(b, 10)
		new("UIStroke", { Color = INK, Thickness = 3, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14) }, b)
		row(b, 7)
		text(b, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), FontFace = BODY, TextSize = 16, TextColor3 = CREAM, Text = Build.TAB_NAMES[name], TextTruncate = Enum.TextTruncate.None })
		local badge = text(b, "Badge", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), BackgroundTransparency = 0, BackgroundColor3 = RED, TextColor3 = WHITE, FontFace = BODY, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Text = "1", Visible = false, TextTruncate = Enum.TextTruncate.None })
		corner(badge, 7)
		stroke(badge, 2)
		pad(badge, 5)
	end

	local bal = new("Frame", {
		Name = "Balance",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(1219 - 21 - 16, 81),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		BackgroundColor3 = CREAM,
		BackgroundTransparency = 0.9,
	}, h)
	corner(bal, 12)
	new("UIStroke", { Color = CREAM, Transparency = 0.8, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bal)
	pad(bal, 14)
	row(bal, 8)
	icon(bal, "Icon", COIN, 24, 1)
	text(bal, "Amount", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = HEAD, TextSize = 16, TextColor3 = CREAM, TextTruncate = Enum.TextTruncate.None, Text = "0" })

	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(1219 - 21, 81 - 21), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = INK }, h)
	corner(cs, 15)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(1219, 81), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, h)
	corner(close, 12)
	stroke(close, 3)
	local x = icon(close, "Icon", CLOSE_ICON, 16)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)
end

-- [[ Browse ]]

-- the RARITY filter's chips: every rarity (the Market takes them all), three rows
local RARITY_SPOTS = {
	standard = { 0, 0, 94 }, selca = { 100, 0, 66 }, store = { 172, 0, 64 },
	luckydraw = { 0, 36, 112 }, fansign = { 120, 36, 92 },
	polaroid = { 0, 72, 138 }, oneofone = { 146, 72, 90 },
}
function Build.RarityChips(f: Instance)
	local old = f:FindFirstChild("Rarities")
	if old then
		old:Destroy()
	end
	local rar = new("Frame", { Name = "Rarities", Position = UDim2.fromOffset(16, 92), Size = UDim2.fromOffset(236, 100), BackgroundTransparency = 1 }, f)
	for _, key in MarketConstants.RARITIES do
		local s = RARITY_SPOTS[key]
		chip(rar, key, s[1], s[2], s[3], Build.RARITY_NAMES[key], C(MarketConstants.RARITY_COLOURS[key]))
	end
	return rar
end

-- a built Market (only Lucky Draw and up) given every rarity: the chips, and what sits under
-- them moved down a row. Run once in Edit:
--   require(<this module>).AllRarities(game.StarterGui.Interface.Frames)
function Build.AllRarities(frames: Instance)
	local market = frames.Market
	local f = market.Pages.Browse.Filters
	local rar = Build.RarityChips(f)
	-- (centre-anchored, like every other built button: ButtonScale grows them from the middle)
	require(ReplicatedStorage.Modules.UI.CenterButtons).Apply(rar)
	if not f:GetAttribute("AllRarities") then
		f:SetAttribute("AllRarities", true)
		for _, name in { "GroupLab", "Group", "SortLab", "Sorts", "ShowLab", "NotOwned", "Bias", "GroupList" } do
			local g = f:FindFirstChild(name) :: GuiObject?
			if g then
				g.Position += UDim2.fromOffset(0, 36)
			end
		end
	end
	for _, d in market:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Lucky Draw and up · tap one to list it" then
			d.Text = "Any card · tap one to list it"
		elseif d:IsA("TextLabel") and d.Text == "No Lucky Draw-and-up cards yet. Open packs to find some!" then
			d.Text = "No cards to sell yet. Open packs to find some!"
		end
	end
end

-- a built Market given the rarity foils (the chips are rebuilt, the Rarity tags get a Foil). Run once in Edit:
--   require(<this module>).RarityFoils(game.StarterGui.Interface.Frames)
function Build.RarityFoils(frames: Instance)
	local market = frames.Market
	local f = market.Pages.Browse.Filters
	local old = f.Rarities
	local rar = Build.RarityChips(f)
	rar.Position, rar.Size = old.Position, old.Size
	require(ReplicatedStorage.Modules.UI.CenterButtons).Apply(rar)
	for _, d in market:GetDescendants() do
		if d.Name == "Rarity" and d:IsA("TextLabel") and not d:FindFirstChild("Foil") then
			new("UIGradient", { Name = "Foil", Rotation = 45, Enabled = false }, d)
		end
	end
end

local function filters(page: Instance)
	local f = card(page, "Filters", 40, 128, 268, 552, CREAM, 22, 8, 4)

	local search = new("Frame", { Name = "Search", Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(236, 42), BackgroundColor3 = WHITE }, f)
	corner(search, 12)
	stroke(search, 3)
	new("TextBox", {
		Name = "Input",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.fromOffset(212, 42),
		BackgroundTransparency = 1,
		FontFace = BODY,
		TextSize = 15,
		TextColor3 = INK,
		PlaceholderText = "Find a member or group",
		PlaceholderColor3 = MUTED,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, search)

	lab(f, "RarityLab", 16, 72, "RARITY")
	Build.RarityChips(f)

	lab(f, "GroupLab", 16, 208, "GROUP")
	local group = new("TextButton", { Name = "Group", Position = UDim2.fromOffset(16, 228), Size = UDim2.fromOffset(236, 42), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "" }, f)
	corner(group, 12)
	stroke(group, 3)
	text(group, "Label", { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(190, 42), TextSize = 15, Text = "All groups" })
	text(group, "Arrow", { Position = UDim2.fromOffset(206, 11), Size = UDim2.fromOffset(20, 20), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Rotation = 90, Text = "›" })

	lab(f, "SortLab", 16, 286, "SORT")
	local sorts = new("Frame", { Name = "Sorts", Position = UDim2.fromOffset(16, 306), Size = UDim2.fromOffset(236, 64), BackgroundTransparency = 1 }, f)
	local sortSpots = { Price = { 0, 0, 112 }, Newest = { 120, 0, 80 }, Rarest = { 0, 36, 76 }, Serial = { 84, 36, 96 } }
	for _, key in MarketConstants.SORTS do
		local s = sortSpots[key]
		chip(sorts, key, s[1], s[2], s[3], Build.SORT_NAMES[key])
	end

	lab(f, "ShowLab", 16, 386, "SHOW")
	toggle(f, "NotOwned", 16, 406, "Only cards I don't have")
	toggle(f, "Bias", 16, 440, "My bias's group")

	-- the group dropdown's list, over everything under it
	local list = new("Frame", { Name = "GroupList", Position = UDim2.fromOffset(16, 276), Size = UDim2.fromOffset(236, 290), BackgroundColor3 = WHITE, Visible = false, ZIndex = 10 }, f)
	corner(list, 12)
	stroke(list, 3)
	local scroll = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = INK,
		ZIndex = 10,
	}, list)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, scroll)
	local item = new("TextButton", { Name = "Item", Size = UDim2.new(1, -8, 0, 32), BackgroundColor3 = YELLOW, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 10 }, scroll)
	corner(item, 8)
	text(item, "Label", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -14, 1, 0), TextSize = 14, Text = "All groups", ZIndex = 10 })
end

local function tile(grid: Instance, i: number)
	local col, r = (i - 1) % 4, (i - 1) // 4
	local holder = new("Frame", { Name = `Tile{i}`, Position = UDim2.fromOffset(20 + col * 222, 58 + r * 238), Size = UDim2.fromOffset(206, 226), BackgroundTransparency = 1 }, grid)
	local face = card(holder, "Face", 0, 0, 206, 226, WHITE, 16, 5, 3)
	local pc = asTile(Photocard.Build(face, "Card", 96, 128))
	pc.Position = UDim2.fromOffset(55, 12)
	local nameRow = new("Frame", { Name = "NameRow", Position = UDim2.fromOffset(14, 148), Size = UDim2.fromOffset(180, 20), BackgroundTransparency = 1 }, face)
	row(nameRow, 6)
	text(nameRow, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = HEAD, TextSize = 15, TextTruncate = Enum.TextTruncate.None, Text = "Member" })
	local newTag = tag(nameRow, "New", 2, MINT, "NEW TO YOU", 16)
	newTag.TextSize = 10
	local np = newTag:FindFirstChildOfClass("UIPadding") :: UIPadding
	np.PaddingLeft, np.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
	local ns = newTag:FindFirstChildOfClass("UIStroke") :: UIStroke
	ns.Thickness = 2
	text(face, "Line", { Position = UDim2.fromOffset(14, 170), Size = UDim2.fromOffset(178, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "Group · Album · by seller" })
	local p = price(face, "Price", 0, 18, 15)
	p.Position = UDim2.fromOffset(14, 192)
	button(face, "View", 110, 184, 82, 32, CREAM, "VIEW", 13, 3)
end

local function grid(page: Instance)
	local g = card(page, "Grid", 332, 128, 908, 552, CREAM, 22, 8, 4)
	g.ClipsDescendants = false
	titleRow(g, 24, 14, "ON SALE", "")
	button(g, "Prev", 732, 12, 34, 34, WHITE, "‹", 18, 2)
	text(g, "PageText", { Position = UDim2.fromOffset(772, 12), Size = UDim2.fromOffset(76, 34), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = "1 / 1" })
	button(g, "Next", 854, 12, 34, 34, WHITE, "›", 18, 2)
	for i = 1, MarketConstants.PER_PAGE do
		tile(g, i)
	end
	text(g, "Empty", { Position = UDim2.fromOffset(0, 220), Size = UDim2.fromOffset(908, 60), FontFace = HEAD, TextSize = 18, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "Nothing on sale here yet", Visible = false })
end

-- [[ Sell ]]

local function sellCards(page: Instance)
	local p = card(page, "Cards", 40, 128, 600, 552, CREAM, 22, 8, 4)
	titleRow(p, 24, 14, "YOUR CARDS", "Any card · tap one to list it")
	local scroll = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(4, 52),
		Size = UDim2.fromOffset(592, 496),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = INK,
	}, p)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(120, 212), CellPadding = UDim2.fromOffset(16, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	new("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, scroll)
	local item = new("TextButton", { Name = "Item", Size = UDim2.fromOffset(120, 212), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false }, scroll)
	local ring = new("Frame", { Name = "Ring", Position = UDim2.fromOffset(-1, -1), Size = UDim2.fromOffset(122, 160), BackgroundTransparency = 1, Visible = false }, item)
	corner(ring, 14)
	stroke(ring, 4, RED)
	local pc = asTile(Photocard.Build(item, "Card", 112, 150))
	pc.Position = UDim2.fromOffset(4, 4)
	text(item, "Title", { Position = UDim2.fromOffset(0, 166), Size = UDim2.fromOffset(120, 18), FontFace = HEAD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = "Member" })
	text(item, "Line", { Position = UDim2.fromOffset(0, 184), Size = UDim2.fromOffset(120, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "Lucky Draw · ×2" })
	text(p, "Empty", { Position = UDim2.fromOffset(40, 220), Size = UDim2.fromOffset(520, 80), FontFace = HEAD, TextSize = 17, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "No cards to sell yet. Open packs to find some!", Visible = false })
end

local function helpRow(box: Instance, name: string, y: number, label: string)
	local r = new("Frame", { Name = name, Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(334, 22), BackgroundTransparency = 1 }, box)
	text(r, "Label", { Size = UDim2.fromOffset(180, 22), FontFace = BODY_BOLD, TextSize = 13, Text = label })
	text(r, "Value", { Position = UDim2.fromOffset(150, 0), Size = UDim2.fromOffset(184, 22), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Text = "–" })
end

local function sellForm(page: Instance)
	local p = card(page, "Form", 664, 128, 576, 552, CREAM, 22, 8, 4)
	text(p, "Title", { Position = UDim2.fromOffset(24, 18), Size = UDim2.fromOffset(400, 30), FontFace = HEAD, TextSize = 22, Text = "LIST A CARD" })
	text(p, "Pick", { Position = UDim2.fromOffset(40, 220), Size = UDim2.fromOffset(496, 80), FontFace = HEAD, TextSize = 17, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "Pick a card on the left to list it" })

	local body = new("Frame", { Name = "Body", Size = UDim2.fromOffset(576, 552), BackgroundTransparency = 1, Visible = false }, p)
	local pc = asTile(Photocard.Build(body, "Card", 150, 200))
	pc.Position = UDim2.fromOffset(24, 58)
	text(body, "Title", { Position = UDim2.fromOffset(194, 56), Size = UDim2.fromOffset(358, 26), FontFace = HEAD, TextSize = 20, Text = "Member" })
	text(body, "Line", { Position = UDim2.fromOffset(194, 82), Size = UDim2.fromOffset(358, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Group · Album · Rarity" })
	local chips = new("Frame", { Name = "Chips", Position = UDim2.fromOffset(194, 108), Size = UDim2.fromOffset(358, 28), BackgroundTransparency = 1 }, body)
	row(chips, 6)
	tag(chips, "Rarity", 1, PINK, "Fansign")
	local serial = tag(chips, "Serial", 2, INK, "#88 of 214")
	serial.TextColor3 = YELLOW
	tag(chips, "Copies", 3, WHITE, "Your only copy")
	local box = new("Frame", { Name = "Help", Position = UDim2.fromOffset(194, 148), Size = UDim2.fromOffset(358, 84), BackgroundColor3 = SAND }, body)
	corner(box, 12)
	stroke(box, 2.5)
	helpRow(box, "Lowest", 6, "Lowest on sale")
	helpRow(box, "Sales", 30, "Last 5 sold for")
	helpRow(box, "Game", 54, "Sell to the game")

	lab(body, "PriceLab", 24, 276, "YOUR PRICE")
	button(body, "Minus", 24, 298, 44, 44, WHITE, "−", 22, 3)
	local box2 = new("Frame", { Name = "Price", Position = UDim2.fromOffset(80, 296), Size = UDim2.fromOffset(416, 48), BackgroundColor3 = WHITE }, body)
	corner(box2, 12)
	stroke(box2, 3)
	row(box2, 8, Enum.HorizontalAlignment.Center)
	icon(box2, "Coin", COIN, 24, 1)
	new("TextBox", {
		Name = "Input",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1,
		FontFace = HEAD,
		TextSize = 22,
		TextColor3 = INK,
		Text = "0",
		ClearTextOnFocus = false,
	}, box2)
	button(body, "Plus", 508, 298, 44, 44, WHITE, "+", 22, 3)

	text(body, "Fee", { Position = UDim2.fromOffset(24, 356), Size = UDim2.fromOffset(200, 20), FontFace = BODY, TextSize = 13, TextColor3 = MUTED, Text = "Market fee 10%" })
	local get = new("Frame", { Name = "YouGet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(552, 356), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), BackgroundTransparency = 1 }, body)
	row(get, 6)
	text(get, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextSize = 13, TextTruncate = Enum.TextTruncate.None, Text = "you get" })
	price(get, "Amount", 2, 18, 13, BODY)

	lab(body, "DurLab", 24, 400, "LISTED FOR")
	local dur = new("Frame", { Name = "Hours", Position = UDim2.fromOffset(120, 393), Size = UDim2.fromOffset(300, 28), BackgroundTransparency = 1 }, body)
	local x = 0
	for _, h in MarketConstants.HOURS do
		local w = if h == 168 then 70 else 56
		chip(dur, tostring(h), x, 0, w, Build.HOUR_NAMES[h])
		x += w + 8
	end

	button(body, "List", 24, 438, 528, 52, MINT, "LIST CARD", 18, 4)
	text(body, "Note", { Position = UDim2.fromOffset(24, 500), Size = UDim2.fromOffset(528, 34), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "It leaves your binder (and your pins) while it's listed. Cancel any time, or it comes back when the time's up." })
end

-- [[ My listings ]] (design board "67 · Market · My listings details")

-- a summary card: its Label, Value (a coin + Amount when `coin`) and Sub line
local function stat(parent: Instance, name: string, x: number, w: number, colour: Color3, label: string, coin: boolean)
	local f = card(parent, name, x, 56, w, 76, colour, 14, 3, 3)
	text(f, "Label", { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(w - 28, 14), TextSize = 11, TextColor3 = MUTED, Text = label })
	if coin then
		local v = price(f, "Value", 0, 22, 22)
		v.Position = UDim2.fromOffset(14, 26)
	else
		text(f, "Value", { Position = UDim2.fromOffset(14, 24), Size = UDim2.fromOffset(w - 28, 28), FontFace = HEAD, TextSize = 24, RichText = true, Text = "0" })
	end
	text(f, "Sub", { Position = UDim2.fromOffset(14, 54), Size = UDim2.fromOffset(w - 28, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "" })
	return f
end

local function listings(page: Instance)
	local p = card(page, "Panel", 40, 128, 1200, 552, CREAM, 22, 8, 4)
	titleRow(p, 24, 14, "MY LISTINGS", "0 of 10 on sale")

	-- the summary strip + COLLECT ALL
	local stats = new("Frame", { Name = "Stats", Size = UDim2.fromOffset(1200, 140), BackgroundTransparency = 1 }, p)
	local sw = 228
	stat(stats, "OnSale", 24, sw, WHITE, "ON SALE", false)
	stat(stats, "Week", 24 + (sw + 12), sw, C("FFD2E5"), "SOLD THIS WEEK", false)
	stat(stats, "ToCollect", 24 + (sw + 12) * 2, sw, YELLOW, "TO COLLECT", true)
	stat(stats, "AllTime", 24 + (sw + 12) * 3, sw, C("D6EEFB"), "ALL TIME", true)
	button(stats, "CollectAll", 24 + (sw + 12) * 4, 56, 1176 - (24 + (sw + 12) * 4), 76, MINT, "COLLECT ALL", 18)

	-- your listings: sold first, then live ones
	local scroll = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(4, 146),
		Size = UDim2.fromOffset(776, 400),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = INK,
	}, p)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, scroll)
	new("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12) }, scroll)

	local holder = new("Frame", { Name = "Row", Size = UDim2.fromOffset(748, 98), BackgroundTransparency = 1, Visible = false }, scroll)
	local face = card(holder, "Face", 0, 0, 740, 92, WHITE, 14, 3, 3)
	local pc = asTile(Photocard.Build(face, "Card", 58, 76))
	pc.Position = UDim2.fromOffset(12, 8)
	text(face, "Title", { Position = UDim2.fromOffset(84, 9), Size = UDim2.fromOffset(300, 22), FontFace = HEAD, TextSize = 16, Text = "Member" })
	text(face, "Line", { Position = UDim2.fromOffset(84, 31), Size = UDim2.fromOffset(300, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "Group · Album · Rarity" })
	local chips = new("Frame", { Name = "Chips", Position = UDim2.fromOffset(84, 55), Size = UDim2.fromOffset(500, 24), BackgroundTransparency = 1 }, face)
	row(chips, 6)
	tag(chips, "Status", 1, C("FF9EC4"), "SOLD", 24)
	tag(chips, "Who", 2, WHITE, "to someone · 2 h ago", 24)
	local bar = new("Frame", { Name = "Bar", LayoutOrder = 3, Size = UDim2.fromOffset(110, 10), BackgroundColor3 = SAND }, chips)
	corner(bar, 5)
	stroke(bar, 2)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = MINT, BorderSizePixel = 0 }, bar)
	corner(fill, 5)
	tag(chips, "Rank", 4, SAND, "3rd cheapest", 24)
	local p1 = price(face, "Price", 0, 20, 18)
	p1.Position = UDim2.fromOffset(410, 18)
	text(face, "Get", { Position = UDim2.fromOffset(410, 44), Size = UDim2.fromOffset(170, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "you get 6,120" })
	button(face, "Action", 594, 25, 130, 42, CREAM, "CANCEL", 14, 3)

	text(p, "Empty", { Position = UDim2.fromOffset(40, 300), Size = UDim2.fromOffset(700, 80), FontFace = HEAD, TextSize = 17, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "Nothing on sale yet. List a card from the Sell tab.", Visible = false })

	-- ACTIVITY: the last 30 days, newest first
	local act = card(p, "Activity", 792, 152, 384, 384, WHITE, 14, 3, 3)
	text(act, "Label", { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(200, 16), TextSize = 12, TextColor3 = MUTED, Text = "ACTIVITY · LAST 30 DAYS" })
	local filt = new("Frame", { Name = "Filters", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(370, 7), Size = UDim2.fromOffset(150, 22), BackgroundTransparency = 1 }, act)
	row(filt, 4, Enum.HorizontalAlignment.Right)
	for i, name in Build.FEED_FILTERS do
		local fb = new("TextButton", { Name = name, LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundColor3 = if i == 1 then YELLOW else WHITE, AutoButtonColor = false, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = name }, filt)
		corner(fb, 7)
		stroke(fb, 2)
		pad(fb, 8)
	end
	local feed = new("ScrollingFrame", {
		Name = "Feed",
		Position = UDim2.fromOffset(6, 34),
		Size = UDim2.fromOffset(372, 344),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = INK,
	}, act)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, feed)
	local item = new("Frame", { Name = "Item", Size = UDim2.fromOffset(358, 46), BackgroundTransparency = 1, Visible = false }, feed)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -8, 0, 2), BackgroundColor3 = TRACK, BorderSizePixel = 0 }, item)
	local t = text(item, "Tag", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(78, 20), BackgroundTransparency = 0, BackgroundColor3 = C("FF9EC4"), TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, Text = "SOLD" })
	corner(t, 6)
	stroke(t, 2)
	text(item, "Text", { Position = UDim2.fromOffset(94, 7), Size = UDim2.fromOffset(186, 17), FontFace = BODY_BOLD, TextSize = 13, RichText = true, Text = "Hanni to <b>someone</b>" })
	text(item, "When", { Position = UDim2.fromOffset(94, 25), Size = UDim2.fromOffset(186, 14), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "2 h ago" })
	text(item, "Amount", { Position = UDim2.fromOffset(282, 0), Size = UDim2.fromOffset(72, 46), TextSize = 13, TextColor3 = C("2E8B57"), TextXAlignment = Enum.TextXAlignment.Right, Text = "+5,850" })
	local again = new("TextButton", { Name = "Again", Position = UDim2.fromOffset(282, 0), Size = UDim2.fromOffset(72, 46), BackgroundTransparency = 1, AutoButtonColor = false, FontFace = BODY, TextSize = 12, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Right, Text = "<u>List again</u>", RichText = true, Visible = false }, item)
	text(act, "None", { Position = UDim2.fromOffset(20, 150), Size = UDim2.fromOffset(344, 60), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "Nothing yet. Sales, listings and cards coming back show up here.", Visible = false })
end

-- rebuilds just Pages.Listings (the rest of the Market stays as it is)
function Build.MyListings(frames: Instance)
	local mineP = frames.Market.Pages.Listings
	for _, ch in mineP:GetChildren() do
		ch:Destroy()
	end
	listings(mineP)
	require(ReplicatedStorage.Modules.UI.CenterButtons).Apply(mineP)
	return mineP
end

-- [[ Card detail ]]

local function detail(root: Instance)
	local d = new("Frame", { Name = "Detail", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = 5 }, root)
	local dim = new("TextButton", {
		Name = "Dim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = C("141028"),
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, d)
	dim.Active = true
	local PX, PY, PW, PH = 170, 125, 940, 470
	local p = card(d, "Panel", PX, PY, PW, PH, CREAM, 22, 8, 4)

	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(PW - 18 - 42, 16), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = INK }, p)
	corner(cs, 15)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(PW - 39, 37), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, p)
	corner(close, 12)
	stroke(close, 3)
	local x = icon(close, "Icon", CLOSE_ICON, 16)
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.fromScale(0.5, 0.5)

	local pc = Photocard.Build(p, "Card", 260, 346)
	pc.Position = UDim2.fromOffset(28, 28)
	local under = new("Frame", { Name = "CardChips", Position = UDim2.fromOffset(28, 392), Size = UDim2.fromOffset(260, 30), BackgroundTransparency = 1 }, p)
	row(under, 6, Enum.HorizontalAlignment.Center)
	tag(under, "Rarity", 1, PINK, "Fansign")
	local serial = tag(under, "Serial", 2, INK, "#41 of 214")
	serial.TextColor3 = YELLOW

	text(p, "Title", { Position = UDim2.fromOffset(316, 24), Size = UDim2.fromOffset(520, 34), FontFace = HEAD, TextSize = 28, Text = "Member" })
	text(p, "Line", { Position = UDim2.fromOffset(316, 60), Size = UDim2.fromOffset(560, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, Text = "Group · Album · Rarity" })
	local tags = new("Frame", { Name = "Tags", Position = UDim2.fromOffset(316, 88), Size = UDim2.fromOffset(596, 28), BackgroundTransparency = 1 }, p)
	row(tags, 8)
	tag(tags, "New", 1, MINT, "New to you")
	tag(tags, "Earns", 2, WHITE, "Earns 105 an hour pinned")
	tag(tags, "Seller", 3, WHITE, "Seller: name · listed 3 h ago · 45 h left")

	-- last 5 sales
	local s = new("Frame", { Name = "Sales", Position = UDim2.fromOffset(316, 132), Size = UDim2.fromOffset(340, 158), BackgroundColor3 = WHITE }, p)
	corner(s, 14)
	stroke(s, 3)
	lab(s, "Lab", 14, 10, "LAST 5 SALES OF THIS CARD")
	local bars = new("Frame", { Name = "Bars", Position = UDim2.fromOffset(14, 32), Size = UDim2.fromOffset(312, 118), BackgroundTransparency = 1 }, s)
	for i = 1, Build.BARS do
		local b = new("Frame", { Name = `Bar{i}`, Position = UDim2.fromOffset((i - 1) * 64, 0), Size = UDim2.fromOffset(56, 118), BackgroundTransparency = 1 }, bars)
		local fill = new("Frame", { Name = "Fill", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(2, 82), Size = UDim2.fromOffset(52, 60), BackgroundColor3 = PINK }, b)
		corner(fill, 6)
		stroke(fill, 2.5)
		text(b, "Price", { Position = UDim2.fromOffset(0, 86), Size = UDim2.fromOffset(56, 14), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Text = "6,200" })
		text(b, "Ago", { Position = UDim2.fromOffset(0, 101), Size = UDim2.fromOffset(56, 13), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "2 d ago" })
	end
	text(s, "Empty", { Position = UDim2.fromOffset(14, 32), Size = UDim2.fromOffset(312, 118), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "No sales of this card yet", Visible = false })

	-- this copy's story
	local h = new("Frame", { Name = "Copy", Position = UDim2.fromOffset(672, 132), Size = UDim2.fromOffset(240, 158), BackgroundColor3 = WHITE }, p)
	corner(h, 14)
	stroke(h, 3)
	lab(h, "Lab", 14, 10, "THIS COPY")
	for i = 1, 3 do
		local r = new("Frame", { Name = `Row{i}`, Position = UDim2.fromOffset(14, 30 + (i - 1) * 40), Size = UDim2.fromOffset(212, 38), BackgroundTransparency = 1 }, h)
		new("Frame", { Name = "Rule", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C("CFC5B3"), BorderSizePixel = 0 }, r)
		text(r, "Left", { Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(150, 32), TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center, Text = "name listed it" })
		text(r, "Right", { Position = UDim2.fromOffset(150, 4), Size = UDim2.fromOffset(62, 32), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true, Text = "3 h ago" })
	end

	-- other copies
	local o = new("Frame", { Name = "Others", Position = UDim2.fromOffset(316, 304), Size = UDim2.fromOffset(596, 40), BackgroundColor3 = SAND }, p)
	corner(o, 12)
	stroke(o, 2.5)
	local ot = new("Frame", { Name = "Text", Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(460, 40), BackgroundTransparency = 1 }, o)
	row(ot, 6)
	text(ot, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextSize = 13, TextTruncate = Enum.TextTruncate.None, Text = "3 other copies on sale, from" })
	price(ot, "Min", 2, 18, 13, BODY)
	local see = new("TextButton", { Name = "See", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(584, 20), Size = UDim2.fromOffset(90, 30), BackgroundTransparency = 1, FontFace = BODY, TextSize = 13, TextColor3 = INK, RichText = true, Text = "<u>See them</u>", TextXAlignment = Enum.TextXAlignment.Right, AutoButtonColor = false }, o)
	see.ZIndex = 2

	-- price + buy
	lab(p, "PriceLab", 316, 364, "PRICE")
	local pr = price(p, "Price", 0, 30, 30)
	pr.Position = UDim2.fromOffset(316, 382)
	text(p, "After", { Position = UDim2.fromOffset(316, 418), Size = UDim2.fromOffset(170, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = "You'll have 0 left" })
	local buy = button(p, "Buy", 500, 368, 412, 62, MINT, "", 20, 4)
	local inner = new("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, buy)
	row(inner, 10, Enum.HorizontalAlignment.Center)
	text(inner, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), FontFace = HEAD, TextSize = 20, TextTruncate = Enum.TextTruncate.None, Text = "BUY FOR" })
	price(inner, "Amount", 2, 22, 20)
end

-- [[ Build ]]

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Market")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Market", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })

	-- the backdrop (a UIGradient multiplies the background colour, so the base is white)
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, root)
	scrim.Active = true
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, DARK_TOP),
			ColorSequenceKeypoint.new(0.41, DARK_TOP),
			ColorSequenceKeypoint.new(0.5, DARK_MID),
			ColorSequenceKeypoint.new(0.59, DARK_LOW),
			ColorSequenceKeypoint.new(1, DARK_LOW),
		}),
	}, scrim)

	header(root)
	local pages = new("Frame", { Name = "Pages", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1 }, root)
	local browse = new("Frame", { Name = "Browse", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1 }, pages)
	filters(browse)
	grid(browse)
	local sell = new("Frame", { Name = "Sell", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, pages)
	sellCards(sell)
	sellForm(sell)
	local mineP = new("Frame", { Name = "Listings", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, pages)
	listings(mineP)
	detail(root)

	root.Parent = frames
	-- centre every button's AnchorPoint so the ButtonScale tween grows from the middle
	require(ReplicatedStorage.Modules.UI.CenterButtons).Apply(root)
	return root
end

return Build
