--| SeasonFx
-- Moving effects on banners and photocards (SeasonConstants.BANNER_FX / PHOTOCARDS[n].Fx),
-- drawn over the art at runtime. One Heartbeat loop drives every effect, and only effects
-- that are on screen are updated. Client only: in Edit mode Apply() does nothing (unless
-- opts.Force, for previewing a still frame in Studio).
--   SeasonFx.Apply(root, effects, { Aspect = 4, Photo = photoFrame?, ZIndex = 3 })
-- root  = the banner frame or the photocard frame; the art fills it with ScaleType.Crop, so
--         effect positions (fractions of the art) are mapped through the same crop
-- Kinds (positions are fractions of the art; sizes are fractions of the art's width):
--   Shine    a soft white glint sweeping across every few seconds
--   Holo     a moving pastel-rainbow wash over the whole thing   { Alpha = 0.8 }
--   Sparkle  4-point stars that glint (pop + quarter turn) in turn                              { At = { {x, y, size} }, Soft = soft white glints? }
--   Glow     soft coloured glows that pulse (Flicker = neon)       { At = { {x, y, size, hex} } }
--   Rays     light rays turning slowly behind a shape             { At = {x, y, size}, Speed }
--   Spin     an image turning in place (vinyl)                     { Image, At = { {x, y, size, deg/s} } }
--   Sway     an image breathing + rocking over its copy (flowers)  { At = { {image, x, y, size} }, Bounce = grow + shrink only? }
--   Hop      images hopping in turn, left to right (letters)        { At = { {image, x, y, size} } }
--   Confetti small pieces drifting down                            { Area = {x0, y0, x1, y1}, Count }
--   Masked   a shape's fill animated under its outline              { Fill, Line, At = {x, y, size}, Mode }
--            Fill = a white silhouette image, Line = its ink outline drawn on top;
--            Mode "Rainbow" slides the pastel rainbow through it, "Pulse" breathes cream → yellow
-- Layer = "Photo" puts an effect in the photocard's photo window, behind the avatar.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local TierShine = require(script.Parent.TierShine)

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local IMAGES = SeasonConstants.FX_IMAGES
local CONFETTI = { C("FFE07A"), C("FFFFFF"), C("9ED8F5"), C("A7E9B8"), C("FF5A4E"), C("FF9EC4") }
local SHINE_EVERY, SHINE_TIME = 3.4, 1.1
local PULSE_FROM, PULSE_TO, PULSE_TIME = C("FFF6D6"), C("FFD24A"), 1.8

local SeasonFx = {}

local active = {} :: { [Frame]: (number) -> () } -- fx holder → its update(t)
local running = false

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- [[ Loop ]]

local function onScreen(gui: GuiObject): boolean
	local node: Instance? = gui
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
	if running then
		return
	end
	running = true
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for holder, update in active do
			if holder.Parent == nil then
				active[holder] = nil
			elseif onScreen(holder) then
				update(t)
			end
		end
	end)
end

-- [[ Placement ]]

-- the art's rectangle inside root under ScaleType.Crop (it overflows on one axis)
local function artFrame(holder: Frame, root: GuiObject, aspect: number): Frame
	local art = new("Frame", { Name = "Art", BackgroundTransparency = 1 }, holder)
	local function fit()
		local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
		if w <= 0 or h <= 0 then
			return
		end
		local aw, ah
		if w / h > aspect then
			aw, ah = w, w / aspect
		else
			aw, ah = h * aspect, h
		end
		-- in scale, not offset: AbsoluteSize already has the Interface's UIScale in it, so an
		-- offset size would be scaled twice and the effects would drift off the art
		art.Size = UDim2.fromScale(aw / w, ah / h)
		art.Position = UDim2.fromScale((1 - aw / w) / 2, (1 - ah / h) / 2)
	end
	fit()
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	return art
end

