--| Leaderboards UI builder
-- Builds the map signs' SurfaceGuis from the "Leaderboards v2 · one big board with tabs + Join
-- the Group" design board, as instances in StarterGui: "Leaderboard_Main" (the big board, 32×20
-- studs = 1280 × 800, five tabs) and "Leaderboard_JoinTheGroup" (16×20 = 640 × 800). Each one's
-- "Board" attribute names the part at Map.Landmarks.Leaderboards it goes on ("Frame" the part
-- behind it, which the client tints to the open tab). Run once in Studio (signs already there
-- are kept as ServerStorage.Leaderboards_Legacy); Client/Leaderboards finds everything by name
-- and only fills in names, values, ranks, the tabs and the Join button.
--   require(StarterPlayer.StarterPlayerScripts.Client.Client.Leaderboards.Build).Build(game.StarterGui)
-- The big board's Sign frame ("Sign", not "Face": a SurfaceGui has a Face property): Header
-- (Title, Sub), Tabs (one TextButton per board, by its Name, + <Name>Shadow), Podium (Place1–3:
-- Card (Photo.Avatar, PlayerName, Value) on a Step), List (Row4–Row10: Rank, PlayerName, Value)
-- and the pinned You row (Chip, Rank, PlayerName, Value).

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local CREAM = C("FBF7F0")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local PINK = C("FF9EC4")
local BLUE = C("9ED8F5")
local PEACH = C("FFD2CE")
local MUTED = C("5C566B")
local MINE = C("FFF1B8") -- your own row
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local COIN = require(game:GetService("ReplicatedStorage").Constants.Currencies).Coins.Icon

local W, H = 640, 800 -- the Join sign
local BW = 1280 -- the big board (same height)
local SIGN_BRIGHTNESS = 1.7
local SIGN_LIGHT_INFLUENCE = 0.35
local HEADER = 118
local TABS_H = 86 -- the tab row under the header
local YOU_H = 56 -- the pinned You row
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
	ColorSequenceKeypoint.new(1, C("B5DDFF")),
})

local Build = {}

-- the big board's tabs, left to right (Name = the PlayerData board; Client/Leaderboards
-- knows each one's colours and text)
Build.TABS = {
	{ Name = "MostWins", Label = "Most Wins" },
	{ Name = "MostAnswers", Label = "Most Answers" },
	{ Name = "TopStreaks", Label = "Top Streaks" },
	{ Name = "PerfectGames", Label = "Perfect Games" },
	{ Name = "TopFans", Label = "Top Fans" },
}
Build.MAIN_SIGN = { Board = "Board1", Frame = "Frame1", Name = "Main" }
Build.JOIN_SIGN = { Board = "Board2", Frame = "Frame2", Name = "JoinTheGroup" }

-- --------------------------------- Helpers -------------------------------- --

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

local function label(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = BODY,
		TextSize = 20,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- a face with a hard ink shadow behind it (<name>Shadow)
local function card(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, radius: number, drop: number, line: number): Frame
	if drop > 0 then
		local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + drop, y + drop), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, BorderSizePixel = 0 }, parent)
		corner(s, radius)
	end
	local f = new("Frame", { Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, BorderSizePixel = 0 }, parent)
	corner(f, radius)
	stroke(f, line)
	return f
end

local function surface(parent: Instance, name: string, board: string, frame: string, w: number): (SurfaceGui, Frame)
	local gui = new("SurfaceGui", {
		Name = "Leaderboard_" .. name,
		Face = Enum.NormalId.Back,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		-- a touch of the street's light and below full brightness, so the pastels don't
		-- blow out under the map's bloom
		LightInfluence = SIGN_LIGHT_INFLUENCE,
		Brightness = SIGN_BRIGHTNESS,
		MaxDistance = 160,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, parent)
	gui:SetAttribute("Board", board) -- Client/Leaderboards points Adornee at this part
	gui:SetAttribute("Frame", frame) -- the frame part behind it
	-- "Sign", not "Face": a SurfaceGui has a Face property, which gui.Face would read instead
	local face = new("Frame", { Name = "Sign", Size = UDim2.fromOffset(w, H), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, gui)
	corner(face, 18)
	stroke(face, 4)
	return gui, face
end

local function header(face: Frame, title: string, sub: string, subColour: Color3)
	local h = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, HEADER), BackgroundColor3 = INK, BorderSizePixel = 0 }, face)
	corner(h, 16)
	-- square off the header's bottom corners
	new("Frame", { Name = "Square", Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = INK, BorderSizePixel = 0 }, h)
	label(h, "Title", { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 48), FontFace = HEAD, TextSize = 44, TextColor3 = WHITE, Text = title })
	label(h, "Sub", { Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = subColour, Text = sub })
