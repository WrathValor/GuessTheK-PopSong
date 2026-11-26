--| HUD: the K-POPPED! layout
-- Reworks the lobby HUD (StarterGui.Interface.HUD) into design board "31 · HUD v2": run once in
-- Studio Edit mode from the command bar, then save the place:
--   require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.HUDController.BuildKPopped).Apply(game.StarterGui.Interface.HUD)
-- Safe to run again (it rebuilds what it made). It changes the HUD in place, so everything the
-- other controllers find by name (Wallet, Starter, Invite, News, nudges, boosts) keeps working:
--   Menu.Tiles   Inventory · Binder · PACKS (big, yellow) · Shop · Rewards, each with a drawn
--                icon and no icon box; Profile and Index tiles are gone (Profile is top right,
--                the Binder took over from the Index)
--   Buttons      a small Profile tile before Invite / News / Settings; on the right side below
--                them: your bias (Bias), the Event card and UGC (moved over from TopLeft)
--   TopLeft      Wins, Coins (+ wallet tab), then the Binder card: coins waiting, the rate an hour
--                from your pins, Collect, and your pins as tiny cards. Roll is hidden (packs
--                replaced the song roll).
-- HUDController fills and wires all of it.

local CardDecor = require(game:GetService("ReplicatedStorage").Modules.UI.CardDecor)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local PINK = C("FF9EC4")
local RED = C("FF5A4E")
local BLUE = C("9ED8F5")
local MUTED = C("5C566B")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

-- the drawn icons (assets/UI/HUD, uploaded to the group)
local ICONS = {
	Inventory = "rbxassetid://121456321096516",
	Binder = "rbxassetid://136348875254033",
	Packs = "rbxassetid://136335975977672",
	Shop = "rbxassetid://86939996907287",
	Rewards = "rbxassetid://79278999029622",
	UGC = "rbxassetid://92718922797751",
	Profile = "rbxassetid://100599141862206", -- an ID card (assets/UI/HUD/Profile.png)
}

local Build = {}

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
local function stroke(p: Instance, t: number, colour: Color3?)
	new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end
-- a sticker badge on a tile's corner ("2 FREE", "104 cards")
local function badge(parent: Instance, name: string, label: string, colour: Color3, rotation: number): TextLabel
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local b = text(parent, name, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 14, 0, -13),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		BackgroundTransparency = 0,
		BackgroundColor3 = colour,
		FontFace = BODY,
		TextSize = 12,
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Center,
		Rotation = rotation,
		ZIndex = 3,
		Visible = false,
	})
	b:SetAttribute("FitTextSkip", true)
	corner(b, 8)
	stroke(b, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, b)
	return b
end
local function shadowFor(button: GuiObject)
	local s = button.Parent:FindFirstChild(button.Name .. "Shadow")
	if s then
		local tl = button.Position - UDim2.fromScale(0, 0)
		local x = tl.X.Offset - button.AnchorPoint.X * button.Size.X.Offset + 4
		local y = tl.Y.Offset - button.AnchorPoint.Y * button.Size.Y.Offset + 4
		s.AnchorPoint = Vector2.zero
		s.Position = UDim2.fromOffset(x, y)
		s.Size = button.Size
	end
end

-- [[ The bottom tiles ]]

