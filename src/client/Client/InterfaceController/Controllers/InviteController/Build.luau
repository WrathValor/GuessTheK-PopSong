--| Invite friends UI builder
-- Builds, from the design boards "Invite friends", "Invite button on the HUD" and "Referral
-- moments":
--   Interface.Frames.Invite       the Invite Friends screen: pink header (INVITE FRIENDS + "n
--                                 friends played" chip + Close), the lilac how-it-works card
--                                 with the INVITE FRIENDS button on the left, the friend
--                                 milestones (track + 4 cards) and "Your friends" on the right
--   Interface.Frames.Invited      "YOU WERE INVITED!" (the friend's welcome gift + COLLECT)
--   Interface.Frames.FriendToast  "<friend> played!" + the inviter's coins, at the top
--   Interface.HUD.Buttons.Invite  the HUD button, right side under Settings (+ its CLAIM badge)
-- Run once in Studio (existing ones are replaced):
--   local B = require(game.StarterPlayer.StarterPlayerScripts.Client.Client.InterfaceController.Controllers.InviteController.Build)
--   B.Build(game.StarterGui.Interface.Frames); B.HUDButton(game.StarterGui.Interface.HUD)
-- InviteController / InvitedController find everything by name.

local ReferralConstants = require(game:GetService("ReplicatedStorage").Constants.ReferralConstants)
local SeasonArt = require(game:GetService("ReplicatedStorage").Modules.UI.SeasonArt)
local ProfileBuild = require(script.Parent.Parent.ProfileController.Build)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local LILAC = C("B9A6FF")
local PINK = C("FF9EC4")
local YELLOW = C("FFE07A")
local BLUE = C("9ED8F5")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local MUTED = C("5C566B")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Build = {}

Build.ICONS = {
	Close = "rbxassetid://118345756178429",
	Friends = "rbxassetid://89291280075774", -- assets/ui/i_friends.png
	Send = "rbxassetid://115640787772687", -- assets/ui/i_send.png
	UserPlus = "rbxassetid://113296101935679", -- assets/ui/i_userplus.png
	Coins = "rbxassetid://105055420801588", -- the HUD coin (Coins card)
}

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

local function pad(p: Instance, l: number, r: number?, t: number?, b: number?)
	new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r or l), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0) }, p)
end

-- face + hard shadow (<name>Shadow behind it)
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number): Frame
	local shadow = new("Frame", { Name = name .. "Shadow", Position = pos + UDim2.fromOffset(drop, drop), Size = size, BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, radius)
	local face = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(face, radius)
	stroke(face, line)
	return face
end

-- a chunky button with a hard shadow (<name>Shadow); centre-anchored for ButtonScale
local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string, textSize: number, drop: number?, radius: number?): TextButton
	local d = drop or 4
	local r = radius or 14
	local shadow = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + d, y + d), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
	corner(shadow, r)
	local b = new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x + w / 2, y + h / 2),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = colour,
		AutoButtonColor = false,
		FontFace = HEAD,
		TextSize = textSize,
		TextColor3 = INK,
		Text = label,
	}, parent)
	corner(b, r)
	stroke(b, 3)
	return b
end

-- a yellow "+500" chip
local function amountChip(parent: Instance, name: string, order: number, amount: number, size: number): TextLabel
	local chip = new("TextLabel", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, size + 6),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = YELLOW,
		FontFace = HEAD,
		TextSize = size,
		TextColor3 = INK,
		Text = `+{amount}`,
	}, parent)
	corner(chip, 8)
	stroke(chip, 2)
	pad(chip, 8)
	return chip
end

local function inlineRow(parent: Instance, name: string, pos: UDim2, h: number): Frame
	local row = new("Frame", { Name = name, Position = pos, Size = UDim2.new(1, -60, 0, h), BackgroundTransparency = 1 }, parent)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	return row
end

local function inlineText(parent: Instance, name: string, order: number, s: string): TextLabel
	return text(parent, name, { LayoutOrder = order, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = s, TextTruncate = Enum.TextTruncate.None })
end

local function avatar(parent: Instance, name: string, pos: UDim2, size: number, colour: Color3, line: number, anchor: Vector2?): ImageLabel
	local a = new("ImageLabel", { Name = name, AnchorPoint = anchor or Vector2.zero, Position = pos, Size = UDim2.fromOffset(size, size), BackgroundColor3 = colour, Image = "", ScaleType = Enum.ScaleType.Crop }, parent)
	corner(a, UDim.new(0.5, 0))
	stroke(a, line)
	return a
end

