--| NameTags
-- Lobby name tags over other players (design board "Name tags · new format"): the name alone
-- on a white plate, and under it one row of small chips: ★ VIP, the player's title, and their
-- win streak (the flame icon, the count, and a dark ×1.2 / ×1.5 / ×2 coin-multiplier badge from
-- 3 wins; yellow, orange from 10). A row with no chips hides. Hidden while that player is in a
-- duel (the "InDuel" attribute): the rival tag takes over there. Replaces Roblox's default
-- overhead name. Phones and tablets draw every tag at TOUCH_SCALE (a fixed-pixel tag covers far
-- more of a small screen). Your own tag shows too, at SELF_SCALE: it sits in the middle of your
-- screen, so full size would cover a lot of the view.
-- The tag is ReplicatedStorage.Assets.NameTag (a BillboardGui made in Studio), cloned per
-- player; the title chip is Modules/UI/TitleChip's.
-- VIP Pass owners (the "VIP" attribute): a gold plate (the Face's "Gold" gradient, pale at the
-- ends) with a white band sweeping across it every few seconds (Face.Gloss: a white frame whose
-- "Band" gradient is see-through except one stripe, slid along with Offset, so it keeps to the
-- rounded corners and stays under the name), a crown on its top-left corner and three
-- twinkling sparkles (looping tweens, only while the tag is a VIP's), plus the ★ VIP chip.
-- UIScale doesn't thin outlines, so a scaled-down tag scales its UIStrokes itself.
-- Streak comes from the "Streak" player attribute, which DataService mirrors from PlayerData.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local TitleChip = require(ReplicatedStorage.Modules.UI.TitleChip)

local LOCAL_PLAYER = Players.LocalPlayer
local TEMPLATE = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("NameTag", 10) :: BillboardGui?

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local ORANGE = C("FF9A5C") -- hot streak (10+)
-- (the title chip is shared/Modules/UI/TitleChip)
local HOT_STREAK = 10
local MULT_FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)

local CROWN_AT = UDim2.fromOffset(2, -4) -- the crown's spot on the plate (it stays still)
local CROWN_TILT = -14
local SHINE_FROM, SHINE_TO = Vector2.new(-1.1, 0), Vector2.new(1.1, 0) -- the band's sweep (gradient Offset)
local SHINE_TIME, SHINE_GAP = 1.1, 1.5 -- seconds across, then a pause
local SELF_SCALE = 0.95 -- the local player's own tag, relative to everyone else's
local TOUCH_SCALE = 0.7 -- every tag on phones / tablets (touch screen, no mouse)

local NameTags = {}

local tags: { [Player]: BillboardGui } = {}
local effects: { [Player]: { Tween } } = {} -- a VIP tag's looping crown + sparkle tweens

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- coin multiplier for a streak (DuelConstants.STREAK_MULTIPLIERS = { {wins, mult}, ... })
local function multiplierFor(streak: number): number
	local best = 1
	for _, pair in DuelConstants.STREAK_MULTIPLIERS do
		if streak >= pair[1] and pair[2] > best then
			best = pair[2]
		end
	end
	return best
end

local function stopEffects(player: Player)
	for _, tween in effects[player] or {} do
		tween:Cancel()
	end
	effects[player] = nil
end

-- the VIP crown sits still; the sparkles twinkle, each sparkle a little out of step
local function startEffects(player: Player, plate: Frame)
	stopEffects(player)
	local list = {}
	local crown = plate:FindFirstChild("Crown") :: ImageLabel
	crown.Position = CROWN_AT
	crown.Rotation = CROWN_TILT
	for i, sparkle in (plate:FindFirstChild("Sparkles") :: Frame):GetChildren() do
		if sparkle:IsA("ImageLabel") then
			sparkle.ImageTransparency = 1
			sparkle.Rotation = 0
			table.insert(list, TweenService:Create(sparkle, TweenInfo.new(0.7 + i * 0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, i * 0.3), {
				ImageTransparency = 0,
				Rotation = 45,
			}))
		end
	end
	local band = plate.Face.Gloss.Band :: UIGradient
	band.Offset = SHINE_FROM
	table.insert(list, TweenService:Create(band, TweenInfo.new(SHINE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, SHINE_GAP), {
		Offset = SHINE_TO,
	}))
	for _, tween in list do
		tween:Play()
	end
	effects[player] = list
