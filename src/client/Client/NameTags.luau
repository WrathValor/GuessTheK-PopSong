--| NameTags
-- Lobby name tags over other players (design board "Lobby name tags"): a white name plate
-- (same look as the rival tag) and, under it, a streak chip when they're on a win streak:
-- "4 win streak" + a dark ×1.2 / ×1.5 / ×2 coin-multiplier badge from 3 wins, yellow, and
-- orange from 10 wins. Hidden while that player is
-- in a duel (the "InDuel" attribute) — the rival tag takes over there. Built on this client
-- only, and replaces Roblox's default overhead name.
-- Streak comes from the "Streak" player attribute, which DataService mirrors from PlayerData.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)

local LOCAL_PLAYER = Players.LocalPlayer

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local ORANGE = C("FF9A5C") -- hot streak (10+)
local LILAC = C("B9A6FF") -- title chip (same as the HUD profile's)
local HOT_STREAK = 10
local MULT_FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local PLATE_H = 30
local CHIP_H = 22

local NameTags = {}

local tags: { [Player]: BillboardGui } = {}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function round(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function outline(parent: Instance, thickness: number)
	new("UIStroke", { Color = INK, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

-- auto-width face + hard shadow, centred, as in RivalTag
local function card(parent: Instance, name: string, y: number, height: number, radius: number, stroke: number, drop: number, colour: Color3)
	local group = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, parent)
	local shadow = new("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(drop, drop),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = INK,
		ZIndex = 1,
	}, group)
	round(shadow, radius)
	outline(shadow, stroke)
	local face = new("Frame", {
		Name = "Face",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
		BackgroundColor3 = colour,
		ZIndex = 2,
	}, group)
	round(face, radius)
	outline(face, stroke)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, face)
	return group, face
end

local function label(parent: Instance, text: string, size: number, height: number): TextLabel
	return new("TextLabel", {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextSize = size,
		TextColor3 = INK,
		Text = text,
		ZIndex = 3,
	}, parent)
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

local function refresh(player: Player)
	local bb = tags[player]
	if not bb then
		return
	end
	bb.Enabled = not player:GetAttribute("InDuel")
	local title = player:GetAttribute("Title")
	local titleChip = bb.Plate.Face:FindFirstChild("Title") :: TextLabel?
	if titleChip then
		titleChip.Text = if type(title) == "string" then title else ""
		titleChip.Visible = type(title) == "string" and title ~= ""
	end
	local streak = player:GetAttribute("Streak") or 0
	local chip = bb:FindFirstChild("Streak") :: Frame
	local face = chip:FindFirstChild("Face") :: Frame
	chip.Visible = streak > 0
	face.BackgroundColor3 = if streak >= HOT_STREAK then ORANGE else YELLOW
	;(face:FindFirstChild("Label") :: TextLabel).Text = `{streak} win streak`
	local mult = multiplierFor(streak)
	local badge = face:FindFirstChild("Mult") :: TextLabel
	badge.Visible = mult > 1
	badge.Text = `×{mult}`
end

local function build(player: Player, character: Model)
	if tags[player] then
		tags[player]:Destroy()
		tags[player] = nil
	end
	local head = character:WaitForChild("Head", 10) :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not head or not character.Parent then
		return
	end
	if humanoid then
		(humanoid :: Humanoid).DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local bb = new("BillboardGui", {
		Name = "NameTag",
		Adornee = head,
		Size = UDim2.fromOffset(240, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0),
		LightInfluence = 0,
		MaxDistance = 80,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local plate, plateFace = card(bb, "Plate", 0, PLATE_H, 11, 3, 3, WHITE)
	plate.ZIndex = 2
	-- [Title] Name
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, plateFace)
	plateFace:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, 8)
	local titleChip = new("TextLabel", {
		Name = "Title",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundColor3 = LILAC,
		FontFace = MULT_FONT,
		TextSize = 11,
		TextColor3 = INK,
		Text = "",
		ZIndex = 3,
		Visible = false,
	}, plateFace)
	round(titleChip, 6)
	outline(titleChip, 2)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, titleChip)
	local nameLabel = label(plateFace, player.DisplayName, 17, PLATE_H)
	nameLabel.LayoutOrder = 2
	local chip, chipFace = card(bb, "Streak", PLATE_H - 1, CHIP_H, 8, 2.5, 2, YELLOW)
	chip.ZIndex = 1
	chipFace:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, 9)
	chipFace:FindFirstChildOfClass("UIPadding").PaddingRight = UDim.new(0, 6)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, chipFace)
	local streakLabel = label(chipFace, "", 12, CHIP_H)
	streakLabel.LayoutOrder = 1
	-- dark coin-multiplier badge (×1.2 / ×1.5 / ×2)
	local badge = new("TextLabel", {
		Name = "Mult",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 15),
		BackgroundColor3 = INK,
		FontFace = MULT_FONT,
		TextSize = 11,
		TextColor3 = YELLOW,
		Text = "",
		ZIndex = 3,
		Visible = false,
	}, chipFace)
	round(badge, 5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, badge)

	bb.Parent = head
	tags[player] = bb
	refresh(player)
end

local function track(player: Player)
	if player == LOCAL_PLAYER then
		return -- you don't see your own tag
	end
	player:GetAttributeChangedSignal("InDuel"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Streak"):Connect(function()
		refresh(player)
	end)
	player:GetAttributeChangedSignal("Title"):Connect(function()
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
		if tags[player] then
			tags[player]:Destroy()
			tags[player] = nil
		end
	end)
end

return NameTags
