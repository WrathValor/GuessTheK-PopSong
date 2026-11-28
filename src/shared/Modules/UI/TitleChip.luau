--| TitleChip
-- The player's title in one rounded, outlined chip, coloured by its tier (a set title levels
-- up with the set, Modules/Library/Cards.SetLevel): Normal on lilac, Gold on gold with a shine
-- sweeping across, Rainbow on the scrolling pastel rainbow (both Modules/UI/TierShine). Used by the HUD profile card,
-- lobby name tags and the Rival found cards.
--   local chip = TitleChip.new(parent, { Height = 18, TextSize = 11, Font = font, ZIndex = 3 })
--   TitleChip.Set(chip, "CARAT", "Gold")   -- tier nil = Normal
-- Season titles (SeasonConstants.SEASON_TITLES, e.g. Debut) are holo foil instead: a silver-lilac
-- sheen on the chip's own gradient and the season's badge ("S0") in a rounded ink box in front of
-- the title. The box is the chip's SeasonBadge, built with the chip (BuildBadge: in Studio for
-- the screens' chips via SeasonController/Build, and in new() for the name tags'); a chip
-- without one falls back to a highlighted "S0".
-- Paint() styles a chip that was built in Studio instead (a TextLabel with a UIStroke and a
-- "Rainbow" UIGradient): the Index's set reward and the roll reveal's title panel.
--   TitleChip.Paint(label, "CARAT", "Gold")   -- tier nil = locked (greyed, 🔒)
-- Group badges (Modules/Library/Ladders) come as tier "Rung:Bronze" … "Rung:Diamond" / "Rung:Legend"
-- with an icon ("Cards" = the photocard, "Songs" = the vinyl) and just the fandom's name: the
-- rung is the chip's look (board 64 · Badges · tier looks; see "Group badges" below). The icon
-- is a BadgeIcon ImageLabel and the look's pieces the chip's Fx (BuildIcon / BuildFx: made by
-- new(), built in Studio for the screens' chips); Legend's rainbow rim is a "LegendSheen"
-- UIGradient on the chip's UIStroke. A Studio chip without them just shows the foil.
--   TitleChip.Set(chip, "MY", "Rung:Gold", "Cards")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local Levels = require(ReplicatedStorage.Modules.Levels)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local Ladders = require(ReplicatedStorage.Modules.Library.Ladders)

local C = Color3.fromHex
local INK = C("1E1B2E")
local TIER_COLOURS = { Normal = C("B9A6FF"), Gold = C("F2C94C"), Rainbow = C("FFFFFF") }
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.25, C("FFD8A8")),
	ColorSequenceKeypoint.new(0.5, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.75, C("B8F0C8")),
	ColorSequenceKeypoint.new(1, C("B5DDFF")),
})
local HOLO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("E9E4FF")),
	ColorSequenceKeypoint.new(0.3, C("C9C2EE")),
	ColorSequenceKeypoint.new(0.45, C("FFFFFF")),
	ColorSequenceKeypoint.new(0.6, C("D9EEFF")),
	ColorSequenceKeypoint.new(1, C("E9D6FF")),
})
local DEFAULT_FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local TitleChip = {}

