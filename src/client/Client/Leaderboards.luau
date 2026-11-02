--| Leaderboards
-- The three signs at Map.Landmarks.Leaderboards (design board "Leaderboards · the three map
-- signs"): Board1 Weekly Wins, Board2 Top Streaks, Board3 Join the Group. Each face is 16×20
-- studs at 40 px/stud = 640 × 800. Built on this client (SurfaceGuis in PlayerGui, adorned
-- to the board parts), so the Join sign can show this player's own button and your own row
-- is highlighted. The boards' data comes from Scribe (PlayerData Leaderboards: WeeklyWins,
-- TopStreaks), which writes, reads and replicates them.
-- Join button: Join the group (Roblox prompt) → Claim rewards → Claimed ✓ (RewardsService
-- checks everything again).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local RewardsCatalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)

local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local CREAM = C("FBF7F0")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local LILAC = C("B9A6FF")
local PINK = C("FF9EC4")
local BLUE = C("9ED8F5")
local GREY = C("EDE4D4")
local MUTED = C("5C566B")
local MINE = C("FFF1B8") -- your own row
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local COIN = "rbxassetid://105055420801588"

local W, H = 640, 800
local SIGN_BRIGHTNESS = 1.7
local SIGN_LIGHT_INFLUENCE = 0.35
local HEADER = 118
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
	ColorSequenceKeypoint.new(1, C("B5DDFF")),
})

local Leaderboards = {}

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

-- a face with a hard ink shadow behind it
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

local function surface(board: BasePart, name: string): (SurfaceGui, Frame)
	-- the placeholder text on the part itself goes (this client draws the real sign)
	for _, g in board:GetChildren() do
		if g:IsA("SurfaceGui") then
			g.Enabled = false
		end
	end
	local gui = new("SurfaceGui", {
		Name = name,
		Adornee = board,
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
	}, LOCAL_PLAYER:WaitForChild("PlayerGui"))
	local face = new("Frame", { Name = "Face", Size = UDim2.fromOffset(W, H), BackgroundColor3 = CREAM, BorderSizePixel = 0 }, gui)
	corner(face, 18)
	stroke(face, 4)
	return gui, face
end

local function header(face: Frame, title: string, sub: string, subColour: Color3): TextLabel
	local h = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, HEADER), BackgroundColor3 = INK, BorderSizePixel = 0 }, face)
	corner(h, 16)
	-- square off the header's bottom corners
	new("Frame", { Name = "Square", Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = INK, BorderSizePixel = 0 }, h)
	label(h, "Title", { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 48), FontFace = HEAD, TextSize = 44, TextColor3 = WHITE, Text = title })
	return label(h, "Sub", { Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = subColour, Text = sub })
end