-- a CanvasGroup, not a Frame: the Profile photocard is tilted, and ClipsDescendants doesn't
-- clip under rotation, so a Frame would let glows and rays spill past the card
local function holderIn(root: GuiObject, zIndex: number, radius: UDim?): Frame
	local holder = new("CanvasGroup", { Name = "Fx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = zIndex }, root)
	if radius then
		new("UICorner", { CornerRadius = radius }, holder)
	end
	return holder
end

local function image(parent: Instance, key: string, x: number, y: number, size: number, zIndex: number): ImageLabel
	return new("ImageLabel", {
		Name = key,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(size, size),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundTransparency = 1,
		Image = IMAGES[key] or key,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = zIndex,
	}, parent)
end

-- A sparkle's glint, p = 0..1 through one cycle → scale, opacity, rotation. It rests small
-- and dim, pops bright past full size with a quarter turn, then settles (4-point stars look
-- the same every 90°, so ending on 90 loops cleanly).
local GLINT_TIME = 2.2
local function ease(a: number, b: number, p: number): number
	p = p * p * (3 - 2 * p)
	return a + (b - a) * p
end
local function glint(p: number): (number, number, number)
	if p < 0.6 then
		return 0.5, 0.35, 0
	elseif p < 0.72 then
		local q = (p - 0.6) / 0.12
		return ease(0.5, 1.35, q), ease(0.35, 1, q), ease(0, 45, q)
	elseif p < 0.84 then
		local q = (p - 0.72) / 0.12
		return ease(1.35, 0.85, q), ease(1, 0.9, q), ease(45, 80, q)
	end
	local q = (p - 0.84) / 0.16
	return ease(0.85, 0.5, q), ease(0.9, 0.35, q), ease(80, 90, q)
end

-- [[ Effects ]] each returns an update(t) or nil

local BUILD = {}

function BUILD.Shine(fx, _art, z, radius)
	local band = new("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = z }, fx)
	if radius then
		new("UICorner", { CornerRadius = radius }, band)
	end
	local grad = new("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(1.2, 0),
	}, band)
	local seed = math.random() * SHINE_EVERY
	return function(t)
		local into = (t + seed) % SHINE_EVERY
		if into >= SHINE_TIME then
			grad.Offset = Vector2.new(1.2, 0)
		else
			local p = into / SHINE_TIME
			p = p * p * (3 - 2 * p)
			grad.Offset = Vector2.new(-1.2 + p * 2.4, 0)
		end
	end
end

function BUILD.Holo(fx, _art, z, radius, spec)
	local wash = new("Frame", { Name = "Holo", Size = UDim2.fromScale(1, 1), BackgroundTransparency = spec.Alpha or 0.8, BorderSizePixel = 0, ZIndex = z }, fx)
	if radius then
		new("UICorner", { CornerRadius = radius }, wash)
	end
	local grad = new("UIGradient", { Name = "Shine", Rotation = 35 }, wash)
	TierShine.Apply(wash, grad, "Rainbow", WHITE) -- TierShine moves it
	return nil
end

function BUILD.Sparkle(_fx, art, z, _radius, spec)
	local list = {}
	local key = if spec.Soft then "SparkleSoft" else "Sparkle"
	for i, at in spec.At do
		local s = image(art, key, at[1], at[2], at[3], z + 1)
		table.insert(list, { s, at[3], i * 0.55 })
	end
	return function(t)
		for _, item in list do
			local scale, alpha, turn = glint(((t + item[3]) % GLINT_TIME) / GLINT_TIME)
			item[1].Size = UDim2.fromScale(item[2] * scale, item[2] * scale)
			item[1].ImageTransparency = 1 - alpha
			item[1].Rotation = turn
		end
	end
end

function BUILD.Glow(_fx, art, z, _radius, spec)
	local list = {}
	for i, at in spec.At do
		local g = image(art, "Glow", at[1], at[2], at[3], z)
		g.ImageColor3 = C(at[4] or "FFFFFF")
		table.insert(list, { g, i * 1.3 })
	end
	local flicker = spec.Flicker == true
	return function(t)
		for i, item in list do
			local tr = 0.45 + 0.15 * math.sin(t * 1.6 + item[2])
			if flicker then
				-- neon: now and then the sign dims and comes back, eased rather than snapped
				local n = math.noise(t * 0.9, i * 3.1)
				local dim = math.clamp((n - 0.22) / 0.18, 0, 1)
				dim = dim * dim * (3 - 2 * dim)
				tr += (0.85 - tr) * dim
			end
			item[1].ImageTransparency = tr
		end
	end
end

function BUILD.Rays(_fx, art, z, _radius, spec)
	local at = spec.At
	local r = image(art, "Rays", at[1], at[2], at[3], z)
	r.ImageTransparency = 0.45
	local speed = spec.Speed or 12
	return function(t)
		r.Rotation = (t * speed) % 360
	end
end

function BUILD.Spin(_fx, art, z, _radius, spec)
	local list = {}
	for _, at in spec.At do
		table.insert(list, { image(art, spec.Image, at[1], at[2], at[3], z + 1), at[4] or 40 })
	end
	return function(t)
		for _, item in list do
			item[1].Rotation = (t * item[2]) % 360
		end
	end
end

function BUILD.Sway(_fx, art, z, _radius, spec)
	-- drawn a touch bigger than the flower in the art so the copy underneath never peeks out
	local list = {}
	for i, at in spec.At do
		table.insert(list, { image(art, at[1], at[2], at[3], at[4] * 1.06, z + 1), at[4] * 1.06, i * 2.1 })
	end
	if spec.Bounce then
		-- in and out only, no rocking (never smaller than the copy in the art)
		return function(t)
			for _, item in list do
				local s = item[2] * (1 + 0.09 * (0.5 + 0.5 * math.sin(t * 2.6 + item[3])))
				item[1].Size = UDim2.fromScale(s, s)
			end
		end
	end
	return function(t)
		for _, item in list do
			local s = item[2] * (1 + 0.06 * math.sin(t * 2.2 + item[3]))
			item[1].Size = UDim2.fromScale(s, s)
			item[1].Rotation = 9 * math.sin(t * 1.4 + item[3])
		end
	end
end

-- letters hopping one after another, left to right, like a crowd cheering (Cheer Slogan).
-- The letters aren't in the art, so nothing shows underneath when they're up.
local HOP_TIME, HOP_GAP, HOP_HEIGHT = 2.4, 0.12, 0.067 -- s, s between letters, of the art's height
function BUILD.Hop(_fx, art, z, _radius, spec)
	local list = {}
	for i, at in spec.At do
		table.insert(list, { image(art, at[1], at[2], at[3], at[4], z + 1), at[2], at[3], (i - 1) * HOP_GAP })
	end
	return function(t)
		for _, item in list do
			local p = ((t - item[4]) % HOP_TIME) / HOP_TIME
			local up, turn = 0, 0
			if p < 0.1 then
				local q = p / 0.1
				up, turn = ease(0, 1, q), ease(0, -6, q)
			elseif p < 0.2 then
				local q = (p - 0.1) / 0.1
				up, turn = ease(1, 0, q), ease(-6, 3, q)
			elseif p < 0.3 then
				turn = ease(3, 0, (p - 0.2) / 0.1)
			end
			item[1].Position = UDim2.fromScale(item[2], item[3] - HOP_HEIGHT * up)
			item[1].Rotation = turn
		end
	end
end

function BUILD.Confetti(_fx, art, z, _radius, spec)
	local area = spec.Area or { 0, 0, 1, 1 }
	local pieces = {}
	for i = 1, spec.Count or 20 do
		local p = new("Frame", {
			Name = "Piece",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.011, 0.011 * 0.6),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			BackgroundColor3 = CONFETTI[(i - 1) % #CONFETTI + 1],
			BorderSizePixel = 0,
			ZIndex = z,
		}, art)
		table.insert(pieces, {
			p,
			area[1] + math.random() * (area[3] - area[1]),
			math.random(),
			0.08 + math.random() * 0.08,
			if math.random() < 0.5 then -1 else 1,
		})
	end
	return function(t)
		for _, item in pieces do
			local fall = (item[3] + t * item[4]) % 1
			local y = area[2] - 0.05 + fall * (area[4] - area[2] + 0.1)
			item[1].Position = UDim2.fromScale(item[2] + 0.012 * math.sin(t * 2 + item[3] * 9), y)
			item[1].Rotation = (t * 140 * item[5] + item[3] * 360) % 360
		end
	end
end

function BUILD.Masked(_fx, art, z, _radius, spec)
	local at = spec.At
	local fill = image(art, spec.Fill, at[1], at[2], at[3], z + 1)
	local line = image(art, spec.Line, at[1], at[2], at[3], z + 2)
	if spec.Mode == "Rainbow" then
		fill.ImageColor3 = WHITE
		TierShine.Add(new("UIGradient", { Name = "Shine", Rotation = 35 }, fill)) -- TierShine moves it
		return nil
	end
	-- Pulse: the fill breathes cream → yellow and the whole shape swells a touch
	local size = at[3]
	return function(t)
		local a = 0.5 - 0.5 * math.cos(t * math.pi * 2 / PULSE_TIME)
		fill.ImageColor3 = PULSE_FROM:Lerp(PULSE_TO, a)
		local s = size * (1 + 0.06 * a)
		fill.Size = UDim2.fromScale(s, s)
		line.Size = fill.Size
	end
end

-- [[ API ]]

local function clear(root: Instance?)
	if not root then
		return
	end
	local old = root:FindFirstChild("Fx")
	if old then
		active[old] = nil
		old:Destroy()
	end
end

function SeasonFx.Apply(root: GuiObject?, effects: { any }?, opts: { [string]: any }?)
	if not root then
		return
	end
	opts = opts or {}
	local photo = opts.Photo
	clear(root)
	clear(photo)
	if not effects or #effects == 0 then
		return
	end
	local live = RunService:IsRunning() and RunService:IsClient()
	if not live and not opts.Force then
		return
	end
	local function radiusOf(g: Instance): UDim?
		local c = g:FindFirstChildOfClass("UICorner")
		return c and c.CornerRadius or nil
	end
	local made = {}
	local function layer(name: string?): (Frame, Frame, number, UDim?)
		local key = name or "Root"
		if made[key] then
			return table.unpack(made[key])
		end
		local target, aspect, z = root, opts.Aspect or 4, opts.ZIndex or 3
		if name == "Photo" and photo then
			-- behind the avatar (ZIndex 1), over the photo background (ZIndex 0)
			target, aspect, z = photo, 256 / 228, 0
		end
		local r = radiusOf(target)
		local fx = holderIn(target, z, r)
		local art = artFrame(fx, target, aspect)
		made[key] = { fx, art, z, r }
		return fx, art, z, r
	end
	local updates = {}
	for _, spec in effects do
		local build = BUILD[spec.Kind]
		if build then
			local fx, art, z, r = layer(spec.Layer)
			local update = build(fx, art, z, r, spec)
			if update then
				table.insert(updates, update)
			end
		end
	end
	if #updates == 0 or not live then
		for _, update in updates do
			update(1.3) -- a still frame for Studio previews
		end
		return
	end
	for _, entry in made do
		local fx = entry[1]
		active[fx] = function(t)
			for _, update in updates do
				update(t)
			end
		end
		break -- one driver is enough: every update runs from the first holder
	end
	start()
end

return SeasonFx