function TitleChip.new(parent: Instance, cfg: { [string]: any }?): Frame
	cfg = cfg or {}
	-- (a plain Frame, not a CanvasGroup: a badge's glow and sparkles reach past its edge)
	local chip = Instance.new("Frame")
	chip.Name = cfg.Name or "TitleChip"
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, cfg.Height or 18)
	chip.BackgroundColor3 = TIER_COLOURS.Normal
	chip.BorderSizePixel = 0
	chip.ZIndex = cfg.ZIndex or 1
	if cfg.LayoutOrder then
		chip.LayoutOrder = cfg.LayoutOrder
	end
	if cfg.AnchorPoint then
		chip.AnchorPoint = cfg.AnchorPoint
	end
	if cfg.Position then
		chip.Position = cfg.Position
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, cfg.Radius or 6)
	corner.Parent = chip
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = cfg.Stroke or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = chip
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Rainbow"
	gradient.Color = RAINBOW
	gradient.Rotation = 20
	gradient.Enabled = false
	gradient.Parent = chip

	local l = Instance.new("TextLabel")
	l.Name = "Title"
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.new(0, 0, 1, 0)
	l.BackgroundTransparency = 1
	l.FontFace = cfg.Font or DEFAULT_FONT
	l.TextSize = cfg.TextSize or 11
	l.TextColor3 = INK
	l.Text = ""
	l.ZIndex = cfg.ZIndex or 1
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, cfg.Pad or 6)
	pad.PaddingRight = UDim.new(0, cfg.Pad or 6)
	pad.Parent = l
	l.Parent = chip
	TitleChip.BuildBadge(chip, cfg.TextSize or 11, cfg.Font) -- shown only for season titles
	TitleChip.BuildIcon(chip, cfg.TextSize or 11) -- shown only for group badges
	TitleChip.BuildFx(chip) -- a badge's look pieces (board 64)
	chip:SetAttribute("Street", true) -- (name tags: Bronze–Gold badges keep still)
	chip.Parent = parent
	return chip
end

-- the group badge's icon (photocard / vinyl), hidden until a badge shows
function TitleChip.BuildIcon(chip: GuiObject, textSize: number): ImageLabel
	local old = chip:FindFirstChild("BadgeIcon")
	if old then
		old:Destroy()
	end
	local size = math.max(12, math.floor(textSize * 1.3))
	local icon = Instance.new("ImageLabel")
	icon.Name = "BadgeIcon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 4, 0.5, 0)
	icon.Size = UDim2.fromOffset(size, size)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.ZIndex = chip.ZIndex + 1
	icon.Parent = chip
	-- Legend's shining gold border (off until a Legend badge shows)
	local line = chip:FindFirstChildOfClass("UIStroke")
	if line and not line:FindFirstChild("LegendSheen") then
		local sheen = Instance.new("UIGradient")
		sheen.Name = "LegendSheen"
		sheen.Enabled = false
		sheen.Parent = line
	end
	return icon
end

-- [[ Group badges (board 64 · Badges · tier looks) ]]
-- A worn badge says just its fandom ("EXO-L"); the chip's look is its rung:
--   Bronze    flat copper
--   Silver    brushed metal, a white shine every 3.6 s
--   Gold      gold foil, a shine every 2.4 s, a sparkle twinkling on its corner
--   Platinum  icy cyan crystal drifting, a white inner rim, a shine every 4 s, a cyan glow
--   Diamond   royal-blue facets, a shine every 1.9 s, three sparkles, a blue glow
--   Legend    ink with gold letters, a turning rainbow rim, a soft shine, gold dust, a gold glow
-- The pieces are the chip's Fx… children (BuildFx: Shine, Facets, Rim, Glow1–3, Spark1–3, Dust1–3), moved
-- by TierShine (still with Low effects on). Name tags (new(): the "Street" attribute) keep
-- Bronze, Silver and Gold still: in a full server only the rare ones move.
local SPARKLE = "rbxassetid://112483120350596" -- 4-point ✦ (assets/UI/Cards/Sparkle.png)
local RUNG_RANK = { Bronze = 1, Silver = 2, Gold = 3, Platinum = 4, Diamond = 5, Legend = 6 }
local function seq(stops: { { any } }): ColorSequence
	local keys = {}
	for _, s in stops do
		table.insert(keys, ColorSequenceKeypoint.new(s[1], C(s[2])))
	end
	return ColorSequence.new(keys)
