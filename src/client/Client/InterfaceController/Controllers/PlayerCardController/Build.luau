--| Player card UI builder
-- Builds Interface.Frames.PlayerCard from the "Profile 2 · clicking another player" design
-- board: a blue top with their photocard, name, title + level chips side by side (Chips) and
-- best board rank; four stat tiles; their 5-card showcase; their streak (flame icon); and Invite
-- to Duel. Also the "View Profile" ProximityPrompt template the controller puts on other players
-- (ReplicatedStorage.Assets.ViewProfilePrompt). Run once in Studio (an existing frame is kept as
-- ServerStorage.PlayerCard_Legacy):
--   require(<this module>).Build(game.StarterGui.Interface.Frames)
-- PlayerCardController finds everything by name. Song cards and the title chip come from
-- ProfileController/Build.

local ProfileBuild = require(script.Parent.Parent.ProfileController.Build)

local new, corner, stroke, text, card, button = ProfileBuild.new, ProfileBuild.corner, ProfileBuild.stroke, ProfileBuild.text, ProfileBuild.card, ProfileBuild.button

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local BLUE = C("9ED8F5")
local YELLOW = C("FFE07A")
local RED = C("FF5A4E")
local MINT = C("A7E9B8")
local MUTED = C("5C566B")
local BODYTEXT = C("4A4458")

local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local Build = {}

