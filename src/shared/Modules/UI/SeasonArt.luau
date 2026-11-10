--| SeasonArt
-- The season pieces every screen shares: the tier Emblem, the TierChip (emblem + "IDOL II")
-- and a profile Banner. Build*() make the instances (run in Studio, from
-- SeasonController/Build); Paint*() fill them at runtime from Constants/SeasonConstants.
--   SeasonArt.PaintEmblem(emblem, tierInfo)        -- tierInfo = SeasonConstants.TierOf(sp)
--   SeasonArt.PaintChip(chip, tierInfo, withDivision?)
--   SeasonArt.PaintBanner(banner, bannerId)
--   SeasonArt.BuildCardSkin(card, photo, radius, withDeco)  -- photocard layers on a card frame
--   SeasonArt.PaintPhotocard(card, photocardId)
--   SeasonArt.Of(player) -> sp, tierInfo, bannerId, photocardId   -- from the player's attributes
-- Banners and photocards with Fx (SeasonConstants) animate through SeasonFx while on screen.
-- The emblem's frame shape changes per tier (circle → rounded square → shield → diamond →
-- burst → holo crest) so tiers read by outline alone, like the "Tier emblems" board. An
-- Image slot takes the final 256 × 256 art: SeasonConstants.TIERS[n].Emblems[division] (the
-- lightstick for III / II / I), else .Emblem.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local TierShine = require(script.Parent.TierShine)
local SeasonFx = require(script.Parent.SeasonFx)
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local WHITE = C("FFFFFF")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local SeasonArt = {}

-- [[ Build helpers ]]

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number | UDim)
	return new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r :: number) }, p)
end

local function stroke(p: Instance, t: number)
	return new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

-- Emblem: a square holder with Shadow + Shape (+ Shape2 for the burst / diamond), a Glyph
-- (the tier's first letter until the art exists) and an Image slot. size = side in px.
function SeasonArt.BuildEmblem(parent: Instance, name: string, pos: UDim2, size: number, anchor: Vector2?): Frame
	local holder = new("Frame", { Name = name, AnchorPoint = anchor or Vector2.zero, Position = pos, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, parent)
	local line = math.max(2, math.floor(size / 18))
	local drop = math.max(2, math.floor(size / 20))
	local inset = math.floor(size * 0.14)
	for _, spec in { { "Shadow", INK, drop }, { "Shape", C("B9A6FF"), 0 } } do
		local f = new("Frame", { Name = spec[1], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, spec[3], 0.5, spec[3]), Size = UDim2.new(1, -inset, 1, -inset), BackgroundColor3 = spec[2], BorderSizePixel = 0 }, holder)
		corner(f, UDim.new(0.5, 0))
		if spec[1] == "Shape" then
			stroke(f, line)
			new("UIGradient", { Name = "Holo", Color = SeasonConstants.HOLO, Rotation = 35, Enabled = false }, f)
		end
	end
	-- second square for the 8-point burst (rotated 45°), drawn under the first
	local shape2 = new("Frame", { Name = "Shape2", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -inset - 4, 1, -inset - 4), Rotation = 45, BackgroundColor3 = C("FF9EC4"), BorderSizePixel = 0, Visible = false, ZIndex = 0 }, holder)
	corner(shape2, UDim.new(0.18, 0))
	stroke(shape2, line)
	-- crown for Legend
	-- crown for Legend: a gold band with three diamond tips, sitting on the crest
	local crown = new("Frame", { Name = "Crown", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, inset + 2), Size = UDim2.new(0.56, 0, 0.26, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 3 }, holder)
	for i, x in { 0.12, 0.5, 0.88 } do
		local tip = new("Frame", { Name = "Tip" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, if i == 2 then 0.32 else 0.45), Size = UDim2.fromScale(0.3, 0.3), SizeConstraint = Enum.SizeConstraint.RelativeXX, Rotation = 45, BackgroundColor3 = C("FFE07A"), ZIndex = 3 }, crown)
		stroke(tip, math.max(1, line - 1))
	end
	local band = new("Frame", { Name = "Band", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 0.48), BackgroundColor3 = C("FFE07A"), ZIndex = 4 }, crown)
	corner(band, 3)
	stroke(band, math.max(1, line - 1))
	new("TextLabel", { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, FontFace = HEAD, TextScaled = true, TextColor3 = INK, Text = "★", ZIndex = 2 }, holder)
	new("ImageLabel", { Name = "Image", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, Visible = false, ZIndex = 4 }, holder)
	-- the animated Legend (TIERS[n].Layers): back, a white disc the rainbow gradient tints,
	-- front, and two sparkles that twinkle. Positions match the 120-unit canvas emblem.
	local layers = new("Frame", { Name = "Layers", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 4 }, holder)
	for i, name in { "Back", "Disc", "Front" } do
		local img = new("ImageLabel", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, ZIndex = 4 + i }, layers)
		if name == "Disc" then
			new("UIGradient", { Name = "Shine", Color = SeasonConstants.HOLO, Rotation = 35, Enabled = false }, img)
		end
	end
	for i, spec in { { 0.817, 0.183, 0.18 }, { 0.133, 0.817, 0.14 } } do
		local sp = new("ImageLabel", { Name = "Spark" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[1], spec[2]), Size = UDim2.fromScale(spec[3], spec[3]), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, ZIndex = 8 }, layers)
		new("UIScale", { Name = "Twinkle" }, sp)
	end
	return holder