end
local RUNG_LOOK = {
	Bronze = { Foil = seq({ { 0, "F1C7A2" }, { 1, "DD9F70" } }), Rotation = 90 },
	Silver = { Foil = seq({ { 0, "F7F8FB" }, { 0.42, "C9D0DB" }, { 0.56, "EEF1F6" }, { 1, "B5BECC" } }), Rotation = 35, Sweep = 3.6 },
	Gold = { Foil = seq({ { 0, "FFF1A8" }, { 0.42, "F2C230" }, { 0.56, "FFE58A" }, { 1, "D9A11E" } }), Rotation = 35, Sweep = 2.4, Sparks = 1 },
	Platinum = { Foil = seq({ { 0, "E9FBFF" }, { 0.25, "9BE6F2" }, { 0.5, "D8F7FF" }, { 0.75, "6FD0E2" }, { 1, "E9FBFF" } }), Rotation = 30, Shift = true, Sweep = 4, Rim = true, Glow = C("6EDCEB") },
	Diamond = { Foil = seq({ { 0, "5E86FF" }, { 0.45, "C9D8FF" }, { 0.6, "7FA0FF" }, { 1, "3F5FE6" } }), Rotation = 35, Sweep = 1.9, Sparks = 3, Facets = true, Glow = C("5A82FF"), Text = C("14123A") },
	Legend = { Ink = true, Sweep = 3, SweepAlpha = 0.55, Spin = true, Dust = true, Glow = C("FFE07A"), Text = Ladders.LEGEND_TEXT },
}
local LEGEND_RIM = seq({ { 0, "FF5A4E" }, { 0.2, "FFE07A" }, { 0.4, "A7E9B8" }, { 0.6, "9ED8F5" }, { 0.8, "B9A6FF" }, { 1, "FF9EC4" } })

-- the chip's look pieces, all hidden until a badge shows. Each is a direct child of the chip
-- named Fx… (a deeper one would make an AutomaticSize chip grow without end), laid over the
-- chip's whole box, past a label's UIPadding, by fitFx.
local FX = { "FxFacets", "FxShine", "FxRim", "FxGlow1", "FxGlow2", "FxGlow3", "FxSpark1", "FxSpark2", "FxSpark3", "FxDust1", "FxDust2", "FxDust3" }

