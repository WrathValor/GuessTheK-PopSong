--| InviteToast
-- The duel invite someone sent you (the "Invites · received" board): a photocard toast at
-- the top of the screen with their headshot, a FRIEND tag, "X wants to duel!", their level,
-- streak and stage, ACCEPT / DECLINE and a bar that drains over the invite's 15 seconds.
-- Accept puts you straight on their stage (Engine/InviteService). Not an Interface
-- controller: it has its own ScreenGui so it shows over any screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)

local InviteRemote = Bridgenet.ReferenceBridge("InviteRemote")
local LOCAL_PLAYER = Players.LocalPlayer

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local MUTED = C("5C566B")
local LILAC_SOFT = C("DCD3FF")
local PINK = C("FF9EC4")
local MINT = C("A7E9B8")
local RED = C("FF5A4E")
local YELLOW = C("FFE07A")
local TRACK = C("EDE4D4")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local W, H = 480, 160
local TOP = 70
local INVITE_TIME = 15

local InviteToast = {}

local gui, card, shadow, current, drain

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

local function text(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local base = { Name = name, BackgroundTransparency = 1, TextColor3 = INK, FontFace = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number, colour: Color3, label: string, size: number): TextButton
	local s = new("Frame", { Name = name .. "Shadow", Position = UDim2.fromOffset(x + 4, y + 4), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK }, parent)
	corner(s, 12)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x + w / 2, y + h / 2), Size = UDim2.fromOffset(w, h), BackgroundColor3 = colour, AutoButtonColor = false, FontFace = HEAD, TextSize = size, TextColor3 = INK, Text = label, ZIndex = 2 }, parent)
	corner(b, 12)
	stroke(b, 3)
	return b
end

-- the same 1280 × 720 canvas scaling as the Interface frames
local function fit(scale: UIScale)
	local camera = workspace.CurrentCamera
	local function update()
		local v = camera.ViewportSize
		scale.Scale = math.min(v.X / 1280, v.Y / 720)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
end

local function build()
	gui = new("ScreenGui", { Name = "Invites", ResetOnSpawn = false, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, LOCAL_PLAYER:WaitForChild("PlayerGui"))
	local canvas = new("Frame", { Name = "Canvas", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1 }, gui)
	fit(new("UIScale", { Name = "Scale" }, canvas))

	shadow = new("Frame", { Name = "CardShadow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640 + 6, TOP + 6), Size = UDim2.fromOffset(W, H), BackgroundColor3 = INK }, canvas)
	corner(shadow, 16)
	card = new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(640, TOP), Size = UDim2.fromOffset(W, H), BackgroundColor3 = WHITE, ClipsDescendants = true }, canvas)
	corner(card, 16)
	stroke(card, 3)
	new("UIScale", { Name = "Pop" }, card)
	new("UIScale", { Name = "Pop" }, shadow)

	local photoShadow = new("Frame", { Name = "PhotoShadow", Position = UDim2.fromOffset(16 + 3, 14 + 3), Size = UDim2.fromOffset(64, 76), Rotation = -3, BackgroundColor3 = INK }, card)
	corner(photoShadow, 10)
	local photo = new("ImageLabel", { Name = "Photo", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(64, 76), Rotation = -3, BackgroundColor3 = LILAC_SOFT, ScaleType = Enum.ScaleType.Crop, Image = "", ZIndex = 2 }, card)
	corner(photo, 10)
	stroke(photo, 3)

	local tag = text(card, "Friend", { Position = UDim2.fromOffset(96, 16), Size = UDim2.fromOffset(56, 18), BackgroundTransparency = 0, BackgroundColor3 = PINK, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "FRIEND" })
	corner(tag, 7)
	stroke(tag, 2)
	text(card, "Title", { Position = UDim2.fromOffset(96, 40), Size = UDim2.fromOffset(W - 96 - 16, 24), FontFace = HEAD, TextSize = 19, Text = "someone wants to duel!" })
	text(card, "Sub", { Position = UDim2.fromOffset(96, 66), Size = UDim2.fromOffset(W - 96 - 16, 18), FontFace = BODY_BOLD, TextSize = 13, TextColor3 = MUTED, Text = "Lv 1 · waiting on Stage 1" })

	local by = 98
	button(card, "Accept", 16, by, W - 32 - 130, 46, MINT, "ACCEPT", 18)
	button(card, "Decline", W - 16 - 120, by, 120, 46, RED, "DECLINE", 14)

	local track = new("Frame", { Name = "Timer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = TRACK, BorderSizePixel = 0, ZIndex = 3 }, card)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = YELLOW, BorderSizePixel = 0, ZIndex = 3 }, track)
	new("Frame", { Name = "Edge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 3 }, fill)

	ButtonScale.ApplyToDescendants(card)
end

local function hide(answer: boolean?)
	if answer ~= nil and current then
		InviteRemote:Fire({ Action = "Answer", Accept = answer })
	end
	current = nil
	if drain then
		drain:Disconnect()
		drain = nil
	end
	if not gui.Enabled then
		return
	end
	local info = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(card.Pop, info, { Scale = 0.6 }):Play()
	TweenService:Create(shadow.Pop, info, { Scale = 0.6 }):Play()
	task.delay(0.14, function()
		if not current then
			gui.Enabled = false
		end
	end)
end

local function show(packet)
	current = packet
	card.Friend.Visible = packet.Friend == true
	card.Title.Position = UDim2.fromOffset(96, if packet.Friend then 40 else 26)
	card.Sub.Position = UDim2.fromOffset(96, if packet.Friend then 66 else 54)
	card.Title.Text = `{packet.Name} wants to duel!`
	local bits = { `Lv {packet.Level or 1}` }
	if (packet.Streak or 0) > 0 then
		table.insert(bits, `{packet.Streak} win streak`)
	end
	local stage = tostring(packet.Stage or ""):gsub("^DuelStage", "Stage ")
	table.insert(bits, `waiting on {stage}`)
	card.Sub.Text = table.concat(bits, " · ")

	card.Photo.Image = ""
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, packet.From, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size150x150)
		if ok and current == packet then
			card.Photo.Image = img
		end
	end)

	gui.Enabled = true
	card.Pop.Scale, shadow.Pop.Scale = 0.6, 0.6
	local pop = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(card.Pop, pop, { Scale = 1 }):Play()
	TweenService:Create(shadow.Pop, pop, { Scale = 1 }):Play()
	Sounds.Play("Notify", { Volume = 0.75 })

	if drain then
		drain:Disconnect()
	end
	local expires = packet.Expires or (workspace:GetServerTimeNow() + INVITE_TIME)
	drain = RunService.RenderStepped:Connect(function()
		local left = expires - workspace:GetServerTimeNow()
		card.Timer.Fill.Size = UDim2.fromScale(math.clamp(left / INVITE_TIME, 0, 1), 1)
		if left <= 0 then
			hide() -- the server sends Expired to the sender
		end
	end)
end

-- --------------------------------- Start ---------------------------------- --

function InviteToast.Start()
	build()
	card.Accept.Activated:Connect(function()
		Sounds.Play("Click")
		hide(true)
	end)
	card.Decline.Activated:Connect(function()
		Sounds.Play("Click")
		hide(false)
	end)
	InviteRemote:Connect(function(packet)
		if type(packet) ~= "table" then
			return
		end
		if packet.Message == "Invite" then
			show(packet)
		elseif packet.Message == "InviteGone" then
			hide()
		end
	end)
end

return InviteToast