end

local function refresh(player: Player)
	local bb = tags[player]
	if not bb then
		return
	end
	bb.Enabled = not player:GetAttribute("InDuel")
	local plate = bb.Tag.Plate
	local chips = bb.Tag.Chips

	local vip = player:GetAttribute("VIP") == true
	plate.Face.BackgroundColor3 = WHITE
	plate.Face.Gold.Enabled = vip
	plate.Face.Gloss.Visible = vip
	plate.Crown.Visible = vip
	plate.Sparkles.Visible = vip
	chips.VIP.Visible = vip
	if vip and not effects[player] then
		startEffects(player, plate)
	elseif not vip then
		stopEffects(player)
	end

	local title = player:GetAttribute("Title")
	local titleChip = chips:FindFirstChild("Title")
	if titleChip then
		TitleChip.Set(titleChip, if type(title) == "string" then title else nil, player:GetAttribute("TitleTier"))
	end

	local streak = player:GetAttribute("Streak") or 0
	local chip = chips.Streak
	chip.Visible = streak > 0
	chip.BackgroundColor3 = if streak >= HOT_STREAK then ORANGE else YELLOW
	chip.Count.Text = tostring(streak)
	local mult = multiplierFor(streak)
	chip.Mult.Visible = mult > 1
	chip.Mult.Text = `×{mult}`

	chips.Visible = vip or streak > 0 or (titleChip ~= nil and (titleChip :: GuiObject).Visible)
end

local function build(player: Player, character: Model)
	stopEffects(player)
	if tags[player] then
		tags[player]:Destroy()
		tags[player] = nil
	end
	local head = character:WaitForChild("Head", 10) :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not head or not character.Parent or not TEMPLATE then
		return
	end
	if humanoid then
		(humanoid :: Humanoid).DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local bb = TEMPLATE:Clone()
	bb.Adornee = head
	bb.Tag.Plate.Face.Label.Text = player.DisplayName
	-- the title chip (shared/Modules/UI/TitleChip), between ★ VIP and the streak
	local titleChip = TitleChip.new(bb.Tag.Chips, { Name = "Title", LayoutOrder = 1, Height = 20, TextSize = 13, Font = MULT_FONT, ZIndex = 3 })
	titleChip.Visible = false

	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local scale = (if player == LOCAL_PLAYER then SELF_SCALE else 1) * (if touch then TOUCH_SCALE else 1)
	if scale ~= 1 then
		-- smaller, around the middle of the tag so it stays where the full-size one was
		bb.Tag.AnchorPoint = Vector2.new(0.5, 0.5)
		bb.Tag.Position = UDim2.fromScale(0.5, 0.5)
		new("UIScale", { Scale = scale }, bb.Tag)
		for _, stroke in bb:GetDescendants() do
			if stroke:IsA("UIStroke") then
				stroke.Thickness *= scale
			end
		end
	end

	bb.Parent = head
	tags[player] = bb
	refresh(player)
end

local function track(player: Player)
	--[[if player == LOCAL_PLAYER then
		return -- you don't see your own tag
	end]]--
	player:GetAttributeChangedSignal("InDuel"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Streak"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Title"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("TitleTier"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("VIP"):Connect(function()
		refresh(player)
	end)
	player.CharacterAdded:Connect(function(character)
		build(player, character)
	end)
	if player.Character then
		task.spawn(build, player, player.Character)
	end
end

function NameTags.Start()
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		stopEffects(player)
		if tags[player] then
			tags[player]:Destroy()
			tags[player] = nil
		end
	end)
end

return NameTags