end

-- -------------------------------- Big board -------------------------------- --

-- podium order on screen: 2nd, 1st, 3rd. Square photocards standing on steps
local SLOTS = {
	{ Place = 2, CardW = 172, StepH = 104, Step = WHITE, Bg = C("DCD3FF"), Tilt = -2, Number = 48 },
	{ Place = 1, CardW = 186, StepH = 150, Step = YELLOW, Bg = WHITE, Rainbow = true, Tilt = 0, Number = 64 },
	{ Place = 3, CardW = 172, StepH = 72, Step = PEACH, Bg = C("CDEBFA"), Tilt = 2, Number = 40 },
}
local COLUMN = 200 -- each podium column (its step's width)

local function mainSign(parent: Instance)
	local spec = Build.MAIN_SIGN
	local gui, face = surface(parent, spec.Name, spec.Board, spec.Frame, BW)
	face.BackgroundColor3 = MINT
	header(face, "LEADERBOARDS", "", YELLOW)

	-- tabs: the open one is coloured, lifted and has its shadow (painted by the client)
	local tabs = new("Frame", { Name = "Tabs", Position = UDim2.fromOffset(0, HEADER), Size = UDim2.fromOffset(BW, TABS_H), BackgroundTransparency = 1 }, face)
	local pad, gap = 22, 14
	local tw = math.floor((BW - pad * 2 - gap * (#Build.TABS - 1) - 4) / #Build.TABS)
	for i, t in Build.TABS do
		local x = pad + (i - 1) * (tw + gap)
		local shadow = new("Frame", { Name = t.Name .. "Shadow", Position = UDim2.fromOffset(x + 4, 16 + 4), Size = UDim2.fromOffset(tw, 58), BackgroundColor3 = INK, BorderSizePixel = 0, Visible = i == 1 }, tabs)
		corner(shadow, 14)
		local b = new("TextButton", {
			Name = t.Name,
			Position = UDim2.fromOffset(x, 16),
			Size = UDim2.fromOffset(tw, 58),
			BackgroundColor3 = if i == 1 then BLUE else WHITE,
			AutoButtonColor = false,
			FontFace = HEAD,
			TextSize = 19,
			TextColor3 = INK,
			Text = t.Label,
		}, tabs)
		corner(b, 14)
		stroke(b, 3)
	end

	local top = HEADER + TABS_H + 14
	local bottom = H - 20 - YOU_H - 14 -- where the podium + list end
	local podium = new("Frame", { Name = "Podium", Position = UDim2.fromOffset(pad, top), Size = UDim2.fromOffset(600, bottom - top), BackgroundTransparency = 1 }, face)
	local ph = bottom - top
	for k, s in SLOTS do
		local col = new("Frame", { Name = "Place" .. s.Place, Position = UDim2.fromOffset((k - 1) * COLUMN, 0), Size = UDim2.fromOffset(COLUMN, ph), BackgroundTransparency = 1 }, podium)
		local step = new("TextLabel", {
			Name = "Step",
			Position = UDim2.fromOffset(0, ph - s.StepH),
			Size = UDim2.fromOffset(COLUMN, s.StepH),
			BackgroundColor3 = s.Step,
			FontFace = HEAD,
			TextSize = s.Number,
			TextColor3 = INK,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Text = tostring(s.Place),
		}, col)
		corner(step, 14)
		stroke(step, 3)
		new("UIPadding", { PaddingBottom = UDim.new(0, 8) }, step)
		-- the photocard, overlapping its step a little
		local photoSize = s.CardW - 20
		local cardH = 10 + photoSize + 4 + 22 + 4 + 28 + 8
		local holder = new("Frame", { Name = "Card", Position = UDim2.fromOffset((COLUMN - s.CardW) / 2, ph - s.StepH - cardH + 14), Size = UDim2.fromOffset(s.CardW, cardH), BackgroundTransparency = 1, Rotation = s.Tilt, ZIndex = 2 }, col)
		local shade = new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(6, 6), Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 2 }, holder)
		corner(shade, 16)
		local c = new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2 }, holder)
		corner(c, 16)
		stroke(c, 3)
		local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(photoSize, photoSize), BackgroundColor3 = s.Bg, ClipsDescendants = true, ZIndex = 2 }, c)
		corner(photo, 10)
		stroke(photo, 2)
		if s.Rainbow then
			new("UIGradient", { Color = RAINBOW, Rotation = 25 }, photo)
		end
		new("ImageLabel", { Name = "Avatar", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ZIndex = 2 }, photo)
		label(c, "PlayerName", { Position = UDim2.fromOffset(8, 10 + photoSize + 4), Size = UDim2.new(1, -16, 0, 22), TextSize = 18, Text = "—", ZIndex = 2 })
		label(c, "Value", { Position = UDim2.fromOffset(8, 10 + photoSize + 4 + 22 + 4), Size = UDim2.new(1, -16, 0, 28), FontFace = HEAD, TextSize = 24, Text = "", ZIndex = 2 })
	end

	local lx = pad + 600 + 22
	local list = card(face, "List", lx, top, BW - lx - pad, bottom - top, CREAM, 14, 0, 3)
	local rowH = math.floor((bottom - top - 20 - 7 * 6) / 7)
	for i = 1, 7 do
		local r = new("Frame", { Name = "Row" .. (i + 3), Position = UDim2.fromOffset(12, 10 + (i - 1) * (rowH + 7)), Size = UDim2.new(1, -24, 0, rowH), BackgroundColor3 = WHITE }, list)
		corner(r, 10)
		stroke(r, 2)
		label(r, "Rank", { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0, 40, 1, 0), FontFace = HEAD, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(i + 3) })
		label(r, "PlayerName", { Position = UDim2.fromOffset(62, 0), Size = UDim2.new(1, -62 - 130, 1, 0), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Text = "—" })
		label(r, "Value", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0, 120, 1, 0), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
	end

	-- You: always the player looking at the sign, wherever they are on the board
	local you = card(face, "You", pad, H - 20 - YOU_H, BW - pad * 2 - 4, YOU_H, MINE, 12, 4, 3)
	local chip = new("TextLabel", { Name = "Chip", Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(56, 28), BackgroundColor3 = INK, FontFace = BODY, TextSize = 15, TextColor3 = YELLOW, Text = "YOU" }, you)
	corner(chip, 7)
	label(you, "Rank", { Position = UDim2.fromOffset(88, 0), Size = UDim2.new(0, 90, 1, 0), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Text = "—" })
	label(you, "PlayerName", { Position = UDim2.fromOffset(184, 0), Size = UDim2.new(1, -184 - 180, 1, 0), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Text = "You" })
	label(you, "Value", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 0), Size = UDim2.new(0, 160, 1, 0), FontFace = HEAD, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
	return gui
