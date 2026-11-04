--| Shop · RollMotion
-- Drives the reveal's motion pieces that ./RollPage builds into RollReveal (FX, Flash, the
-- card's Bars / Sweep / Motion scale, the mystery face): the ambient glows, the circular
-- waveform, the particles, the white flash, the equaliser bars, the card's float and the
-- screen shake. ./Roll decides when; this only knows how. Everything is put away by Stop().
--   local fx = RollMotion.new(reveal)
--   fx:Glow("A", colour, 0.4, 0.3)   fx:Ring(colour, 1, 1.4, 0.5)   fx:Orbit(1, 12, colours)
--   fx:Burst(colours, 1.8)   fx:Flash(0.15)   fx:Bars(true)   fx:Float(true)   fx:Shake(6)

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local C = Color3.fromHex
local INK = C("1E1B2E")

local CENTRE = Vector2.new(640, 300)
local RINGS, DOTS, BARS = 5, 24, 7

local RollMotion = {}
RollMotion.__index = RollMotion

local function tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- particle i's direction: spread round the card, a little wider than tall
local function dirOf(i: number): Vector2
	local a = (i / DOTS) * math.pi * 2 + 0.2
	local r = 320 + (i % 3) * 45
	return Vector2.new(math.cos(a) * r, math.sin(a) * r * 0.9)
end

function RollMotion.new(reveal: Frame)
	local self = setmetatable({}, RollMotion)
	self._reveal = reveal
	self._fx = reveal.FX
	self._card = reveal.Card
	self._home = reveal.Position
	self._cardHome = reveal.Card.Position
	self._ring = 0
	self._bars = false
	self._float = false
	self._pulse = false
	return self
end

-- [[ Glows ]]

-- which = "A" (the mystery lilac) or "B" (the group colour)
function RollMotion:Glow(which: string, colour: Color3?, transparency: number, time: number, size: number?)
	local g = self._fx["Glow" .. which]
	if colour then
		g.ImageColor3 = colour
	end
	tween(g, time, { ImageTransparency = transparency, Size = UDim2.fromOffset(size or 640, size or 640) }, Enum.EasingStyle.Sine)
end

function RollMotion:Flash(transparency: number, colour: Color3?)
	local f = self._reveal.Flash
	f.ImageColor3 = colour or Color3.new(1, 1, 1)
	f.ImageTransparency = transparency
	tween(f, 0.35, { ImageTransparency = 1 })
end

-- [[ The circular waveform ]]