-- rounds a panel header's top corners to follow the panel (Roblox doesn't clip children to a
-- parent's UICorner); "Square" fills its bottom half so the rule under it stays straight
local function roundTop(h: Frame, radius: number)
	corner(h, radius)
	new("Frame", { Name = "Square", Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = h.BackgroundColor3, BorderSizePixel = 0, ZIndex = 0 }, h)
end

local function scrim(root: Instance, alpha: number)
	local s = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = alpha,
		BorderSizePixel = 0,
	}, root)
	s.Active = true
	return s
end

-- ------------------------------ Invite screen ----------------------------- --

local function header(panel: Frame, w: number)
	local h = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = PINK, BorderSizePixel = 0 }, panel)
	roundTop(h, 16)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	local left = new("Frame", { Name = "Left", Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -90, 1, 0), BackgroundTransparency = 1 }, h)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	text(left, "Title", { LayoutOrder = 1, Size = UDim2.fromOffset(0, 64), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 26, Text = "INVITE FRIENDS", TextTruncate = Enum.TextTruncate.None })
	local chip = new("Frame", { Name = "PlayedChip", LayoutOrder = 2, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE }, left)
	corner(chip, 15)
	stroke(chip, 2)
	pad(chip, 8, 12)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, chip)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = Build.ICONS.Friends }, chip)
	text(chip, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, Text = "0 friends played", TextTruncate = Enum.TextTruncate.None })

	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(w - 14 - 42 + 3, 14), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = INK }, h)
	corner(cs, 12)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w - 14 - 21, 32), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, h)
	corner(close, 12)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Image = Build.ICONS.Close }, close)
end

-- one "how it works" step: a white card with a numbered disc
local function step(parent: Instance, i: number, y: number, h: number, colour: Color3, title: string): Frame
	local s = new("Frame", { Name = "Step" .. i, Position = UDim2.fromOffset(18, y), Size = UDim2.fromOffset(324, h), BackgroundColor3 = WHITE }, parent)
	corner(s, 12)
	stroke(s, 2)
	local n = new("TextLabel", { Name = "Number", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = colour, FontFace = HEAD, TextSize = 15, TextColor3 = INK, Text = tostring(i) }, s)
	corner(n, UDim.new(0.5, 0))
	stroke(n, 2)
	text(s, "Title", { Position = UDim2.fromOffset(54, 10), Size = UDim2.fromOffset(258, 18), TextSize = 15, Text = title })
	return s
end

local function howCard(content: Frame, h: number)
	local how = card(content, "How", UDim2.fromOffset(0, 0), UDim2.fromOffset(360, h), LILAC, 16, 4, 3)
	text(how, "Heading", { Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(324, 54), FontFace = HEAD, TextSize = 21, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "Bring a friend,\nyou both get rewards" })

	local s1 = step(how, 1, 84, 72, YELLOW, "Send an invite")
	text(s1, "Body", { Position = UDim2.fromOffset(54, 30), Size = UDim2.fromOffset(258, 34), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = "Roblox's invite pop-up opens. Pick friends or copy your link." })

	local s2 = step(how, 2, 166, 64, BLUE, "They join for the first time")
	local r2 = inlineRow(s2, "Row", UDim2.fromOffset(54, 32), 22)
	inlineText(r2, "Text", 1, "They get a welcome gift")
	amountChip(r2, "Amount", 2, ReferralConstants.FRIEND_GIFT, 13)

	local s3 = step(how, 3, 240, 64, MINT, "They finish their first game")
	local r3 = inlineRow(s3, "Row", UDim2.fromOffset(54, 32), 22)
	inlineText(r3, "Text", 1, "You get")
	amountChip(r3, "Amount", 2, ReferralConstants.INVITER_GIFT, 13)
	inlineText(r3, "After", 3, "+ a milestone step")

	local foot = 34
	local by = h - 18 - foot - 10 - 60
	local invite = button(how, "InviteButton", 18, by, 324, 60, YELLOW, "", 20, 4)
	local inner = new("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, invite)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = Build.ICONS.Send }, inner)
	text(inner, "Label", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 20, Text = "INVITE FRIENDS", TextTruncate = Enum.TextTruncate.None })
	text(how, "Footnote", { Position = UDim2.fromOffset(18, h - 18 - foot), Size = UDim2.fromOffset(324, foot), FontFace = BODY_BOLD, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "Only new players count, once each. Friends who've played before still get to play with you." })
end

