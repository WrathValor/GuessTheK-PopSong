--| TitleChip
-- The player's title in one rounded, outlined chip, coloured by its tier (a set title levels
-- up with the set, Modules/Library/Cards.SetLevel): Normal on lilac, Gold on gold with a shine
-- sweeping across, Rainbow on the scrolling pastel rainbow (both Modules/UI/TierShine). Used by the HUD profile card,
-- lobby name tags and the Rival found cards.
--   local chip = TitleChip.new(parent, { Height = 18, TextSize = 11, Font = font, ZIndex = 3 })
--   TitleChip.Set(chip, "CARAT", "Gold")   -- tier nil = Normal
-- Paint() styles a chip that was built in Studio instead (a TextLabel with a UIStroke and a
-- "Rainbow" UIGradient): the Index's set reward and the roll reveal's title panel.
--   TitleChip.Paint(label, "CARAT", "Gold")   -- tier nil = locked (greyed, 🔒)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)

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
	chip.Parent = parent
	return chip
end

-- tier = "Normal" | "Gold" | "Rainbow" (nil = Normal)
function TitleChip.Set(chip: Instance, title: string?, tier: string?)
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
	label.Text = if locked then `🔒 {title}` else title
	label.TextColor3 = if locked then LOCKED_TEXT else INK
	if line then
		line.Color = if locked then LOCKED_LINE else INK
	end
	TierShine.Apply(label, gradient, if locked then nil else tier, if locked then LOCKED_BG else TIER_COLOURS[tier :: string])
end

return TitleChip