function TitleChip.BuildFx(chip: GuiObject)
	for _, name in FX do
		local old = chip:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local old = chip:FindFirstChild("Fx") -- (an older single holder)
	if old then
		old:Destroy()
	end
	local c = chip:FindFirstChildOfClass("UICorner")
	local r = if c then c.CornerRadius.Offset else 6
	local line = chip:FindFirstChildOfClass("UIStroke")
	local lt = if line then line.Thickness else 2
	local z = chip.ZIndex
	local h = math.max(chip.Size.Y.Offset, 18)
	-- inset: how far in from the chip's edge (negative: out past it)
	local function layer(name: string, inset: number, radius: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = C("FFFFFF")
		f.BorderSizePixel = 0
		f.Visible = false
		f.ZIndex = z
		f:SetAttribute("Inset", inset)
		local k = Instance.new("UICorner")
		k.CornerRadius = UDim.new(0, radius)
		k.Parent = f
		f.Parent = chip
		return f
	end
	-- Diamond: two light facet bars across
	local facets = layer("FxFacets", 0, r)
	local fg = Instance.new("UIGradient")
	fg.Rotation = 25
	fg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(0.301, 0.5), NumberSequenceKeypoint.new(0.36, 0.5),
		NumberSequenceKeypoint.new(0.361, 1), NumberSequenceKeypoint.new(0.62, 1), NumberSequenceKeypoint.new(0.621, 0.62), NumberSequenceKeypoint.new(0.66, 0.62),
		NumberSequenceKeypoint.new(0.661, 1), NumberSequenceKeypoint.new(1, 1),
	})
	fg.Parent = facets
	-- the shine band (TierShine "Sweep" moves its Band)
	local shine = layer("FxShine", 0, r)
	local band = Instance.new("UIGradient")
	band.Name = "Band"
	band.Rotation = 20
	band.Offset = Vector2.new(1.1, 0)
	band.Parent = shine
	-- Platinum: a white inner rim
	local rim = layer("FxRim", 2, math.max(2, r - 2))
	rim.BackgroundTransparency = 1
	local rs = Instance.new("UIStroke")
	rs.Color = C("FFFFFF")
	rs.Thickness = 1.5
	rs.Transparency = 0.1
	rs.Parent = rim
	-- Platinum+: a soft glow round the outline (rings just outside it, fading out)
	for i, spec in { { 2, 0.35 }, { 4, 0.62 }, { 7, 0.82 } } do
		local g = layer("FxGlow" .. i, -lt, r + lt)
		g.BackgroundTransparency = 1
		local gs = Instance.new("UIStroke")
		gs.Name = "Halo"
		gs.Thickness = spec[1]
		gs.Transparency = spec[2]
		gs.Parent = g
	end
	-- sparkles: on the top-right corner, the bottom-left, the top edge
	local size = math.max(10, math.floor(h * 0.6))
	for i, k in { 1, 0.75, 0.7 } do
		local sp = Instance.new("ImageLabel")
		sp.Name = "FxSpark" .. i
		sp.AnchorPoint = Vector2.new(0.5, 0.5)
		local s = math.floor(size * k)
		sp.Size = UDim2.fromOffset(s, s)
		sp:SetAttribute("Size", s)
		sp:SetAttribute("Delay", (i - 1) * 0.6)
		sp.BackgroundTransparency = 1
		sp.Image = SPARKLE
		sp.ImageColor3 = C("FFFFFF")
		sp.Visible = false
		sp.ZIndex = z + 1
		sp.Parent = chip
	end
	-- Legend: gold dust drifting up from the bottom edge
	for i, x in { 0.18, 0.52, 0.8 } do
		local d = Instance.new("Frame")
		d.Name = "FxDust" .. i
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(3, 3)
		d.BackgroundColor3 = C("FFE7A0")
		d.BackgroundTransparency = 1
		d.BorderSizePixel = 0
		d.Visible = false
		d.ZIndex = z + 1
		d:SetAttribute("Delay", (i - 1) * 0.9)
		d:SetAttribute("X", x)
		local k = Instance.new("UICorner")
		k.CornerRadius = UDim.new(1, 0)
		k.Parent = d
		d.Parent = chip
	end
end

-- lay the Fx over the chip's whole box: a label chip's UIPadding moves its children
local function fitFx(gui: GuiObject)
	local pad = gui:FindFirstChildOfClass("UIPadding")
	local l, r, t, b = 0, 0, 0, 0
	if pad then
		l, r, t, b = pad.PaddingLeft.Offset, pad.PaddingRight.Offset, pad.PaddingTop.Offset, pad.PaddingBottom.Offset
	end
	for _, name in FX do
		local f = gui:FindFirstChild(name) :: GuiObject?
		if f then
			local inset = f:GetAttribute("Inset")
			if inset then
				f.Position = UDim2.new(0, -l + inset, 0, -t + inset)
				f.Size = UDim2.new(1, l + r - inset * 2, 1, t + b - inset * 2)
			elseif name == "FxSpark1" then
				f.Position = UDim2.new(1, r - 2, 0, -t + 2)
			elseif name == "FxSpark2" then
				f.Position = UDim2.new(0, -l + 3, 1, b - 2)
			elseif name == "FxSpark3" then
				f.Position = UDim2.new(0.5, (r - l) / 2, 0, -t - 1)
			else -- dust
				local x = f:GetAttribute("X") or 0.5
				f.Position = UDim2.new(x, -l + (l + r) * x, 1, b - 3)
			end
		end
	end
end

