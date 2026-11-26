-- ------------------------------ Full screen ------------------------------- --
-- Design board "61 · Style (full screen)": the Banners frame becomes a full-screen screen like
-- the Shop, Quests and Market. A dark backdrop, "Style" + its line top left (40, 54 / 90),
-- Sets · Banners · Photocards tabs top centre (Header.Tabs: on = cream with an outline), MORE IN
-- THE SHOP (Header.Shop: the Shop's Profile style tab) and ✕ top right; the preview on a cream
-- page on the left (your profile card, bigger), the grid on a cream page on the right with its
-- heading (Panel.PageHead: the tab's name + Owned) and the pager. Only what you own is listed
-- (BannersController). Run once in Edit, after Build.Banners (again = same result):
--   local m = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("SeasonController", true).Build
--   local c = m:Clone(); c.Parent = m.Parent; require(c).BannersFullScreen(game.StarterGui.Interface.Frames); c:Destroy()

local FS_DARK_TOP, FS_DARK_MID, FS_DARK_LOW = C("3B2F66"), C("2A2340"), C("221C36")
local FS_PREVIEW = { 40, 128, 380, 552 } -- x, y, w, h
local FS_PAGE = { 444, 128, 796, 552 }
Build.STYLE_TILE_W = 179 -- (the grids' tiles: 4 across the page)

-- a cream page with a hard shadow grown by its outline (UIStroke draws outside the frame)
local function fsPage(parent: Instance, name: string, spec: { number }): Frame
	for _, n in { name, name .. "Shadow" } do
		local old = parent:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local x, y, w, h = spec[1], spec[2], spec[3], spec[4]
	local line, drop = 4, 8
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + drop - line, y + drop - line), Size = UDim2.fromOffset(w + line * 2, h + line * 2), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 0 }, parent)
	corner(shadow, 22 + line)
	local page = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = CREAM, BorderSizePixel = 0, ZIndex = 0 }, parent)
	corner(page, 22)
	new("UIStroke", { Color = INK, Thickness = line, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, page)
	return page
end

function Build.BannersFullScreen(frames: Instance)
	local root = frames:FindFirstChild("Banners")
	assert(root, "build the Banners frame first (Build.Banners)")

	-- backdrop: a UIGradient multiplies the colour, so the base is white
	local scrim = root.Scrim
	scrim.BackgroundColor3 = WHITE
	scrim.BackgroundTransparency = 0
	local g = scrim:FindFirstChildOfClass("UIGradient") or new("UIGradient", {}, scrim)
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, FS_DARK_TOP),
		ColorSequenceKeypoint.new(0.41, FS_DARK_TOP),
		ColorSequenceKeypoint.new(0.5, FS_DARK_MID),
		ColorSequenceKeypoint.new(0.59, FS_DARK_LOW),
		ColorSequenceKeypoint.new(1, FS_DARK_LOW),
	})
	root.PanelShadow.Visible = false

	-- the panel is the whole canvas, see-through
	local panel = root.Panel
	panel.Position, panel.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(1280, 720)
	panel.BackgroundTransparency = 1
	local ps = panel:FindFirstChildOfClass("UIStroke")
	if ps then
		ps.Enabled = false
	end
	if panel:FindFirstChild("Rule") then
		panel.Rule.Visible = false
	end

	-- header: Style + its line, tabs, shop, ✕
	local header = panel.Header
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromOffset(1280, 120)
	header.SquareBottom.Visible = false
	local title = header.Title
	title.Position, title.Size = UDim2.fromOffset(40, 54), UDim2.fromOffset(400, 36)
	title.FontFace, title.TextSize, title.TextColor3 = HEAD, 30, CREAM
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Style"
	local oldSub = header:FindFirstChild("Sub")
	if oldSub then
		oldSub:Destroy()
	end
	text(header, "Sub", { Position = UDim2.fromOffset(40, 90), Size = UDim2.fromOffset(400, 18), FontFace = BODY_BOLD, TextSize = 14, TextColor3 = CREAM, TextTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Left, Text = "Your banner and photocard frame" })

	local tabs = header.Tabs
	tabs.AnchorPoint = Vector2.new(0.5, 0)
	tabs.Position = UDim2.fromOffset(640, 58)
	tabs.Size = UDim2.fromOffset(0, 46)
	tabs.AutomaticSize = Enum.AutomaticSize.X
	tabs.BackgroundColor3 = CREAM
	tabs.BackgroundTransparency = 0.9
	for _, cls in { "UICorner", "UIStroke", "UIPadding" } do
		local o = tabs:FindFirstChildOfClass(cls)
		if o then
			o:Destroy()
		end
	end
	corner(tabs, 14)
	new("UIStroke", { Color = CREAM, Transparency = 0.8, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tabs)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, tabs)
	tabs:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 4)
	tabs:FindFirstChildOfClass("UIListLayout").VerticalAlignment = Enum.VerticalAlignment.Center
	for name, label in { Sets = "Sets", Banners = "Banners", Cards = "Photocards" } do
		local t = tabs[name]
		t.Size = UDim2.fromOffset(0, 36)
		t.FontFace, t.TextSize = BODY, 16
		t.Text = label
		t.BackgroundColor3 = CREAM
		t.BackgroundTransparency = 1
		t.TextColor3 = CREAM
		t:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 10)
		local s = t:FindFirstChildOfClass("UIStroke")
		s.Thickness, s.Enabled = 3, false
		local p = t:FindFirstChildOfClass("UIPadding")
		p.PaddingLeft, p.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	end

	-- ✕ where every full screen has it
	header.Close.Position = UDim2.fromOffset(1219, 81)
	header.CloseShadow.Position = UDim2.fromOffset(1219 - 21, 81 - 21)
	header.CloseShadow.Size = UDim2.fromOffset(48, 48)
	-- MORE IN THE SHOP: left of ✕ (BannersController opens the Shop's Profile style tab)
	for _, n in { "Shop", "ShopShadow" } do
		local old = header:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local sw, sh = 190, 40
	local sx, sy = 1219 - 21 - 16 - sw, 81 - sh / 2
	local shopShadow = new("Frame", { Name = "ShopShadow", Position = UDim2.fromOffset(sx, sy), Size = UDim2.fromOffset(sw + 6, sh + 6), BackgroundColor3 = INK, BorderSizePixel = 0 }, header)
	corner(shopShadow, 15)
	local shop = new("TextButton", { Name = "Shop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx + sw / 2, 81), Size = UDim2.fromOffset(sw, sh), BackgroundColor3 = PINK, AutoButtonColor = false, FontFace = HEAD, TextSize = 14, TextColor3 = INK, Text = "MORE IN THE SHOP" }, header)
	corner(shop, 12)
	new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, shop)

	-- the two cream pages
	fsPage(panel, "PreviewPage", FS_PREVIEW)
	fsPage(panel, "Page", FS_PAGE)

	-- grid heading: the tab's name + how many you own (Owned moves here from the tabs)
	local oldHead = panel:FindFirstChild("PageHead")
	if oldHead then
		oldHead.Owned.Parent = tabs -- (keep the label; it's re-homed just below)
		oldHead:Destroy()
	end
	local head = new("Frame", { Name = "PageHead", Position = UDim2.fromOffset(FS_PAGE[1] + 24, FS_PAGE[2] + 14), Size = UDim2.fromOffset(560, 30), BackgroundTransparency = 1 }, panel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, head)
	text(head, "Title", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), FontFace = HEAD, TextSize = 22, TextTruncate = Enum.TextTruncate.None, Text = "SETS" })
	local owned = tabs:FindFirstChild("Owned")
	if owned then
		owned.Parent = head
		owned.LayoutOrder = 2
		owned.Size = UDim2.fromOffset(0, 24)
		owned.TextSize = 13
		owned.TextColor3 = C("6B6480")
	end

	-- pager: top right of the grid page
	local pager = header.Pager
	pager.Position = UDim2.fromOffset(FS_PAGE[1] + FS_PAGE[3] - 20 - 150, FS_PAGE[2] + 10)

	-- grids: on the page, 4 bigger tiles across
	for _, name in { "Grid", "Cards", "Sets" } do
		local grid = panel[name]
		grid.Position = UDim2.fromOffset(FS_PAGE[1] + 22, FS_PAGE[2] + 60)
		grid.Size = UDim2.fromOffset(FS_PAGE[3] - 44, FS_PAGE[4] - 68)
		grid.ZIndex = 1
		local template = grid:FindFirstChild("Template")
		if template then
			template.Size = UDim2.fromOffset(Build.STYLE_TILE_W, template.Size.Y.Offset)
		end
	end

	-- preview: your profile card, bigger, then the name + where it's from, then EQUIP
	local preview = panel.Preview
	preview.Position = UDim2.fromOffset(FS_PREVIEW[1] + 18, FS_PREVIEW[2] + 16)
	preview.Size = UDim2.fromOffset(FS_PREVIEW[3] - 40, FS_PREVIEW[4] - 36)
	preview.ZIndex = 1
	local heading = preview.Heading
	heading.Size = UDim2.fromOffset(340, 16)
	heading.FontFace, heading.TextSize, heading.TextColor3 = BODY, 12, C("6B6480")
	heading.Text = "PREVIEW · YOUR PROFILE CARD"
	local k = (FS_PREVIEW[3] - 40 - 7) / 294 -- the card's width on the page
	for _, n in { "Card", "CardShadow" } do
		local f = preview[n]
		local s = f:FindFirstChild("Grow") or new("UIScale", { Name = "Grow" }, f)
		s.Scale = k
	end
	preview.Card.Position = UDim2.fromOffset(0, 26)
	preview.CardShadow.Position = UDim2.fromOffset(7, 33)
	local info = preview.Info
	info.Position = UDim2.fromOffset(0, 26 + 176 * k + 22)
	info.Size = UDim2.fromOffset(FS_PREVIEW[3] - 40, 140)
	info.BackgroundTransparency = 1
	local is = info:FindFirstChildOfClass("UIStroke")
	if is then
		is.Enabled = false
	end
	preview.InfoShadow.Visible = false
	info.BannerName.Position, info.BannerName.Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 30)
	info.BannerName.TextSize = 24
	info.Source.Position, info.Source.Size = UDim2.fromOffset(0, 38), UDim2.new(1, 0, 0, 80)
	info.Source.TextSize = 14
	local ew, eh = FS_PREVIEW[3] - 40, 56
	local ey = FS_PREVIEW[4] - 36 - eh - 6
	preview.Equip.Size = UDim2.fromOffset(ew, eh)
	preview.Equip.Position = UDim2.fromOffset(ew / 2, ey + eh / 2)
	preview.Equip.TextSize = 20
	preview.EquipShadow.Size = UDim2.fromOffset(ew + 6, eh + 6)
	preview.EquipShadow.Position = UDim2.fromOffset(1, ey + 1) -- (drop 4, grown by the 3 px outline)
	return root
end

