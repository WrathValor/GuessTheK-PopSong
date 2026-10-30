--| StageStatus
-- The neon strip under each duel stage's lip (Visual.Stage_Neon) shows whether it's free,
-- so players can read the street at a glance:
--   • soft white        – empty: anyone can step on
--   • yellow            – one player waiting for a rival (join = instant duel)
--   • pink, pulsing     – a duel (or solo game) is on
-- DuelService calls Refresh(stage) whenever a stage's players or State change.

local TweenService = game:GetService("TweenService")

local StageStatus = {}

local C = Color3.fromHex
local EMPTY = C("F4F0FA")
local WAITING = C("FFE07A")
local LIVE = C("FF9EC4")
local LIVE_DIM = C("C9638E")
local PULSE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local pulses: { [any]: Tween } = {}

function StageStatus.Refresh(stage)
	local visual = stage.Model:FindFirstChild("Visual")
	local strip = visual and visual:FindFirstChild("Stage_Neon") :: BasePart?
	if not strip then
		return
	end
	local count = (if stage.Players.A then 1 else 0) + (if stage.Players.B then 1 else 0)
	local status = if stage.State == "InProgress" then "Live" elseif count > 0 then "Waiting" else "Empty"
	if stage.Status == status then
		return
	end
	stage.Status = status
	stage.Model:SetAttribute("Status", status)

	local old = pulses[stage]
	if old then
		old:Cancel()
		pulses[stage] = nil
	end
	if status == "Live" then
		strip.Color = LIVE
		local pulse = TweenService:Create(strip, PULSE, { Color = LIVE_DIM })
		pulses[stage] = pulse
		pulse:Play()
	else
		TweenService:Create(strip, FADE, { Color = if status == "Waiting" then WAITING else EMPTY }):Play()
	end
end

return StageStatus
