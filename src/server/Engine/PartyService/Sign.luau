--| PartyService · Sign
-- What a Party Stage shows the street: the neon strip under its lip (lilac while people are
-- in the lobby, pulsing pink in a match, soft white when empty) and a small sign above it
-- ("PARTY STAGE 1" + "Step on to host" / "Waiting for players · 3 / 6" / "Friends only" /
-- "Starting…" / "In match · round 3 / 7"), so players can pick a stage from a distance.
-- The sign is switched off for now (SHOW_SIGN); only the neon strip shows.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartyConstants = require(ReplicatedStorage.Constants.PartyConstants)

local Sign = {}

local C = Color3.fromHex
local INK = C("1E1B2E")
local PULSE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local SHOW_SIGN = false

local pulses: { [any]: Tween } = {}

local function board(party)
	local anchor = party.Model:FindFirstChild("StatusAnchor") :: BasePart?
	if not anchor then
		return nil
	end
	local gui = anchor:FindFirstChild("PartySign") :: BillboardGui?
	if gui then
		return gui
	end
	gui = Instance.new("BillboardGui")
	gui.Name = "PartySign"
	gui.Size = UDim2.fromOffset(230, 62)
	gui.StudsOffset = Vector3.new(0, -4, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = C("FFFFFF")
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.Parent = card
	local name = Instance.new("TextLabel")
	name.Name = "StageName"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(0, 8)
	name.Size = UDim2.new(1, 0, 0, 22)
	name.FontFace = HEAD
	name.TextSize = 17
	name.TextColor3 = INK
	name.Parent = card
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(0, 32)
	status.Size = UDim2.new(1, 0, 0, 20)
	status.FontFace = BODY
	status.TextSize = 14
	status.TextColor3 = C("5C566B")
	status.Parent = card
	gui.Parent = anchor
	return gui
end

-- line = the status text; state = "Empty" | "Waiting" | "Live"
function Sign.Refresh(party, line: string, state: string)
	local gui = if SHOW_SIGN then board(party) else nil
	if gui then
		gui.Card.StageName.Text = string.upper(party.Title)
		gui.Card.Status.Text = line
		gui.Card.BackgroundColor3 = if state == "Live" then C("FF9EC4") elseif state == "Waiting" then C("DCD3FF") else C("FFFFFF")
	end
	local visual = party.Model:FindFirstChild("Visual")
	local strip = visual and visual:FindFirstChild("Stage_Neon") :: BasePart?
	if not strip or party.NeonState == state then
		return
	end
	party.NeonState = state
	local old = pulses[party]
	if old then
		old:Cancel()
		pulses[party] = nil
	end
	local colour = C(PartyConstants.STATUS_COLOURS[state] or PartyConstants.STATUS_COLOURS.Empty)
	if state == "Live" then
		strip.Color = colour
		local pulse = TweenService:Create(strip, PULSE, { Color = colour:Lerp(INK, 0.3) })
		pulses[party] = pulse
		pulse:Play()
	else
		TweenService:Create(strip, FADE, { Color = colour }):Play()
	end
end

return Sign
