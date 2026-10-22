--| LoadingCard
-- Round-start UI from the "Round start · loading audio" design boards:
--   • Loading: the screen dims and a card in the middle says "Loading audio…" (or
--     "Loading dance…") with bouncing equaliser bars and a scrolling striped bar.
--   • Ready: once loaded, nothing auto-plays — a red ring pulses round the Play button and
--     a "Ready! Press play" sticker bobs above it until the player presses play.
-- The UI itself lives in Studio (Interface.Frames.Game: LoadingDim + LoadingCard, and
-- ReadyRing + ReadySticker under Controls.PlayButton). LoadingCard.Build made it once and
-- can rebuild it; LoadingCard.new just finds it and drives the animations.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local LILAC = C("B9A6FF")
local LILAC_LIGHT = C("DCD3FF")
local RED = C("FF5A4E")
local MUTED = C("5C566B")
local HEAVY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
local BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local Z = 60 -- above the round controls and the scoreboard
local POP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE = TweenInfo.new(0.25)

local LoadingCard = {}
LoadingCard.__index = LoadingCard

-- Diagonal stripes for the progress bar, shifted by `phase` (0–1 = one stripe pair).
-- Animated by rebuilding the gradient: the card is tilted, and Roblox doesn't clip inside
-- rotated frames, so a sliding strip would poke out of the bar.
local BAND = 0.125
local function stripes(phase: number): ColorSequence
	local keys = {}
	local x = (phase % 1) * 2 * BAND - 2 * BAND
	local k = 0
	while x < 1 do
		local a, b = math.max(x, 0), math.min(x + BAND, 1)
		if b - a > 0.002 then
			local colour = if k % 2 == 0 then LILAC else LILAC_LIGHT
			table.insert(keys, ColorSequenceKeypoint.new(a, colour))
			table.insert(keys, ColorSequenceKeypoint.new(b - 0.0005, colour))
		end
		x += BAND
		k += 1
	end
	keys[1] = ColorSequenceKeypoint.new(0, keys[1].Value)
	keys[#keys] = ColorSequenceKeypoint.new(1, keys[#keys].Value)
	return ColorSequence.new(keys)
end

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
	new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r) }, p)
end

local function stroke(p: Instance, t: number, colour: Color3?)
	return new("UIStroke", {
		Color = colour or INK,
		Thickness = t,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, p)
end

-- a face with a hard ink shadow behind it, both children of `parent`
local function card(parent: Instance, name: string, pos: UDim2, size: UDim2, colour: Color3, radius: number, drop: number, line: number, z: number)
	local shadow = new("Frame", {
		Name = name .. "Shadow",
		Position = pos + UDim2.fromOffset(drop, drop),
		Size = size,
		BackgroundColor3 = INK,
		ZIndex = z,
	}, parent)
	corner(shadow, radius)
	local face = new("Frame", {
		Name = name,
		Position = pos,
		Size = size,
		BackgroundColor3 = colour,
		ZIndex = z + 1,
	}, parent)
	corner(face, radius)
	stroke(face, line)
	return face, shadow
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = INK,
		FontFace = HEAVY,
		TextSize = 14,
		ZIndex = Z + 3,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base, parent)
end

