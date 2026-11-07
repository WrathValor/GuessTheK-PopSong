--| TierShine
-- The moving tier effects, like the canvas mockups. Every gradient added here is driven by one
-- Heartbeat loop (one ColorSequence of each kind built per frame and shared, so any number
-- costs the same). Client only.
--   • Rainbow – the pastel rainbow slides sideways in a slow loop
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

local RunService = game:GetService("RunService")

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

-- On screen? Every GuiObject above the gradient is Visible, and its ScreenGui / BillboardGui is
-- Enabled. (A few property reads per gradient; far cheaper than redrawing what nobody sees.)
local function shown(gradient: UIGradient): boolean
	local node = gradient.Parent
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function start()
	if running or not RunService:IsClient() then
		return
	end
	running = true
	RunService.Heartbeat:Connect(function()
		if next(gradients) == nil then
			return
		end
		local t = os.clock()
		local rb, gd = nil, nil
		for gradient in gradients do
			if gradient.Enabled and shown(gradient) then
				if gradient:GetAttribute("Shine") == "Gold" then
					gd = gd or goldOffset(t)
					if gradient.Color ~= GOLD_BAND then
						gradient.Color = GOLD_BAND
					end
					gradient.Offset = gd
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
