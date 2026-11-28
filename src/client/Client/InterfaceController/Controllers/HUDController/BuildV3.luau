--| HUD: v3 layout
-- Reworks the lobby HUD (StarterGui.Interface.HUD) into design board "54 · HUD v3": run once in
-- Studio Edit mode from the command bar, then save the place:
--   local m = game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.HUDController.BuildV3
--   local c = m:Clone(); c.Parent = m.Parent; require(c).Apply(game.StarterGui.Interface.HUD); c:Destroy()
-- Safe to run again (it rebuilds what it made). The pieces it replaces (Wins, Coins + wallet,
-- Season, the Binder card, Bias, Event, UGC, the old Profile button, Menu.Tiles) move to
-- ServerStorage.OldHUD, so nothing is lost. Quick Play and the level bar keep their looks: only
-- where they sit changes (and the level bar is as wide as Quick Play).
--   TopLeft   the Shop banner (SALE chip), a 2 × 2 grid (Binder +coins chip, Packs free count,
--             Market NEW chip, Quests count), then the Daily Rewards pill (count)
--   Buttons   Invite · News (Updates) · Settings as small icon-only squares top right; Profile
--             and Gifts tiles down the right side
--   Menu      the coins on a dark band that fades out at both ends, Quick Play, the level bar
--   BottomLeft the running boost potions (Coins / XP / Luck) with their time left
-- HUDController fills and wires all of it.

local ServerStorage = game:GetService("ServerStorage")

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local PINK = C("FF9EC4")
local RED = C("FF5A4E")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

-- the drawn icons (assets/UI/HUD/v3, uploaded to the group)
local ICONS = {
	Shop = "rbxassetid://135341060709651", -- a basket with a photocard and a pack
	Binder = "rbxassetid://117698097103164",
	Packs = "rbxassetid://91499562174663",
	Market = "rbxassetid://108322757402267",
	Quests = "rbxassetid://76532358558493",
	Daily = "rbxassetid://107374560329984",
	Profile = "rbxassetid://135371002855223",
	Gifts = "rbxassetid://119916041465663",
	Invite = "rbxassetid://136138562502098",
	News = "rbxassetid://90269034577955", -- a megaphone (Updates)
	Settings = "rbxassetid://104886311749989",
}
local COIN = "rbxassetid://105055420801588" -- the HUD coin

-- each tile's two gradient colours (light top-left, deeper bottom-right)
local TILE_COLOURS = {
	Shop = { "FFC2BC", "FF5A4E" },
	Binder = { "FFD2E3", "FF9EC4" },
	Packs = { "FFF0B8", "FFD25E" },
	Market = { "FFE2D6", "FFB38A" },
	Quests = { "D9F7E2", "7FD99A" },
	Daily = { "EAE2FF", "B9A6FF" },
	Profile = { "E5DCFF", "B9A6FF" },
	Gifts = { "D6F0FC", "8FCFF0" },
}

local TILE = 74 -- a square tile
local SHADOW = 4 -- tile shadow offset
local LEFT_X, LEFT_Y = 24, 170 -- the left column's top-left (TopLeft canvas)
local RIGHT_X, RIGHT_Y = 1186, 178 -- the right column's top-left (Buttons canvas)

local Build = {}

-- the names this build makes (marked V3 once made)
local MADE = {}
for _, n in { "Shop", "Binder", "Packs", "Market", "Quests", "Daily", "Profile", "Gifts", "Invite", "Coins" } do
	MADE[n] = true
	MADE[n .. "Shadow"] = true
end

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
local function gradient(p: Instance, key: string)
	local c = TILE_COLOURS[key]
	new("UIGradient", { Color = ColorSequence.new(C(c[1]), C(c[2])), Rotation = 70 }, p)
end
-- white heavy text with an ink outline (the tiles' labels)
local function outlined(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = HEAD,
		TextColor3 = WHITE,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, parent)
	for k, v in props do
		(l :: any)[k] = v
	end
	new("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	return l
end
local function shadowFor(button: GuiObject, offset: number, r: number)
	local s = new("Frame", {
		Name = button.Name .. "Shadow",
		AnchorPoint = button.AnchorPoint,
		Position = UDim2.fromOffset(button.Position.X.Offset + offset, button.Position.Y.Offset + offset),
		Size = button.Size,
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex - 1,
	}, button.Parent)
	corner(s, r)
	return s
end
-- a small chip on a tile's top edge (top right): "+412", "SALE", "NEW"
local function chip(parent: Instance, name: string, text: string, colour: Color3)
	local c = new("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -10),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = colour,
		FontFace = BODY,
		TextSize = 11,
		TextColor3 = INK,
		Text = text,
		ZIndex = 4,
	}, parent)
	corner(c, 6)
	stroke(c, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, c)
	return c
end
-- a red count bubble on a tile's top-right corner
local function count(parent: Instance, x: number?)
	local b = new("TextLabel", {
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, x or -7, 0, 2),
		Size = UDim2.fromOffset(22, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = RED,
		FontFace = HEAD,
		TextSize = 12,
		TextColor3 = WHITE,
		Text = "1",
		Visible = false,
		ZIndex = 5,
	}, parent)
	corner(b, 11)
	stroke(b, 2.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, b)
	return b
end
-- (pos is the top-left corner; the button is anchored at its centre so ButtonScale grows it from the middle)
local function button(parent: Instance, name: string, pos: Vector2, size: Vector2, r: number): TextButton
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y / 2),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
	}, parent)
	corner(b, r)
	stroke(b, 3)
	return b