-- every moving piece off, and hidden
local function clearFx(gui: GuiObject, gradient: UIGradient?)
	for _, name in FX do
		local f = gui:FindFirstChild(name) :: GuiObject?
		if f then
			f.Visible = false
			TierShine.RemoveFx(f)
		end
	end
	local shine = gui:FindFirstChild("FxShine")
	TierShine.RemoveFx(shine and shine:FindFirstChild("Band"))
	TierShine.RemoveFx(gradient)
	local line = gui:FindFirstChildOfClass("UIStroke")
	local sheen = line and line:FindFirstChild("LegendSheen")
	if sheen then
		TierShine.RemoveFx(sheen)
	end
end

-- a group badge's look (tier "Rung:<name>"): true if it is one. `gui` holds the colour +
-- gradient (+ BadgeIcon, Fx), `label` the text (+ its UIPadding).
local function paintRung(gui: GuiObject, label: TextLabel, gradient: UIGradient?, tier: string?, iconKind: string?): boolean
	local rung = type(tier) == "string" and string.match(tier, "^Rung:(%a+)$")
	local icon = gui:FindFirstChild("BadgeIcon") :: ImageLabel?
	local pad = label:FindFirstChildOfClass("UIPadding")
	if pad and pad:GetAttribute("BaseLeft") == nil then
		pad:SetAttribute("BaseLeft", pad.PaddingLeft.Offset)
	end
	local look = rung and RUNG_LOOK[rung]
	clearFx(gui, gradient)
	local line = gui:FindFirstChildOfClass("UIStroke")
	local sheen = line and line:FindFirstChild("LegendSheen") :: UIGradient?
	if not look then
		if icon then
			icon.Visible = false
		end
		if sheen and sheen.Enabled then
			sheen.Enabled = false
			sheen:SetAttribute("Shine", nil)
			line.Color = INK
		end
		if gradient and gradient:GetAttribute("Rung") then
			gradient:SetAttribute("Rung", nil)
			gradient:SetAttribute("Shine", nil)
			gradient.Offset = Vector2.zero
			gradient.Rotation = gradient:GetAttribute("BaseRotation") or gradient.Rotation
		end
		return false
	end
	-- still: a name tag's Bronze–Gold (only Platinum+ move on the street)
	local still = gui:GetAttribute("Street") == true and RUNG_RANK[rung] <= 3
	-- the foil (or Legend's ink)
	if gradient then
		if gradient:GetAttribute("BaseRotation") == nil then
			gradient:SetAttribute("BaseRotation", gradient.Rotation) -- (put back for a title)
		end
		gradient:SetAttribute("Rung", rung)
		gradient:SetAttribute("Shine", "Static") -- (TierShine's own loop leaves it alone)
		gradient.Offset = Vector2.zero
		gradient.Enabled = not look.Ink
		if not look.Ink then
			gradient.Color = look.Foil
			gradient.Rotation = look.Rotation
			if look.Shift and not still then
				TierShine.AddFx(gradient, "Shift")
			end
		end
	end
	gui.BackgroundColor3 = if look.Ink or not gradient then (if look.Ink then INK else Ladders.COLOURS[rung]) else C("FFFFFF")
	-- the outline: ink, or Legend's turning rainbow rim
	if line then
		line.Color = if look.Spin and sheen then C("FFFFFF") else INK
		if sheen then
			sheen.Enabled = look.Spin == true
			sheen:SetAttribute("Shine", if look.Spin then "Static" else nil)
			if look.Spin then
				sheen.Color = LEGEND_RIM
				sheen.Offset = Vector2.zero
				TierShine.AddFx(sheen, "Spin")
			end
		end
	end
	-- the pieces
	if gui:FindFirstChild("FxShine") then
		fitFx(gui)
		local shine = gui.FxShine :: Frame
		if look.Sweep then
			shine.Visible = true
			local band = shine.Band :: UIGradient
			local a = look.SweepAlpha or 0.15
			band.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, a),
				NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
			})
			band:SetAttribute("Every", look.Sweep)
			band.Offset = Vector2.new(1.1, 0)
			if not still then
				TierShine.AddFx(band, "Sweep")
			end
		end
		gui.FxFacets.Visible = look.Facets == true
		gui.FxRim.Visible = look.Rim == true
		for i = 1, 3 do
			local g = gui:FindFirstChild("FxGlow" .. i) :: Frame?
			if g then
				g.Visible = look.Glow ~= nil
				if look.Glow then
					g.Halo.Color = look.Glow
				end
			end
			local sp = gui:FindFirstChild("FxSpark" .. i) :: ImageLabel?
			if sp then
				sp.Visible = (look.Sparks or 0) >= i
				if sp.Visible then
					if still then
						sp.ImageTransparency = 0.1
					else
						TierShine.AddFx(sp, "Twinkle")
					end
				end
			end
			local d = gui:FindFirstChild("FxDust" .. i) :: Frame?
			if d then
				d.Visible = look.Dust == true
				if look.Dust then
					TierShine.AddFx(d, "Rise")
				end
			end
		end
	end
	label.RichText = false
	label.TextColor3 = look.Text or INK
	local image = iconKind and Ladders.ICONS[iconKind]
	if icon and pad then
		icon.Visible = image ~= nil
		icon.Image = image or ""
		icon.ImageColor3 = if look.Ink then Ladders.LEGEND_TEXT else C("FFFFFF")
		local left = pad:GetAttribute("BaseLeft") + (if image then icon.Size.X.Offset + 3 else 0)
		pad.PaddingLeft = UDim.new(0, left)
		local x = if icon.Parent == label then 4 - left else 4
		icon.Position = UDim2.new(0, x, 0.5, 0)
	end
	if gui:FindFirstChild("FxShine") then
		fitFx(gui) -- (the icon may have moved the padding)
	end
	return true
