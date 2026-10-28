--| Juice
-- Small reusable UI animations so screens feel alive:
--   Juice.Stagger(list)        cards pop in one after another (scale from 0.6 with a bounce)
--   Juice.Pop(gui, amount)     a quick punch (grows then springs back) – for "something changed"
--   Juice.Shake(gui)           a short side-to-side wobble – for "no" (not enough coins…)
--   Juice.CountUp(label, a, b, format)   rolls a number from a to b
--   Juice.SlideIn(gui, fromY)  toasts / banners rise into place with a pop
-- Each animated object gets its own UIScale named "JuiceScale" (separate from ButtonScale's),
-- and objects that aren't laid out by a UIListLayout are re-anchored to their centre once
-- (without moving) so they grow from the middle.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Juice = {}

local STAGGER_IN = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_UP = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_DOWN = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function inLayout(gui: GuiObject): boolean
	local parent = gui.Parent
	return parent ~= nil and (parent:FindFirstChildOfClass("UIListLayout") ~= nil or parent:FindFirstChildOfClass("UIGridLayout") ~= nil)
end

-- centre the anchor once so scaling happens around the middle
local function centre(gui: GuiObject)
	-- AutomaticSize objects report Size 0 on the grown axis, so re-anchoring them would shift
	-- them by half their real width (a right-anchored chip ends up half outside its frame).
	-- Those keep their anchor and pop from it instead.
	if gui:GetAttribute("JuiceCentred") or inLayout(gui) or gui.AutomaticSize ~= Enum.AutomaticSize.None then
		return
	end
	gui:SetAttribute("JuiceCentred", true)
	local a, pos, size = gui.AnchorPoint, gui.Position, gui.Size
	if a == Vector2.new(0.5, 0.5) then
		return
	end
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = pos + UDim2.new(size.X.Scale * (0.5 - a.X), size.X.Offset * (0.5 - a.X), size.Y.Scale * (0.5 - a.Y), size.Y.Offset * (0.5 - a.Y))
end

local function scaleOf(gui: GuiObject): UIScale
	local s = gui:FindFirstChild("JuiceScale") :: UIScale?
	if not s then
		-- a button already scaled by ButtonScale keeps that one; never stack two UIScales
		local existing = gui:FindFirstChildOfClass("UIScale")
		if existing then
			return existing
		end
		local new = Instance.new("UIScale")
		new.Name = "JuiceScale"
		new.Parent = gui
		s = new
	end
	return s :: UIScale
end

-- Pop a list of GuiObjects in one after another (skips hidden ones).
function Juice.Stagger(list: { GuiObject }, gap: number?, from: number?)
	local step = gap or 0.035
	local n = 0
	for _, gui in list do
		if gui and gui.Visible then
			centre(gui)
			local s = scaleOf(gui)
			s.Scale = from or 0.6
			local delay = n * step
			n += 1
			task.delay(delay, function()
				TweenService:Create(s, STAGGER_IN, { Scale = 1 }):Play()
			end)
		end
	end
end

-- Grow by `amount` (default 12%) then spring back.
function Juice.Pop(gui: GuiObject?, amount: number?)
	if not gui then
		return
	end
	centre(gui)
	local s = scaleOf(gui)
	local up = TweenService:Create(s, POP_UP, { Scale = 1 + (amount or 0.12) })
	up.Completed:Once(function()
		TweenService:Create(s, POP_DOWN, { Scale = 1 }):Play()
	end)
	up:Play()
end

-- Quick wobble, for a refusal.
function Juice.Shake(gui: GuiObject?)
	if not gui then
		return
	end
	local token = (gui:GetAttribute("JuiceShake") or 0) + 1
	gui:SetAttribute("JuiceShake", token)
	local base = gui:GetAttribute("JuiceShakeRot")
	if base == nil then
		base = gui.Rotation
		gui:SetAttribute("JuiceShakeRot", base)
	end
	task.spawn(function()
		for i, r in { 6, -5, 4, -3, 2, 0 } do
			if gui:GetAttribute("JuiceShake") ~= token then
				return
			end
			gui.Rotation = base + r
			task.wait(0.035)
		end
		gui.Rotation = base
	end)
end

-- Roll `label` from a to b over `duration` seconds. `format(n)` turns the number into text.
function Juice.CountUp(label: TextLabel, from: number, to: number, format: ((number) -> string)?, duration: number?)
	local token = (label:GetAttribute("JuiceCount") or 0) + 1
	label:SetAttribute("JuiceCount", token)
	local fmt = format or function(n)
		return tostring(math.floor(n))
	end
	local d = duration or math.clamp(math.abs(to - from) / 800, 0.25, 0.8)
	local t0 = os.clock()
	task.spawn(function()
		while label:GetAttribute("JuiceCount") == token do
			local p = math.min((os.clock() - t0) / d, 1)
			local eased = 1 - (1 - p) ^ 3
			label.Text = fmt(from + (to - from) * eased)
			if p >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- Rise `fromY` px into place with a pop (toasts, banners).
function Juice.SlideIn(gui: GuiObject, fromY: number?)
	centre(gui)
	local home = gui:GetAttribute("JuiceHome")
	if home == nil then
		home = gui.Position
		gui:SetAttribute("JuiceHome", home)
	end
	gui.Position = home + UDim2.fromOffset(0, fromY or 20)
	TweenService:Create(gui, SLIDE, { Position = home }):Play()
	Juice.Pop(gui, 0.08)
end

return Juice