end

-- TierChip: tier colour chip with a small emblem and the label ("IDOL II")
function SeasonArt.BuildChip(parent: Instance, name: string, pos: UDim2, height: number, anchor: Vector2?): Frame
	local chip = new("Frame", { Name = name, AnchorPoint = anchor or Vector2.zero, Position = pos, Size = UDim2.fromOffset(0, height), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C("B9A6FF") }, parent)
	corner(chip, math.floor(height * 0.36))
	stroke(chip, math.max(2, math.floor(height / 9)))
	new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, math.floor(height * 0.4)) }, chip)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, chip)
	local emblem = SeasonArt.BuildEmblem(chip, "Emblem", UDim2.new(), height - 4)
	emblem.LayoutOrder = 1
	new("TextLabel", { Name = "Label", LayoutOrder = 2, Size = UDim2.fromOffset(0, height), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, FontFace = HEAD, TextSize = math.floor(height * 0.5), TextColor3 = INK, Text = "TRAINEE III" }, chip)
	return chip
end

-- Banner: Fill frame (rounded on all corners) + SquareBottom (so the bottom edge can sit flat
-- on a rule) + an Art image. Gradients run left → right so the two halves line up.
function SeasonArt.BuildBanner(parent: Instance, name: string, pos: UDim2, size: UDim2, radius: number, squareBottom: boolean): Frame
	local banner = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = C("9ED8F5"), BorderSizePixel = 0 }, parent)
	corner(banner, radius)
	new("UIGradient", { Name = "Tint", Rotation = 0, Enabled = false }, banner)
	if squareBottom then
		local sq = new("Frame", { Name = "SquareBottom", Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = C("9ED8F5"), BorderSizePixel = 0 }, banner)
		new("UIGradient", { Name = "Tint", Rotation = 0, Enabled = false }, sq)
	end
	-- the stage-light stripes most season banners carry (Pattern), right of the quiet zone
	local pattern = new("Frame", { Name = "Pattern", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.55, 1), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false }, banner)
	for i = 0, 6 do
		new("Frame", { Name = "Beam" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(i / 6, 0, 0.5, 0), Size = UDim2.new(0, 14, 1.6, 0), Rotation = 28, BackgroundColor3 = WHITE, BackgroundTransparency = 0.68, BorderSizePixel = 0 }, pattern)
	end
	local art = new("ImageLabel", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop, Visible = false }, banner)
	corner(art, radius)
	return banner
end

-- [[ Paint ]]

