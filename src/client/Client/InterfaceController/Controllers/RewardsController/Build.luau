--| Rewards UI builder
-- Builds Interface.Frames.Rewards from the "Rewards — Level rewards" + "Rewards — Quests" boards
-- (Song Index Redesign canvas): salmon header with a "n ready to claim" chip, then one scrolling
-- body of four sections, top to bottom (Content has a UIListLayout; RewardsController sizes the
-- Quests section to its row count):
--   Levels  – level chip + XP bar, ‹ page › + CLAIM ALL, a track with a node per card, six level
--             cards (LV n, state chip, its one reward: art + amount, CLAIM / ✓ CLAIMED)
--   Quests  – Daily | Weekly tabs (with ready badges), reset chip, up to 4 quest rows (icon tile,
--             title + hint, progress bar, reward chips, CLAIM / ✓ CLAIMED / SWAP QUEST), bonus bar
--   Daily   – daily login: streak chip, track with 7 dots, 7 shorter day cards
--   Group   – the one-time group card
-- Every picture is the game's own: the shop's coin pile, the currency icons (Constants/
-- Currencies), the season icon sheet (SeasonConstants.ICONS) and the UI atlas (gtks_atlas0).
-- Claim buttons follow the Season Track: mint CLAIM, cream ✓ CLAIMED, same size.
-- Run once in Studio (an existing frame is kept as ServerStorage.Rewards_Legacy):
--   require(<this module>).Build(game.StarterGui.Interface.Frames)
-- RewardsController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local SALMON = C("FFD2CE")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local PALE = C("FFF6D6")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)

local CLOSE_ICON = "rbxassetid://118345756178429"
local COIN = Currencies.Coins.Icon -- same coin as the HUD + shop
local COIN_STACK = "rbxassetid://83386580979392" -- one thick coin, side-on (the shop's bundle art)
local ATLAS = "rbxassetid://87950570350196" -- gtks_atlas0
local LILAC = C("B9A6FF")
local SAND = C("F3EEE5") -- ✓ CLAIMED buttons

local Build = {}
Build.DAYS = 7
Build.QUESTS = 3 -- daily quests
Build.QUEST_ROWS = 4 -- rows built (weekly has 4)
Build.LEVEL_CARDS = 6
Build.ROW_H, Build.ROW_GAP = 78, 12
Build.ATLAS = ATLAS
-- the icons the controller paints with (all already in the game)
Build.ICONS = {
	Coins = COIN,
	Tickets = Currencies.Tickets.Icon,
	Upgrades = Currencies.Upgrades.Icon,
	Pile = ShopCatalog.CoinBundles[2].Pile, -- the shop's coin pile (the Season Track's coin art)
	Title = SeasonConstants.ICONS.Title,
	XP = SeasonConstants.ICONS.XP,
	Daily = SeasonConstants.ICONS.Daily,
	Weekly = SeasonConstants.ICONS.Weekly,
}
-- quest icon per stat: a season icon, or a cell in the UI atlas ({ image, rect offset })
Build.QUEST_ICONS = {
	Correct = { SeasonConstants.ICONS.Correct },
	Wins = { SeasonConstants.ICONS.Win },
	BestRun = { SeasonConstants.ICONS.Streak },
	Duels = { SeasonConstants.ICONS.Duel },
	Solo = { SeasonConstants.ICONS.Solo },
	Perfect = { SeasonConstants.ICONS.Perfect },
	NewSongs = { ATLAS, Vector2.new(0, 200) }, -- i_cards
	DailySong = { SeasonConstants.ICONS.Daily }, -- (until it has its own icon)
}
Build.QUEST_TILE = { Correct = "9ED8F5", Wins = "FFB38A", BestRun = "FFD2CE", Duels = "B9A6FF", Solo = "A7E9B8", Perfect = "FFE07A", NewSongs = "DCD3FF", DailySong = "FF9EC4" }
Build.REWARD_CHIP = { Coins = "FFE07A", Tickets = "FF9EC4", Upgrades = "A7E9B8", XP = "DCD3FF" }
Build.ART_BG = { Coins = "FFE07A", Tickets = "DCD3FF", Upgrades = "9ED8F5", Title = "CDEBFA" }
-- each day card shows one pile of coins, one coin taller per day (2 on day 1 … 8 on day 7),
-- each coin nudged a little left/right like the original design
Build.MAX_STACKS = 8
Build.DAY_STACKS = { 2, 3, 4, 5, 6, 7, 8 }
Build.COIN_W, Build.COIN_H, Build.COIN_STEP = 50, 30, 8

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