-- one tile: its drawn icon (no icon box), label, size and centre (inside Menu.Tiles)
local function tile(tiles: Instance, name: string, from: string, label: string, cx: number, cy: number, w: number, h: number, colour: Color3, big: boolean?)
	local t = tiles:FindFirstChild(name)
	if not t then
		t = tiles[from]:Clone()
		t.Name = name
		t.Parent = tiles
		local s = tiles[from .. "Shadow"]:Clone()
		s.Name = name .. "Shadow"
		s.Parent = tiles
		for _, extra in { "Badge", "Sale" } do
			local e = t:FindFirstChild(extra)
			if e then
				e:Destroy()
			end
		end
	end
	-- (a shadow is drawn under its button: siblings draw in child order, so the button goes last)
	t.Parent = nil
	t.Parent = tiles
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromOffset(cx, cy)
	t.Size = UDim2.fromOffset(w, h)
	t.BackgroundColor3 = colour
	t.UIStroke.Thickness = if big then 4 else 3
	shadowFor(t)
	local shadow = tiles[name .. "Shadow"]
	if big then
		shadow.Position += UDim2.fromOffset(2, 2) -- (a deeper drop for the main one)
	end
	-- the icon comes out of its box
	local box = t:FindFirstChild("IconBox")
	local icon = t:FindFirstChild("Icon") or (box and box:FindFirstChild("Icon"))
	if box then
		box.Visible = false
	end
	if icon then
		icon.Parent = t
		icon.Image = ICONS[name]
		icon.ImageRectOffset = Vector2.zero
		icon.ImageRectSize = Vector2.zero
		icon.ScaleType = Enum.ScaleType.Fit
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Size = if big then UDim2.fromOffset(64, 56) else UDim2.fromOffset(50, 48)
		icon.Position = UDim2.fromOffset(w / 2, if big then 40 else 36)
		icon.BackgroundTransparency = 1
		icon.ZIndex = 2
	end
	local l = t.Label
	l.Text = label
	l.Size = UDim2.fromOffset(w, 20)
	l.Position = UDim2.fromOffset(0, if big then h - 34 else h - 30)
	l.FontFace = if big then HEAD else BODY
	l.TextSize = if big then 18 else 13
	return t
end

local function tiles(menu: Instance)
	local ts = menu.Tiles
	ts.Position = UDim2.fromOffset(340, 564)
	ts.Size = UDim2.fromOffset(600, 96)
	-- Inventory · Binder · PACKS · Shop · Rewards (Packs in the middle, bottoms in line)
	tile(ts, "Inventory", "Inventory", "Inventory", 51, 48, 100, 96, WHITE)
	tile(ts, "Binder", "Inventory", "Binder", 163, 48, 100, 96, WHITE)
	tile(ts, "Packs", "Inventory", "PACKS", 300, 41, 140, 110, YELLOW, true)
	tile(ts, "Shop", "Shop", "Shop", 437, 48, 100, 96, WHITE)
	tile(ts, "Rewards", "Rewards", "Rewards", 549, 48, 100, 96, WHITE)
	badge(ts.Packs, "Free", "2 FREE", RED, 7)
	badge(ts.Binder, "Count", "0 cards", MINT, 6)
	if ts.Shop:FindFirstChild("Sale") then
		ts.Shop.Sale.Position = UDim2.new(1, -30, 0, -12)
	end
	if ts.Rewards:FindFirstChild("Badge") then
		ts.Rewards.Badge.Position = UDim2.new(1, -16, 0, -12)
	end
	-- Profile moved top right; the Binder took over from the Index
	for _, gone in { "Profile", "ProfileShadow", "Index", "IndexShadow" } do
		local g = ts:FindFirstChild(gone)
		if g then
			g:Destroy()
		end
	end
end

-- [[ Top right: Invite, and the right-hand column (your bias, Event, Profile + UGC) ]]

