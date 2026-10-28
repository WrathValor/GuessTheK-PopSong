--| CenterButtons
-- Gives every button under `root` a centred AnchorPoint (0.5, 0.5) without moving it, so the
-- ButtonScale hover/press tween grows from the middle instead of pushing out of its frame.
-- Buttons laid out by a UIListLayout/UIGridLayout are left alone (the layout places them).
-- Auto-sized buttons are frozen to their current size first, since a centred child can't
-- drive its parent's AutomaticSize. Safe to run more than once.

local CenterButtons = {}

local function inLayout(gui: GuiObject): boolean
	local parent = gui.Parent
	return parent ~= nil and (parent:FindFirstChildOfClass("UIListLayout") ~= nil or parent:FindFirstChildOfClass("UIGridLayout") ~= nil)
end

-- design-pixel size of `gui` (AbsoluteSize divided by any UIScale above it)
local function designSize(gui: GuiObject): Vector2
	local scale = 1
	local node = gui.Parent
	while node and not node:IsA("LayerCollector") do
		local s = node:FindFirstChildOfClass("UIScale")
		if s then
			scale *= s.Scale
		end
		node = node.Parent
	end
	return gui.AbsoluteSize / scale
end

function CenterButtons.Apply(root: Instance): number
	local changed = 0
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.AnchorPoint ~= Vector2.new(0.5, 0.5) and not inLayout(d) then
			if d.AutomaticSize ~= Enum.AutomaticSize.None then
				local size = designSize(d)
				d.AutomaticSize = Enum.AutomaticSize.None
				d.Size = UDim2.fromOffset(math.ceil(size.X), math.ceil(size.Y))
				local holder = d.Parent
				if holder and holder:IsA("GuiObject") and holder.AutomaticSize ~= Enum.AutomaticSize.None then
					holder.AutomaticSize = Enum.AutomaticSize.None
					holder.Size = UDim2.fromOffset(math.ceil(size.X) + 3, holder.Size.Y.Offset)
				end
			end
			local a, pos, size = d.AnchorPoint, d.Position, d.Size
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Position = pos
				+ UDim2.new(size.X.Scale * (0.5 - a.X), size.X.Offset * (0.5 - a.X), size.Y.Scale * (0.5 - a.Y), size.Y.Offset * (0.5 - a.Y))
			changed += 1
		end
	end
	return changed
end

return CenterButtons