-- --------------------------------- Build ---------------------------------- --
-- Creates the instances (run once in Studio; replaces any old copy).
function LoadingCard.Build(gameFrame: Frame, playButton: GuiButton)
	for _, old in { gameFrame:FindFirstChild("LoadingDim"), gameFrame:FindFirstChild("LoadingCard"), playButton:FindFirstChild("ReadyRing"), playButton:FindFirstChild("ReadySticker") } do
		old:Destroy()
	end
	local self = {} :: any

	-- dims the stage, scoreboard and controls while loading
	self.Dim = new("Frame", {
		Name = "LoadingDim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4000, 4000),
		BackgroundColor3 = INK,
		BackgroundTransparency = 1,
		ZIndex = Z,
		Visible = false,
	}, gameFrame)

	-- the card: a holder that pops (UIScale) with the face + shadow inside
	local holder = new("Frame", {
		Name = "LoadingCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 296),
		Size = UDim2.fromOffset(340, 200),
		Rotation = -1.5,
		BackgroundTransparency = 1,
		ZIndex = Z + 1,
		Visible = false,
	}, gameFrame)
	self.Card = holder
	self.CardScale = new("UIScale", {}, holder)
	local face = card(holder, "Face", UDim2.new(), UDim2.fromScale(1, 1), WHITE, 18, 6, 3, Z + 1)

	-- "ROUND n" tag on the top edge
	local tag = card(holder, "Tag", UDim2.fromOffset(106, -16), UDim2.fromOffset(128, 28), YELLOW, 9, 3, 3, Z + 3)
	self.TagLabel = text(tag, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		TextSize = 13,
		Text = "ROUND 1",
		ZIndex = Z + 5,
	})

	-- equaliser chip
	local eq = new("Frame", {
		Name = "Equaliser",
		Position = UDim2.fromOffset(130, 32),
		Size = UDim2.fromOffset(80, 58),
		BackgroundColor3 = MINT,
		ZIndex = Z + 3,
	}, face)
	corner(eq, 14)
	stroke(eq, 3)
	self.Bars = {}
	for i = 1, 4 do
		local bar = new("Frame", {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 13 + (i - 1) * 15, 1, -9),
			Size = UDim2.fromOffset(9, 14),
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			ZIndex = Z + 4,
		}, eq)
		corner(bar, 3)
		table.insert(self.Bars, bar)
	end

	self.Title = text(face, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 0, 32),
		TextSize = 25,
		Text = "Loading audio…",
	})
	self.Sub = text(face, {
		Name = "Sub",
		Position = UDim2.fromOffset(0, 132),
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = BOLD,
		TextSize = 14,
		TextColor3 = MUTED,
		Text = "Get ready — the round unlocks in a sec",
	})

	-- striped progress bar (stripes animated through the gradient, see stripes())
	local track = new("Frame", {
		Name = "Progress",
		Position = UDim2.fromOffset(40, 164),
		Size = UDim2.fromOffset(260, 14),
		BackgroundColor3 = LILAC_LIGHT,
		ClipsDescendants = true,
		ZIndex = Z + 3,
	}, face)
	corner(track, 7)
	stroke(track, 2.5)
	local stripeFrame = new("Frame", {
		Name = "Stripes",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ZIndex = Z + 3,
	}, track)
	corner(stripeFrame, 7)
	new("UIGradient", { Color = stripes(0) }, stripeFrame)
	self.Stripes = stripeFrame

	-- READY: pulsing ring round the play button
	local ring = new("Frame", {
		Name = "ReadyRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 1, 8),
		BackgroundTransparency = 1,
		ZIndex = Z,
		Visible = false,
	}, playButton)
	corner(ring, UDim.new(0.5, 0))
	self.RingStroke = stroke(ring, 4, RED)
	self.RingScale = new("UIScale", {}, ring)
	self.Ring = ring

	-- READY: "Ready! Press play" sticker above the play button
	local sticker = new("Frame", {
		Name = "ReadySticker",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(-38, -20),
		Size = UDim2.fromOffset(204, 42),
		Rotation = -2,
		BackgroundTransparency = 1,
		ZIndex = Z,
		Visible = false,
	}, playButton)
	local sFace = card(sticker, "Face", UDim2.new(), UDim2.fromScale(1, 1), YELLOW, 12, 4, 3, Z)
	local dot = new("Frame", {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = RED,
		ZIndex = Z + 3,
	}, sFace)
	corner(dot, UDim.new(0.5, 0))
	stroke(dot, 2)
	text(dot, { Size = UDim2.fromScale(1, 1), TextSize = 10, Text = "▶", Position = UDim2.fromOffset(1, 0) })
	text(sFace, {
		Name = "Label",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -50, 1, 0),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Ready! Press play",
	})
	text(sticker, {
		Name = "Arrow",
		Position = UDim2.new(0, 52, 1, 2),
		Size = UDim2.fromOffset(24, 14),
		TextSize = 16,
		Text = "▼",
		ZIndex = Z + 2,
	})
	self.Sticker = sticker