end

local BADGE_GAP = 4 -- chip edge → badge, and badge → title text (+2)

-- The rounded ink box a season title's badge sits in ("S0"), hidden until a season title shows.
-- `chip` is what the badge sits in (the TextLabel for Studio chips, the CanvasGroup for new()).
function TitleChip.BuildBadge(chip: GuiObject, textSize: number, font: Font?): TextLabel
	local old = chip:FindFirstChild("SeasonBadge")
	if old then
		old:Destroy()
	end
	local h = math.max(12, math.floor(textSize * 1.25))
	local badge = Instance.new("TextLabel")
	badge.Name = "SeasonBadge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, BADGE_GAP, 0.5, 0)
	badge.Size = UDim2.fromOffset(math.floor(textSize * 1.35) + 8, h)
	badge.BackgroundColor3 = INK
	badge.BorderSizePixel = 0
	badge.FontFace = font or DEFAULT_FONT
	badge.TextSize = math.max(8, textSize - 2)
	badge.TextColor3 = C("FBF7F0")
	badge.Text = "S0"
	badge.Visible = false
	badge.ZIndex = chip.ZIndex + 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.floor(h * 0.35))
	corner.Parent = badge
	badge.Parent = chip
	return badge
end

-- a season title's look: holo foil on the gradient + its badge in front. True if `title` is one.
-- `gui` holds the gradient (+ SeasonBadge); `label` holds the text (+ its UIPadding).
local function paintSeason(gui: GuiObject, label: TextLabel, gradient: UIGradient?, title: string?): boolean
	local badge = title and SeasonConstants.SEASON_TITLES[title]
	local box = gui:FindFirstChild("SeasonBadge") :: TextLabel?
	local pad = label:FindFirstChildOfClass("UIPadding")
	if pad and pad:GetAttribute("BaseLeft") == nil then
		pad:SetAttribute("BaseLeft", pad.PaddingLeft.Offset)
	end
	if not badge or not gradient then
		label.RichText = false
		if gradient and gradient:GetAttribute("Shine") == "Static" then
			gradient:SetAttribute("Shine", nil)
		end
		if box then
			box.Visible = false
		end
		if pad then
			pad.PaddingLeft = UDim.new(0, pad:GetAttribute("BaseLeft"))
		end
		return false
	end
	gui.BackgroundColor3 = C("FFFFFF")
	gradient.Color = HOLO
	gradient.Rotation = 115
	gradient.Offset = Vector2.zero
	gradient.Enabled = true
	gradient:SetAttribute("Shine", "Static") -- TierShine leaves it alone
	label.TextColor3 = INK
	if box and pad then
		box.Visible = true
		box.Text = badge
		local left = BADGE_GAP + box.Size.X.Offset + BADGE_GAP + 2
		pad.PaddingLeft = UDim.new(0, left)
		-- a UIPadding moves the label's children too: pull the badge back to the chip's edge
		local x = if box.Parent == label then BADGE_GAP - left else BADGE_GAP
		box.Position = UDim2.new(0, x, 0.5, 0)
		label.RichText = false
		label.Text = title
	else
		label.RichText = true
		label.Text = `<mark color="#1E1B2E"><font color="#FBF7F0"> {badge} </font></mark>  {title}`
	end
	return true
