--| PreDuel pack UI builder
-- Adds the duel-pack bits to Interface.Frames.PreDuel (from the "Pack rounds" board):
--   • Packs    – sticker chip on the bottom edge of the stake card: "Packs ON · My Pack + HYBE
--                Pack" (mint) or "Packs off · <rival> has none on" (grey). Hidden with no packs.
--   • SoloPool – solo only, same spot: SONG POOL [Mix with all songs] [Only my pack]
-- Run once in Studio (safe to run again); PreDuelController finds them by name.

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local LILAC = C("B9A6FF")
local PINK = C("FF9EC4")
local NIGHT = C("3B2A6B")

local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local Build = {}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(p: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end

local function stroke(p: Instance, t: number)
	new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

-- two overlapping photocards, the pack icon
local function packIcon(parent: Instance, order: number)
	local holder = new("Frame", { Name = "Icon", LayoutOrder = order, Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1 }, parent)
	for i, spec in { { 1, 3, LILAC }, { 7, 1, PINK } } do
		local f = new("Frame", { Name = "Card" .. i, Position = UDim2.fromOffset(spec[1], spec[2]), Size = UDim2.fromOffset(9, 13), BackgroundColor3 = spec[3] }, holder)
		corner(f, 2)
		stroke(f, 1.6)
	end
	return holder
end

function Build.Build(frame: Instance)
	for _, n in { "Packs", "PacksShadow", "SoloPool", "SoloPoolShadow" } do
		local old = frame:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local stake = frame.Stake
	local y = stake.Position.Y.Offset + stake.Size.Y.Offset -- bottom edge of the stake card

	-- [[ Packs chip ]]
	local chip = new("Frame", {
		Name = "Packs",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, y + 6),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = MINT,
		Visible = false,
		ZIndex = 4,
	}, frame)
	corner(chip, 10)
	stroke(chip, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, chip)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, chip)
	local icon = packIcon(chip, 1)
	for _, d in icon:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 4
		end
	end
	local slash = new("Frame", { Name = "Off", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1.3, 0), Rotation = 45, BackgroundColor3 = INK, BorderSizePixel = 0, Visible = false, ZIndex = 5 }, icon)
	slash.Name = "Off"
	new("TextLabel", {
		Name = "Label",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1,
		FontFace = BODY,
		TextSize = 14,
		TextColor3 = INK,
		Text = "Packs ON · My Pack + HYBE Pack",
		ZIndex = 4,
	}, chip)

	-- [[ Solo pool picker ]]
	local w, h = 470, 38
	local shadow = new("Frame", { Name = "SoloPoolShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(643, y + 11), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, Visible = false, ZIndex = 3 }, frame)
	corner(shadow, 12)
	local pool = new("Frame", { Name = "SoloPool", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(640, y + 8), Size = UDim2.fromOffset(w, h), BackgroundColor3 = NIGHT, Visible = false, ZIndex = 4 }, frame)
	corner(pool, 12)
	stroke(pool, 3)
	new("TextLabel", {
		Name = "Heading",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromOffset(100, h),
		BackgroundTransparency = 1,
		FontFace = HEAD,
		TextSize = 13,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "SONG POOL",
		ZIndex = 4,
	}, pool)
	local bw = (w - 112 - 8 - 8) / 2
	for i, spec in { { "Mix", "Mix with all songs" }, { "Pack", "Only my pack" } } do
		local b = new("TextButton", {
			Name = spec[1],
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(112 + (i - 1) * (bw + 8) + bw / 2, h / 2),
			Size = UDim2.fromOffset(bw, 28),
			BackgroundColor3 = if i == 1 then LILAC else WHITE,
			BackgroundTransparency = if i == 1 then 0 else 0.65,
			FontFace = BODY,
			TextSize = 13,
			TextColor3 = INK,
			Text = spec[2],
			AutoButtonColor = false,
			ZIndex = 4,
		}, pool)
		corner(b, 9)
		stroke(b, 2)
	end
	return chip, pool
end

return Build