local function headshot(userId: number): string
	return `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

-- --------------------------- Podium + list boards -------------------------- --

-- podium order on screen: 2nd, 1st, 3rd
local SLOTS = {
	{ Place = 2, W = 170, H = 262, Bg = C("DCD3FF") },
	{ Place = 1, W = 196, H = 304, Bg = WHITE, Rainbow = true },
	{ Place = 3, W = 170, H = 246, Bg = C("CDEBFA") },
}

local function rankBoard(board: BasePart, name: string, title: string, sub: string, subColour: Color3, bg: Color3, unit: string)
	local gui, face = surface(board, name)
	face.BackgroundColor3 = bg
	local subLabel = header(face, title, sub, subColour)

	local podium = new("Frame", { Name = "Podium", Position = UDim2.fromOffset(0, HEADER), Size = UDim2.fromOffset(W, 330), BackgroundTransparency = 1 }, face)
	local total, gap = 0, 18
	for _, s in SLOTS do
		total += s.W
	end
	local x = math.floor((W - total - gap * 2) / 2)
	local cards = {}
	for _, s in SLOTS do
		local c = card(podium, "Place" .. s.Place, x, 330 - 10 - s.H, s.W, s.H, WHITE, 16, 6, 3)
		local photo = new("Frame", { Name = "Photo", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -10 - 8 - 22 - 4 - 30 - 6), BackgroundColor3 = s.Bg, ClipsDescendants = true }, c)
		corner(photo, 10)
		stroke(photo, 2)
		if s.Rainbow then
			new("UIGradient", { Color = RAINBOW, Rotation = 25 }, photo)
		end
		new("ImageLabel", { Name = "Avatar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 1), SizeConstraint = Enum.SizeConstraint.RelativeXX, BackgroundTransparency = 1, Image = "" }, photo)
		label(c, "PlayerName", { Position = UDim2.new(0, 8, 1, -8 - 30 - 4 - 22), Size = UDim2.new(1, -16, 0, 22), TextSize = 18, Text = "—" })
		label(c, "Value", { Position = UDim2.new(0, 8, 1, -8 - 30), Size = UDim2.new(1, -16, 0, 30), FontFace = HEAD, TextSize = 26, Text = "" })
		local badge = new("TextLabel", {
			Name = "Badge",
			Position = UDim2.fromOffset(-14, -14),
			Size = UDim2.fromOffset(42, 42),
			BackgroundColor3 = if s.Place == 1 then YELLOW else WHITE,
			FontFace = HEAD,
			TextSize = 19,
			TextColor3 = INK,
			Text = tostring(s.Place),
			ZIndex = 3,
		}, c)
		corner(badge, 21)
		stroke(badge, 3)
		cards[s.Place] = c
		x += s.W + gap
	end

	local listY = HEADER + 330 + 6
	local list = card(face, "List", 18, listY, W - 36, H - listY - 18, CREAM, 14, 0, 3)
	local rowsH = H - listY - 18 - 20
	local rowH = math.floor((rowsH - 6 * 6) / 7)
	local rows = {}
	for i = 1, 7 do
		local r = new("Frame", { Name = "Row" .. (i + 3), Position = UDim2.fromOffset(12, 10 + (i - 1) * (rowH + 6)), Size = UDim2.new(1, -24, 0, rowH), BackgroundColor3 = WHITE }, list)
		corner(r, 10)
		stroke(r, 2)
		label(r, "Rank", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 34, 1, 0), FontFace = HEAD, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(i + 3) })
		label(r, "PlayerName", { Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -52 - 90, 1, 0), TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Text = "—" })
		label(r, "Value", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 90, 1, 0), FontFace = HEAD, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
		rows[i + 3] = r
	end

	local function fill()
		local ok, entries = pcall(PlayerData.GetLeaderboard, name, 10)
		entries = if ok and type(entries) == "table" then entries else {}
		-- nobody shows with a score of 0 (a fresh week, or a streak that never started)
		local shown = {}
		for _, e in entries do
			if type(e.Score) ~= "number" or e.Score > 0 then
				table.insert(shown, e)
			end
		end
		entries = shown
		for place = 1, 10 do
			local e = entries[place]
			local mine = e ~= nil and e.UserId == LOCAL_PLAYER.UserId
			local value = if e then (if type(e.Score) == "number" then tostring(e.Score) else tostring(e.Score)) else ""
			if place <= 3 then
				local c = cards[place]
				c.PlayerName.Text = if e then e.Name else "—"
				c.Value.Text = if e then `{value} {unit}` else ""
				c.Photo.Avatar.Image = if e then headshot(e.UserId) else ""
				c.BackgroundColor3 = if mine then MINE else WHITE
			else
				local r = rows[place]
				r.PlayerName.Text = if e then e.Name else "—"
				r.Value.Text = value
				r.BackgroundColor3 = if mine then MINE else WHITE
			end
		end
	end
	fill()
	pcall(function()
		PlayerData.OnLeaderboard:Connect(function(boardName)
			if boardName == name then
				fill()
			end
		end)
	end)
	-- the replicated cache can land before OnLeaderboard is hooked; poll a little too
	task.spawn(function()
		while gui.Parent do
			task.wait(30)
			fill()
		end
	end)
	return gui, subLabel
end

-- ------------------------------ Join the Group ----------------------------- --

local JOIN_STATES = {
	Join = { Note = "Join Wrath's UGC to unlock all three", Label = "JOIN THE GROUP", Bg = MINT, Text = INK, Shadow = true },
	Claim = { Note = "You're in! Your rewards are waiting", Label = "CLAIM REWARDS", Bg = YELLOW, Text = INK, Shadow = true },
	Claimed = { Note = "Thanks for joining Wrath's UGC", Label = "CLAIMED ✓", Bg = GREY, Text = C("6B647A"), Shadow = false },
}

local function joinBoard(board: BasePart)
	local _, face = surface(board, "JoinTheGroup")
	face.BackgroundColor3 = PINK
	header(face, "JOIN THE GROUP", "FREE REWARDS · ONE TIME", MINT)
	label(face, "Heading", { Position = UDim2.fromOffset(0, HEADER + 24), Size = UDim2.new(1, 0, 0, 36), FontFace = HEAD, TextSize = 30, Text = "3 free rewards for joining" })

	-- three reward photocards, the middle (group stage) biggest
	local top = HEADER + 24 + 36
	local area = 392
	local specs = {
		{ Name = "Coins", W = 186, H = 278, Big = tostring(RewardsCatalog.GROUP.Coins), Small = "coins", Bg = C("FFF6D6") },
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
			-- the real group stage with your avatar on it, like the shop cards (CosmeticView);
			-- the drawn shapes below only show until the model has loaded
			art.BackgroundColor3 = C("4A3F78")
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
			CosmeticView.Show(art, "Stage", RewardsCatalog.GROUP.Stage)
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
				Text = RewardsCatalog.GROUP.Title,
				Rotation = -4,
			}, art)
			corner(chip, 12)
			stroke(chip, 3)
		end
		x += s.W + 16
	end

	-- the button that follows this player
	local bottomTop = top + area
	local note = label(face, "Note", { Position = UDim2.fromOffset(0, bottomTop + 20), Size = UDim2.new(1, 0, 0, 24), TextSize = 19, TextColor3 = C("4A2440"), Text = "" })
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
		Text = "",
		AutoButtonColor = false,
	}, face)
	corner(button, 16)
	stroke(button, 4)

	local inGroup = false
	local busy = false
	local function claimed(): boolean
		local ok, v = pcall(PlayerData.Rewards.Claimed.Has, RewardsCatalog.GROUP.ClaimedKey)
		return ok and v == true
	end
	local function state(): string
		return if claimed() then "Claimed" elseif inGroup then "Claim" else "Join"
	end
	local function paint()
		local s = JOIN_STATES[state()]
		note.Text = s.Note
		button.Text = if busy then "…" else s.Label
		button.BackgroundColor3 = s.Bg
		button.TextColor3 = s.Text
		shadow.Visible = s.Shadow
		button.Active = state() ~= "Claimed"
	end

	button.Activated:Connect(function()
		if busy then
			return
		end
		local now = state()
		if now == "Claim" then
			RewardsRemote:Fire({ Action = "ClaimGroup" })
		elseif now == "Join" then
			busy = true
			paint()
			task.spawn(function()
				local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, RewardsCatalog.GROUP.GroupId)
				AnalyticsClient.Event("GroupJoinPrompt", 1, if not ok then "Error"
					elseif status == Enum.GroupMembershipStatus.Joined then "Joined"
					elseif status == Enum.GroupMembershipStatus.AlreadyMember then "AlreadyMember"
					elseif status == Enum.GroupMembershipStatus.JoinRequestPending then "Pending"
					else "Cancelled")
				busy = false
				if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
					inGroup = true
					RewardsRemote:Fire({ Action = "ClaimGroup" }) -- straight to the reward
				end
				paint()
			end)
		end
	end)
	pcall(function()
		PlayerData.Rewards.Claimed.Observe(paint)
	end)
	task.spawn(function()
		local ok, member = pcall(LOCAL_PLAYER.IsInGroup, LOCAL_PLAYER, RewardsCatalog.GROUP.GroupId)
		inGroup = ok and member == true
		paint()
	end)
	paint()
end

-- ---------------------------------- Start ---------------------------------- --

-- weekly boards reset Monday 00:00 UTC (PlayerData PeriodReset)
local WEEK, MONDAY0 = 7 * 86400, 4 * 86400 -- 1970-01-05 was a Monday
local function resetText(): string
	local now = os.time()
	local left = (math.floor((now - MONDAY0) / WEEK) + 1) * WEEK + MONDAY0 - now
	local d, h = math.floor(left / 86400), math.floor(left % 86400 / 3600)
	return if d > 0 then `RESETS MONDAY · {d}D {h}H` else `RESETS IN {h}H {math.floor(left % 3600 / 60)}M`
end

function Leaderboards.Start()
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		local folder = map and map:WaitForChild("Landmarks", 30)
		folder = folder and folder:WaitForChild("Leaderboards", 30)
		if not folder then
			warn("[Leaderboards] Map.Landmarks.Leaderboards not found")
			return
		end
		local weekly, streaks, join = folder:WaitForChild("Board1", 10), folder:WaitForChild("Board2", 10), folder:WaitForChild("Board3", 10)
		local _, weeklySub
		if weekly then
			_, weeklySub = rankBoard(weekly, "WeeklyWins", "WEEKLY WINS", resetText(), YELLOW, MINT, "wins")
		end
		if streaks then
			rankBoard(streaks, "TopStreaks", "TOP STREAKS", "BEST WIN STREAK · ALL TIME", PINK, LILAC, "streak")
		end
		if join then
			joinBoard(join)
		end
		while weeklySub and weeklySub.Parent do
			weeklySub.Text = resetText()
			task.wait(30)
		end
	end)
end

return Leaderboards
