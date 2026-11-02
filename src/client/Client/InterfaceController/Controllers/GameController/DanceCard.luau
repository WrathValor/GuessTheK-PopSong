--| DanceCard
-- "Get this dance" on the round reveal: when the answer has a dance in the group's UGC
-- (Constants/UGCCatalog.SONGS), a small card next to the answer shows it on your avatar with
-- its Robux price. Hidden when there's no dance or you already own it.
--   DanceCard.Build(reveal)        – once, in Studio (Reveal.Dance); safe to run twice
--   DanceCard.Show(reveal, songId) – every reveal

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGC = require(ReplicatedStorage.Modules.UGC)
local UGCCatalog = require(ReplicatedStorage.Constants.UGCCatalog)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local MUTED = C("5C566B")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local ROBUX = "rbxassetid://83637405007021" -- the shop's Robux icon (UGCCatalog.ROBUX_ICON wins)

local DanceCard = {}

local function new(className: string, props, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(p, r)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end
local function stroke(p, t)
	new("UIStroke", { Color = INK, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

function DanceCard.Build(reveal: Instance)
	if reveal:FindFirstChild("Dance") then
		return reveal.Dance
	end
	local x, y, w, h = 966, 236, 214, 286
	local shadow = new("Frame", { Name = "DanceShadow", Position = UDim2.fromOffset(x + 6, y + 6), Size = UDim2.fromOffset(w, h), BackgroundColor3 = INK, Rotation = 2, Visible = false }, reveal)
	corner(shadow, 16)
	local card = new("Frame", { Name = "Dance", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, Rotation = 2, Visible = false }, reveal)
	corner(card, 16)
	stroke(card, 3)
	local tag = new("TextLabel", {
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = YELLOW,
		FontFace = HEAD,
		TextSize = 12,
		TextColor3 = INK,
		Text = "GET THIS DANCE",
		Rotation = -3,
		ZIndex = 8,
	}, card)
	corner(tag, 9)
	stroke(tag, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, tag)
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 160), BackgroundColor3 = C("4A3F78"), ClipsDescendants = true }, card)
	corner(art, 10)
	stroke(art, 2)
	new("TextLabel", { Name = "Title", Position = UDim2.fromOffset(12, 174), Size = UDim2.new(1, -24, 0, 20), BackgroundTransparency = 1, FontFace = BODY, TextSize = 15, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "Song · dance emote" }, card)
	new("TextLabel", { Name = "Sub", Position = UDim2.fromOffset(12, 194), Size = UDim2.new(1, -24, 0, 16), BackgroundTransparency = 1, FontFace = BODY_BOLD, TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, Text = "Item - by " .. UGCCatalog.CREATOR }, card)
	local buy = new("TextButton", { Name = "Buy", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -32), Size = UDim2.new(1, -16, 0, 42), BackgroundColor3 = MINT, Text = "", AutoButtonColor = false }, card)
	corner(buy, 10)
	stroke(buy, 3)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, buy)
	new("ImageLabel", { Name = "Icon", LayoutOrder = 1, Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = ROBUX, ScaleType = Enum.ScaleType.Fit }, buy)
	new("TextLabel", { Name = "Label", LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundTransparency = 1, FontFace = HEAD, TextSize = 16, TextColor3 = INK, Text = "40" }, buy)
	return card
end

function DanceCard.Show(reveal: Instance, songId: string?)
	local card = reveal:FindFirstChild("Dance")
	if not card then
		return
	end
	local item = UGC.ForSong(songId)
	local show = item ~= nil and item.Kind == "Dance" and UGC.Owned(item.Id) ~= true
	card.Visible = show
	local shadow = reveal:FindFirstChild("DanceShadow")
	if shadow then
		shadow.Visible = show
	end
	card:SetAttribute("AssetId", if show then item.Id else nil)
	if not show then
		return
	end
	card.Title.Text = item.Name
	card.Sub.Text = `{item.Name} - by {UGCCatalog.CREATOR}`
	card.Buy.Label.Text = tostring(item.Price)
	if UGCCatalog.ROBUX_ICON ~= "" then
		card.Buy.Icon.Image = UGCCatalog.ROBUX_ICON
		card.Buy.Icon.ImageColor3 = INK
	end
	CosmeticView.Show(card.Art, "Dance", tostring(item.Id))
end

-- the Buy button (connect once)
function DanceCard.Connect(reveal: Instance, janitor)
	local card = reveal:FindFirstChild("Dance")
	if not card then
		return
	end
	janitor:Add(card.Buy.Activated:Connect(function()
		local id = card:GetAttribute("AssetId")
		if id then
			UGC.Buy(id, "Reveal")
		end
	end))
end

return DanceCard