end

-- Finds the Studio-built UI and drives it.
function LoadingCard.new(gameFrame: Frame, playButton: GuiButton)
	local self = setmetatable({}, LoadingCard)
	self._conns = {}
	self._loading = false
	self._ready = false

	self.Dim = gameFrame:WaitForChild("LoadingDim")
	self.Card = gameFrame:WaitForChild("LoadingCard")
	self.CardScale = self.Card:FindFirstChildOfClass("UIScale")
	local face = self.Card:WaitForChild("Face")
	self.TagLabel = self.Card:WaitForChild("Tag"):WaitForChild("Label")
	self.Title = face:WaitForChild("Title")
	self.Sub = face:WaitForChild("Sub")
	self.Stripes = face:WaitForChild("Progress"):WaitForChild("Stripes")
	self.StripeGradient = self.Stripes:FindFirstChildOfClass("UIGradient")
	local eq = face:WaitForChild("Equaliser")
	self.Bars = {}
	for i = 1, 4 do
		table.insert(self.Bars, eq:WaitForChild("Bar" .. i))
	end
	self.Ring = playButton:WaitForChild("ReadyRing")
	self.RingStroke = self.Ring:FindFirstChildOfClass("UIStroke")
	self.RingScale = self.Ring:FindFirstChildOfClass("UIScale")
	self.Sticker = playButton:WaitForChild("ReadySticker")

	-- start hidden whatever state Studio left them in
	self.Dim.Visible = false
	self.Dim.BackgroundTransparency = 1
	self.Card.Visible = false
	self.Ring.Visible = false
	self.Sticker.Visible = false

	-- one animation loop for bars, stripes, ring and sticker; only does work while visible
	table.insert(self._conns, RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if self._loading then
			for i, bar in self.Bars do
				local h = 10 + 24 * (0.5 + 0.5 * math.sin(t * 7 + i * 1.4))
				bar.Size = UDim2.fromOffset(9, math.floor(h))
			end
			if self.StripeGradient then
				self.StripeGradient.Color = stripes(t * 1.2)
			end
		end
		if self._ready then
			local p = (t % 1.3) / 1.3
			self.RingScale.Scale = 1 + 0.55 * p
			self.RingStroke.Transparency = 0.1 + 0.9 * p
			self.Sticker.Position = UDim2.fromOffset(-38, -20 - 6 * (0.5 + 0.5 * math.sin(t * 4)))
		end
	end))

	return self
end

-- --------------------------------- States --------------------------------- --
function LoadingCard:ShowLoading(round: number, mode: string?)
	self._loading = true
	self.TagLabel.Text = `ROUND {round}`
	self.Title.Text = if mode == "Choreography" then "Loading dance…" else "Loading audio…"
	self.Dim.Visible = true
	TweenService:Create(self.Dim, FADE, { BackgroundTransparency = 0.72 }):Play()
	self.Card.Visible = true
	self.CardScale.Scale = 0.8
	TweenService:Create(self.CardScale, POP_IN, { Scale = 1 }):Play()
end

function LoadingCard:HideLoading()
	if not self._loading then
		return
	end
	self._loading = false
	TweenService:Create(self.Dim, FADE, { BackgroundTransparency = 1 }):Play()
	local tween = TweenService:Create(self.CardScale, POP_OUT, { Scale = 0.85 })
	tween.Completed:Once(function()
		if not self._loading then
			self.Card.Visible = false
			self.Dim.Visible = false
		end
	end)
	tween:Play()
end

function LoadingCard:ShowReady()
	self._ready = true
	self.Ring.Visible = true
	self.Sticker.Visible = true
end

function LoadingCard:HideReady()
	self._ready = false
	self.Ring.Visible = false
	self.Sticker.Visible = false
end

function LoadingCard:HideAll()
	self:HideReady()
	self._loading = false
	self.Card.Visible = false
	self.Dim.Visible = false
	self.Dim.BackgroundTransparency = 1
end

function LoadingCard:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	self._conns = {}
end

return LoadingCard
