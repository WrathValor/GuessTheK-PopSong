--| FitText
-- Keeps text inside its box on every screen size. The 1280x720 canvases are scaled down a
-- lot on phones, and text is rounded to whole device pixels after that, so text that fits
-- the design on PC can run wider than its box on mobile ("coi...", chips spilling out of a card).
--   * Every fixed-size label/button becomes TextScaled, capped by a "FitCap"
--     UITextSizeConstraint at its design TextSize. It never grows past the design, and it
--     shrinks only when the text wouldn't fit. The cap is in screen pixels (UIScale doesn't
--     apply to it), so it's design size × the canvas UIScale, kept in step when that changes.
--     Code that sets TextSize later still works: the cap follows it.
--   * Auto-sized labels can't be TextScaled (their box comes from their text), so rows of
--     auto-sized chips (a horizontal UIListLayout that doesn't wrap) shrink their chips
--     together, through a "FitRow" UIScale on each chip, until the row fits its frame.
-- FitText.Watch(root) applies both to everything under root, including UI built later.
-- A label with the FitTextSkip attribute is left alone.

local FitText = {}

local MIN_RATIO = 0.5 -- scaled text never shrinks below half its design size
local MIN_ROW_SCALE = 0.6 -- chip rows never shrink below 60%
local ROW_SLACK = 4 -- px of free room before a shrunk row grows back (stops flicker)

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- the design-canvas UIScale above `gui` (Frames.Scale / HUD.Scale), if any
local function canvasScaleOf(gui: Instance): UIScale?
	local node = gui
	while node.Parent and not node.Parent:IsA("LayerCollector") do
		node = node.Parent
	end
	return node:FindFirstChildOfClass("UIScale")
end

-- [[ Labels → TextScaled with a design-size cap ]] --

local function isFitLabel(gui: Instance): boolean
	return (gui:IsA("TextLabel") or gui:IsA("TextButton"))
		and not gui:GetAttribute("FitTextSkip") -- sized by its own controller (e.g. the Index footer)
		and gui.AutomaticSize == Enum.AutomaticSize.None
		and not (gui.TextScaled and gui:FindFirstChildOfClass("UITextSizeConstraint")) -- already set up by hand
end

function FitText.Label(label: TextLabel | TextButton)
	if watched[label] then
		return
	end
	watched[label] = true
	local canvas = canvasScaleOf(label)
	local cap = label:FindFirstChild("FitCap") :: UITextSizeConstraint?
	if not cap then
		cap = Instance.new("UITextSizeConstraint")
		cap.Name = "FitCap"
		cap.Parent = label
	end
	local base = label:GetAttribute("FitBaseSize") or label.TextSize
	label:SetAttribute("FitBaseSize", base)

	local function update()
		local s = if canvas then canvas.Scale else 1
		local max = math.clamp(math.floor(base * s + 0.5), 1, 100)
		cap.MaxTextSize = max
		cap.MinTextSize = math.clamp(math.floor(base * MIN_RATIO * s), 1, max)
	end
	update()
	label.TextScaled = true
	label:GetPropertyChangedSignal("TextSize"):Connect(function()
		-- code changed the design size (TextSize no longer drives the text, the cap does)
		base = label.TextSize
		label:SetAttribute("FitBaseSize", base)
		update()
	end)
	if canvas then
		canvas:GetPropertyChangedSignal("Scale"):Connect(update)
	end
end

-- [[ Chip rows ]] --

local function chipScale(chip: GuiObject): UIScale?
	local s = chip:FindFirstChild("FitRow")
	if s then
		return s :: UIScale
	end
	if chip:FindFirstChildOfClass("UIScale") then
		return nil -- already scaled by something else (ButtonScale, Juice): leave it alone
	end
	local new = Instance.new("UIScale")
	new.Name = "FitRow"
	new.Parent = chip
	return new
end

local function fitRow(row: GuiObject, layout: UIListLayout)
	local avail = row.AbsoluteSize.X
	local content = layout.AbsoluteContentSize.X
	if avail <= 0 or content <= 0 then
		return
	end
	local k = row:GetAttribute("FitRowScale") or 1
	local target = k
	if content > avail + 0.5 then
		target = k * avail / content
	elseif k < 1 and content < avail - ROW_SLACK then
		target = math.min(1, k * (avail - ROW_SLACK) / content)
	end
	target = math.clamp(target, MIN_ROW_SCALE, 1)
	if math.abs(target - k) < 0.005 then
		return
	end
	row:SetAttribute("FitRowScale", target)
	for _, chip in row:GetChildren() do
		if chip:IsA("GuiObject") then
			local s = chipScale(chip)
			if s then
				s.Scale = target
			end
		end
	end
end

local function isChipRow(gui: Instance): boolean
	if not gui:IsA("GuiObject") or gui:IsA("ScrollingFrame") or gui.AutomaticSize ~= Enum.AutomaticSize.None then
		return false
	end
	local layout = gui:FindFirstChildOfClass("UIListLayout")
	if not (layout and layout.FillDirection == Enum.FillDirection.Horizontal and not layout.Wraps) then
		return false
	end
	-- only rows of auto-sized text chips; fixed rows (tabs, card grids) are laid out by design
	local chips = 0
	for _, c in gui:GetChildren() do
		if c:IsA("GuiObject") then
			if not (c:IsA("TextLabel") and c.AutomaticSize ~= Enum.AutomaticSize.None) then
				return false
			end
			chips += 1
		end
	end
	return chips >= 2
end

function FitText.Row(row: GuiObject)
	if watched[row] then
		return
	end
	local layout = row:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end
	watched[row] = true
	local function refit()
		if row.Parent then
			fitRow(row, layout)
		end
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refit)
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
end

-- [[ Whole trees ]] --

local function consider(gui: Instance)
	if isFitLabel(gui) then
		FitText.Label(gui :: any)
	elseif isChipRow(gui) then
		FitText.Row(gui :: any)
	end
end

function FitText.Watch(root: Instance)
	local count = 0
	for _, d in root:GetDescendants() do
		local ok, err = pcall(consider, d)
		if not ok then
			warn("[FitText]", d:GetFullName(), err)
		elseif watched[d] then
			count += 1
		end
	end
	print(`[FitText] fitting {count} labels and rows under {root.Name}`) -- check on a phone with /console
	root.DescendantAdded:Connect(function(d)
		-- wait a frame so the builder has finished setting the new UI's properties
		task.defer(function()
			if d.Parent then
				consider(d)
				-- a chip added to an existing row makes that row a candidate
				if d.Parent:IsA("GuiObject") then
					consider(d.Parent)
				end
			end
		end)
	end)
end

return FitText