local function pad(p: Instance, l: number, r: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l) }, p)
end

local function row(parent: Instance, gap: number)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
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

local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

local function pill(parent: Instance, name: string, label: string, colour: Color3, order: number?): TextLabel
	local c = text(parent, name, {
		LayoutOrder = order or 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
	})
	corner(c, UDim.new(0.5, 0))
	stroke(c, 2)
	pad(c, 12)
	return c
end

local function button(parent: Instance, name: string, pos: UDim2, size: UDim2, label: string): TextButton
	local b = new("TextButton", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = INK,
		FontFace = HEAD,
		TextSize = 14,
		TextColor3 = YELLOW,
		Text = label,
		AutoButtonColor = false,
	}, parent)
	corner(b, 10)
	stroke(b, 2)
	return b
end

local function heading(parent: Instance, name: string, y: number, title: string): Frame
	local h = new("Frame", { Name = name, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, parent)
	row(h, 10)
	text(h, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), FontFace = HEAD, TextSize = 22, TextTruncate = Enum.TextTruncate.None, Text = title })
	return h
end

-- [[ Group reward card: the three rewards as small photocards (coins, the real group stage
-- model via CosmeticView, the title tag), then the text and the Claim button ]]
local COIN_ICON = require(game:GetService("ReplicatedStorage").Constants.Currencies).Coins.Icon

local function tile(parent: Instance, name: string, x: number, w: number, colour: Color3): Frame
	local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + 3, 12 + 3), Size = UDim2.fromOffset(w, 96), BackgroundColor3 = INK }, parent)
	corner(s, 10)
	local t = new("Frame", { Name = name, Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(w, 96), BackgroundColor3 = colour, ClipsDescendants = false }, parent)
	corner(t, 10)
	stroke(t, 2)
	return t
end

-- (Re)builds the reward tiles + text on the Group card; keeps the Claim button. Safe twice.
function Build.GroupRewards(group: Instance)
	for _, n in { "Art", "CoinsTile", "CoinsTileShadow", "StageTile", "StageTileShadow", "TitleTile", "TitleTileShadow", "GroupTitle", "Sub" } do
		local old = group:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local coins = tile(group, "CoinsTile", 16, 90, C("FFF6D6"))
	new("ImageLabel", { Name = "Coin", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 1, Image = COIN_ICON, ScaleType = Enum.ScaleType.Fit }, coins)
	text(coins, "Amount", { Position = UDim2.new(0, 0, 1, -32), Size = UDim2.new(1, 0, 0, 24), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Text = "500" })

	local stage = tile(group, "StageTile", 116, 126, C("4A3F78"))
	stage.ClipsDescendants = false
	local art = new("Frame", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C("4A3F78"), ClipsDescendants = true }, stage)
	corner(art, 10)
	local chip = text(stage, "Exclusive", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(84, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		FontFace = HEAD,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "EXCLUSIVE",
		ZIndex = 5,
	})
	corner(chip, 6)
	stroke(chip, 2)

	local title = tile(group, "TitleTile", 252, 104, C("DCD3FF"))
	local tag = text(title, "Tag", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(88, 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Supporter",
		Rotation = -4,
	})
	corner(tag, 8)
	stroke(tag, 2)

	local tx = 252 + 104 + 22
	text(group, "GroupTitle", { Position = UDim2.fromOffset(tx, 34), Size = UDim2.new(1, -tx - 180, 0, 24), FontFace = HEAD, TextSize = 18, Text = "3 free rewards for joining" })
	text(group, "Sub", { Position = UDim2.fromOffset(tx, 62), Size = UDim2.new(1, -tx - 180, 0, 34), FontFace = BODY_BOLD, TextSize = 13, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "500 coins, the Group Exclusive stage and the Supporter title. Join our Roblox group, then claim. One time only." })
end

