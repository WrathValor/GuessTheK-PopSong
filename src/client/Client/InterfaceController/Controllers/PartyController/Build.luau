--| Party UI builder
-- Builds Interface.Frames.Party from the "Party Stages" boards: queue-style white cards with a
-- sticker on top, one per page (only one shows at a time, flipping between them):
--   Lobby     the stage's card: title + line, the setlist (6 photocards in join order, #1 hosts),
--             INVITE + SETTINGS + START (host) or READY UP (guest), Leave stage
--   Settings  Duel / Free-for-all, Songs › Edit, Owned songs count, Spots − n +, and the
--             "Every match" box (Friends only, Spectators), DONE
--   Invite    who's in the server (friends first) with Invite / Sent / Busy, paged
--   Player    a player's card for the host: MAKE HOST, REMOVE (+ block)
--   Songs     gens + groups (any mix) or single songs in / out, the pool size, SAVE
--   Prompt    one card for every pop-up: friends only (ask to join), full (spectate), an invite,
--             a join request (host), removed, …
--   Results   the FFA / party duel results: placement photocards + your coins
--   Watch     a small card while spectating
--   Toast     one line at the top
-- Also builds Game.FFABoard, the round screen's scoreboard for 3–6 players.
-- Run once in Studio (replaces an existing Party frame); PartyController finds everything by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local SAND = C("F3EBDD")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local LILAC = C("B9A6FF")
local BLUE = C("9ED8F5")
local MINT = C("A7E9B8")
local PINK = C("FF9EC4")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local LINE = C("CFC5B3")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Build = {}
Build.SLOTS = 6
Build.INVITE_ROWS = 4
Build.SONG_ROWS = 5
Build.CHIPS = 18
Build.GENS = 4

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
	return new("UIStroke", { Color = colour or INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a chunky button (centre-anchored for ButtonScale) with a hard shadow sibling; Title + Sub
local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, drop: number, title: string, sub: string?): TextButton
	if drop > 0 then
		local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + drop, y + drop), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK }, parent)
		corner(s, 12)
	end
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2, y + h / 2), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, AutoButtonColor = false, Text = "" }, parent)
	corner(b, 12)
	stroke(b, 3)
	if sub then
		text(b, "Title", { Position = UDim2.fromOffset(0, h / 2 - 19), Size = UDim2.new(1, 0, 0, 22), FontFace = HEAD, TextSize = 15, Text = title })
		text(b, "Sub", { Position = UDim2.fromOffset(8, h / 2 + 3), Size = UDim2.new(1, -16, 0, 16), FontFace = BODY_BOLD, TextSize = 11, Text = sub })
	else
		text(b, "Title", { Size = UDim2.fromScale(1, 1), FontFace = if drop > 0 then HEAD else BODY, TextSize = if drop > 0 then 15 else 14, Text = title })
	end
	return b
end

local function mini(parent: Instance, name: string, x: number, y: number, w: number, h: number, label: string): TextButton
	local b = new("TextButton", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, AutoButtonColor = false, FontFace = BODY, TextSize = 13, TextColor3 = INK, Text = label }, parent)
	corner(b, 8)
	stroke(b, 2)
	return b
end

local function toggle(parent: Instance, name: string, x: number, y: number): TextButton
	local t = new("TextButton", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(42, 24), BackgroundColor3 = MINT, AutoButtonColor = false, Text = "" }, parent)
	corner(t, 12)
	stroke(t, 2)
	local knob = new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = WHITE }, t)
	corner(knob, 8)
	stroke(knob, 2)
	return t
end