-- one ring from `from` to `to` times its size, fading out over `time`
function RollMotion:Ring(colour: Color3, from: number, to: number, time: number, thickness: number?)
	self._ring = self._ring % RINGS + 1
	local ring = self._fx["Ring" .. self._ring]
	local line = ring.UIStroke
	line.Color = colour
	line.Thickness = thickness or 4
	line.Transparency = 0.15
	ring.S.Scale = from
	tween(ring.S, time, { Scale = to })
	tween(line, time, { Transparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
end

-- rings keep pulsing every `every` seconds until StopRings()
function RollMotion:PulseRings(colours: { Color3 }, every: number)
	local token = {}
	self._pulseToken = token
	task.spawn(function()
		local i = 0
		while self._pulseToken == token and self._reveal.Visible do
			i += 1
			self:Ring(colours[(i - 1) % #colours + 1], 0.75, 1.45, every * 1.6)
			task.wait(every)
		end
	end)
end

function RollMotion:StopRings()
	self._pulseToken = nil
end

-- [[ Particles ]]

local function dot(self, i: number): Frame
	return self._fx["Dot" .. i]
end

local function show(d: Frame, transparency: number, time: number)
	tween(d, time, { BackgroundTransparency = transparency })
	tween(d.UIStroke, time, { Transparency = transparency })
end

-- particles first..last drift in round the card (from 35% to 55% of the way out)
function RollMotion:Orbit(first: number, last: number, colours: { Color3 })
	for i = first, last do
		local d = dot(self, i)
		local v = dirOf(i)
		d.BackgroundColor3 = colours[(i - 1) % #colours + 1]
		d.Position = UDim2.fromOffset(CENTRE.X + v.X * 0.35, CENTRE.Y + v.Y * 0.35)
		d.BackgroundTransparency, d.UIStroke.Transparency = 1, 1
		show(d, 0.05, 0.25)
		tween(d, 0.8, { Position = UDim2.fromOffset(CENTRE.X + v.X * 0.55, CENTRE.Y + v.Y * 0.55) }, Enum.EasingStyle.Sine)
	end
end

-- every showing particle edges outwards (the build-up's last moment)
function RollMotion:Spread(amount: number, time: number)
	for i = 1, DOTS do
		local d = dot(self, i)
		if d.BackgroundTransparency < 1 then
			local v = dirOf(i)
			tween(d, time, { Position = UDim2.fromOffset(CENTRE.X + v.X * amount, CENTRE.Y + v.Y * amount) }, Enum.EasingStyle.Sine)
		end
	end
end

-- particles fly out from the card and fade. colours = nil keeps each one's colour.
function RollMotion:Burst(colours: { Color3 }?, reach: number, count: number?, time: number?)
	for i = 1, count or DOTS do
		local d = dot(self, i)
		local v = dirOf(i)
		if colours then
			d.BackgroundColor3 = colours[(i - 1) % #colours + 1]
		end
		if d.BackgroundTransparency >= 1 then
			d.Position = UDim2.fromOffset(CENTRE.X + v.X * 0.3, CENTRE.Y + v.Y * 0.3)
		end
		d.BackgroundTransparency, d.UIStroke.Transparency = 0, 0
		tween(d, time or 0.5, { Position = UDim2.fromOffset(CENTRE.X + v.X * reach, CENTRE.Y + v.Y * reach) })
		task.delay((time or 0.5) * 0.4, function()
			show(d, 1, (time or 0.5) * 0.6)
		end)
	end
end

function RollMotion:ClearParticles(time: number)
	for i = 1, DOTS do
		local d = dot(self, i)
		if d.BackgroundTransparency < 1 then
			show(d, 1, time)
		end
	end
end

-- [[ Bars, note pulse, float (one Heartbeat loop for all three) ]]

local function bars(art: Instance): { Frame }
	local out = {}
	local row = art:FindFirstChild("Bars")
	if row then
		for i = 1, BARS do
			table.insert(out, row["Bar" .. i])
		end
	end
	return out
end

function RollMotion:_loop()
	if self._conn then
		return
	end
	local mystery, front = bars(self._card.Back.Art), bars(self._card.Art)
	local note = self._card.Back.Art.Note.Pulse
	local t0 = os.clock()
	self._conn = RunService.Heartbeat:Connect(function()
		if not self._reveal.Visible then
			self:Stop()
			return
		end
		local t = os.clock() - t0
		if self._bars then
			local list = if self._card.Back.Visible then mystery else front
			for i, b in list do
				-- each bar its own speed, so they never move together
				local h = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * (7 + i * 1.7) + i * 1.3))
				b.Size = UDim2.fromOffset(14, math.floor(24 + 72 * h))
			end
		end
		if self._pulse then
			note.Scale = 1 + 0.08 * math.sin(t * 8)
		end
		if self._float then
			self._card.Position = self._cardHome + UDim2.fromOffset(0, math.floor(-6 * (0.5 + 0.5 * math.sin(t * 5))))
		end
	end)
end

function RollMotion:Bars(on: boolean)
	self._bars = on
	self:_loop()
end

function RollMotion:Pulse(on: boolean)
	self._pulse = on
	if not on then
		self._card.Back.Art.Note.Pulse.Scale = 1
	end
	self:_loop()
end

function RollMotion:Float(on: boolean)
	self._float = on
	if not on then
		tween(self._card, 0.15, { Position = self._cardHome })
	end
	self:_loop()
end

-- [[ Light across the card ]]

-- the mystery face's gloss
function RollMotion:Gloss(time: number)
	local g = self._card.Back.Art.Gloss:FindFirstChildOfClass("UIGradient")
	g.Offset = Vector2.new(-1, 0)
	tween(g, time, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

-- the gold / prism light crossing the face. colours = a ColorSequence or a single colour
function RollMotion:Sweep(colour: Color3 | ColorSequence, time: number)
	local s = self._card.Sweep
	local grad = s:FindFirstChildOfClass("UIGradient")
	if typeof(colour) == "ColorSequence" then
		s.BackgroundColor3 = Color3.new(1, 1, 1)
		grad.Color = colour
	else
		s.BackgroundColor3 = colour
		grad.Color = ColorSequence.new(Color3.new(1, 1, 1))
	end
	grad.Offset = Vector2.new(-1, 0)
	s.BackgroundTransparency = 0
	local t = tween(grad, time, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	t.Completed:Once(function()
		s.BackgroundTransparency = 1
	end)
end

-- [[ Shake ]]

-- the whole reveal jolts: strength px, fading over ~0.25 s
function RollMotion:Shake(strength: number)
	local reveal, home = self._reveal, self._home
	task.spawn(function()
		for i = 1, 8 do
			local k = strength * (1 - i / 9)
			reveal.Position = home + UDim2.fromOffset(math.random(-100, 100) / 100 * k, math.random(-100, 100) / 100 * k)
			task.wait(0.03)
		end
		reveal.Position = home
	end)
end

-- [[ Put away ]]

function RollMotion:Reset()
	self:StopRings()
	self._bars, self._pulse, self._float = false, false, false
	for _, g in { self._fx.GlowA, self._fx.GlowB, self._reveal.Flash } do
		g.ImageTransparency = 1
	end
	for i = 1, RINGS do
		self._fx["Ring" .. i].UIStroke.Transparency = 1
	end
	for i = 1, DOTS do
		local d = dot(self, i)
		d.BackgroundTransparency, d.UIStroke.Transparency = 1, 1
		d.UIStroke.Color = INK
	end
	self._card.Sweep.BackgroundTransparency = 1
	self._card.Position = self._cardHome
	self._reveal.Position = self._home
end

function RollMotion:Stop()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self:Reset()
end

return RollMotion
