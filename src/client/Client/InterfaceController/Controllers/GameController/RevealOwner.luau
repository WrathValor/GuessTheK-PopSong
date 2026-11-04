--| RevealOwner
-- The round reveal's answer card when somebody in the game owns the song (replaces the old
-- "♪ YOUR SONG" tag): the card takes that card's tier finish (Gold shines, Rainbow scrolls,
-- Modules/UI/TierShine; Normal stays white) and an "Owned by WrathValor" line sits at the
-- bottom ("Owned by Mujtabah & WrathValor" when you both own it). The tier shown is yours if
-- you own it, else the owner's. Build(reveal) runs once in Studio (adds the card's "Tier"
-- UIGradient and the "Owned" label); Set() fills it each reveal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local MUTED = C("5C566B")
local INK = C("1E1B2E")

local RevealOwner = {}

function RevealOwner.Build(reveal: Instance)
	local card = reveal.Answer
	if card:FindFirstChild("Owned") then
		return
	end
	local grad = Instance.new("UIGradient")
	grad.Name = "Tier"
	grad.Rotation = 35
	grad.Enabled = false
	grad.Parent = card
	local owned = Instance.new("TextLabel")
	owned.Name = "Owned"
	owned.Position = UDim2.fromOffset(20, 164)
	owned.Size = UDim2.new(1, -40, 0, 20)
	owned.BackgroundTransparency = 1
	owned.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	owned.TextSize = 15
	owned.TextColor3 = MUTED
	owned.TextXAlignment = Enum.TextXAlignment.Center
	owned.TextTruncate = Enum.TextTruncate.AtEnd
	owned.Text = "Owned by Player"
	owned.Visible = false
	owned.Parent = card
end

-- info = the round's OwnedTag ({ Owners = { { UserId, Name, Tier } } }) or nil
function RevealOwner.Set(reveal: Instance, info)
	local card = reveal.Answer
	local grad = card:FindFirstChild("Tier") :: UIGradient?
	local owned = card:FindFirstChild("Owned") :: TextLabel?
	local owners = info and info.Owners or {}
	if #owners == 0 then
		TierShine.Apply(card, grad, nil, WHITE)
		if owned then
			owned.Visible = false
		end
		return
	end
	local mine, names = nil, {}
	for _, owner in owners do
		if owner.UserId == Players.LocalPlayer.UserId then
			mine = owner
			table.insert(names, 1, owner.Name or Players.LocalPlayer.DisplayName)
		else
			table.insert(names, owner.Name or "Rival")
		end
	end
	local tier = (mine or owners[1]).Tier or "Normal"
	TierShine.Apply(card, grad, tier, WHITE)
	if owned then
		owned.Visible = true
		owned.Text = `Owned by {table.concat(names, " & ")}`
		owned.TextColor3 = if tier == "Normal" then MUTED else INK
	end
end

return RevealOwner
