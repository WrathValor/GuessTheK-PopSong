--| AlbumsController · Reveal
-- The rare reveals (design board "42 · Rare reveals"): from Lucky Draw up, the card back hints
-- at what's coming, then the reveal plays in that card's own material. Each step up is longer
-- and louder. Plays on duplicates too. The pieces are instances in Pull.Fx (behind the card)
-- and Pull.FxTop (over it), from Build.RevealFx.
--   Lucky Draw  hint: gold glow + wobble     reveal: rays, a coin burst, gold confetti
--   Fansign     hint: heartbeat hops, pink-silver glow, hearts puff out of the edges
--               reveal: pink spotlight, hearts float up, a marker signature scribbles across
--   Polaroid    hint: a camera flash charging round the back, blinking faster (READY)
--               flip: a white flash and the polaroid slides up; reveal: it develops, then the
--               signature and the date stamp come in
--   One of One  hint (2.4 s, plays by itself): the stage goes dark, the back trembles harder
--               and harder, rainbow light cracks through it; flip: a flash and a shockwave, the
--               card springs in (0.4 → 1.12 → 1); reveal: ONE OF ONE flies together in gold, the
--               1/1 seal stamps on, gold dust, rainbow confetti, and a gentle sway
-- AlbumsController calls Hint when a rare back comes up, Flip at the flip (it says whether it
-- moved the card itself), Land once the face is up and Reset whenever the card moves on.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Modules.Sounds)

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local HOLDER_AT = UDim2.fromOffset(640, 300)
local ONE_HINT = 2.4 -- seconds of the One of One's build-up (it can't be skipped)

local GOLD = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFF1B8")),
	ColorSequenceKeypoint.new(0.4, C("F6D77E")),
	ColorSequenceKeypoint.new(0.7, C("E8C15A")),
	ColorSequenceKeypoint.new(1, C("C9952B")),
})
local FOIL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("C9D3E3")),
	ColorSequenceKeypoint.new(0.25, C("FFFFFF")),
	ColorSequenceKeypoint.new(0.5, C("FF9EC4")),
	ColorSequenceKeypoint.new(0.75, C("FFFFFF")),
	ColorSequenceKeypoint.new(1, C("C9D3E3")),
})
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FF5A4E")),
	ColorSequenceKeypoint.new(1 / 6, C("FFE07A")),
	ColorSequenceKeypoint.new(2 / 6, C("A7E9B8")),
	ColorSequenceKeypoint.new(3 / 6, C("9ED8F5")),
	ColorSequenceKeypoint.new(4 / 6, C("B9A6FF")),
	ColorSequenceKeypoint.new(5 / 6, C("FF9EC4")),
	ColorSequenceKeypoint.new(1, C("FF5A4E")),
})
local DEVELOPING = Color3.fromRGB(46, 30, 20) -- a polaroid's photo before it develops

-- the banner over the card, by rarity: { text, gradient, rotation }
local BANNER = {
	luckydraw = { "LUCKY DRAW!", GOLD, -2 },
	fansign = { "♡ FANSIGN BENEFIT!", FOIL, -2 },
	polaroid = { "SIGNED POLAROID!", nil, 3 },
}
-- confetti colours, by rarity
local CONFETTI = {
	luckydraw = { C("FFE07A"), C("FFF1B8"), C("E8C15A"), WHITE, C("C9952B") },
	fansign = { C("FF9EC4"), WHITE, C("C9D3E3"), C("FFD2E5") },
	oneofone = { C("FF5A4E"), C("FFE07A"), C("A7E9B8"), C("9ED8F5"), C("B9A6FF"), C("FF9EC4") },
}

-- the night's stars: each fades in (fade 0→1) and then twinkles on its own phase
local function twinkle(stars: Instance, t: number, fade: number)
	for _, star in stars:GetChildren() do
		local phase = star:GetAttribute("Phase") or 0
		local glint = 0.55 + 0.45 * math.sin(t * 2.2 + phase)
		star.BackgroundTransparency = 1 - fade * 0.85 * glint
	end
end

-- the One of One's gold 1/1 seal, on the card's outer decor
local function sealOf(holder: Instance): Frame?
	for _, d in holder:GetDescendants() do
		if d.Name == "Seal" and d:FindFirstChild("Disc") then
			return d
		end
	end
	return nil
end