local SHAPE = {
	Circle = { Radius = UDim.new(0.5, 0), Rotation = 0, Burst = false, Glyph = "♪" },
	Square = { Radius = UDim.new(0.24, 0), Rotation = 0, Burst = false, Glyph = "♫" },
	Shield = { Radius = UDim.new(0.34, 0), Rotation = 0, Burst = false, Glyph = "♥" },
	Hexagon = { Radius = UDim.new(0.2, 0), Rotation = 45, Burst = false, Glyph = "★" },
	Burst = { Radius = UDim.new(0.18, 0), Rotation = 0, Burst = true, Glyph = "◉" },
	Crest = { Radius = UDim.new(0.5, 0), Rotation = 0, Burst = false, Glyph = "★" },
}

function SeasonArt.PaintEmblem(emblem: Instance, info)
	if not emblem then
		return
	end
	local tier = info.Tier
	local shape = SHAPE[tier.Shape] or SHAPE.Circle
	local face, shadow = emblem:FindFirstChild("Shape"), emblem:FindFirstChild("Shadow")
	for _, f in { face, shadow } do
		if f then
			f.Rotation = shape.Rotation
			local c = f:FindFirstChildOfClass("UICorner")
			if c then
				c.CornerRadius = shape.Radius
			end
		end
	end
	local holo = face and face:FindFirstChild("Holo")
	if face and holo then
		if tier.Holo then
			TierShine.Apply(face, holo, "Rainbow", WHITE)
		else
			holo.Enabled = false
			face.BackgroundColor3 = tier.Colour
		end
	end
	local s2 = emblem:FindFirstChild("Shape2")
	if s2 then
		s2.Visible = shape.Burst
		s2.BackgroundColor3 = tier.Colour
	end
	local crown = emblem:FindFirstChild("Crown")
	if crown then
		crown.Visible = tier.Holo == true
	end
	local image = emblem:FindFirstChild("Image")
	local src = (tier.Emblems and tier.Emblems[info.Division]) or tier.Emblem -- one lightstick per division
	local art = src ~= nil and src ~= ""
	if image then
		image.Image = src or ""
		image.Visible = art
	end
	-- animated Legend: layered art, rainbow on the disc, twinkling sparkles
	local layers = emblem:FindFirstChild("Layers")
	local layered = layers ~= nil and tier.Layers ~= nil
	if layers then
		layers.Visible = layered
		if layered then
			for _, name in { "Back", "Disc", "Front" } do
				layers[name].Image = tier.Layers[name]
			end
			TierShine.Apply(layers.Disc, layers.Disc.Shine, "Rainbow", WHITE)
			for i = 1, 2 do
				local sp = layers["Spark" .. i]
				sp.Image = tier.Layers.Sparkle or ""
				sp.Visible = tier.Layers.Sparkle ~= nil
				if sp.Visible and RunService:IsRunning() and RunService:IsClient() and not sp:GetAttribute("Twinkling") then
					sp:SetAttribute("Twinkling", true)
					local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
					task.delay((i - 1) * 0.9, function()
						if sp.Parent then
							sp.Twinkle.Scale, sp.ImageTransparency = 0.6, 0.7
							TweenService:Create(sp.Twinkle, info, { Scale = 1 }):Play()
							TweenService:Create(sp, info, { ImageTransparency = 0 }):Play()
						end
					end)
				end
			end
		end
		if image and layered then
			image.Visible = false
		end
	end
	for _, part in { face, shadow, s2, crown, emblem:FindFirstChild("Glyph") } do
		if part and art then
			(part :: any).Visible = false
		end
	end
	local glyph = emblem:FindFirstChild("Glyph")
	if glyph and not art then
		glyph.Visible = true
		glyph.Text = shape.Glyph
	end
end

function SeasonArt.PaintChip(chip: Instance, info, withDivision: boolean?)
	if not chip then
		return
	end
	-- seasons off (SeasonConstants.ENABLED): no tier anywhere; a Chips row closes the gap
	(chip :: any).Visible = SeasonConstants.ENABLED
	if not SeasonConstants.ENABLED then
		return
	end
	(chip :: any).BackgroundColor3 = if info.Tier.Holo then C("1E1B2E") else info.Tier.Colour
	local label = chip:FindFirstChild("Label")
	if label then
		label.Text = if withDivision == false then string.upper(info.Tier.Name) else info.Label
		label.TextColor3 = if info.Tier.Holo then C("FFE07A") else INK
	end
	SeasonArt.PaintEmblem(chip:FindFirstChild("Emblem"), info)
