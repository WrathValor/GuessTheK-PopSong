--| TitleChip
-- The title chip with the bias pack joined on: "Fan | ♥ CARAT" (design board "Bias pack 1").
-- One rounded, outlined chip: the title on lilac, then (if the player has a bias pack) a
-- divider and the bias in its group colour. Used by the HUD profile card, lobby name tags and
-- the Rival found cards.
--   local chip = TitleChip.new(parent, { Height = 18, TextSize = 11, Font = font, ZIndex = 3 })
--   TitleChip.Set(chip, "Fan", "♥ CARAT", "9ED8F5")   -- bias nil = title only
--   TitleChip.FromAttribute(player:GetAttribute("Bias")) -> text?, colourHex?

local INK = Color3.fromHex("1E1B2E")
local LILAC = Color3.fromHex("B9A6FF")
local DEFAULT_FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local TitleChip = {}

local function part(chip: Instance, name: string, order: number, colour: Color3, cfg): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = order
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.new(0, 0, 1, 0)
	l.BackgroundColor3 = colour
	l.BorderSizePixel = 0
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
	return l
end

function TitleChip.new(parent: Instance, cfg: { [string]: any }?): CanvasGroup
	cfg = cfg or {}
	local chip = Instance.new("CanvasGroup")
	chip.Name = cfg.Name or "TitleChip"
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, cfg.Height or 18)
	chip.BackgroundColor3 = LILAC
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
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = chip
	part(chip, "Title", 1, LILAC, cfg)
	local bias = part(chip, "Bias", 2, LILAC, cfg)
	bias.Visible = false
	local div = Instance.new("Frame")
	div.Name = "Divider"
	div.Size = UDim2.new(0, cfg.Stroke or 2, 1, 0)
	div.Position = UDim2.fromOffset(-(cfg.Pad or 6), 0) -- the label's UIPadding shifts children
	div.BackgroundColor3 = INK
	div.BorderSizePixel = 0
	div.ZIndex = (cfg.ZIndex or 1) + 1
	div.Parent = bias
	chip.Parent = parent
	return chip
end

function TitleChip.Set(chip: Instance, title: string?, bias: string?, colourHex: string?)
	local t = chip:FindFirstChild("Title") :: TextLabel
	local b = chip:FindFirstChild("Bias") :: TextLabel
	t.Text = title or ""
	t.Visible = title ~= nil and title ~= ""
	b.Visible = bias ~= nil and bias ~= ""
	b.Text = bias or ""
	if colourHex then
		b.BackgroundColor3 = Color3.fromHex(colourHex)
	end
	-- no title: the bias is the whole chip, so drop its divider
	local div = b:FindFirstChild("Divider")
	if div then
		div.Visible = t.Visible
	end
	;(chip :: GuiObject).Visible = t.Visible or b.Visible
end

-- the "Bias" player attribute DataService sets: "♥ CARAT|9ED8F5"
function TitleChip.FromAttribute(value: any): (string?, string?)
	if type(value) ~= "string" or value == "" then
		return nil, nil
	end
	local text, colour = string.match(value, "^(.*)|(%x+)$")
	return text, colour
end

return TitleChip