local function tween(gui: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(gui, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local Reveal = {}
Reveal.__index = Reveal

Reveal.ONE_HINT = ONE_HINT
Reveal.CONFETTI = CONFETTI

function Reveal.new(page: Frame)
	local self = setmetatable({}, Reveal)
	self.Page = page
	-- (two layers: Fx behind the card, FxTop over it; Parts finds a piece in either)
	self.Layers = { page.Fx, page.FxTop }
	self.Parts = {}
	for _, layer in self.Layers do
		for _, child in layer:GetChildren() do
			self.Parts[child.Name] = child
		end
	end
	self.Token = 0
	self.Conn = nil :: RBXScriptConnection?
	return self
end

-- runs fn(t, dt) every frame until Stop / Reset (or the next loop)
function Reveal:_loop(fn: (number, number) -> ())
	if self.Conn then
		self.Conn:Disconnect()
	end
	local t = 0
	self.Conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		fn(t, dt)
	end)
end

function Reveal:Stop()
	if self.Conn then
		self.Conn:Disconnect()
		self.Conn = nil
	end
end

-- hides every piece and puts the card back as it was (call when the card moves on)
function Reveal:Reset(holder: Frame?)
	self:Stop()
	self.Token += 1
	if self.StopCrowd then -- (the Fansign's crowd / the One of One's choir, until the card moves on)
		self.StopCrowd(0.5)
		self.StopCrowd = nil
	end
	local fx = self.Parts
	for _, layer in self.Layers do
		layer.Visible = false
	end
	for _, child in fx do
		if child:IsA("GuiObject") then
			child.Visible = false
		end
	end
	fx.Night.BackgroundTransparency = 1
	twinkle(fx.Night.Stars, 0, 0)
	fx.Night.Haze.ImageTransparency = 1
	fx.Big.Scale.Scale = 1
	fx.Glow.ImageTransparency = 1
	fx.Spot.ImageTransparency = 1
	fx.Charge.UIStroke.Transparency = 1
	fx.Scribble.Reveal.Offset = Vector2.new(-1, 0)
	for _, heart in fx.Hearts:GetChildren() do
		heart.Position = UDim2.fromOffset(heart.Position.X.Offset, 760)
	end
	holder = holder or self.Page.Holder
	if holder then
		local cracks = holder.Back:FindFirstChild("Cracks")
		if cracks then
			cracks.Visible = false
		end
		holder.Rotation = 0
		local seal = sealOf(holder)
		if seal and seal:FindFirstChild("Stamp") then
			seal.Stamp.Scale = 1
			seal.Rotation = 0
		end
		local photo = holder.Face.Card.Photo
		photo.Art.ImageColor3 = WHITE
		local top = photo:FindFirstChild("Decor")
		if top then
			top.Sig.Text.TextTransparency = 0
			top.Sig.Shadow.TextTransparency = 0.4
			top.Date.TextTransparency = 0
		end
	end
end

-- [[ Hint: the card back, before the flip ]]

function Reveal:Hint(key: string, holder: Frame, onDone: (() -> ())?)
	self:Reset(holder)
	local fx = self.Parts
	for _, layer in self.Layers do
		layer.Visible = true
	end
	local glow = fx.Glow
	if key == "luckydraw" then
		glow.Visible = true
		glow.ImageColor3 = C("F2C94C")
		glow.Colour.Enabled = false
		local shimmer = -1
		self:_loop(function(t)
			if math.floor(t / 2) ~= shimmer then -- (the 2 s shimmer, again while it waits)
				shimmer = math.floor(t / 2)
				Sounds.Play("LuckyShimmer")
			end
			holder.Rotation = math.sin(t * 40) * 2.5
			glow.ImageTransparency = 0.3 - 0.2 * math.sin(t * 5)
		end)
	elseif key == "fansign" then
		glow.Visible = true
		glow.ImageColor3 = WHITE
		glow.Colour.Enabled = true
		glow.Colour.Color = FOIL
		fx.Leaks.Visible = true
		local leaks = fx.Leaks:GetChildren()
		local beat = -1
		self:_loop(function(t)
			-- a heartbeat: two hops every 1.1 s
			local q = t % 1.1
			local hop = 0
			if q < 0.16 then
				hop = math.sin(q / 0.16 * math.pi)
			elseif q > 0.26 and q < 0.42 then
				hop = math.sin((q - 0.26) / 0.16 * math.pi)
			end
			holder.Position = HOLDER_AT + UDim2.fromOffset(0, -10 * hop)
			glow.ImageTransparency = 0.55 - 0.45 * hop
			local n = math.floor(t / 1.1)
			if n ~= beat then
				beat = n
				Sounds.Play("Heartbeat")
				for i = 1, 2 do
					local heart = leaks[(n * 2 + i) % #leaks + 1]
					if heart and heart:IsA("TextLabel") then
						local home = heart:GetAttribute("Home") or heart.Position
						local dir = Vector2.new(home.X.Offset - 640, home.Y.Offset - 300).Unit
						heart.Position = home
						heart.TextTransparency = 0
						heart.UIStroke.Transparency = 0
						tween(heart, 0.9, { Position = home + UDim2.fromOffset(dir.X * 50, dir.Y * 30 - 40), TextTransparency = 1 })
						tween(heart.UIStroke, 0.9, { Transparency = 1 })
					end
				end
			end
		end)
	elseif key == "polaroid" then
		local charge = fx.Charge
		charge.Visible = true
		fx.ChargeText.Visible = true
		local nextBlink, blinks = 0.3, 0
		self:_loop(function(t)
			if t >= nextBlink then
				blinks += 1
				charge.UIStroke.Transparency = 0
				task.delay(0.07, function()
					charge.UIStroke.Transparency = 1
				end)
				Sounds.Play("FlashBeep", { Pitch = 1 + math.min(blinks, 10) * 0.04 })
				nextBlink = t + math.max(0.16, 0.7 - blinks * 0.09)
			end
			fx.ChargeText.TextTransparency = 0.15 + 0.25 * math.abs(math.sin(t * 3))
		end)
	elseif key == "oneofone" then
		local night = fx.Night
		night.Visible = true
		tween(night, 0.8, { BackgroundTransparency = 0.08 })
		tween(night.Haze, 0.8, { ImageTransparency = 0 })
		glow.Visible = true
		glow.ImageColor3 = WHITE
		glow.Colour.Enabled = true
		glow.Colour.Color = RAINBOW
		local cracks = holder.Back:FindFirstChild("Cracks")
		local done = false
		Sounds.Play("OneRumble")
		self:_loop(function(t)
			local k = math.min(t / ONE_HINT, 1)
			local amp = 1 + k * 6
			holder.Position = HOLDER_AT + UDim2.fromOffset(math.random(-10, 10) / 10 * amp, math.random(-10, 10) / 10 * amp)
			holder.Rotation = math.sin(t * 50) * (0.5 + k * 4)
			holder.Scale.Scale = 1 + k * 0.06
			glow.ImageTransparency = 1 - k
			glow.Colour.Rotation = (t * 240) % 360
			twinkle(night.Stars, t, math.clamp((t - 0.2) / 0.4, 0, 1))
			if cracks then
				cracks.Visible = t > ONE_HINT * 0.4
			end
			if not done and t >= ONE_HINT then
				done = true
				if onDone then
					task.spawn(onDone)
				end
			end
		end)
	end
end

-- [[ Flip: the moment it turns over ]]

-- does the Polaroid's and One of One's own flip (and returns true); other rarities use the
-- normal squash flip. onLanded runs once the face is up.
function Reveal:Flip(key: string, holder: Frame, onLanded: () -> ()): boolean
	self:Stop()
	local fx = self.Parts
	fx.Charge.Visible = false
	fx.ChargeText.Visible = false
	fx.Leaks.Visible = false
	holder.Rotation = 0
	holder.Position = HOLDER_AT
	local flash = self.Page.Flash
	if key == "polaroid" then
		Sounds.Play("Shutter")
		flash.BackgroundTransparency = 0
		tween(flash, 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		holder.Back.Visible = false
		holder.Face.Card.Photo.Art.ImageColor3 = DEVELOPING
		local top = holder.Face.Card.Photo:FindFirstChild("Decor")
		if top then
			top.Sig.Text.TextTransparency = 1
			top.Sig.Shadow.TextTransparency = 1
			top.Date.TextTransparency = 1
		end
		holder.Position = HOLDER_AT + UDim2.fromOffset(0, 70)
		tween(holder, 0.55, { Position = HOLDER_AT }, Enum.EasingStyle.Back, Enum.EasingDirection.Out).Completed:Once(onLanded)
		return true
	elseif key == "oneofone" then
		Sounds.Play("OneBurst")
		flash.BackgroundTransparency = 0
		tween(flash, 0.6, { BackgroundTransparency = 1 })
		local shock = fx.Shock
		shock.Visible = true
		shock.Size = UDim2.fromOffset(60, 60)
		shock.UIStroke.Transparency = 0
		tween(shock, 0.7, { Size = UDim2.fromOffset(1500, 1500) })
		tween(shock.UIStroke, 0.7, { Transparency = 1 })
		fx.Glow.Visible = false
		holder.Back.Visible = false
		-- (the mock-up's spring: 0.4 / -12° → 1.12 / 3° → 1 / 0°)
		local stars = fx.Night.Stars
		self:_loop(function(t)
			twinkle(stars, t + ONE_HINT, 1)
		end)
		holder.Scale.Scale = 0.4
		holder.Rotation = -12
		local token = self.Token
		tween(holder.Scale, 0.34, { Scale = 1.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tween(holder, 0.34, { Rotation = 3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Once(function()
			if self.Token ~= token then
				return
			end
			tween(holder.Scale, 0.26, { Scale = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			tween(holder, 0.26, { Rotation = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Once(onLanded)
		end)
		-- (the seal waits to be stamped on once the card lands)
		local seal = sealOf(holder)
		if seal and seal:FindFirstChild("Stamp") then
			seal.Stamp.Scale = 0
		end
		return true
	end
	fx.Glow.Visible = false
	return false
end

-- [[ Land: the face is up ]]

-- plays the reveal; confetti(colours) is the stage's confetti burst, banner(text, gradient,
-- rotation) shows the rarity banner. Returns how long it takes before a tap may move on.
function Reveal:Land(key: string, holder: Frame, confetti: ({ Color3 }) -> (), banner: (string, ColorSequence?, number) -> ()): number
	local fx = self.Parts
	for _, layer in self.Layers do
		layer.Visible = true
	end
	local spec = BANNER[key]
	if spec then
		banner(spec[1], spec[2], spec[3])
	end
	if key == "luckydraw" then
		Sounds.Play("LuckyCoins")
		confetti(CONFETTI.luckydraw)
		local coins = fx.Coins
		coins.Visible = true
		for i, coin in coins:GetChildren() do
			local angle = (i / 16) * math.pi * 2 + math.random() * 0.3
			local r = math.random(170, 280)
			local x, y = math.cos(angle) * r, math.sin(angle) * r * 0.8 - 60
			coin.Position = UDim2.fromOffset(0, 0)
			coin.Rotation = 0
			coin.BackgroundTransparency = 0
			coin.UIStroke.Transparency = 0
			tween(coin, 0.45, { Position = UDim2.fromOffset(x, y), Rotation = math.random(-200, 200) }).Completed:Once(function()
				tween(coin, 1.1, { Position = UDim2.fromOffset(x * 1.05, y + 380), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tween(coin.UIStroke, 1.1, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
		end
		return 0
	elseif key == "fansign" then
		Sounds.Play("FansCheer")
		-- the crowd keeps going until the player taps on (Reset stops it)
		local crowdToken = self.Token
		task.delay(1.2, function()
			if self.Token == crowdToken and not self.StopCrowd then
				self.StopCrowd = Sounds.Loop("FansCrowd")
			end
		end)
		confetti(CONFETTI.fansign)
		local spot = fx.Spot
		spot.Visible = true
		tween(spot, 0.5, { ImageTransparency = 1 - (spot:GetAttribute("Shown") or 0.45) })
		local hearts = fx.Hearts
		hearts.Visible = true
		for _, heart in hearts:GetChildren() do
			local x = heart.Position.X.Offset
			heart.Position = UDim2.fromOffset(x, 760)
			heart.Rotation = 0
			heart.TextTransparency = 0
			task.delay(heart:GetAttribute("Delay") or 0, function()
				tween(heart, 2.2, { Position = UDim2.fromOffset(x + math.random(-30, 30), -60), Rotation = math.random(-25, 25) }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			end)
		end
		local scribble = fx.Scribble
		scribble.Visible = true
		scribble.ImageTransparency = 0
		scribble.Reveal.Offset = Vector2.new(-1, 0)
		local token = self.Token
		task.delay(0.25, function()
			if self.Token ~= token then
				return
			end
			Sounds.Play("MarkerScribble")
			tween(scribble.Reveal, 0.7, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.delay(1.6, function()
				if self.Token == token then
					tween(scribble, 0.5, { ImageTransparency = 1 })
				end
			end)
		end)
		return 0
	elseif key == "polaroid" then
		local photo = holder.Face.Card.Photo
		tween(photo.Art, 1.6, { ImageColor3 = WHITE }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local top = photo:FindFirstChild("Decor")
		local token = self.Token
		task.delay(1.3, function()
			if self.Token ~= token or not top then
				return
			end
			Sounds.Play("MarkerScribble", { Pitch = 1.1 })
			tween(top.Sig.Text, 0.5, { TextTransparency = 0 })
			tween(top.Sig.Shadow, 0.5, { TextTransparency = 0.4 })
			task.delay(0.5, function()
				if self.Token == token then
					Sounds.Play("FlashBeep", { Pitch = 0.8 })
					top.Date.TextTransparency = 0
				end
			end)
		end)
		return 0.6
	elseif key == "oneofone" then
		Sounds.Play("OneChoir")
		-- the choir pad swells in under the hit as it rings out (both in C major, so they
		-- blend) and carries on until the player taps on (Reset stops it)
		local loopToken = self.Token
		task.delay(0.15, function()
			if self.Token == loopToken and not self.StopCrowd then
				self.StopCrowd = Sounds.Loop("OneLoop", { FadeIn = 1.3, At = 1 })
			end
		end)
		confetti(CONFETTI.oneofone)
		local token = self.Token
		-- ONE OF ONE: the letters fly in wide apart and small, close up past full size, settle
		local big = fx.Big
		big.Visible = true
		local layout = big.Letters.Layout
		local letters = {}
		for _, letter in big.Letters:GetChildren() do
			if letter:IsA("TextLabel") then
				table.insert(letters, letter)
				letter.TextTransparency = 1
				letter.UIStroke.Transparency = 1
				tween(letter, 0.25, { TextTransparency = 0 })
				tween(letter.UIStroke, 0.25, { Transparency = 0 })
			end
		end
		table.sort(letters, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		layout.Padding = UDim.new(0, 26)
		big.Scale.Scale = 0.3
		tween(layout, 0.42, { Padding = UDim.new(0, 2) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		tween(big.Scale, 0.42, { Scale = 1.1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out).Completed:Once(function()
			if self.Token == token then
				tween(big.Scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			end
		end)

		-- the 1/1 seal stamps on: big and turned, a hard landing, then still
		local seal = sealOf(holder)
		if seal and seal:FindFirstChild("Stamp") then
			seal.Stamp.Scale = 0
			task.delay(0.4, function()
				if self.Token ~= token then
					return
				end
				seal.Stamp.Scale = 3
				seal.Rotation = -90
				tween(seal.Stamp, 0.24, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tween(seal, 0.24, { Rotation = 8 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
					if self.Token ~= token then
						return
					end
					Sounds.Play("CardPop", { Pitch = 0.8 })
					tween(seal.Stamp, 0.18, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					tween(seal, 0.18, { Rotation = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end)
			end)
		end

		local dust = fx.Dust
		dust.Visible = true
		local motes = dust:GetChildren()
		local stars = fx.Night.Stars
		self:_loop(function(t)
			-- each letter catches the gold a beat after the one before
			for i, letter in letters do
				letter.Gold.Offset = Vector2.new(1 - 2 * ((t / 2.5 - i * 0.06) % 1), 0)
			end
			twinkle(stars, t + ONE_HINT + 0.6, 1)
			-- (the mock-up tilts the card in 3D; a slow sway stands in for it)
			if t < 0.3 then -- (a light screen shake as it lands)
				local amp = 4 * (1 - t / 0.3)
				holder.Position = HOLDER_AT + UDim2.fromOffset(math.random(-10, 10) / 10 * amp, math.random(-10, 10) / 10 * amp)
			else
				holder.Position = HOLDER_AT
				holder.Rotation = 1.5 * math.sin((t - 0.3) * 1.7)
			end
			for i, mote in motes do
				local r = ((t - (mote:GetAttribute("Delay") or 0)) % 3.2) / 3.2
				local fade = if r < 0.15 then r / 0.15 else 1 - (r - 0.15) / 0.85
				mote.Position = UDim2.new((i - 0.5) / #motes + 0.03 * math.sin(t * 1.5 + i), 0, 1, -360 * r * r)
				mote.ImageTransparency = 1 - fade * 0.7
				mote.Dot.BackgroundTransparency = 1 - fade
			end
		end)
		return 1.4 -- (the reveal can't be skipped: taps wait this long after it lands)
	end
	return 0
end

return Reveal