-- a reward chip: a pastel pill with the currency icon in its left padding (RewardsController
-- sets the colour, icon and "+75")
local function rewardChip(parent: Instance, name: string, order: number, h: number): TextLabel
	local c = text(parent, name, {
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
		BackgroundTransparency = 0,
		BackgroundColor3 = YELLOW,
		FontFace = HEAD,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.None,
		Text = "+100",
	})
	corner(c, 10)
	stroke(c, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, h + 2), PaddingRight = UDim.new(0, 10) }, c)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -h + 4, 0.5, 0), Size = UDim2.fromOffset(h - 8, h - 8), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit }, c)
	return c
end

-- Season Track claim button: mint CLAIM; RewardsController turns it cream for ✓ CLAIMED
local function claimButton(parent: Instance, name: string, pos: UDim2, size: UDim2): TextButton
	local b = new("TextButton", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = MINT,
		FontFace = HEAD,
		TextSize = 14,
		TextColor3 = INK,
		Text = "CLAIM",
		AutoButtonColor = false,
	}, parent)
	corner(b, 9)
	stroke(b, 3)
	return b
end

local function smallChip(parent: Instance, name: string, pos: UDim2, h: number, colour: Color3, label: string, anchor: Vector2?): TextLabel
	local c = text(parent, name, {
		AnchorPoint = anchor or Vector2.zero,
		Position = pos,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.None,
		Text = label,
	})
	corner(c, math.floor(h * 0.36))
	stroke(c, 2)
	pad(c, 7)
	return c
end

local function section(content: Instance, name: string, order: number, h: number): Frame
	return new("Frame", { Name = name, LayoutOrder = order, Size = UDim2.fromOffset(Build.W, h), BackgroundTransparency = 1 }, content)
end

Build.W = 980
Build.LEVEL_W, Build.LEVEL_GAP, Build.LEVEL_H = 150, 16, 226