-- a milestone card (Art holds whichever art the milestone has: TitleArt, a 3D model through
-- CosmeticView, or the banner + photocard thumbnails)
local function milestoneCard(grid: Frame, i: number, m, x: number, w: number, h: number)
	local holder = new("Frame", { Name = "M" .. m.Key, LayoutOrder = i, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w + 4, h + 4), BackgroundTransparency = 1 }, grid)
	local face = card(holder, "Face", UDim2.fromOffset(0, 0), UDim2.fromOffset(w, h), C(m.Colour), 14, 4, 3)
	text(face, "Need", { Position = UDim2.fromOffset(8, 9), Size = UDim2.new(1, -16, 0, 18), FontFace = HEAD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Text = if m.Need == 1 then "1 FRIEND" else `{m.Need} FRIENDS` })
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 34), Size = UDim2.new(1, -20, 0, 78), BackgroundColor3 = C(m.ArtBg), ClipsDescendants = true }, face)
	corner(art, 10)
	stroke(art, 2)
	if m.Title then
		local t = new("TextLabel", { Name = "TitleArt", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = LILAC, FontFace = BODY, TextSize = 15, TextColor3 = INK, Text = m.Title, Rotation = -4 }, art)
		corner(t, 9)
		stroke(t, 3)
		pad(t, 12)
	elseif m.Banner then
		-- like the shop's banner + photocard sets (SeasonController/Build.ShopStyle), scaled to
		-- the box: the banner across the top, the photocard (your avatar in it) standing in front.
		-- InviteController paints them with SeasonArt.
		art.BackgroundColor3 = CREAM
		local bh = 30
		-- rounded top (to follow the box: Roblox doesn't clip to a parent's UICorner), square bottom
		local banner = SeasonArt.BuildBanner(art, "Banner", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, bh), 9, true)
		banner.ZIndex = 1
		new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, bh), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 2 }, art)
		local cw, chh = 44, 53
		local cs = new("Frame", { Name = "CardShadow", Position = UDim2.new(0.5, -cw / 2 + 2, 0, 18 + 2), Size = UDim2.fromOffset(cw, chh), Rotation = -5, BackgroundColor3 = INK, ZIndex = 3 }, art)
		corner(cs, 6)
		local pc = new("Frame", { Name = "Card", Position = UDim2.new(0.5, -cw / 2, 0, 18), Size = UDim2.fromOffset(cw, chh), Rotation = -5, BackgroundColor3 = WHITE, ZIndex = 3 }, art)
		corner(pc, 6)
		stroke(pc, 2)
		local ph = ProfileBuild.Photo(pc, UDim2.fromScale(12 / 280, 12 / 334), UDim2.fromScale(256 / 280, 228 / 334), 1)
		ph:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 3)
		SeasonArt.BuildCardSkin(pc, ph, 6, true)
	else
		-- a 3D model goes here (CosmeticView); this shows until it loads
		text(art, "ArtLabel", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Text = if m.Mic then "MIC" else "PLATFORM" })
	end
	text(face, "Reward", { Position = UDim2.fromOffset(10, 118), Size = UDim2.new(1, -20, 0, 32), TextSize = 13, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.None, Text = m.Text })
	-- the button: CLAIM! (yellow + shadow) when ready, "n / need friends" before, Claimed after
	local bs = new("Frame", { Name = "ClaimShadow", Position = UDim2.new(0, 13, 1, -44 + 3), Size = UDim2.new(1, -20, 0, 34), BackgroundColor3 = INK, Visible = false }, face)
	corner(bs, 10)
	local claim = new("TextButton", { Name = "Claim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -27), Size = UDim2.new(1, -20, 0, 34), BackgroundColor3 = WHITE, AutoButtonColor = false, FontFace = BODY, TextSize = 13, TextColor3 = MUTED, Text = `0 / {m.Need} friends` }, face)
	corner(claim, 10)
	stroke(claim, 2)
	return holder
end

local function rightColumn(content: Frame, x: number, w: number, h: number)
	local right = new("Frame", { Name = "Right", Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, h), BackgroundTransparency = 1 }, content)

	local mh = new("Frame", { Name = "MilestonesHead", Size = UDim2.fromOffset(w, 30), BackgroundTransparency = 1 }, right)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, mh)
	text(mh, "Heading", { LayoutOrder = 1, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, FontFace = HEAD, TextSize = 22, Text = "Friend milestones", TextTruncate = Enum.TextTruncate.None })
	local count = new("TextLabel", { Name = "Count", LayoutOrder = 2, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = `0 / {ReferralConstants.MAX}` }, mh)
	corner(count, 8)
	stroke(count, 2)
	pad(count, 8)

	local track = new("CanvasGroup", { Name = "Track", Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(w - 4, 16), BackgroundColor3 = WHITE }, right)
	corner(track, 8)
	stroke(track, 2)
	new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, track)

	local gap = 12
	local cw = math.floor((w - 4 - gap * 3) / 4)
	local chH = 196
	local grid = new("Frame", { Name = "Milestones", Position = UDim2.fromOffset(0, 70), Size = UDim2.fromOffset(w, chH + 4), BackgroundTransparency = 1 }, right)
	for i, m in ReferralConstants.MILESTONES do
		milestoneCard(grid, i, m, (i - 1) * (cw + gap), cw, chH)
	end

	local fy = 70 + chH + 22
	text(right, "FriendsHeading", { Position = UDim2.fromOffset(0, fy), Size = UDim2.fromOffset(300, 30), FontFace = HEAD, TextSize = 22, Text = "Your friends" })
	local list = new("Frame", { Name = "Friends", Position = UDim2.fromOffset(0, fy + 38), Size = UDim2.fromOffset(w - 4, h - fy - 38), BackgroundTransparency = 1 }, right)
	local rowH, rowGap = 44, 8
	for i = 1, ReferralConstants.FRIENDS_SHOWN do
		local row = new("Frame", { Name = "Row" .. i, Position = UDim2.fromOffset(0, (i - 1) * (rowH + rowGap)), Size = UDim2.new(1, 0, 0, rowH), BackgroundColor3 = WHITE, Visible = false }, list)
		corner(row, 12)
		stroke(row, 2)
		avatar(row, "Avatar", UDim2.fromOffset(12, 7), 30, C("FFD2CE"), 2)
		text(row, "FriendName", { Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -230, 1, 0), TextSize = 15, Text = "Friend" })
		local chip = new("TextLabel", { Name = "Status", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = MINT, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = "Played" }, row)
		corner(chip, 14)
		stroke(chip, 2)
		pad(chip, 10)
	end
	text(list, "More", { Position = UDim2.fromOffset(4, ReferralConstants.FRIENDS_SHOWN * (rowH + rowGap) - 2), Size = UDim2.new(1, -8, 0, 16), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "and 0 more", Visible = false })
	local empty = new("Frame", { Name = "Empty", Size = UDim2.new(1, 0, 0, rowH * 2 + rowGap), BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, Visible = true }, list)
	corner(empty, 12)
	stroke(empty, 2, C("8A8398"))
	text(empty, "Label", { Size = UDim2.fromScale(1, 1), FontFace = BODY_BOLD, TextSize = 15, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Text = "No friends yet. Send an invite and they'll show up here." })