end

-- ------------------------------ Join the Group ----------------------------- --

local function joinSign(parent: Instance, groupCoins: number, groupTitle: string)
	local gui, face = surface(parent, Build.JOIN_SIGN.Name, Build.JOIN_SIGN.Board, Build.JOIN_SIGN.Frame, W)
	face.BackgroundColor3 = PINK
	header(face, "JOIN THE GROUP", "FREE REWARDS · ONE TIME", MINT)
	label(face, "Heading", { Position = UDim2.fromOffset(0, HEADER + 24), Size = UDim2.new(1, 0, 0, 36), FontFace = HEAD, TextSize = 30, Text = "3 free rewards for joining" })

	-- three reward photocards, the middle (group stage) biggest
	local top = HEADER + 24 + 36
	local area = 392
	local specs = {
		{ Name = "Coins", W = 186, H = 278, Big = tostring(groupCoins), Small = "coins", Bg = C("FFF6D6") },
		{ Name = "Stage", W = 220, H = 330, Big = "Group stage", Small = "only from joining", Bg = C("4A3F78") },
		{ Name = "Title", W = 186, H = 278, Big = "Title", Small = "on your name tag", Bg = C("DCD3FF") },
	}
	local x = math.floor((W - (186 + 220 + 186) - 2 * 16) / 2)
	for _, s in specs do
		local y = top + math.floor((area - s.H) / 2)
		local c = card(face, s.Name, x, y, s.W, s.H, WHITE, 16, 6, 3)
		local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -10 - 8 - 22 - 34 - 4), BackgroundColor3 = s.Bg, ClipsDescendants = true }, c)
		corner(art, 10)
		stroke(art, 2)
		label(c, "Big", { Position = UDim2.new(0, 6, 1, -8 - 22 - 34), Size = UDim2.new(1, -12, 0, 34), FontFace = HEAD, TextSize = if s.Name == "Coins" then 32 else 25, Text = s.Big })
		label(c, "Small", { Position = UDim2.new(0, 6, 1, -8 - 22), Size = UDim2.new(1, -12, 0, 22), TextSize = 17, TextColor3 = MUTED, Text = s.Small })
		if s.Name == "Coins" then
			new("ImageLabel", { Name = "Coin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(100, 100), BackgroundTransparency = 1, Image = COIN, ScaleType = Enum.ScaleType.Fit }, art)
		elseif s.Name == "Stage" then
			-- the drawn stage shows until the real one (CosmeticView, filled in by the client) has loaded
			local back = new("Frame", { Name = "Back", Position = UDim2.fromScale(0.18, 0.16), Size = UDim2.fromScale(0.64, 0.44), BackgroundColor3 = BLUE }, art)
			corner(back, 30)
			new("UIStroke", { Color = WHITE, Thickness = 3 }, back)
			local pad = new("Frame", { Name = "Pad", Position = UDim2.fromScale(0.22, 0.56), Size = UDim2.fromScale(0.56, 0.2), BackgroundColor3 = MINT }, art)
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pad)
			new("UIStroke", { Color = WHITE, Thickness = 3 }, pad)
			local tag = new("TextLabel", {
				Name = "Exclusive",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.fromOffset(120, 26),
				BackgroundColor3 = YELLOW,
				FontFace = HEAD,
				TextSize = 13,
				TextColor3 = INK,
				Text = "EXCLUSIVE",
				ZIndex = 3,
			}, c)
			corner(tag, 9)
			stroke(tag, 3)
		else
			local chip = new("TextLabel", {
				Name = "Chip",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(140, 42),
				BackgroundColor3 = YELLOW,
				FontFace = BODY,
				TextSize = 24,
				TextColor3 = INK,
				Text = groupTitle,
				Rotation = -4,
			}, art)
			corner(chip, 12)
			stroke(chip, 3)
		end
		x += s.W + 16
	end

	-- the button that follows this player (Join → Claim → Claimed ✓, painted by the client)
	local bottomTop = top + area
	label(face, "Note", { Position = UDim2.fromOffset(0, bottomTop + 20), Size = UDim2.new(1, 0, 0, 24), TextSize = 19, TextColor3 = C("4A2440"), Text = "" })
	local bw, bh = 460, 80
	local by = bottomTop + 20 + 24 + 14
	local shadow = new("Frame", { Name = "ButtonShadow", Position = UDim2.fromOffset((W - bw) / 2 + 6, by + 6), Size = UDim2.fromOffset(bw, bh), BackgroundColor3 = INK }, face)
	corner(shadow, 16)
	local button = new("TextButton", {
		Name = "Button",
		Position = UDim2.fromOffset((W - bw) / 2, by),
		Size = UDim2.fromOffset(bw, bh),
		BackgroundColor3 = MINT,
		FontFace = HEAD,
		TextSize = 30,
		TextColor3 = INK,
		Text = "JOIN THE GROUP",
		AutoButtonColor = false,
	}, face)
	corner(button, 16)
	stroke(button, 4)
	return gui
end

-- ---------------------------------- Build ---------------------------------- --

function Build.Build(starterGui: Instance)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
	local storage = game:GetService("ServerStorage")
	local legacy = storage:FindFirstChild("Leaderboards_Legacy")
	if legacy then
		legacy:Destroy()
	end
	legacy = Instance.new("Folder")
	legacy.Name = "Leaderboards_Legacy"
	for _, child in starterGui:GetChildren() do
		if child:IsA("SurfaceGui") and string.sub(child.Name, 1, 12) == "Leaderboard_" then
			child.Parent = legacy
		end
	end
	legacy.Parent = storage

	mainSign(starterGui)
	joinSign(starterGui, RewardsCatalog.GROUP.Coins, RewardsCatalog.GROUP.Title)
end

return Build