-- [[ Level rewards ]]
local function levelsSection(content: Instance)
	local W = Build.W
	local s = section(content, "Levels", 1, 78 + Build.LEVEL_H + 6 + 26)
	local h = heading(s, "Heading", 0, "Level rewards")
	h.Size = UDim2.fromOffset(560, 34)
	local lv = pill(h, "LevelChip", "LV 1", YELLOW, 2)
	lv.FontFace = HEAD
	local xp = new("Frame", { Name = "XPBar", LayoutOrder = 3, Size = UDim2.fromOffset(150, 14), BackgroundColor3 = WHITE, ClipsDescendants = true }, h)
	corner(xp, 7)
	stroke(xp, 2)
	local xf = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = LILAC, BorderSizePixel = 0 }, xp)
	corner(xf, 5)
	text(h, "XPText", { LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "0 / 100 XP" })

	local pager = new("Frame", { Name = "Pager", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(420, 34), BackgroundTransparency = 1 }, s)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pager)
	for i, spec in { { "Prev", "‹" }, { "Next", "›" } } do
		local b = new("TextButton", { Name = spec[1], LayoutOrder = if i == 1 then 1 else 3, Size = UDim2.fromOffset(34, 32), BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = 20, TextColor3 = INK, Text = spec[2], AutoButtonColor = false }, pager)
		corner(b, 9)
		stroke(b, 3)
	end
	text(pager, "Page", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "Levels 2–12 · 1/5" })
	local all = claimButton(pager, "ClaimAll", UDim2.new(), UDim2.fromOffset(124, 32))
	all.LayoutOrder = 4
	all.Text = "CLAIM ALL"
	all.TextSize = 13

	-- the track: a line through the card centres, a node per card
	local cw, gap = Build.LEVEL_W, Build.LEVEL_GAP
	local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(0, 44), Size = UDim2.fromOffset(W, 24), BackgroundTransparency = 1 }, s)
	local line = new("Frame", { Name = "Line", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, cw / 2, 0.5, 0), Size = UDim2.new(1, -cw, 0, 8), BackgroundColor3 = WHITE }, track)
	corner(line, 4)
	stroke(line, 2)
	local fill = new("Frame", { Name = "Fill", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, cw / 2, 0.5, 0), Size = UDim2.fromOffset(300, 8), BackgroundColor3 = LILAC }, track)
	corner(fill, 4)
	stroke(fill, 2)
	for i = 1, Build.LEVEL_CARDS do
		local n = new("Frame", { Name = "Node" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, (i - 1) * (cw + gap) + cw / 2, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = WHITE, ZIndex = 2 }, track)
		corner(n, UDim.new(0.5, 0))
		stroke(n, 3)
	end

	local cards = new("Frame", { Name = "Cards", Position = UDim2.fromOffset(0, 78), Size = UDim2.fromOffset(W, Build.LEVEL_H + 6), BackgroundTransparency = 1 }, s)
	for i = 1, Build.LEVEL_CARDS do
		local holder = new("Frame", { Name = "Card" .. i, Position = UDim2.fromOffset((i - 1) * (cw + gap), 0), Size = UDim2.fromOffset(cw, Build.LEVEL_H), BackgroundTransparency = 1 }, cards)
		local sh = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0, Visible = false }, holder)
		corner(sh, 14)
		local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE }, holder)
		corner(face, 14)
		stroke(face, 3)
		text(face, "Number", { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(60, 22), FontFace = HEAD, TextSize = 16, Text = "LV 2" })
		smallChip(face, "State", UDim2.new(1, -8, 0, 9), 20, WHITE, "LOCKED", Vector2.new(1, 0))
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 38), Size = UDim2.new(1, -20, 0, 92), BackgroundColor3 = YELLOW, ClipsDescendants = true }, face)
		corner(art, 10)
		stroke(art, 3)
		-- coins: the shop's coin pile (drawn big, anchored on the coins like the Season Track)
		new("ImageLabel", { Name = "Pile", AnchorPoint = Vector2.new(0.5, 0.64), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(150, 150), BackgroundTransparency = 1, Image = Build.ICONS.Pile, ScaleType = Enum.ScaleType.Fit }, art)
		-- tickets / upgrades: the currency icon
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(70, 70), BackgroundTransparency = 1, Image = Build.ICONS.Tickets, ScaleType = Enum.ScaleType.Fit, Visible = false }, art)
		-- title levels: your name with the title chip under it, like the Inventory
		local ta = new("Frame", { Name = "TitleArt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, art)
		text(ta, "Player", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -2), Size = UDim2.new(1, -10, 0, 20), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Text = "Player" })
		local tc = text(ta, "Chip", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 3), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundTransparency = 0, BackgroundColor3 = YELLOW, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "Rookie" })
		corner(tc, 6)
		stroke(tc, 2)
		pad(tc, 8)
		new("UIGradient", { Name = "Rainbow", Rotation = 20, Enabled = false }, tc) -- animated titles (TierShine)
		text(face, "Amount", { Position = UDim2.fromOffset(10, 136), Size = UDim2.new(1, -20, 0, 24), FontFace = HEAD, TextSize = 20, Text = "50" })
		text(face, "Kind", { Position = UDim2.fromOffset(10, 160), Size = UDim2.new(1, -20, 0, 16), TextSize = 13, TextColor3 = MUTED, Text = "coins" })
		claimButton(face, "Claim", UDim2.new(0, 10, 1, -10 - 30), UDim2.new(1, -20, 0, 30))
	end
end

-- [[ Quests ]]

-- Places the rows + bonus for `rows` quests and sizes the section (RewardsController calls it
-- when the tab changes: daily has 3, weekly 4).
function Build.LayoutQuests(s: Instance, rows: number)
	local rowsH = rows * Build.ROW_H + (rows - 1) * Build.ROW_GAP
	for i = 1, Build.QUEST_ROWS do
		local r = s.Rows:FindFirstChild("Row" .. i)
		local sh = s.Rows:FindFirstChild("Row" .. i .. "Shadow")
		if r then
			r.Visible = i <= rows
		end
		if sh then
			sh.Visible = i <= rows
		end
	end
	s.Rows.Size = UDim2.fromOffset(Build.W, rowsH + 4)
	-- (anchor-aware: the claim punch re-anchors the bar to its centre, Rewards.settle)
	local bonus = s.Bonus
	local a, size = bonus.AnchorPoint, bonus.Size
	bonus.Position = UDim2.new(size.X.Scale * a.X, size.X.Offset * a.X, size.Y.Scale * a.Y, 46 + rowsH + 16 + size.Y.Offset * a.Y)
	s.Size = UDim2.fromOffset(Build.W, 46 + rowsH + 16 + 72 + 4 + 26)
