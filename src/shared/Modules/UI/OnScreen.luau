--| OnScreen
-- Is a piece of UI actually being drawn where the player can see it? Shared by the looping
-- effects (CosmeticView's auto turn, TierShine, SeasonFx) so they skip work nobody sees.
--   OnScreen.Gui(gui, clip?)  – every GuiObject from `gui` up is Visible, and its LayerCollector
--                               is showing (below). clip = also false when a ClipsDescendants /
--                               ScrollingFrame ancestor has scrolled or clipped it out of view
--   OnScreen.Collector(lc)    – a ScreenGui: Enabled. A SurfaceGui / BillboardGui: Enabled, and
--                               the part it's drawn on is within range and inside the camera's view
-- Range for world UI: the gui's MaxDistance, capped at RANGE (a "AnimateRange" number attribute on
-- the SurfaceGui / BillboardGui overrides the cap, e.g. a huge screen seen from across the map).
-- The view test is a cone round the camera's look direction, widened by the part's size, so a
-- big screen counts as soon as any of it could be in frame.

local Workspace = game:GetService("Workspace")

local OnScreen = {}

local RANGE = { SurfaceGui = 250, BillboardGui = 120 } -- studs; past this, effects hold still

-- where world UI is drawn: its Adornee, else the part / attachment / model it sits in
local function anchorOf(lc: LayerCollector): (Vector3?, number)
	local target = (lc :: any).Adornee or lc.Parent
	if target and target:IsA("BasePart") then
		return target.Position, target.Size.Magnitude / 2
	elseif target and target:IsA("Attachment") then
		return target.WorldPosition, 1
	elseif target and target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		return cf.Position, size.Magnitude / 2
	end
	return nil, 0 -- not adorned to anything: Roblox doesn't draw it
end

local function worldVisible(lc: LayerCollector): boolean
	local cam = Workspace.CurrentCamera
	if not cam then
		return true
	end
	local pos, radius = anchorOf(lc)
	if not pos then
		return false
	end
	local range = lc:GetAttribute("AnimateRange") or RANGE[lc.ClassName] or 200
	local max = (lc :: any).MaxDistance
	if type(max) == "number" and max > 0 and max < range then
		range = max
	end
	local camPos = cam.CFrame.Position
	local toPart = pos - camPos
	local dist = toPart.Magnitude
	if dist <= radius then
		return true -- the camera is inside / right up against it
	end
	if dist - radius > range then
		return false
	end
	-- inside the view cone (the screen's diagonal half-angle), widened by the part's own size
	local viewport = cam.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local halfV = math.tan(math.rad(cam.FieldOfView) / 2)
	local halfDiag = math.atan(halfV * math.sqrt(1 + aspect * aspect))
	local spread = math.asin(math.min(1, radius / dist))
	local cos = cam.CFrame.LookVector:Dot(toPart / dist)
	return math.acos(math.clamp(cos, -1, 1)) <= halfDiag + spread
end

function OnScreen.Collector(lc: LayerCollector): boolean
	if not lc.Enabled then
		return false
	end
	if lc:IsA("SurfaceGui") or lc:IsA("BillboardGui") then
		return worldVisible(lc)
	end
	return true
end

function OnScreen.Gui(gui: Instance, clip: boolean?): boolean
	local pos, size
	if clip and gui:IsA("GuiObject") then
		pos, size = gui.AbsolutePosition, gui.AbsoluteSize
	end
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
			if pos and node ~= gui and (node.ClipsDescendants or node:IsA("ScrollingFrame")) then
				local p, s = node.AbsolutePosition, node.AbsoluteSize
				if pos.X > p.X + s.X or pos.Y > p.Y + s.Y or pos.X + size.X < p.X or pos.Y + size.Y < p.Y then
					return false
				end
			end
		elseif node:IsA("LayerCollector") then
			return OnScreen.Collector(node)
		end
		node = node.Parent
	end
	return false
end

return OnScreen
