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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)

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

function TitleChip.new(parent: Instance, cfg: { [string]: any }?): CanvasGroup
	cfg = cfg or {}
	local chip = Instance.new("CanvasGroup")
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
	chip.Parent = parent
	return chip
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

-- tier = "Normal" | "Gold" | "Rainbow" (nil = Normal)
function TitleChip.Set(chip: Instance, title: string?, tier: string?)
	local label0 = chip:FindFirstChild("Title") :: TextLabel
	local gui = chip :: GuiObject
	if paintSeason(gui, label0, chip:FindFirstChild("Rainbow") :: UIGradient?, title) then
		gui.Visible = true
		return
	end
	local level = if tier and TIER_COLOURS[tier] then tier else "Normal"
	local label = chip:FindFirstChild("Title") :: TextLabel
	label.Text = title or ""
	TierShine.Apply(chip :: GuiObject, chip:FindFirstChild("Rainbow") :: UIGradient?, level, TIER_COLOURS[level])
	;(chip :: GuiObject).Visible = title ~= nil and title ~= ""
end

local LOCKED_BG, LOCKED_TEXT, LOCKED_LINE = C("ECE6DA"), C("8A8398"), C("A39A8C")

function TitleChip.Paint(label: TextLabel, title: string, tier: string?)
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
	TierShine.Apply(label, gradient, if locked then nil else tier, if locked then LOCKED_BG else TIER_COLOURS[tier :: string])
end

return TitleChip