end

local function inviteScreen(frames: Instance)
	local root = new("Frame", { Name = "Invite", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	scrim(root, 0.6)
	local W, H = 1040, 620
	local panel = card(root, "Panel", UDim2.fromOffset(120, 50), UDim2.fromOffset(W, H), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true
	header(panel, W)
	local ch = H - 67 - 20 - 22
	local content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(22, 67 + 20), Size = UDim2.fromOffset(W - 44, ch), BackgroundTransparency = 1 }, panel)
	howCard(content, ch - 4)
	rightColumn(content, 382, W - 44 - 382, ch)
	root.Parent = frames
	return root
end

-- ------------------------------ Welcome card ------------------------------ --

local function invitedCard(frames: Instance)
	local root = new("Frame", { Name = "Invited", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	scrim(root, 0.45)
	local W, H = 440, 366
	local panel = card(root, "Panel", UDim2.fromOffset(640 - W / 2, 360 - H / 2), UDim2.fromOffset(W, H), CREAM, 18, 8, 3)
	panel.ClipsDescendants = true
	local head = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = PINK, BorderSizePixel = 0 }, panel)
	roundTop(head, 16)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	text(head, "Title", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Text = "YOU WERE INVITED!" })

	local who = new("Frame", { Name = "Inviter", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, 78), Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, panel)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, who)
	local a = avatar(who, "Avatar", UDim2.new(), 56, C("FFD2CE"), 3)
	a.LayoutOrder = 1
	local names = new("Frame", { Name = "Names", LayoutOrder = 2, Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, who)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, names)
	text(names, "InviterName", { LayoutOrder = 1, Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, TextSize = 18, Text = "Friend", TextTruncate = Enum.TextTruncate.None })
	text(names, "Sub", { LayoutOrder = 2, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "brought you to the street", TextTruncate = Enum.TextTruncate.None })

	local gift = card(panel, "Gift", UDim2.fromOffset(22, 150), UDim2.fromOffset(W - 44, 80), YELLOW, 14, 4, 3)
	new("ImageLabel", { Name = "Coins", Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(56, 56), BackgroundTransparency = 1, Image = Build.ICONS.Coins, ScaleType = Enum.ScaleType.Fit }, gift)
	text(gift, "Label", { Position = UDim2.fromOffset(88, 16), Size = UDim2.fromOffset(200, 16), TextSize = 13, Text = "Welcome gift" })
	text(gift, "Amount", { Position = UDim2.fromOffset(88, 32), Size = UDim2.fromOffset(240, 34), FontFace = HEAD, TextSize = 30, Text = `+{ReferralConstants.FRIEND_GIFT}` })

	text(panel, "Note", { Position = UDim2.fromOffset(22, 246), Size = UDim2.fromOffset(W - 44, 34), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "Play your first game and Friend gets a reward too." })
	button(panel, "Collect", 22, H - 22 - 52, W - 44, 52, MINT, "COLLECT", 18, 4, 12)
	root.Parent = frames
	return root