end
-- a square tile: gradient, big icon, outlined label at the bottom
local function tile(parent: Instance, name: string, label: string, x: number, y: number): TextButton
	local t = button(parent, name, Vector2.new(x, y), Vector2.new(TILE, TILE), 14)
	gradient(t, name)
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1,
		Image = ICONS[name],
		ZIndex = 3,
	}, t)
	outlined(t, "Label", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, 0, 0, 14), Text = label, ZIndex = 3 })
	shadowFor(t, SHADOW, 14)
	return t
end
-- a small cream square, icon only (top right)
local function square(parent: Instance, name: string, centreX: number): TextButton
	local b = button(parent, name, Vector2.new(centreX - 22, 40 - 22), Vector2.new(44, 44), 12) -- (centred on centreX, 40 like News / Settings)
	b.BackgroundColor3 = CREAM
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Image = ICONS[name],
		ZIndex = 3,
	}, b)
	shadowFor(b, 3, 12)
	return b
end
local function dot(parent: Instance, name: string)
	local d = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = RED,
		Visible = false,
		ZIndex = 5,
	}, parent)
	corner(d, 7)
	stroke(d, 2)
	return d
end

-- moves a finished-with instance (and its shadow) to ServerStorage.OldHUD/<group>
local function retire(group: Instance, name: string)
	local old = ServerStorage:FindFirstChild("OldHUD") or new("Folder", { Name = "OldHUD" }, ServerStorage)
	local into = old:FindFirstChild(group.Name) or new("Folder", { Name = group.Name }, old)
	for _, n in { name, name .. "Shadow" } do
		local inst = group:FindFirstChild(n)
		if inst and not inst:GetAttribute("V3") then
			local prev = into:FindFirstChild(n)
			if prev then
				prev:Destroy()
			end
			inst.Parent = into
		end
	end
end
local function clear(group: Instance, name: string)
	for _, n in { name, name .. "Shadow" } do
		local inst = group:FindFirstChild(n)
		if inst and inst:GetAttribute("V3") then
			inst:Destroy()
		end
	end
end