-- a white card (centre-anchored) + its shadow, with the sticker on top
-- every party card sits on the same bottom edge (BOTTOM) unless cy says otherwise
local BOTTOM = 705
local function card(root: Instance, name: string, w: number, h: number, cy: number?, tag: string, tagColour: Color3): Frame
	cy = cy or BOTTOM - h / 2
	local shadow = new("Frame", { Name = name .. "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640 + 6, cy + 6), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, Visible = false }, root)
	corner(shadow, 16)
	new("UIScale", { Name = "Flip" }, shadow)
	local c = new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, cy), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, Visible = false }, root)
	corner(c, 16)
	stroke(c, 3)
	new("UIScale", { Name = "Flip" }, c)
	local tagShadow = new("Frame", { Name = "TagShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w / 2 + 3, 3), Size = UDim2.fromOffset(190, 31), Rotation = -2, BackgroundColor3 = INK, ZIndex = 2 }, c)
	corner(tagShadow, 10)
	local t = text(c, "Tag", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(w / 2, 0), Size = UDim2.fromOffset(190, 31), Rotation = -2, BackgroundTransparency = 0, BackgroundColor3 = tagColour, FontFace = HEAD, TextSize = 13, Text = tag, ZIndex = 3 })
	corner(t, 10)
	stroke(t, 3)
	return c
end

local function heading(c: Frame, title: string, sub: string)
	text(c, "Title", { Position = UDim2.fromOffset(16, 26), Size = UDim2.new(1, -32, 0, 30), FontFace = HEAD, TextSize = 23, Text = title })
	text(c, "Sub", { Position = UDim2.fromOffset(16, 58), Size = UDim2.new(1, -32, 0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = sub })
end

-- a two / three way switch: a sand bar with one dark button
local function segmented(c: Frame, name: string, y: number, labels: { string }, margin: number): Frame
	local w = c.Size.X.Offset - margin * 2
	local seg = new("Frame", { Name = name, Position = UDim2.fromOffset(margin, y), Size = UDim2.fromOffset(w, 42), BackgroundColor3 = SAND }, c)
	corner(seg, 12)
	stroke(seg, 3)
	-- the pills fill the track with a 3px inset all round
	local bw = (w - 6 - 3 * (#labels - 1)) / #labels
	for i, label in labels do
		local b = new("TextButton", { Name = "Option" .. i, Position = UDim2.fromOffset(3 + (i - 1) * (bw + 3), 3), Size = UDim2.fromOffset(bw, 36), BackgroundColor3 = INK, AutoButtonColor = false, FontFace = BODY, TextSize = 13, TextColor3 = YELLOW, Text = label }, seg)
		corner(b, 8)
	end
	return seg
end

local function row(parent: Instance, name: string, x: number, y: number, w: number, h: number, label: string): Frame
	local r = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE }, parent)
	corner(r, 12)
	stroke(r, 3)
	text(r, "Label", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 220, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Text = label })
	return r
end

-- a small photocard: Photo (tilted, with Avatar + Initials), Num badge, Crown
local function photocard(parent: Instance, name: string, x: number, y: number, w: number, h: number, tilt: number): Frame
	local photo = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Rotation = tilt, BackgroundColor3 = C("DCD3FF") }, parent)
	corner(photo, 9)
	stroke(photo, 3)
	local avatar = new("ImageLabel", { Name = "Avatar", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop }, photo)
	corner(avatar, 6)
	text(photo, "Initials", { Size = UDim2.fromScale(1, 1), FontFace = HEAD, TextSize = 18, Text = "" })
	local num = text(photo, "Num", { Position = UDim2.fromOffset(-9, -9), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0, BackgroundColor3 = INK, TextColor3 = WHITE, FontFace = HEAD, TextSize = 10, Text = "1", ZIndex = 3 })
	corner(num, 11)
	stroke(num, 2)
	local crown = text(photo, "Crown", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -14), Size = UDim2.fromOffset(42, 20), BackgroundTransparency = 0, BackgroundColor3 = YELLOW, FontFace = HEAD, TextSize = 9, Text = "HOST", Visible = false, ZIndex = 3 })
	corner(crown, 7)
	stroke(crown, 3)
	return photo
end