-- the stat tiles, in grid order (PlayerCardController fills them from the player's attributes)
Build.STATS = {
	{ Name = "Wins", Label = "WINS", Colour = "A7E9B8" },
	{ Name = "BestStreak", Label = "BEST STREAK", Colour = "FFD2CE" },
	{ Name = "Perfect", Label = "PERFECT GAMES", Colour = "FFE07A" },
	{ Name = "Songs", Label = "SONGS OWNED", Colour = "DCD3FF" },
}
Build.SHOWCASE = 5
Build.ATLAS = "rbxassetid://87950570350196" -- gtks_atlas0 (assets/ui/atlas.json)
Build.FLAME = Vector2.new(800, 0) -- i_flame_coral

local W, H = 470, 568

function Build.Build(frames: Instance)
	local old = frames:FindFirstChild("PlayerCard")
	if old then
		local storage = game:GetService("ServerStorage")
		local keep = storage:FindFirstChild("PlayerCard_Legacy")
		if keep then
			keep:Destroy()
		end
		old.Name = "PlayerCard_Legacy"
		old.Parent = storage
	end

	local root = new("Frame", { Name = "PlayerCard", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false })
	local scrim = new("Frame", {
		Name = "Scrim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 360),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
	}, root)
	scrim.Active = true
	-- clicking outside the card closes it
	local away = new("TextButton", { Name = "Away", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, 360), Size = UDim2.fromOffset(4000, 4000), BackgroundTransparency = 1, Text = "" }, root)
	away:SetAttribute("NoButtonScale", true)

	local panel = card(root, "Panel", UDim2.fromOffset((1280 - W) / 2, (720 - H) / 2), UDim2.fromOffset(W, H), CREAM, 22, 9, 3)
	panel.ClipsDescendants = true

	-- top: who they are
	local top = new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 134), BackgroundColor3 = BLUE, BorderSizePixel = 0 }, panel)
	new("Frame", { Name = "Rule", Position = UDim2.fromOffset(0, 134), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK, BorderSizePixel = 0 }, panel)
	local pc = new("Frame", { Name = "Photocard", Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(92, 106), BackgroundColor3 = WHITE, Rotation = -3 }, top)
	corner(pc, 12)
	stroke(pc, 3)
	ProfileBuild.Photo(pc, UDim2.fromOffset(6, 6), UDim2.new(1, -12, 1, -12), 2)
	text(top, "PlayerName", { Position = UDim2.fromOffset(128, 16), Size = UDim2.fromOffset(W - 128 - 70, 32), FontFace = HEAD, TextSize = 24, Text = "Player" })
	-- title + level, side by side
	local chips = new("Frame", { Name = "Chips", Position = UDim2.fromOffset(128, 54), Size = UDim2.fromOffset(W - 128 - 18, 28), BackgroundTransparency = 1 }, top)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	local title = ProfileBuild.TitleLabel(chips, "Title", UDim2.new(), UDim2.fromOffset(0, 28), 15, 0)
	title.LayoutOrder = 1
	local lv = new("TextLabel", { Name = "Level", LayoutOrder = 2, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, FontFace = BODY, TextSize = 14, TextColor3 = WHITE, Text = "LV 1" }, chips)
	corner(lv, 9)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, lv)
	text(top, "Rank", { Position = UDim2.fromOffset(128, 92), Size = UDim2.fromOffset(W - 128 - 18, 22), TextSize = 15, Text = "" })
	local cs = new("Frame", { Name = "CloseShadow", Position = UDim2.fromOffset(W - 18 - 40 + 3, 14 + 3), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = INK }, top)
	corner(cs, 11)
	local close = new("ImageButton", { Name = "Close", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W - 18 - 20, 14 + 20), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = RED, Image = "", AutoButtonColor = false }, top)
	corner(close, 11)
	stroke(close, 3)
	new("ImageLabel", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1, Image = ProfileBuild.ICONS.Close }, close)

	local body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(18, 137 + 16), Size = UDim2.fromOffset(W - 36, H - 137 - 32), BackgroundTransparency = 1 }, panel)
	local bw = W - 36

	-- stat tiles, 2 × 2
	local stats = new("Frame", { Name = "Stats", Size = UDim2.fromOffset(bw, 126), BackgroundTransparency = 1 }, body)
	local tw, th = math.floor((bw - 10) / 2), 58
	for i, spec in Build.STATS do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local tile = card(stats, spec.Name, UDim2.fromOffset(col * (tw + 10), row * (th + 10)), UDim2.fromOffset(tw, th), C(spec.Colour), 12, 0, 3)
		text(tile, "Label", { Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -24, 0, 14), TextSize = 12, TextColor3 = BODYTEXT, Text = spec.Label })
		text(tile, "Value", { Position = UDim2.fromOffset(12, 22), Size = UDim2.new(1, -24, 0, 30), FontFace = HEAD, TextSize = 24, Text = "0" })
	end

	-- their showcase
	text(body, "ShowcaseHeading", { Position = UDim2.fromOffset(0, 140), Size = UDim2.fromOffset(200, 22), FontFace = HEAD, TextSize = 16, Text = "Showcase" })
	local showcase = new("Frame", { Name = "Showcase", Position = UDim2.fromOffset(0, 168), Size = UDim2.fromOffset(bw, 110), BackgroundTransparency = 1 }, body)
	local cw, ch = 76, 104
	local gap = math.floor((bw - 6 - Build.SHOWCASE * cw) / (Build.SHOWCASE - 1))
	local tilt = { -3, 2, -1, 3, -2 }
	for i = 1, Build.SHOWCASE do
		ProfileBuild.SongCard(showcase, "Card" .. i, UDim2.fromOffset(2 + (i - 1) * (cw + gap), 2), cw, ch, tilt[i])
	end
	text(showcase, "Empty", { Size = UDim2.fromScale(1, 1), FontFace = BODY, TextSize = 14, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, Text = "No cards yet", Visible = false })

	-- their streak (same rule as the lobby name tag: from 3 wins)
	local streak = new("Frame", { Name = "Streak", Position = UDim2.fromOffset(0, 290), Size = UDim2.fromOffset(bw, 40), BackgroundColor3 = WHITE }, body)
	corner(streak, 12)
	stroke(streak, 3)
	new("ImageLabel", { Name = "Flame", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Image = Build.ATLAS, ImageRectOffset = Build.FLAME, ImageRectSize = Vector2.new(96, 96) }, streak)
	text(streak, "Text", { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -42 - 76, 1, 0), TextSize = 16, Text = "On a 0 win streak" })
	local mult = new("TextLabel", { Name = "Mult", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(52, 24), BackgroundColor3 = INK, FontFace = BODY, TextSize = 14, TextColor3 = YELLOW, Text = "×1.5" }, streak)
	corner(mult, 8)

	button(body, "Invite", 0, 344, bw - 5, 58, MINT, "INVITE TO DUEL", 19)
	root.Parent = frames
	Build.Prompt()
	return root
end

-- The "View Profile" prompt (ReplicatedStorage.Assets.ViewProfilePrompt): the controller puts a
-- copy on every other player's HumanoidRootPart, so walking up to someone shows it.
function Build.Prompt(): ProximityPrompt
	local assets = game:GetService("ReplicatedStorage"):WaitForChild("Assets")
	local old = assets:FindFirstChild("ViewProfilePrompt")
	if old then
		old:Destroy()
	end
	return new("ProximityPrompt", {
		Name = "ViewProfilePrompt",
		ActionText = "View Profile",
		ObjectText = "",
		KeyboardKeyCode = Enum.KeyCode.F, -- E is the duel stages' Join Duel
		GamepadKeyCode = Enum.KeyCode.ButtonY,
		HoldDuration = 0,
		MaxActivationDistance = 9,
		RequiresLineOfSight = false,
		Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton, -- just the nearest player's
		UIOffset = Vector2.new(0, 0),
	}, assets)
end

return Build