function Build.Apply(hud: Instance)
	local topLeft, buttons, menu = hud:FindFirstChild("TopLeft"), hud:FindFirstChild("Buttons"), hud:FindFirstChild("Menu")
	assert(topLeft and buttons and menu, "BuildV3: HUD needs TopLeft, Buttons and Menu")

	-- [[ out with the old ]]
	for _, n in { "Wins", "Coins", "Wallet", "WalletSink", "Season", "Binder", "Roll", "UGC", "NewDrop" } do
		retire(topLeft, n)
	end
	for _, n in { "Bias", "Event", "UGC", "Profile", "Invite" } do
		retire(buttons, n)
	end
	retire(menu, "Tiles")
	-- (a rebuild: the v3 pieces made last time)
	for _, n in { "Shop", "Binder", "Packs", "Market", "Quests", "Daily" } do
		clear(topLeft, n)
	end
	for _, n in { "Gifts", "Profile", "Invite" } do
		clear(buttons, n)
	end
	clear(menu, "Coins")
	local bottomLeft = hud:FindFirstChild("BottomLeft")
	if bottomLeft then
		bottomLeft.Visible = true -- (the running potions: HUDController/Boosts)
	end

	-- [[ TopLeft: Shop banner, 2 × 2 grid, Daily Rewards ]]
	local shop = button(topLeft, "Shop", Vector2.new(LEFT_X, LEFT_Y), Vector2.new(TILE * 2 + 10, 60), 14)
	gradient(shop, "Shop")
	count(shop) -- coin upgrades you can afford (SetShopBadge)
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundTransparency = 1,
		Image = ICONS.Shop,
		ZIndex = 3,
	}, shop)
	outlined(shop, "Label", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 62, 0.5, 0),
		Size = UDim2.fromOffset(86, 26),
		TextSize = 22,
		Text = "Shop",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	chip(shop, "Sale", "SALE", YELLOW)
	shadowFor(shop, SHADOW, 14)

	local row1, row2 = LEFT_Y + 60 + 12, LEFT_Y + 60 + 12 + TILE + 12
	local binder = tile(topLeft, "Binder", "Binder", LEFT_X, row1)
	chip(binder, "Waiting", "+0", YELLOW).Visible = false
	local packs = tile(topLeft, "Packs", "Packs", LEFT_X + TILE + 10, row1)
	count(packs)
	local market = tile(topLeft, "Market", "Market", LEFT_X, row2)
	chip(market, "New", "NEW", MINT)
	count(market) -- sales to collect + ended listings (SetMarketBadge)
	local quests = tile(topLeft, "Quests", "Quests", LEFT_X + TILE + 10, row2)
	count(quests)

	local daily = button(topLeft, "Daily", Vector2.new(LEFT_X, row2 + TILE + 12), Vector2.new(TILE * 2 + 10, 44), 12)
	gradient(daily, "Daily")
	new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 1,
		Image = ICONS.Daily,
		ZIndex = 3,
	}, daily)
	outlined(daily, "Label", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 44, 0.5, 0),
		Size = UDim2.fromOffset(108, 18),
		TextSize = 13,
		Text = "Daily Rewards",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	count(daily, -2)
	shadowFor(daily, SHADOW, 12)

	-- [[ Buttons: Invite · News · Settings (top right), Profile + Gifts (right side) ]]
	local news, settings = buttons:FindFirstChild("News"), buttons:FindFirstChild("Settings")
	for _, b in { news, settings } do
		if b then
			b.BackgroundColor3 = CREAM
			local icon = b:FindFirstChild("Icon")
			if icon then
				icon.Image = ICONS[b.Name]
				icon.ImageRectSize = Vector2.zero -- (the old icons were cut from a sheet)
				icon.ImageRectOffset = Vector2.zero
				icon.Size = UDim2.fromOffset(30, 30)
			end
		end
	end
	local newsX = if news then news.Position.X.Offset else 1184
	local invite = square(buttons, "Invite", newsX - 54)
	dot(invite, "ClaimBadge") -- (InviteController: a friend's reward to claim)

	tile(buttons, "Profile", "Profile", RIGHT_X, RIGHT_Y)
	local gifts = tile(buttons, "Gifts", "Gifts", RIGHT_X, RIGHT_Y + TILE + 12)
	count(gifts)

	-- [[ Menu: coins band, Quick Play, the level bar ]]
	local quick, quickShadow = menu:FindFirstChild("QuickPlay"), menu:FindFirstChild("QuickPlayShadow")
	local bar, barShadow = menu:FindFirstChild("XPBar"), menu:FindFirstChild("XPBarShadow")
	local barY = if bar then bar.Position.Y.Offset else 674
	local quickY = barY - 46 -- Quick Play's centre: its bottom 12 above the level bar's outline
	if quick then
		quick.Position = UDim2.fromOffset(640, quickY)
	end
	if quickShadow then
		quickShadow.Position = UDim2.fromOffset(640 - 180 + 6, quickY - 28 + 6)
	end
	if bar then
		bar.Size = UDim2.fromOffset(360, bar.Size.Y.Offset)
		bar.Position = UDim2.fromOffset(640 - 180, barY)
	end
	if barShadow and bar then
		barShadow.Size = UDim2.fromOffset(360, bar.Size.Y.Offset)
		barShadow.Position = UDim2.fromOffset(640 - 180 + 4, barY + 4)
	end

	local coins = new("TextButton", {
		Name = "Coins",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, quickY - 28 - 3 - 8 - 15),
		Size = UDim2.fromOffset(300, 30),
		BackgroundColor3 = C("0E0B1A"),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
	}, menu)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.28, 0.3),
			NumberSequenceKeypoint.new(0.72, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, coins)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, coins)
	local amount = new("TextLabel", {
		Name = "Amount",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = HEAD,
		TextSize = 19,
		TextColor3 = YELLOW,
		Text = "0",
		ZIndex = 3,
	}, coins)
	new("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, amount)
	new("ImageLabel", {
		Name = "Icon",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Image = COIN,
		ZIndex = 3,
	}, coins)

	-- everything made here is marked, so a rebuild replaces it (and never retires it)
	for _, group in { topLeft, buttons, menu } do
		for _, child in group:GetChildren() do
			if MADE[child.Name] then
				child:SetAttribute("V3", true)
			end
		end
	end
	return true
end

return Build
