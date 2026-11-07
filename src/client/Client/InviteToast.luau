--| InviteToast
-- An invite someone sent you (the "Invites · received" board): a photocard toast at the top
-- of the screen with their headshot, a FRIEND tag, a title, a line of detail and ACCEPT /
-- DECLINE. It goes away by itself when the invite runs out. Two kinds use it:
--   • duel invites (InviteRemote): "X wants to duel!", level, streak, stage. Accept puts you
--     straight on their stage (Engine/InviteService).
--   • Party Stage invites (PartyController → InviteToast.Show): "X invited you", the mode and
--     how full the stage is.
-- Not an Interface controller: it has its own ScreenGui so it shows over any screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local W, H = 340, 112
local TOP = 70
local INVITE_TIME = 15 -- duel invites, when the packet has no Expires

local InviteToast = {}

local gui, card, shadow, current

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

	local photoShadow = new("Frame", { Name = "PhotoShadow", Position = UDim2.fromOffset(12 + 3, 10 + 3), Size = UDim2.fromOffset(44, 52), Rotation = -3, BackgroundColor3 = INK }, card)
	corner(photoShadow, 10)
	local photo = new("ImageLabel", { Name = "Photo", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(44, 52), Rotation = -3, BackgroundColor3 = LILAC_SOFT, ScaleType = Enum.ScaleType.Crop, Image = "", ZIndex = 2 }, card)
	corner(photo, 10)
	stroke(photo, 3)

	local tag = text(card, "Friend", { Position = UDim2.fromOffset(68, 8), Size = UDim2.fromOffset(52, 16), BackgroundTransparency = 0, BackgroundColor3 = PINK, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None, Text = "FRIEND" })
	corner(tag, 7)
	stroke(tag, 2)
	text(card, "Title", { Position = UDim2.fromOffset(68, 27), Size = UDim2.fromOffset(W - 80, 20), FontFace = HEAD, TextSize = 15, Text = "someone wants to duel!" })
	text(card, "Sub", { Position = UDim2.fromOffset(68, 48), Size = UDim2.fromOffset(W - 80, 16), FontFace = BODY_BOLD, TextSize = 10, TextColor3 = MUTED, Text = "Lv 1 · waiting on Stage 1" })

	local by = 70
	button(card, "Accept", 12, by, W - 28 - 92, 32, MINT, "ACCEPT", 14)
	button(card, "Decline", W - 12 - 84, by, 84, 32, RED, "DECLINE", 11)

	ButtonScale.ApplyToDescendants(card)
end

-- answer = true / false (the buttons) or nil (it ran out / was withdrawn)
local function hide(answer: boolean?)
	local shown = current
	current = nil
	if answer ~= nil and shown and shown.Answer then
		shown.Answer(answer)
	end
	if not gui or not gui.Enabled then
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

-- opts = { From = userId, Friend, Title, Sub, Expires (server time), Answer = fn(accept),
--          Kind = "Duel" | "Party" }
local function show(opts)
	current = opts
	card.Friend.Visible = opts.Friend == true
	card.Title.Position = UDim2.fromOffset(68, if opts.Friend then 27 else 18)
	card.Sub.Position = UDim2.fromOffset(68, if opts.Friend then 48 else 39)
	card.Title.Text = opts.Title or ""
	card.Sub.Text = opts.Sub or ""

	card.Photo.Image = ""
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, opts.From, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size150x150)
		if ok and current == opts then
			card.Photo.Image = img
		end
	end)

	gui.Enabled = true
	card.Pop.Scale, shadow.Pop.Scale = 0.6, 0.6
	local pop = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(card.Pop, pop, { Scale = 1 }):Play()
	TweenService:Create(shadow.Pop, pop, { Scale = 1 }):Play()
	Sounds.Play("Notify", { Volume = 0.75 })

	-- gone by itself when it runs out (the server tells the sender)
	local expires = opts.Expires or (workspace:GetServerTimeNow() + INVITE_TIME)
	task.delay(math.max(expires - workspace:GetServerTimeNow(), 0), function()
		if current == opts then
			hide()
		end
	end)
end

local function duelInvite(packet)
	local bits = { `Lv {packet.Level or 1}` }
	if (packet.Streak or 0) > 0 then
		table.insert(bits, `{packet.Streak} win streak`)
	end
	local stage = tostring(packet.Stage or ""):gsub("^DuelStage", "Stage ")
	table.insert(bits, `waiting on {stage}`)
	show({
		Kind = "Duel",
		From = packet.From,
		Friend = packet.Friend,
		Title = `{packet.Name} wants to duel!`,
		Sub = table.concat(bits, " · "),
		Expires = packet.Expires,
		Answer = function(accept)
			InviteRemote:Fire({ Action = "Answer", Accept = accept })
		end,
	})
end

-- --------------------------------- API ------------------------------------ --

-- Party Stage invites (PartyController) use the same toast; see show() for opts.
function InviteToast.Show(opts)
	if not gui then
		return
	end
	show(opts)
end

-- withdraw the toast if it's still showing this kind of invite (nil = any)
function InviteToast.Hide(kind: string?)
	if current and (kind == nil or current.Kind == kind) then
		hide()
	end
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
			duelInvite(packet)
		elseif packet.Message == "InviteGone" then
			InviteToast.Hide("Duel")
		end
	end)
end

return InviteToast