end

local function questsSection(content: Instance)
	local W = Build.W
	local s = section(content, "Quests", 2, 400)
	local h = heading(s, "Heading", 0, "Quests")
	h.Size = UDim2.fromOffset(W, 34)
	local tabs = new("Frame", { Name = "Tabs", LayoutOrder = 2, Size = UDim2.fromOffset(240, 34), BackgroundTransparency = 1 }, h)
	row(tabs, 8)
	for i, spec in { { "Daily", "DAILY" }, { "Weekly", "WEEKLY" } } do
		local t = new("TextButton", { Name = spec[1], LayoutOrder = i, Size = UDim2.fromOffset(112, 34), BackgroundColor3 = if i == 1 then INK else WHITE, FontFace = HEAD, TextSize = 13, TextColor3 = if i == 1 then YELLOW else INK, Text = spec[2], AutoButtonColor = false }, tabs)
		corner(t, 10)
		stroke(t, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 30), PaddingRight = UDim.new(0, 8) }, t)
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -24, 0.5, 0), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = Build.ICONS[spec[1]], ScaleType = Enum.ScaleType.Fit }, t)
		local badge = text(t, "Badge", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 8, 0, 0), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0, BackgroundColor3 = RED, TextColor3 = WHITE, FontFace = HEAD, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Text = "1", ZIndex = 3, Visible = false })
		corner(badge, UDim.new(0.5, 0))
		stroke(badge, 2)
	end
	local reset = pill(h, "Reset", "Resets in 5h 18m", WHITE, 3)
	corner(reset, 8)
	text(h, "Note", { LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "One free swap a day." })

	local RW = W - 4
	local rows = new("Frame", { Name = "Rows", Position = UDim2.fromOffset(0, 46), Size = UDim2.fromOffset(W, 300), BackgroundTransparency = 1 }, s)
	for i = 1, Build.QUEST_ROWS do
		local r = card(rows, "Row" .. i, UDim2.fromOffset(0, (i - 1) * (Build.ROW_H + Build.ROW_GAP)), UDim2.fromOffset(RW, Build.ROW_H), WHITE, 14, 4, 3)
		local tileF = new("Frame", { Name = "Tile", Position = UDim2.fromOffset(13, 12), Size = UDim2.fromOffset(54, 54), BackgroundColor3 = C("9ED8F5") }, r)
		corner(tileF, 12)
		stroke(tileF, 3)
		new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(38, 38), BackgroundTransparency = 1, Image = SeasonConstants.ICONS.Win, ScaleType = Enum.ScaleType.Fit }, tileF)
		text(r, "QuestTitle", { Position = UDim2.fromOffset(82, 14), Size = UDim2.fromOffset(290, 24), FontFace = HEAD, TextSize = 16, Text = "Quest" })
		text(r, "Hint", { Position = UDim2.fromOffset(82, 40), Size = UDim2.fromOffset(290, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Hint" })
		-- bar, count and reward chips share the row's centre line
		local bar = new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 390, 0.5, 0), Size = UDim2.fromOffset(186, 14), BackgroundColor3 = WHITE, ClipsDescendants = true }, r)
		corner(bar, 7)
		stroke(bar, 2)
		local f = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, bar)
		corner(f, 5)
		text(r, "Progress", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 586, 0.5, 0), Size = UDim2.fromOffset(62, 20), TextSize = 14, Text = "1 / 2" })
		local rewards = new("Frame", { Name = "Rewards", Position = UDim2.fromOffset(660, 0), Size = UDim2.fromOffset(164, Build.ROW_H), BackgroundTransparency = 1 }, r)
		row(rewards, 8)
		rewardChip(rewards, "Chip1", 1, 30)
		rewardChip(rewards, "Chip2", 2, 30)
		claimButton(r, "Claim", UDim2.new(1, -14 - 128, 0.5, -16), UDim2.fromOffset(128, 32))
		local swap = new("TextButton", { Name = "Swap", Position = UDim2.new(1, -14 - 128, 0.5, -16), Size = UDim2.fromOffset(128, 32), BackgroundColor3 = WHITE, FontFace = BODY, TextSize = 13, TextColor3 = INK, Text = "SWAP QUEST", AutoButtonColor = false, Visible = false }, r)
		corner(swap, 9)
		stroke(swap, 3)
	end

	local bonus = new("Frame", { Name = "Bonus", Position = UDim2.fromOffset(0, 330), Size = UDim2.fromOffset(RW, 72), BackgroundColor3 = PALE }, s)
	corner(bonus, 14)
	stroke(bonus, 3)
	text(bonus, "BonusTitle", { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(420, 22), FontFace = HEAD, TextSize = 15, Text = "BONUS · finish all 3 quests" })
	-- a pip per quest (filled as they're claimed), then "1 of 3 claimed"
	local pipsF = new("Frame", { Name = "Pips", Position = UDim2.fromOffset(16, 40), Size = UDim2.fromOffset(420, 20), BackgroundTransparency = 1 }, bonus)
	row(pipsF, 7)
	for i = 1, Build.QUEST_ROWS do
		local p = new("Frame", { Name = "Pip" .. i, LayoutOrder = i, Size = UDim2.fromOffset(14, 14), BackgroundColor3 = WHITE }, pipsF)
		corner(p, UDim.new(0.5, 0))
		stroke(p, 2)
	end
	local sub = text(pipsF, "Sub", { LayoutOrder = 10, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "1 of 3 claimed" })
	new("UIPadding", { PaddingLeft = UDim.new(0, 4) }, sub)
	local br = new("Frame", { Name = "Rewards", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14 - 128 - 14, 0, 0), Size = UDim2.fromOffset(260, 72), BackgroundTransparency = 1 }, bonus)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, br)
	rewardChip(br, "Chip1", 1, 30)
	rewardChip(br, "Chip2", 2, 30)
	rewardChip(br, "Chip3", 3, 30) -- (the daily bonus: coins, an upgrade + XP)
	claimButton(bonus, "Claim", UDim2.new(1, -14 - 128, 0.5, -16), UDim2.fromOffset(128, 32))

	Build.LayoutQuests(s, Build.QUESTS)