local function buildLobby(root: Instance)
	local W, H = 540, 470
	local c = card(root, "Lobby", W, H, 470, "PARTY STAGE 1", LILAC)
	heading(c, "Waiting for players…", "4 / 6 · free-for-all · every song")
	local list = new("Frame", { Name = "Setlist", Position = UDim2.fromOffset(0, 96), Size = UDim2.fromOffset(W, 150), BackgroundTransparency = 1 }, c)
	local tilts = { -3, 2, -2, 3, -2, 2 }
	local SW, GAP = 74, 10
	local x0 = (W - (Build.SLOTS * SW + (Build.SLOTS - 1) * GAP)) / 2
	for i = 1, Build.SLOTS do
		local slot = new("Frame", { Name = "Slot" .. i, Position = UDim2.fromOffset(x0 + (i - 1) * (SW + GAP), 0), Size = UDim2.fromOffset(SW, 150), BackgroundTransparency = 1 }, list)
		photocard(slot, "Photo", 4, 12, 66, 84, tilts[i])
		text(slot, "PlayerName", { Position = UDim2.fromOffset(-4, 104), Size = UDim2.new(1, 8, 0, 18), TextSize = 12, Text = "Open" })
		text(slot, "State", { Position = UDim2.fromOffset(-4, 122), Size = UDim2.new(1, 8, 0, 14), FontFace = BODY, TextSize = 11, TextColor3 = MUTED, Text = "" })
		new("TextButton", { Name = "Hit", Size = UDim2.fromOffset(SW, 104), BackgroundTransparency = 1, Text = "" }, slot)
	end
	-- host: INVITE | SETTINGS, START ; guest: READY UP + the rules line
	button(c, "Invite", 24, 256, 240, 58, BLUE, 4, "INVITE", "2 spots open")
	button(c, "Settings", 276, 256, 240, 58, LILAC, 4, "SETTINGS", "FFA · every song · ×1.3 coins")
	button(c, "Start", 24, 326, 492, 58, MINT, 4, "START", "3 / 4 ready · 5 s countdown")
	button(c, "Ready", 24, 256, 492, 58, YELLOW, 4, "READY UP", "Everyone's waiting on you")
	text(c, "Rules", { Position = UDim2.fromOffset(24, 330), Size = UDim2.fromOffset(492, 50), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Text = "FFA · Gen 4 · 48 songs · owned songs off · friends only · ×1.12 coins" })
	local leave = button(c, "Leave", 24, 404, 492, 44, WHITE, 0, "Leave stage")
	leave.Title.TextColor3 = C("E0382C")
end

local function buildSettings(root: Instance)
	local W = 540
	local c = card(root, "Settings", W, 528, nil, "STAGE SETTINGS", YELLOW)
	heading(c, "How do you want to play?", "Only the host can change these")
	segmented(c, "Mode", 86, { "1v1 Duel", "Free-for-all" }, 22)
	local RW = W - 44
	local songs = row(c, "SongsRow", 22, 140, RW, 46, "Songs")
	text(songs, "Value", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 0), Size = UDim2.new(0, 250, 1, 0), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "Every song" })
	mini(songs, "Edit", RW - 76, 8, 64, 30, "Edit")
	local owned = row(c, "OwnedRow", 22, 194, RW, 46, "Owned songs count")
	toggle(owned, "Toggle", RW - 56, 11)
	local spots = row(c, "SpotsRow", 22, 248, RW, 46, "Spots")
	text(spots, "Note", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -116, 0, 0), Size = UDim2.new(0, 200, 1, 0), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "FFA: 3–6 · duel: 2" })
	mini(spots, "Minus", RW - 108, 8, 30, 30, "−")
	text(spots, "Value", { Position = UDim2.fromOffset(RW - 76, 0), Size = UDim2.new(0, 30, 1, 0), FontFace = HEAD, TextSize = 15, Text = "6" })
	mini(spots, "Plus", RW - 44, 8, 30, 30, "+")

	local every = new("Frame", { Name = "Every", Position = UDim2.fromOffset(22, 306), Size = UDim2.fromOffset(RW, 140), BackgroundColor3 = CREAM }, c)
	corner(every, 14)
	stroke(every, 3, LINE)
	text(every, "Heading", { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(110, 20), FontFace = HEAD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Text = "Every match" })
	text(every, "Sub", { Position = UDim2.fromOffset(124, 8), Size = UDim2.fromOffset(RW - 140, 20), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "who can join this stage, whatever you play" })
	local friends = row(every, "FriendsRow", 10, 34, RW - 20, 44, "Friends only")
	text(friends, "Note", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 0), Size = UDim2.new(0, 200, 1, 0), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "your invites still get in" })
	toggle(friends, "Toggle", RW - 20 - 56, 10)
	local spec = row(every, "SpectatorsRow", 10, 86, RW - 20, 44, "Spectators")
	text(spec, "Note", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 0), Size = UDim2.new(0, 200, 1, 0), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "watch when full" })
	toggle(spec, "Toggle", RW - 20 - 56, 10)

	button(c, "Done", 22, 458, RW, 54, MINT, 4, "DONE", "Coins ×1.3 · FFA ×1.3")