end

-- ------------------------------ Friend toast ------------------------------ --

local function friendToast(frames: Instance)
	local W, H = 360, 68
	local root = new("Frame", { Name = "FriendToast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 76), Size = UDim2.fromOffset(W + 5, H + 5), BackgroundTransparency = 1, Visible = false, ZIndex = 60 })
	local face = card(root, "Face", UDim2.fromOffset(0, 0), UDim2.fromOffset(W, H), CREAM, 14, 5, 3)
	avatar(face, "Avatar", UDim2.fromOffset(12, 12), 44, LILAC, 3)
	text(face, "Title", { Position = UDim2.fromOffset(68, 13), Size = UDim2.new(1, -150, 0, 20), TextSize = 15, Text = "Friend played!" })
	text(face, "Sub", { Position = UDim2.fromOffset(68, 34), Size = UDim2.new(1, -150, 0, 18), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, Text = `Friends: 1 / {ReferralConstants.MAX}` })
	local chip = new("TextLabel", { Name = "Amount", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = YELLOW, FontFace = HEAD, TextSize = 16, TextColor3 = INK, Text = `+{ReferralConstants.INVITER_GIFT}` }, face)
	corner(chip, 10)
	stroke(chip, 2)
	pad(chip, 10)
	root.Parent = frames
	return root
end

-- --------------------------------- Public --------------------------------- --

function Build.Build(frames: Instance)
	for _, name in { "Invite", "Invited", "FriendToast" } do
		local old = frames:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	inviteScreen(frames)
	invitedCard(frames)
	friendToast(frames)
end

-- the HUD button: a pink square in the top-right row, left of News + Settings (same 44 px
-- size, one 54 px step apart), with the add-friend icon, a green +300 tag on its bottom edge
-- (the reward per friend), and a red CLAIM tag in its place while a milestone is ready
-- (InviteController)
function Build.HUDButton(hud: Instance)
	local group = hud:FindFirstChild("Buttons")
	assert(group, "Build.HUDButton: no HUD.Buttons")
	for _, name in { "Invite", "InviteShadow" } do
		local old = group:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local size = 44
	local cx, cy = 1130, 40 -- News is at 1184, Settings at 1238
	local shadow = new("Frame", { Name = "InviteShadow", Position = UDim2.fromOffset(cx - size / 2 + 3, cy - size / 2 + 3), Size = UDim2.fromOffset(size, size), BackgroundColor3 = INK, BorderSizePixel = 0 }, group)
	corner(shadow, 12)
	local b = new("TextButton", { Name = "Invite", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(size, size), BackgroundColor3 = PINK, AutoButtonColor = false, Text = "" }, group)
	corner(b, 12)
	stroke(b, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Image = Build.ICONS.UserPlus }, b)
	-- the tag on the bottom edge: +300, or CLAIM while a milestone is ready
	local sticker = new("TextLabel", { Name = "Sticker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Rotation = 6, BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 11, TextColor3 = INK, Text = `+{ReferralConstants.INVITER_GIFT}`, ZIndex = 3 }, b)
	corner(sticker, 9)
	stroke(sticker, 3)
	pad(sticker, 7)
	local badge = new("TextLabel", { Name = "ClaimBadge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Rotation = 6, BackgroundColor3 = RED, FontFace = HEAD, TextSize = 11, TextColor3 = WHITE, Text = "CLAIM", Visible = false, ZIndex = 4 }, b)
	corner(badge, 9)
	stroke(badge, 3)
	pad(badge, 8)
	return b
end

return Build