local function buttons(hud: Instance)
	local b = hud.Buttons

	-- your bias: a tilted mini photocard, name, group, the bias bonus (opens the bias picker)
	local old = b:FindFirstChild("Bias")
	if old then
		old:Destroy()
	end
	local oldS = b:FindFirstChild("BiasShadow")
	if oldS then
		oldS:Destroy()
	end
	local bs = new("Frame", { Name = "BiasShadow", Position = UDim2.fromOffset(1086, 236), Size = UDim2.fromOffset(178, 86), BackgroundColor3 = INK }, b)
	corner(bs, 12)
	local bias = new("TextButton", { Name = "Bias", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(1171, 275), Size = UDim2.fromOffset(178, 86), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, b)
	corner(bias, 12)
	stroke(bias, 3)
	local card = new("Frame", { Name = "Card", Position = UDim2.fromOffset(10, 11), Size = UDim2.fromOffset(46, 62), Rotation = -4, BackgroundColor3 = WHITE }, bias)
	corner(card, 6)
	stroke(card, 2)
	local art = new("ImageLabel", { Name = "Art", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundColor3 = C("FFD2E5"), ScaleType = Enum.ScaleType.Crop, Image = "" }, card)
	corner(art, 4)
	stroke(art, 1.5)
	text(bias, "Label", { Position = UDim2.fromOffset(66, 10), Size = UDim2.fromOffset(104, 12), TextSize = 10, TextColor3 = MUTED, Text = "MY BIAS" })
	local name = text(bias, "Member", { Position = UDim2.fromOffset(66, 23), Size = UDim2.fromOffset(104, 20), FontFace = HEAD, TextSize = 16, Text = "YEJI", RichText = true, TextTruncate = Enum.TextTruncate.AtEnd })
	name:SetAttribute("FitTextSkip", true)
	text(bias, "Group", { Position = UDim2.fromOffset(66, 43), Size = UDim2.fromOffset(104, 14), TextSize = 12, Text = "ITZY", TextTruncate = Enum.TextTruncate.AtEnd })
	local chip = text(bias, "Bonus", { Position = UDim2.fromOffset(66, 60), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = PINK, TextSize = 10, Text = "2× PULLS · 1.5× COINS" })
	chip:SetAttribute("FitTextSkip", true)
	corner(chip, 6)
	stroke(chip, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, chip)

	-- the Event card and UGC move over from TopLeft, under your bias
	local topLeft = hud.TopLeft
	for _, n in { "Event", "EventShadow", "UGC", "UGCShadow" } do
		local g = topLeft:FindFirstChild(n)
		if g then
			g.Parent = b
		end
	end
	if b:FindFirstChild("Event") then
		b.Event.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Event.Position = UDim2.fromOffset(1171, 420) -- (under the Profile + UGC row; shown only while an event is live)
		shadowFor(b.Event)
	end
	if b:FindFirstChild("UGC") then
		local u = b.UGC
		u.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Profile + UGC: one row right under your bias card (bias card ends at y 318)
		u.Size = UDim2.fromOffset(74, 44)
		u.Position = UDim2.fromOffset(1223, 352)
		u.Label.Position = UDim2.fromOffset(40, 0)
		u.Label.Size = UDim2.new(1, -46, 1, 0)
		u.Chip.BackgroundTransparency = 1
		u.Chip.UIStroke.Enabled = false
		u.Chip.Icon.Image = ICONS.UGC
		u.Chip.Icon.ImageRectOffset = Vector2.zero
		u.Chip.Icon.ImageRectSize = Vector2.zero
		u.Chip.Icon.Size = UDim2.fromOffset(28, 28)
		shadowFor(u)

		-- Profile: a pill like UGC, beside it (left), not a tile in the top-right row
		for _, gone in { "Profile", "ProfileShadow" } do
			local g = b:FindFirstChild(gone)
			if g then
				g:Destroy()
			end
		end
		local p = u:Clone()
		p.Name = "Profile"
		local tag = p:FindFirstChild("New")
		if tag then
			tag:Destroy()
		end
		p.Label.Text = "Profile"
		p.Chip.Icon.Image = ICONS.Profile
		p.Chip.Icon.Size = UDim2.fromOffset(28, 28)
		p.Size = UDim2.fromOffset(96, 44)
		p.Position = UDim2.fromOffset(1130, 352)
		local ps = b.UGCShadow:Clone()
		ps.Name = "ProfileShadow"
		ps.Parent = b
		p.Parent = b -- (after its shadow, so it draws on top)
		shadowFor(p)
	end

	-- Invite: back to a blue pill with its label, left of News + Settings (its +300 / CLAIM tags
	-- stay on the bottom edge)
	local inv = b:FindFirstChild("Invite")
	if inv then
		inv.AnchorPoint = Vector2.new(0.5, 0.5)
		inv.Size = UDim2.fromOffset(108, 44)
		inv.Position = UDim2.fromOffset(1098, 40) -- (right edge 10 px left of News)
		inv.BackgroundColor3 = BLUE
		inv.Icon.AnchorPoint = Vector2.new(0, 0.5)
		inv.Icon.Position = UDim2.new(0, 12, 0.5, 0)
		inv.Icon.Size = UDim2.fromOffset(26, 26)
		local label = inv:FindFirstChild("Label")
		if not label and b:FindFirstChild("UGC") then
			label = b.UGC.Label:Clone()
			label.Parent = inv
		end
		if label then
			label.Text = "Invite"
			label.Position = UDim2.fromOffset(44, 0)
			label.Size = UDim2.new(1, -52, 1, 0)
		end
		local s = b:FindFirstChild("InviteShadow")
		if s then
			s.Parent = nil
			s.Parent = b
			inv.Parent = nil
			inv.Parent = b -- (over its shadow)
		end
		shadowFor(inv)
	end
end

-- [[ Top left: the Binder card ]]

local function binderCard(hud: Instance)
	local topLeft = hud.TopLeft
	for _, n in { "Binder", "BinderShadow" } do
		local g = topLeft:FindFirstChild(n)
		if g then
			g:Destroy()
		end
	end
	-- (the song roll is gone: packs replaced it)
	for _, n in { "Roll", "RollShadow" } do
		local g = topLeft:FindFirstChild(n)
		if g then
			g.Visible = false
		end
	end
	-- (below the coins card's wallet tab, which hangs under it)
	local s = new("Frame", { Name = "BinderShadow", Position = UDim2.fromOffset(24, 378), Size = UDim2.fromOffset(178, 96), BackgroundColor3 = INK }, topLeft)
	corner(s, 12)
	local card = new("TextButton", { Name = "Binder", Position = UDim2.fromOffset(20, 374), Size = UDim2.fromOffset(178, 96), BackgroundColor3 = WHITE, Text = "", AutoButtonColor = false }, topLeft)
	card:SetAttribute("NoButtonScale", true)
	corner(card, 12)
	stroke(card, 3)
	new("ImageLabel", { Name = "Icon", Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(34, 32), BackgroundTransparency = 1, Image = ICONS.Binder, ScaleType = Enum.ScaleType.Fit }, card)
	text(card, "Label", { Position = UDim2.fromOffset(48, 10), Size = UDim2.fromOffset(80, 12), TextSize = 10, TextColor3 = MUTED, Text = "BINDER · 0/HR" })
	local amount = text(card, "Amount", { Position = UDim2.fromOffset(48, 22), Size = UDim2.fromOffset(80, 22), FontFace = HEAD, TextSize = 19, Text = "+0" })
	amount:SetAttribute("FitTextSkip", true)
	local collect = new("TextButton", { Name = "Collect", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(141, 26), Size = UDim2.fromOffset(58, 32), BackgroundColor3 = YELLOW, FontFace = BODY, TextSize = 13, TextColor3 = INK, Text = "Collect", AutoButtonColor = false }, card)
	corner(collect, 10)
	stroke(collect, 3)
	local pins = new("Frame", { Name = "Pins", Position = UDim2.fromOffset(10, 52), Size = UDim2.fromOffset(160, 36), BackgroundTransparency = 1 }, card)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, pins)
	for i = 1, 5 do
		local p = new("Frame", { Name = "Pin" .. i, LayoutOrder = i, Size = UDim2.fromOffset(24, 34), BackgroundColor3 = WHITE }, pins)
		corner(p, 4)
		stroke(p, 2)
		local a = new("ImageLabel", { Name = "Art", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = C("FFD2E5"), ScaleType = Enum.ScaleType.Crop, Image = "" }, p)
		corner(a, 2)
		-- an empty or locked slot
		local e = new("Frame", { Name = "Empty", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.94, Visible = false }, p)
		corner(e, 4)
		text(e, "Mark", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 14, TextColor3 = MUTED, Text = "+", TextXAlignment = Enum.TextXAlignment.Center })
		CardDecor.BuildMini(p) -- the rarity's frame (gold, holo, cosmic rim)
	end
	text(card, "Hint", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(170, 55), Size = UDim2.fromOffset(40, 30), TextSize = 10, TextColor3 = MUTED, Text = "", TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true, Visible = false })
end

function Build.Apply(hud: Instance)
	buttons(hud)
	tiles(hud.Menu)
	binderCard(hud)
	return hud
end

return Build