end

local function buildInvite(root: Instance)
	local W = 540
	local c = card(root, "Invite", W, 478, nil, "INVITE", BLUE)
	heading(c, "Who's coming?", "2 spots open · invites skip Friends only")
	segmented(c, "Filter", 86, { "Friends here", "Everyone here" }, 24)
	local RW = W - 48
	for i = 1, Build.INVITE_ROWS do
		local r = new("Frame", { Name = "Row" .. i, Position = UDim2.fromOffset(24, 140 + (i - 1) * 62), Size = UDim2.fromOffset(RW, 54), BackgroundColor3 = WHITE }, c)
		corner(r, 12)
		stroke(r, 3)
		local pc = new("ImageLabel", { Name = "Avatar", Position = UDim2.fromOffset(10, 7), Size = UDim2.fromOffset(32, 40), Rotation = if i % 2 == 0 then 3 else -3, BackgroundColor3 = C("DCD3FF"), ScaleType = Enum.ScaleType.Crop }, r)
		corner(pc, 6)
		stroke(pc, 2)
		text(r, "PlayerName", { Position = UDim2.fromOffset(54, 7), Size = UDim2.fromOffset(300, 20), TextXAlignment = Enum.TextXAlignment.Left, Text = "Player" })
		text(r, "Sub", { Position = UDim2.fromOffset(54, 27), Size = UDim2.fromOffset(300, 16), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "Lv 1 · friend" })
		local b = mini(r, "Send", RW - 96, 11, 84, 32, "Invite")
		b.BackgroundColor3 = BLUE
	end
	text(c, "Empty", { Position = UDim2.fromOffset(24, 140), Size = UDim2.fromOffset(RW, 240), FontFace = BODY, TextSize = 15, TextColor3 = MUTED, TextWrapped = true, Text = "Nobody else is in this server right now", Visible = false })
	mini(c, "Prev", W / 2 - 74, 390, 34, 30, "‹")
	text(c, "Page", { Position = UDim2.fromOffset(W / 2 - 34, 390), Size = UDim2.fromOffset(68, 30), FontFace = HEAD, TextSize = 13, Text = "1 / 1" })
	mini(c, "Next", W / 2 + 40, 390, 34, 30, "›")
	button(c, "Back", 24, 426, RW, 40, WHITE, 0, "Back")
end