end

-- [[ Daily login ]]
local function dailySection(content: Instance)
	local W = Build.W
	local CH = 204
	local s = section(content, "Daily", 3, 86 + CH + 4 + 26)
	local dh = heading(s, "Heading", 0, "Daily login")
	local streak = pill(dh, "Streak", "Streak: day 3", WHITE, 2)
	streak.Size = UDim2.fromOffset(0, 30)
	text(dh, "Note", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.None, Text = "Miss a day and it resets." })

	local dayW = (W - 6 * 12) / Build.DAYS
	local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(dayW / 2, 44 + 9), Size = UDim2.fromOffset(W - dayW, 12), BackgroundColor3 = WHITE, ClipsDescendants = true }, s)
	corner(track, 6)
	stroke(track, 2)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0.33, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, track)
	corner(fill, 4)
	local dots = new("Frame", { Name = "Dots", Position = UDim2.fromOffset(0, 44), Size = UDim2.fromOffset(W, 30), BackgroundTransparency = 1 }, s)
	for i = 1, Build.DAYS do
		local d = new("Frame", { Name = "Dot" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((i - 1) * (dayW + 12) + dayW / 2, 15), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = WHITE }, dots)
		corner(d, UDim.new(0.5, 0))
		stroke(d, 3)
	end

	local days = new("Frame", { Name = "Days", Position = UDim2.fromOffset(0, 86), Size = UDim2.fromOffset(W, CH + 6), BackgroundTransparency = 1 }, s)
	for i = 1, Build.DAYS do
		local x = (i - 1) * (dayW + 12)
		local holder = new("Frame", { Name = "Day" .. i, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(dayW - 4, CH), BackgroundTransparency = 1 }, days)
		local glow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 12, 1, 12), BackgroundColor3 = YELLOW, Visible = false }, holder)
		corner(glow, 20)
		local face = card(holder, "Face", UDim2.new(), UDim2.fromScale(1, 1), C("EDE4D4"), 16, 4, 3)
		text(face, "DayLabel", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 18), FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = `DAY {i}` })
		local coins = new("Frame", { Name = "Coins", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(64, 88), BackgroundTransparency = 1 }, face)
		for k = 1, Build.MAX_STACKS do
			-- same wobble as the design's ovals: alternate 3px, every third coin back 3px
			local cx = 7 + ((k - 1) % 2) * 3 - (if (k - 1) % 3 == 2 then 3 else 0)
			new("ImageLabel", {
				Name = "Stack" .. k,
				Position = UDim2.new(0, cx, 1, -Build.COIN_H - (k - 1) * Build.COIN_STEP),
				Size = UDim2.fromOffset(Build.COIN_W, Build.COIN_H),
				BackgroundTransparency = 1,
				Image = COIN_STACK, -- one thick coin, side-on
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = k, -- higher coins draw on top
				Visible = k <= Build.DAY_STACKS[i],
			}, coins)
		end
		text(face, "Amount", { Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 22), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "50" })
		local unit = new("Frame", { Name = "Unit", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 143), Size = UDim2.fromOffset(56, 14), BackgroundTransparency = 1 }, face)
		new("ImageLabel", { Name = "Coin", Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Image = COIN }, unit)
		text(unit, "Label", { Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(38, 14), TextSize = 12, Text = "coins" })
		claimButton(face, "Claim", UDim2.new(0, 8, 1, -10 - 30), UDim2.new(1, -16, 0, 30))
		if i == Build.DAYS then
			local big = text(holder, "Big", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 10, 0, -14),
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 22),
				BackgroundTransparency = 0,
				BackgroundColor3 = RED,
				TextSize = 11,
				TextTruncate = Enum.TextTruncate.None,
				Rotation = 8,
				Text = "BIG!",
				ZIndex = 10,
			})
			corner(big, 8)
			stroke(big, 2)
			pad(big, 7)
		end
	end