end

function SeasonArt.PaintBanner(banner: Instance, id: string?)
	if not banner then
		return
	end
	local spec = SeasonConstants.Banner(id)
	local parts = { banner }
	local sq = banner:FindFirstChild("SquareBottom")
	if sq then
		table.insert(parts, sq)
	end
	for _, part in parts do
		local tint = part:FindFirstChild("Tint")
		if spec.Gradient and spec.Id == "S0Legend" and tint then
			TierShine.Apply(part, tint, "Rainbow", WHITE)
		elseif tint then
			part.BackgroundColor3 = WHITE
			tint.Color = spec.Gradient or ColorSequence.new(spec.Fill)
			tint.Enabled = spec.Gradient ~= nil
			if not spec.Gradient then
				part.BackgroundColor3 = spec.Fill
			end
		else
			part.BackgroundColor3 = spec.Fill
		end
	end
	local hasArt = spec.Art ~= nil and spec.Art ~= ""
	local pattern = banner:FindFirstChild("Pattern")
	if pattern then
		pattern.Visible = spec.Gradient ~= nil and not hasArt
	end
	local art = banner:FindFirstChild("Art")
	if art then
		art.Image = spec.Art or ""
		art.Visible = spec.Art ~= nil and spec.Art ~= ""
	end
	banner:SetAttribute("BannerId", spec.Id)
	banner:SetAttribute("Dark", spec.Dark == true)
	SeasonFx.Apply(banner, SeasonConstants.BANNER_FX[spec.Id], { Aspect = 4, ZIndex = 3 })
end

-- Photocard skin on an existing card frame + its photo frame (ProfileController/Build.Photo):
-- Skin (the card art, under everything), Bg in the photo (behind the avatar) and, on big
-- cards, Deco (the stickers over the window). Safe to run again.
function SeasonArt.BuildCardSkin(card: GuiObject, photo: GuiObject, radius: number, withDeco: boolean)
	for _, name in { "Skin", "Deco" } do
		local old = card:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local oldBg = photo:FindFirstChild("Bg")
	if oldBg then
		oldBg:Destroy()
	end
	local skin = new("ImageLabel", { Name = "Skin", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Stretch, ZIndex = 0 }, card)
	corner(skin, radius)
	new("ImageLabel", { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop, ZIndex = 0 }, photo)
	if withDeco then
		new("ImageLabel", { Name = "Deco", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Stretch, ZIndex = 2 }, card)
	end
end

-- fill a skinned card with a photocard (nil / unknown id = the plain rainbow card)
function SeasonArt.PaintPhotocard(card: GuiObject?, id: string?)
	if not card then
		return
	end
	local photo = card:FindFirstChild("Photo")
	local spec = SeasonConstants.Photocard(id)
	local skin, deco = card:FindFirstChild("Skin"), card:FindFirstChild("Deco")
	local bg = photo and photo:FindFirstChild("Bg")
	if skin then
		skin.Image = if spec then spec.Face else ""
	end
	if deco then
		deco.Image = if spec then spec.Deco else ""
	end
	if bg then
		bg.Image = if spec then spec.Photo else ""
	end
	local rainbow = photo and photo:FindFirstChild("Rainbow")
	if rainbow then
		rainbow.Enabled = spec == nil
	end
	card:SetAttribute("PhotocardId", if spec then spec.Id else nil)
	-- effects only on the big cards (the ones with stickers); small ones stay still
	SeasonFx.Apply(card, if spec and deco then spec.Fx else nil, { Aspect = 280 / 334, Photo = photo, ZIndex = 2 })
end

-- a player's season, from their attributes (SeasonService will set these)
function SeasonArt.Of(player: Player?)
	local sp = player and player:GetAttribute("SeasonSP") or 0
	local banner = player and player:GetAttribute("Banner") or SeasonConstants.DEFAULT_BANNER
	local photocard = player and player:GetAttribute("Photocard") or SeasonConstants.DEFAULT_PHOTOCARD
	return sp, SeasonConstants.TierOf(sp), banner, photocard
end

SeasonArt.CREAM = CREAM

return SeasonArt