end

-- tier = "Normal" | "Gold" | "Rainbow" (nil = Normal) | "Rung:<name>" (a group badge, + icon)
function TitleChip.Set(chip: Instance, title: string?, tier: string?, icon: string?)
	local label0 = chip:FindFirstChild("Title") :: TextLabel
	local gui = chip :: GuiObject
	if paintRung(gui, label0, chip:FindFirstChild("Rainbow") :: UIGradient?, tier, icon) then
		label0.Text = title or ""
		gui.Visible = title ~= nil and title ~= ""
		return
	end
	if paintSeason(gui, label0, chip:FindFirstChild("Rainbow") :: UIGradient?, title) then
		gui.Visible = true
		return
	end
	local level = if tier and TIER_COLOURS[tier] then tier else "Normal"
	local label = chip:FindFirstChild("Title") :: TextLabel
	label.Text = title or ""
	-- a Normal level title wears its own colour (Levels.TITLE_COLOURS)
	local colour = if level == "Normal" and title then Levels.TITLE_COLOURS[title] or TIER_COLOURS.Normal else TIER_COLOURS[level]
	TierShine.Apply(chip :: GuiObject, chip:FindFirstChild("Rainbow") :: UIGradient?, level, colour)
	;(chip :: GuiObject).Visible = title ~= nil and title ~= ""
end

local LOCKED_BG, LOCKED_TEXT, LOCKED_LINE = C("ECE6DA"), C("8A8398"), C("A39A8C")

function TitleChip.Paint(label: TextLabel, title: string, tier: string?, icon: string?)
	if paintRung(label, label, label:FindFirstChild("Rainbow") :: UIGradient?, tier, icon) then
		label.Text = title -- (paintRung set the border: ink, or Legend's gold)
		return
	end
	local locked = tier == nil or TIER_COLOURS[tier] == nil
	local line = label:FindFirstChildOfClass("UIStroke")
	local gradient = label:FindFirstChild("Rainbow") :: UIGradient?
	if not locked and paintSeason(label, label, gradient, title) then
		if line then
			line.Color = INK
		end
		return
	end
	label.Text = if locked then `🔒 {title}` else title
	label.TextColor3 = if locked then LOCKED_TEXT else INK
	if line then
		line.Color = if locked then LOCKED_LINE else INK
	end
	local colour = if locked then LOCKED_BG
		elseif tier == "Normal" then Levels.TITLE_COLOURS[title] or TIER_COLOURS.Normal
		else TIER_COLOURS[tier :: string]
	TierShine.Apply(label, gradient, if locked then nil else tier, colour)
end

return TitleChip
