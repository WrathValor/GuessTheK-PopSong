--| TierShine
-- The moving tier effects, like the canvas mockups. Every gradient added here is driven by one
-- Heartbeat loop (one ColorSequence of each kind built per frame and shared, so any number
-- costs the same). Client only.
--   • Rainbow – the pastel rainbow slides sideways in a slow loop
--   • Diamond – (group badges) ice blue with a white glint sweeping across, between the gold ones
--   • Legend  – (group badges) on a chip's UIStroke: the gold border with the same shine running along it
--   • Gold    – gold, with a soft white shine sweeping across every few seconds. The band is a
--               fixed gold–shine–gold gradient moved with Offset from fully off the left edge to
--               fully off the right, so it always slides out instead of stopping on the card
--               (rotated gradients reach past 0..1 at the corners, which used to catch the band)
-- Apply() sets a GuiObject up for its tier: Gold / Rainbow paint the object white and let the
-- gradient carry the colour; anything else turns the gradient off and uses `otherColour`.
--   TierShine.Apply(face, face.Level, "Gold", WHITE)
--   TierShine.Add(gradient) / TierShine.AddAll(root, name)   -- register without changing it
-- Only gradients that are on screen are updated: a closed screen (the Index with Rainbow cards
-- on its page, say) costs nothing until it opens again.
-- The list is a normal table (not weak): Roblox can collect an instance's Lua handle from a
-- weak table while the instance is still on screen, which froze the animation.
-- Group badge chips (board 64 · Badges · tier looks; Modules/UI/TitleChip) add their own moving
-- pieces, driven by the same loop:
--   TierShine.AddFx(obj, kind) / TierShine.RemoveFx(obj)
--     "Sweep"   – a UIGradient light band (attribute Every: seconds between passes) crossing
--     "Shift"   – a UIGradient's colours drifting slowly back and forth (Platinum's crystal)
--     "Spin"    – a UIGradient turning (Legend's rainbow rim)
--     "Twinkle" – an ImageLabel sparkle growing and fading (attributes Delay, Size)
--     "Rise"    – a Frame of gold dust drifting up and fading (attribute Delay)
--   TierShine.SetLowEffects(on)   -- (Client/SettingsController) the pieces stop where they rest;
--                                  -- every tier keeps its colours and glow

local RunService = game:GetService("RunService")

local OnScreen = require(script.Parent.OnScreen)

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local RAINBOW = { C("FFB3C7"), C("FFD8A8"), C("FFF1A8"), C("B8F0C8"), C("B5DDFF"), C("D8C4FF") }
local GOLD, SHINE = C("F2C94C"), C("FFF6D6")
local RAINBOW_PERIOD = 4 -- seconds for the rainbow to go all the way round
local SHINE_EVERY, SHINE_TIME, SHINE_WIDTH = 2.6, 1.3, 0.14 -- a sweep every 2.6 s, 1.3 s long
-- how far either side of the centre the band starts / ends (Offset units): past the far corner
-- of a wide card under a 35° gradient, so the band is fully off before it stops
local SHINE_REACH = 1.1
local STEPS = 12 -- rainbow keypoints (Roblox allows up to 20)

local TierShine = {}

local gradients = {} :: { [UIGradient]: boolean }
local fx = {} :: { [Instance]: string }
local lowEffects = false
local running = false

-- [[ Colours ]]

local function rainbowAt(x: number): Color3
	local n = #RAINBOW
	local pos = (x % 1) * n
	local i = math.floor(pos)
	return RAINBOW[i % n + 1]:Lerp(RAINBOW[(i + 1) % n + 1], pos - i)
end

local function rainbow(t: number): ColorSequence
	local phase = t / RAINBOW_PERIOD
	local points = table.create(STEPS + 1)
	for s = 0, STEPS do
		local x = s / STEPS
		points[s + 1] = ColorSequenceKeypoint.new(x, rainbowAt(phase + x * 0.5)) -- half the loop at a time
	end
	return ColorSequence.new(points)
end

-- gold with the shine band in the middle; Offset slides it across
local GOLD_BAND = ColorSequence.new({
	ColorSequenceKeypoint.new(0, GOLD),
	ColorSequenceKeypoint.new(0.5 - SHINE_WIDTH, GOLD),
	ColorSequenceKeypoint.new(0.5, SHINE),
	ColorSequenceKeypoint.new(0.5 + SHINE_WIDTH, GOLD),
	ColorSequenceKeypoint.new(1, GOLD),
})
-- ice blue with a white glint (group badge Diamond)
local ICE, ICE_DEEP, GLINT = C("9ED8F5"), C("5BB8EA"), C("FFFFFF")
local DIAMOND_BAND = ColorSequence.new({
	ColorSequenceKeypoint.new(0, ICE_DEEP),
	ColorSequenceKeypoint.new(0.5 - SHINE_WIDTH * 1.4, ICE),
	ColorSequenceKeypoint.new(0.5, GLINT),
	ColorSequenceKeypoint.new(0.5 + SHINE_WIDTH * 1.4, ICE),
	ColorSequenceKeypoint.new(1, ICE_DEEP),
})
local RESTING = Vector2.new(SHINE_REACH, 0) -- band parked off the right edge between sweeps
local CENTRED = Vector2.zero

-- where the band is now: off the left at the start of a sweep, off the right at the end
local function goldOffset(t: number): Vector2
	local into = t % SHINE_EVERY
	if into >= SHINE_TIME then
		return RESTING
	end
	local p = into / SHINE_TIME
	p = p * p * (3 - 2 * p) -- ease in and out: the band glides on and off
	return Vector2.new(-SHINE_REACH + p * 2 * SHINE_REACH, 0)
end

-- [[ Loop ]]

-- On screen? Every GuiObject above the gradient is Visible, and its ScreenGui is Enabled (or its
-- name tag / street screen is in range and in view: Modules/UI/OnScreen). A few property reads
-- per gradient; far cheaper than redrawing what nobody sees.
local function shown(gradient: UIGradient): boolean
	local parent = gradient.Parent
	return parent ~= nil and OnScreen.Gui(parent)
end

-- [[ Badge pieces ]]

-- a badge chip's band: off to the left until 55% of its period, across by 85%, then gone
local function sweepOffset(t: number, every: number): Vector2
	local p = (t % every) / every
	if p < 0.55 or p > 0.85 then
		return RESTING
	end
	local q = (p - 0.55) / 0.3
	q = q * q * (3 - 2 * q)
	return Vector2.new(-SHINE_REACH + q * 2 * SHINE_REACH, 0)
end

-- where each piece sits while still (Low effects, or a still nametag)
local function rest(obj: Instance, kind: string)
	if kind == "Sweep" then
		(obj :: UIGradient).Offset = RESTING
	elseif kind == "Shift" then
		(obj :: UIGradient).Offset = Vector2.zero
	elseif kind == "Spin" then
		(obj :: UIGradient).Rotation = 45
	elseif kind == "Twinkle" then
		local size = obj:GetAttribute("Size") or 12
		;(obj :: ImageLabel).Size = UDim2.fromOffset(size, size)
		;(obj :: ImageLabel).ImageTransparency = 0.1
	elseif kind == "Rise" then
		(obj :: Frame).BackgroundTransparency = 1
	end
end

local function stepFx(obj: Instance, kind: string, t: number)
	local delay = obj:GetAttribute("Delay") or 0
	if kind == "Sweep" then
		(obj :: UIGradient).Offset = sweepOffset(t + delay, obj:GetAttribute("Every") or 3)
	elseif kind == "Shift" then
		(obj :: UIGradient).Offset = Vector2.new(0.3 * math.sin(t / 5 * 2 * math.pi), 0)
	elseif kind == "Spin" then
		(obj :: UIGradient).Rotation = (t * 60) % 360
	elseif kind == "Twinkle" then
		local size = obj:GetAttribute("Size") or 12
		local wave = 0.5 - 0.5 * math.cos(((t - delay) % 1.8) / 1.8 * 2 * math.pi) -- 0 → 1 → 0
		local s = math.floor(size * (0.5 + 0.6 * wave) + 0.5)
		;(obj :: ImageLabel).Size = UDim2.fromOffset(s, s)
		;(obj :: ImageLabel).ImageTransparency = 0.8 - 0.8 * wave
	elseif kind == "Rise" then
		local r = ((t - delay) % 2.6) / 2.6
		local f = obj :: Frame
		local fade = if r < 0.15 then r / 0.15 else 1 - (r - 0.15) / 0.85
		f.Position = UDim2.new(f.Position.X.Scale, f.Position.X.Offset, 1, -3 - 30 * r)
		f.BackgroundTransparency = 1 - fade
	end
end

local function start()
	if running or not RunService:IsClient() then
		return
	end
	running = true
	RunService.Heartbeat:Connect(function()
		if next(fx) ~= nil and not lowEffects then
			local now = os.clock()
			for obj, kind in fx do
				local gui = if obj:IsA("UIGradient") then obj.Parent else obj
				if gui and OnScreen.Gui(gui) then
					stepFx(obj, kind, now)
				end
			end
		end
		if next(gradients) == nil then
			return
		end
		local t = os.clock()
		local rb, gd = nil, nil
		for gradient in gradients do
			if gradient.Enabled and shown(gradient) then
				local shine = gradient:GetAttribute("Shine")
				if shine == "Static" then
					continue -- painted once by its owner (a season title's holo foil): leave it
				end
				if shine == "Gold" then
					gd = gd or goldOffset(t)
					if gradient.Color ~= GOLD_BAND then
						gradient.Color = GOLD_BAND
					end
					gradient.Offset = gd
				elseif shine == "Diamond" then
					if gradient.Color ~= DIAMOND_BAND then
						gradient.Color = DIAMOND_BAND
					end
					gradient.Offset = goldOffset(t + SHINE_EVERY / 2) -- (glints between the gold sweeps)
				elseif shine == "Legend" then
					if gradient.Color ~= GOLD_BAND then
						gradient.Color = GOLD_BAND
					end
					gradient.Offset = goldOffset(t * 1.4) -- (a little quicker: it's the top)
				else
					rb = rb or rainbow(t)
					gradient.Color = rb
					if gradient.Offset ~= CENTRED then
						gradient.Offset = CENTRED -- in case it was gold before
					end
				end
			end
		end
	end)
end

-- [[ API ]]

function TierShine.Add(gradient: UIGradient?)
	if not gradient or gradients[gradient] then
		return
	end
	gradients[gradient] = true
	gradient.Destroying:Once(function()
		gradients[gradient] = nil
	end)
	start()
end

function TierShine.AddFx(obj: Instance, kind: string)
	if fx[obj] == kind then
		return
	end
	local fresh = fx[obj] == nil
	fx[obj] = kind
	if fresh then
		obj.Destroying:Once(function()
			fx[obj] = nil
		end)
	end
	if lowEffects then
		rest(obj, kind)
	end
	start()
end

function TierShine.RemoveFx(obj: Instance?)
	if obj and fx[obj] then
		rest(obj, fx[obj])
		fx[obj] = nil
	end
end

-- Low effects: the badge pieces stop where they rest (the tier's colours and glow stay)
function TierShine.SetLowEffects(on: boolean)
	lowEffects = on
	if on then
		for obj, kind in fx do
			rest(obj, kind)
		end
	end
end

-- every UIGradient named `name` under `root` (e.g. all "Level" gradients on a grid of cards)
function TierShine.AddAll(root: Instance, name: string)
	for _, d in root:GetDescendants() do
		if d:IsA("UIGradient") and d.Name == name then
			TierShine.Add(d)
		end
	end
end

-- tier = "Gold" | "Rainbow" | anything else (no effect: `otherColour`)
function TierShine.Apply(gui: GuiObject, gradient: UIGradient?, tier: string?, otherColour: Color3)
	local on = gradient ~= nil and (tier == "Gold" or tier == "Rainbow")
	gui.BackgroundColor3 = if on then WHITE else otherColour
	if gradient then
		gradient.Enabled = on
		gradient:SetAttribute("Shine", if on then tier else nil)
		if on then
			TierShine.Add(gradient)
		end
	end
end

return TierShine