end

-- [[ Group reward ]]
local function groupSection(content: Instance)
	local W = Build.W
	local s = section(content, "GroupReward", 4, 42 + 120 + 4 + 6)
	heading(s, "Heading", 0, "Group reward")
	local group = card(s, "Group", UDim2.fromOffset(0, 42), UDim2.fromOffset(W - 4, 120), MINT, 16, 4, 3)
	Build.GroupRewards(group)
	local gs = new("Frame", { Name = "ClaimShadow", Position = UDim2.new(1, -20 - 140 + 4, 0.5, -25 + 4), Size = UDim2.fromOffset(140, 50), BackgroundColor3 = RED }, group)
	corner(gs, 12)
	local gb = button(group, "Claim", UDim2.new(1, -20 - 140, 0.5, -25), UDim2.fromOffset(140, 50), "CLAIM")
	gb.TextSize = 16
	gb:FindFirstChildOfClass("UIStroke").Thickness = 3
end

-- The claim toast ("Claim toast · 3 options" board, option A): a white strip at the bottom with a
-- mint tick, "Claimed!" + where it came from, every reward with its icon, and a pink bar that
-- runs out. The small claims use it (one quest, the daily login, one level, the group reward).
-- Items holds the rewards; the controller clones ItemTemplate / TitleTemplate / StreakTemplate.
-- Safe to run again on a built frame:
--   require(<this module>).ClaimToast(game.StarterGui.Interface.Frames.Rewards)
Build.TOAST_W, Build.TOAST_H = 460, 74
function Build.ClaimToast(root: Instance)
	local old = root:FindFirstChild("ClaimToast")
	if old then
		old:Destroy()
	end
	local holder = new("Frame", {
		Name = "ClaimToast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(640, 700),
		Size = UDim2.fromOffset(Build.TOAST_W, Build.TOAST_H),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
	}, root)
	local shadow = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 20 }, holder)
	corner(shadow, 16)
	local face = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 21 }, holder)
	corner(face, 16)
	stroke(face, 3)

	local tick = new("Frame", { Name = "Tick", Position = UDim2.fromOffset(12, 13), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = MINT, ZIndex = 22 }, face)
	corner(tick, UDim.new(0.5, 0))
	stroke(tick, 3)
	text(tick, "Mark", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 22, Text = "✓", TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 23 })

	local top = new("Frame", { Name = "Top", Position = UDim2.fromOffset(68, 9), Size = UDim2.fromOffset(Build.TOAST_W - 82, 20), BackgroundTransparency = 1, ZIndex = 22 }, face)
	row(top, 8)
	text(top, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = HEAD, TextSize = 15, Text = "Claimed!", TextTruncate = Enum.TextTruncate.None, ZIndex = 22 })
	text(top, "Source", { LayoutOrder = 2, Size = UDim2.new(1, -90, 0, 20), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Quest · Win 3 duels", ZIndex = 22 })

	local items = new("Frame", { Name = "Items", Position = UDim2.fromOffset(68, 33), Size = UDim2.fromOffset(Build.TOAST_W - 82, 26), BackgroundTransparency = 1, ZIndex = 22 }, face)
	row(items, 12)

	-- a currency or stage: icon + "+150" (or the stage's name)
	local item = new("Frame", { Name = "ItemTemplate", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundTransparency = 1, Visible = false, ZIndex = 22 }, face)
	row(item, 5)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit, ZIndex = 22 }, item)
	text(item, "Amount", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), FontFace = HEAD, TextSize = 15, Text = "+150", TextTruncate = Enum.TextTruncate.None, ZIndex = 22 })

	-- a title: "TITLE" + the chip (TitleChip.Paint colours it)
	local title = new("Frame", { Name = "TitleTemplate", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), BackgroundTransparency = 1, Visible = false, ZIndex = 22 }, face)
	row(title, 5)
	text(title, "Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), FontFace = BODY, TextSize = 11, TextColor3 = MUTED, Text = "TITLE", TextTruncate = Enum.TextTruncate.None, ZIndex = 22 })
	local chip = text(title, "Chip", {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundTransparency = 0,
		BackgroundColor3 = MINT,
		FontFace = HEAD,
		TextSize = 12,
		Text = "Rookie",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 22,
	})
	corner(chip, 8)
	stroke(chip, 2)
	pad(chip, 9)
	new("UIGradient", { Name = "Rainbow", Enabled = false }, chip)

	-- the daily login's streak pill
	local streak = new("Frame", { Name = "StreakTemplate", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundColor3 = C("FFE4D0"), Visible = false, ZIndex = 22 }, face)
	corner(streak, UDim.new(0.5, 0))
	stroke(streak, 2)
	pad(streak, 8)
	row(streak, 4)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = SeasonConstants.ICONS.Streak, ScaleType = Enum.ScaleType.Fit, ZIndex = 23 }, streak)
	text(streak, "Days", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), FontFace = BODY, TextSize = 12, Text = "4 day streak", TextTruncate = Enum.TextTruncate.None, ZIndex = 23 })

	-- the bar that runs out while it's up: a rounded pill inside the card (ClipsDescendants
	-- doesn't follow the card's round corners, so it can't run edge to edge)
	local bar = new("Frame", { Name = "Timer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -6), Size = UDim2.new(1, -24, 0, 5), BackgroundColor3 = C("FF9EC4"), BorderSizePixel = 0, ZIndex = 22 }, face)
	corner(bar, UDim.new(0.5, 0))
	return holder
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Rewards")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("Rewards_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "Rewards_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "Rewards", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
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

	local PW, PH = 1040, 620
	local panel = card(root, "Panel", UDim2.fromOffset(120, 50), UDim2.fromOffset(PW, PH), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true

	-- header
	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = SALMON, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	local titleRow = new("Frame", { Name = "TitleRow", Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(500, 64), BackgroundTransparency = 1 }, header)
	row(titleRow, 12)
	text(titleRow, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), FontFace = HEAD, TextSize = 26, TextTruncate = Enum.TextTruncate.None, Text = "REWARDS" })
	pill(titleRow, "Ready", "3 ready to claim", MINT, 2)
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(PW - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, header)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(PW - 14 - 21, 32), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, header)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = CLOSE_ICON }, close)

	-- scrolling body: the sections stack in Content (UIListLayout); the canvas follows
	local body = new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 67),
		Size = UDim2.new(1, 0, 1, -67),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = INK,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
	}, panel)
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(Build.W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, body)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }, content)
	new("UIPadding", { PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 14) }, content)

	levelsSection(content)
	questsSection(content)
	dailySection(content)
	groupSection(content)

	-- toast
	local toast = text(root, "Toast", {
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
		ZIndex = 20,
	})
	corner(toast, 10)
	pad(toast, 16)
	Build.ClaimToast(root)

	root.Parent = frames
	require(game:GetService("ReplicatedStorage").Modules.UI.CenterButtons).Apply(root)
	return root
end

return Build