local function buildPlayer(root: Instance)
	local W = 540
	local c = card(root, "Player", W, 420, nil, "PLAYER", YELLOW)
	local photo = photocard(c, "Photo", W / 2 - 46, 34, 92, 116, -3)
	photo.Initials.TextSize = 24
	text(c, "PlayerName", { Position = UDim2.fromOffset(16, 162), Size = UDim2.new(1, -32, 0, 28), FontFace = HEAD, TextSize = 20, Text = "player" })
	text(c, "Sub", { Position = UDim2.fromOffset(16, 190), Size = UDim2.new(1, -32, 0, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Lv 1 · joined 4th · not ready" })
	button(c, "MakeHost", 24, 222, 240, 58, YELLOW, 4, "MAKE HOST", "They get the settings")
	button(c, "Kick", 276, 222, 240, 58, RED, 4, "REMOVE", "Locked once it starts") -- not "Remove": Instance:Remove() would shadow it
	local block = row(c, "BlockRow", 24, 296, W - 48, 44, "Block them from this stage")
	toggle(block, "Toggle", W - 48 - 56, 10)
	button(c, "Back", 24, 356, W - 48, 44, WHITE, 0, "Back")
end

local function buildSongs(root: Instance)
	local W = 600
	local c = card(root, "Songs", W, 566, nil, "PICK SONGS", YELLOW)
	heading(c, "Which songs can come up?", "Same pool for everyone · all 4 answers come from it")
	segmented(c, "View", 86, { "Gens + groups", "Songs" }, 22)
	local RW = W - 44

	local gens = new("Frame", { Name = "GensView", Position = UDim2.fromOffset(22, 140), Size = UDim2.fromOffset(RW, 300), BackgroundTransparency = 1 }, c)
	local GW = (RW - 3 * 8) / 4
	for i = 1, Build.GENS do
		local g = new("TextButton", { Name = "Gen" .. i, Position = UDim2.fromOffset((i - 1) * (GW + 8), 0), Size = UDim2.fromOffset(GW, 56), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "" }, gens)
		corner(g, 12)
		stroke(g, 3)
		new("UIGradient", { Name = "Part", Enabled = false }, g) -- filled as far as the share of groups on
		text(g, "GenName", { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 20), FontFace = HEAD, TextSize = 14, Text = `Gen {i + 1}` })
		text(g, "State", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 16), TextSize = 11, Text = "All · 24" })
		-- the "you're looking at this gen" marker: a little diamond under the tile
		new("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(10, 10), Rotation = 45, BackgroundColor3 = INK, Visible = false, ZIndex = 2 }, g)
	end
	text(gens, "GroupsHeading", { Position = UDim2.fromOffset(0, 70), Size = UDim2.fromOffset(120, 20), TextXAlignment = Enum.TextXAlignment.Left, Text = "Gen 3 groups" })
	text(gens, "GroupsSub", { Position = UDim2.fromOffset(120, 70), Size = UDim2.fromOffset(260, 20), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "3 of 10 on · tap a gen to see its groups" })
	new("TextButton", { Name = "AllOn", Position = UDim2.fromOffset(RW - 128, 68), Size = UDim2.fromOffset(60, 24), BackgroundTransparency = 1, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = "<u>All on</u>", RichText = true }, gens)
	new("TextButton", { Name = "AllOff", Position = UDim2.fromOffset(RW - 62, 68), Size = UDim2.fromOffset(60, 24), BackgroundTransparency = 1, FontFace = BODY, TextSize = 12, TextColor3 = INK, Text = "<u>All off</u>", RichText = true }, gens)
	local chips = new("Frame", { Name = "Chips", Position = UDim2.fromOffset(0, 98), Size = UDim2.fromOffset(RW, 200), BackgroundTransparency = 1 }, gens)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	for i = 1, Build.CHIPS do
		local chip = new("TextButton", { Name = "Chip" .. i, LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), BackgroundColor3 = INK, AutoButtonColor = false, FontFace = BODY, TextSize = 12, TextColor3 = WHITE, Text = "GROUP" }, chips)
		corner(chip, 9)
		stroke(chip, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) }, chip)
	end

	local songs = new("Frame", { Name = "SongsView", Position = UDim2.fromOffset(22, 140), Size = UDim2.fromOffset(RW, 300), BackgroundTransparency = 1, Visible = false }, c)
	for i = 1, Build.SONG_ROWS do
		local r = new("TextButton", { Name = "Row" .. i, Position = UDim2.fromOffset(0, (i - 1) * 54), Size = UDim2.fromOffset(RW, 48), BackgroundColor3 = WHITE, AutoButtonColor = false, Text = "" }, songs)
		corner(r, 12)
		stroke(r, 3)
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(26, 32), Rotation = if i % 2 == 0 then 3 else -3, BackgroundColor3 = LILAC }, r)
		corner(art, 5)
		stroke(art, 2)
		text(r, "SongName", { Position = UDim2.fromOffset(48, 6), Size = UDim2.fromOffset(RW - 120, 20), TextXAlignment = Enum.TextXAlignment.Left, Text = "Song" })
		text(r, "Artist", { Position = UDim2.fromOffset(48, 25), Size = UDim2.fromOffset(RW - 120, 16), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "Artist" })
		toggle(r, "Toggle", RW - 56, 12).Active = false
	end
	mini(songs, "Prev", RW / 2 - 74, 274, 34, 30, "‹")
	text(songs, "Page", { Position = UDim2.fromOffset(RW / 2 - 34, 274), Size = UDim2.fromOffset(68, 30), FontFace = HEAD, TextSize = 13, Text = "1 / 1" })
	mini(songs, "Next", RW / 2 + 40, 274, 34, 30, "›")

	local pool = new("Frame", { Name = "Pool", Position = UDim2.fromOffset(22, 452), Size = UDim2.fromOffset(RW, 22), BackgroundTransparency = 1 }, c)
	local check = text(pool, "Check", { Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 0, BackgroundColor3 = MINT, TextSize = 11, Text = "✓" })
	corner(check, 10)
	stroke(check, 2)
	text(pool, "Text", { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, RichText = true, Text = "48 songs · 20+ keeps coins + XP on" })
	button(c, "Back", 22, 488, 120, 54, WHITE, 0, "Back")
	button(c, "Save", 154, 488, RW - 132, 54, MINT, 4, "SAVE · 48 SONGS", "Custom pool · ×0.6 coins")
