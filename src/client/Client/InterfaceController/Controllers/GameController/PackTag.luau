--| PackTag
-- The tag under the round scoreboard: a themed solo game's theme ("GEN 4"). It can still show
-- who owns the song (lilac "♪ YOUR SONG", pink "♪ WrathValor's SONG"), but the game passes no
-- owners any more: ownership shows on the round reveal instead (./RevealOwner). Build(gameFrame) runs once in Studio; Set() fills it.

local Players = game:GetService("Players")

local C = Color3.fromHex
local INK = C("1E1B2E")
local LILAC = C("B9A6FF")
local PINK = C("FF9EC4")
local YELLOW = C("FFE07A")
local GOLD = C("F2C94C")
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local PackTag = {}

function PackTag.Build(gameFrame: Instance)
	local old = gameFrame:FindFirstChild("PackTag")
	if old then
		old:Destroy()
	end
	local panel = gameFrame.Scoreboard.Panel
	local tag = Instance.new("TextLabel")
	tag.Name = "PackTag"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.fromOffset(panel.Position.X.Offset + panel.Size.X.Offset / 2, panel.Position.Y.Offset + panel.Size.Y.Offset + 12)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.Size = UDim2.fromOffset(0, 24)
	tag.BackgroundColor3 = LILAC
	tag.FontFace = BODY
	tag.TextSize = 13
	tag.TextColor3 = INK
	tag.Text = "♪ YOUR SONG · Normal"
	tag.Visible = false
	tag.ZIndex = 3
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = tag
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tag
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = tag
	tag.Parent = gameFrame
	return tag
end

-- info = packet.OwnedTag ({ Owners = { { UserId, Name, Tier } }, XP = bonus? }) or nil
-- theme = packet.Theme ("Gen 4") on a themed solo game: shown in front of the song text,
-- or on its own in yellow on rounds nobody owns
function PackTag.Set(gameFrame: Instance, info, theme: string?)
	local tag = gameFrame:FindFirstChild("PackTag")
	if not tag then
		return
	end
	tag.Visible = info ~= nil or theme ~= nil
	if not info then
		if theme then
			tag.BackgroundColor3 = YELLOW
			tag.Text = string.upper(theme)
		end
		return
	end
	local mine, other
	for _, owner in info.Owners or {} do
		if owner.UserId == Players.LocalPlayer.UserId then
			mine = owner
		else
			other = owner
		end
	end
	local text
	if mine and other then
		text = "♪ YOU BOTH OWN THIS"
	elseif mine then
		text = `♪ YOUR SONG · {mine.Tier or "Normal"}`
	else
		text = `♪ {if other then other.Name else "Rival"}'s SONG`
	end
	if mine and info.XP then
		text ..= ` · +{info.XP} XP if you get it`
	end
	local tier = mine and mine.Tier
	tag.BackgroundColor3 = if tier == "Gold" or tier == "Rainbow" then GOLD elseif mine then LILAC else PINK
	tag.Text = if theme then `{string.upper(theme)} · {text}` else text
end

return PackTag
