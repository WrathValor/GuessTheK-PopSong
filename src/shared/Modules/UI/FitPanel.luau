--| FitPanel
-- Grows a 1000x640 screen panel on small screens (phones). The 1280x720 Frames canvas shrinks
-- a lot there, so the panel (and its shadow) is scaled up by as much as MAX while it still fits
-- on screen and clears the Roblox topbar buttons. Reads the canvas's real scale and centre
-- (Interface's AutoScale drops it below the topbar on phones). Desktop-sized screens stay at 1.
-- Used by the Shop, Song Roll and UGC screens.
--   FitPanel.Watch(frame, janitor)   -- fit now, and again whenever AutoScale moves the canvas

local GuiService = game:GetService("GuiService")

local MAX = 1.24
local MARGIN = 6
local GAP = 8
local TOPBAR_MAX = 58 -- same clamp as Interface's AutoScale (some phones over-report Max.Y)

local FitPanel = {}

function FitPanel.Fit(frame: Frame)
	local canvas = frame.Parent :: GuiObject
	local gui = frame:FindFirstAncestorOfClass("ScreenGui")
	local canvasScale = canvas and canvas:FindFirstChildOfClass("UIScale")
	if not (gui and canvasScale) then
		return
	end
	local size = gui.AbsoluteSize
	local s0 = canvasScale.Scale
	local cx = size.X / 2
	local cy = canvas.Position.Y.Scale * size.Y + canvas.Position.Y.Offset
	local inset = GuiService.TopbarInset
	local barBottom = inset.Max.Y - gui.AbsolutePosition.Y
	if barBottom <= 0 or barBottom > TOPBAR_MAX then
		barBottom = TOPBAR_MAX
	end
	local barRight = inset.Min.X - gui.AbsolutePosition.X
	local k = 1
	if s0 < 0.8 then
		k = MAX
		while k > 1 do
			local s = s0 * k
			local left, top, bottom = cx - 500 * s, cy - 320 * s, cy + 320 * s
			local fits = left >= MARGIN and top >= MARGIN and bottom <= size.Y - MARGIN
			local clearOfTopbar = top >= barBottom + GAP or left >= barRight + GAP
			if fits and clearOfTopbar then
				break
			end
			k -= 0.02
		end
		k = math.max(k, 1)
	end
	for _, name in { "Panel", "PanelShadow" } do
		local part = frame:FindFirstChild(name) :: GuiObject?
		if part then
			-- scale around the centre: re-anchor once, keeping the same resting place
			if part.AnchorPoint ~= Vector2.new(0.5, 0.5) then
				local a, sz, p = part.AnchorPoint, part.Size, part.Position
				part.AnchorPoint = Vector2.new(0.5, 0.5)
				part.Position = p
					+ UDim2.new(sz.X.Scale * (0.5 - a.X), sz.X.Offset * (0.5 - a.X), sz.Y.Scale * (0.5 - a.Y), sz.Y.Offset * (0.5 - a.Y))
			end
			local fit = part:FindFirstChild("Fit") :: UIScale? or Instance.new("UIScale")
			fit.Name = "Fit"
			fit.Scale = k
			fit.Parent = part
		end
	end
end

function FitPanel.Watch(frame: Frame, janitor)
	FitPanel.Fit(frame)
	local canvas = frame.Parent :: GuiObject
	local canvasScale = canvas:FindFirstChildOfClass("UIScale")
	if canvasScale then
		janitor:Add(canvasScale:GetPropertyChangedSignal("Scale"):Connect(function()
			FitPanel.Fit(frame)
		end))
	end
	janitor:Add(canvas:GetPropertyChangedSignal("Position"):Connect(function()
		FitPanel.Fit(frame)
	end))
end

return FitPanel