end

local function buildPrompt(root: Instance)
	local W = 460
	local c = card(root, "Prompt", W, 366, nil, "PARTY STAGE 1", LILAC)
	heading(c, "Friends only", "hyunnie_x is hosting for friends.")
	c.Sub.Size = UDim2.new(1, -32, 0, 34)
	c.Sub.TextWrapped = true
	c.Sub.TextTruncate = Enum.TextTruncate.None
	local photo = photocard(c, "Photo", W / 2 - 40, 104, 80, 100, -3)
	photo.Num.Visible = false
	photo.Initials.TextSize = 20
	button(c, "Primary", 24, 226, W - 48, 58, BLUE, 4, "ASK TO JOIN", "3 / 6 on the stage")
	button(c, "Secondary", 24, 300, W - 48, 44, WHITE, 0, "Not now")
end

local function buildResults(root: Instance)
	local W = 640
	local c = card(root, "Results", W, 540, nil, "FFA RESULTS", PINK)
	heading(c, "2nd place!", "Party Stage 1 · 5 players · 7 rounds")
	local places = new("Frame", { Name = "Places", Position = UDim2.fromOffset(0, 90), Size = UDim2.fromOffset(W, 200), BackgroundTransparency = 1 }, c)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, places)
	local tilts = { -3, 2, -2, 3, -1, 2 }
	for i = 1, Build.SLOTS do
		local p = new("Frame", { Name = "Place" .. i, LayoutOrder = i, Size = UDim2.fromOffset(88, 196), BackgroundTransparency = 1 }, places)
		local h = if i == 1 then 116 elseif i == 2 then 106 else 96
		local photo = photocard(p, "Photo", (88 - h * 0.78) / 2, 124 - h, math.floor(h * 0.78), h, tilts[i])
		photo.Num.Size = UDim2.fromOffset(28, 28)
		photo.Num.Position = UDim2.fromOffset(-10, -10)
		photo.Num.TextSize = 12
		text(p, "PlayerName", { Position = UDim2.fromOffset(-6, 132), Size = UDim2.new(1, 12, 0, 18), TextSize = 12, Text = "player" })
		text(p, "Points", { Position = UDim2.fromOffset(-6, 150), Size = UDim2.new(1, 12, 0, 20), FontFace = HEAD, TextSize = 15, Text = "58 pts" })
		text(p, "Note", { Position = UDim2.fromOffset(-6, 170), Size = UDim2.new(1, 12, 0, 14), FontFace = BODY_BOLD, TextSize = 10, TextColor3 = MUTED, Text = "" })
	end
	local box = new("Frame", { Name = "Coins", Position = UDim2.fromOffset(24, 300), Size = UDim2.fromOffset(W - 48, 110), BackgroundColor3 = CREAM }, c)
	corner(box, 12)
	stroke(box, 3)
	for i, y in { 8, 32 } do
		text(box, "Line" .. i, { Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -120, 0, 20), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
		text(box, "Value" .. i, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, y), Size = UDim2.fromOffset(100, 20), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
	end
	new("Frame", { Name = "Divider", Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 2), BackgroundColor3 = LINE, BorderSizePixel = 0 }, box)
	text(box, "YouGet", { Position = UDim2.fromOffset(14, 70), Size = UDim2.fromOffset(120, 28), TextXAlignment = Enum.TextXAlignment.Left, Text = "You get" })
	local coins = text(box, "CoinsChip", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -112, 0, 68), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), BackgroundTransparency = 0, BackgroundColor3 = YELLOW, FontFace = HEAD, TextSize = 16, Text = "+55 coins", TextTruncate = Enum.TextTruncate.None })
	corner(coins, 8)
	stroke(coins, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, coins)
	local xp = text(box, "XPChip", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 68), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30), BackgroundTransparency = 0, BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = 16, Text = "+95 XP", TextTruncate = Enum.TextTruncate.None })
	corner(xp, 8)
	stroke(xp, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, xp)
	text(c, "Rule", { Position = UDim2.fromOffset(24, 418), Size = UDim2.fromOffset(W - 48, 16), FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, Text = "1st 100% · 2nd 70% · 3rd 50% · everyone else who finishes 30% · leaving early pays 0" })
	button(c, "Back", 24, 448, W - 48 - 172, 58, MINT, 4, "BACK TO STAGE", "Same settings · ready up again")
	local leave = button(c, "Leave", W - 24 - 160, 448, 160, 58, WHITE, 0, "Leave stage")
	leave.Title.TextColor3 = C("E0382C")
end

local function buildWatch(root: Instance)
	local W = 560
	local c = card(root, "Watch", W, 150, 112, "SPECTATING", LILAC)
	text(c, "Title", { Position = UDim2.fromOffset(16, 22), Size = UDim2.new(1, -32, 0, 24), FontFace = HEAD, TextSize = 18, Text = "Party Stage 1 · round 3 / 7" })
	local list = new("Frame", { Name = "Scores", Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 38), BackgroundTransparency = 1 }, c)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i = 1, Build.SLOTS do
		local chip = text(list, "P" .. i, { LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), BackgroundTransparency = 0, BackgroundColor3 = CREAM, TextSize = 12, RichText = true, TextTruncate = Enum.TextTruncate.None, Text = "name <b>0</b>" })
		corner(chip, 9)
		stroke(chip, 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, chip)
	end
	button(c, "Stop", W / 2 - 90, 100, 180, 36, WHITE, 0, "Stop watching")
end

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("Party")
	if old then
		old:Destroy()
	end
	local root = new("Frame", { Name = "Party", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, frames)
	buildLobby(root)
	buildSettings(root)
	buildInvite(root)
	buildPlayer(root)
	buildSongs(root)
	buildPrompt(root)
	buildResults(root)
	buildWatch(root)
	local t = text(root, "Toast", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 150), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), BackgroundTransparency = 0, BackgroundColor3 = WHITE, TextSize = 14, Text = "hyunnie_x joined", TextTruncate = Enum.TextTruncate.None, Visible = false, ZIndex = 10 })
	corner(t, 12)
	stroke(t, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, t)
	return root
end

-- the round screen's scoreboard for 3–6 players: the duel ticket (Game.Scoreboard) widened.
-- Same stub (full-height yellow, flat right edge), dashed perforation, ROUND n/7 + pips, then
-- one cell per player (place badge, name, status, score) with a hard shadow; yours is red.
-- Cells are sized + placed by GameController/FFABoard for however many are playing.
Build.FFA_PANEL = Vector2.new(980, 84)
Build.FFA_CELLS_X = 132 -- where the player cells start inside the panel
function Build.FFABoard(game_: Instance)
	local old = game_:FindFirstChild("FFABoard")
	if old then
		old:Destroy()
	end
	local W, H = Build.FFA_PANEL.X, Build.FFA_PANEL.Y
	local root = new("Frame", { Name = "FFABoard", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false }, game_)
	local shadow = new("Frame", { Name = "PanelShadow", Position = UDim2.fromOffset(155, 25), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK }, root)
	corner(shadow, 14)
	local panel = new("Frame", { Name = "Panel", Position = UDim2.fromOffset(150, 20), Size = UDim2.fromOffset(W, H), BackgroundColor3 = WHITE }, root)
	corner(panel, 14)
	stroke(panel, 3)

	-- round stub (as Game.Scoreboard.Panel.Stub)
	local stub = new("Frame", { Name = "Stub", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(117, 78), BackgroundColor3 = YELLOW, BorderSizePixel = 0 }, panel)
	corner(stub, 11)
	new("Frame", { Name = "SquareRight", Position = UDim2.fromOffset(94, 0), Size = UDim2.fromOffset(23, 78), BackgroundColor3 = YELLOW, BorderSizePixel = 0 }, stub)
	local perf = new("Frame", { Name = "Perforation", Position = UDim2.fromOffset(120, 3), Size = UDim2.fromOffset(3, 72), BackgroundTransparency = 1 }, panel)
	for i = 0, 6 do
		new("Frame", { Position = UDim2.fromOffset(0, i * 11), Size = UDim2.fromOffset(3, 6), BackgroundColor3 = INK, BorderSizePixel = 0 }, perf)
	end
	text(stub, "RoundLabel", { Position = UDim2.fromOffset(0, 11), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Text = "ROUND" })
	text(stub, "Round", { Position = UDim2.fromOffset(0, 27), Size = UDim2.new(1, 0, 0, 30), FontFace = HEAD, TextSize = 30, Text = "1/7" })
	local pips = new("Frame", { Name = "Pips", Position = UDim2.fromOffset(21, 61), Size = UDim2.fromOffset(72, 8), BackgroundTransparency = 1 }, stub)
	for i = 1, 7 do
		local pip = new("Frame", { Name = "Pip" .. i, Position = UDim2.fromOffset(math.floor((i - 1) * 10.5 + 0.5), 0), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = WHITE }, pips)
		corner(pip, 99)
		stroke(pip, 1)
	end

	-- player cells (FFABoard lays them out); each has a hard shadow behind it
	local cells = new("Frame", { Name = "Players", Position = UDim2.fromOffset(Build.FFA_CELLS_X, 0), Size = UDim2.new(1, -Build.FFA_CELLS_X, 1, 0), BackgroundTransparency = 1 }, panel)
	for i = 1, Build.SLOTS do
		local drop = new("Frame", { Name = "Shadow" .. i, Size = UDim2.fromOffset(150, 60), BackgroundColor3 = INK, BorderSizePixel = 0 }, cells)
		corner(drop, 10)
		local cell = new("Frame", { Name = "Player" .. i, Size = UDim2.fromOffset(150, 60), BackgroundColor3 = CREAM, ZIndex = 2 }, cells)
		corner(cell, 10)
		stroke(cell, 2)
		local rank = text(cell, "Rank", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0, BackgroundColor3 = WHITE, FontFace = HEAD, TextSize = 12, Text = tostring(i), ZIndex = 2 })
		corner(rank, 13)
		stroke(rank, 2)
		text(cell, "PlayerName", { Position = UDim2.fromOffset(42, 12), Size = UDim2.new(1, -90, 0, 18), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = "player", ZIndex = 2 })
		text(cell, "Status", { Position = UDim2.fromOffset(42, 31), Size = UDim2.new(1, -90, 0, 16), FontFace = BODY_BOLD, TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "Listening…", ZIndex = 2 })
		text(cell, "Score", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(44, 34), FontFace = HEAD, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right, Text = "0", ZIndex = 2 })
	end
	local tag = text(root, "Tag", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, 118), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24), BackgroundTransparency = 0, BackgroundColor3 = WHITE, TextSize = 12, Text = "Party Stage 1 · FFA", TextTruncate = Enum.TextTruncate.None })
	corner(tag, 9)
	stroke(tag, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, tag)
	return root
end

return Build
