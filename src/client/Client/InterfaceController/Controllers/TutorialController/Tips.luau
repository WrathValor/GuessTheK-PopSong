--| Tutorial tips
-- The coach marks during the practice round (design boards "Tutorial 2/3"): the screen dims
-- except for one part of the round screen (outlined in dashed yellow), and a cream speech
-- bubble explains it. "Got it" moves on; "Skip tutorial" hides the tips for good. Drawn in
-- Interface.Frames (so it scales with the 1280×720 canvas) above everything else; the lit
-- part stays clickable. With a controller, A is "Got it" and Y "Skip tutorial" while a tip is up
-- (bound above the round's answer buttons, Modules/UI/PadBinds), and a step's PadBody is shown
-- instead of its Body: {LB} {RB} {A} {B} {X} {Y} in it become the pad's own button names.
--   local tips = Tips.new(frames, onSkip)
--   tips:Show(steps)   – steps: { { Spot = Rect, Title, Body, PadBody?, Tip = "1 / 3" }, … } in order
--   tips:Hide()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CREAM = C("FBF7F0")
local MINT = C("A7E9B8")
local YELLOW = C("FFE07A")
local BODY_INK = C("3E3850")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local Z = 200
local PAD_NAMES = {
	LB = Enum.KeyCode.ButtonL1, RB = Enum.KeyCode.ButtonR1,
	A = Enum.KeyCode.ButtonA, B = Enum.KeyCode.ButtonB, X = Enum.KeyCode.ButtonX, Y = Enum.KeyCode.ButtonY,
}
local DIM = 0.4 -- background transparency of the dimmed parts

local Tips = {}
Tips.__index = Tips

-- where things are on the round screen (design px, 1280×720)
Tips.SPOTS = {
	Clip = Rect.new(140, 482, 1062, 578), -- play button, clip tiers, skip
	Answers = Rect.new(138, 584, 1142, 676),
	Reveal = Rect.new(340, 168, 990, 426), -- the answer card + points
}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

function Tips.new(frames: Instance, onSkip: () -> ())
	local self = setmetatable({}, Tips)
	self._onSkip = onSkip
	local root = new("Frame", { Name = "TutorialTips", Size = UDim2.fromOffset(1280, 720), BackgroundTransparency = 1, Visible = false, ZIndex = Z }, frames)
	self._root = root
	-- four dim panels around the lit spot (they swallow clicks; the spot doesn't)
	self._dim = {}
	for _, n in { "Top", "Bottom", "Left", "Right" } do
		self._dim[n] = new("Frame", { Name = n, BackgroundColor3 = INK, BackgroundTransparency = DIM, BorderSizePixel = 0, Active = true, ZIndex = Z }, root)
	end
	local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, ZIndex = Z + 1 }, root)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, ring)
	new("UIStroke", { Color = YELLOW, Thickness = 3 }, ring)
	self._ring = ring

	local shadow = new("Frame", { Name = "BubbleShadow", Size = UDim2.fromOffset(520, 150), BackgroundColor3 = INK, ZIndex = Z + 2 }, root)
	new("UICorner", { CornerRadius = UDim.new(0, 16) }, shadow)
	local bubble = new("Frame", { Name = "Bubble", Size = UDim2.fromOffset(520, 150), BackgroundColor3 = CREAM, ZIndex = Z + 3, Active = true }, root)
	new("UICorner", { CornerRadius = UDim.new(0, 16) }, bubble)
	new("UIStroke", { Color = INK, Thickness = 3 }, bubble)
	local tag = new("TextLabel", { Name = "Tag", Position = UDim2.fromOffset(18, 16), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), BackgroundColor3 = INK, TextColor3 = YELLOW, FontFace = BODY, TextSize = 13, Text = "TIP 1 / 3", ZIndex = Z + 4 }, bubble)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, tag)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, tag)
	new("TextLabel", { Name = "Title", Position = UDim2.fromOffset(110, 12), Size = UDim2.new(1, -128, 0, 28), BackgroundTransparency = 1, FontFace = HEAD, TextSize = 20, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = Z + 4 }, bubble)
	new("TextLabel", { Name = "Body", Position = UDim2.fromOffset(18, 46), Size = UDim2.new(1, -36, 0, 46), BackgroundTransparency = 1, FontFace = BODY_BOLD, TextSize = 15, TextColor3 = BODY_INK, TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "", ZIndex = Z + 4 }, bubble)
	local skip = new("TextButton", { Name = "Skip", Position = UDim2.new(0, 18, 1, -40), Size = UDim2.fromOffset(110, 26), BackgroundTransparency = 1, FontFace = BODY, TextSize = 13, TextColor3 = C("6B647A"), TextXAlignment = Enum.TextXAlignment.Left, Text = "<u>Skip tutorial</u>", RichText = true, ZIndex = Z + 4 }, bubble)
	local gotShadow = new("Frame", { Name = "GotItShadow", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -15, 1, -11), Size = UDim2.fromOffset(110, 38), BackgroundColor3 = INK, ZIndex = Z + 4 }, bubble)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, gotShadow)
	local got = new("TextButton", { Name = "GotIt", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -14), Size = UDim2.fromOffset(110, 38), BackgroundColor3 = MINT, FontFace = HEAD, TextSize = 14, TextColor3 = INK, Text = "Got it", AutoButtonColor = false, ZIndex = Z + 5 }, bubble)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, got)
	new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, got)
	-- the pointer under/over the bubble
	local arrow = new("TextLabel", { Name = "Arrow", Size = UDim2.fromOffset(30, 20), BackgroundTransparency = 1, FontFace = HEAD, TextSize = 26, TextColor3 = INK, Text = "▼", ZIndex = Z + 4 }, root)
	self._bubble, self._shadow, self._arrow = bubble, shadow, arrow

	-- controller icons: A just left of Got it, Y just right of Skip tutorial (PadBinds paints them)
	local function padIcon(parent: GuiObject, position: UDim2)
		new("ImageLabel", { Name = "PadIcon", AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Visible = false, ZIndex = Z + 6 }, parent)
	end
	padIcon(got, UDim2.new(0, -20, 0.5, 0))
	padIcon(skip, UDim2.new(0, 104, 0.5, 0))
	self._got, self._skip = got, skip

	got.Activated:Connect(function()
		self:_next()
	end)
	skip.Activated:Connect(function()
		self:_skipAll()
	end)
	return self
end

function Tips:_skipAll()
	self:Hide()
	self._onSkip()
end

function Tips:_spot(r: Rect)
	local d = self._dim
	d.Top.Position, d.Top.Size = UDim2.fromOffset(-2000, -2000), UDim2.fromOffset(5280, 2000 + r.Min.Y)
	d.Bottom.Position, d.Bottom.Size = UDim2.fromOffset(-2000, r.Max.Y), UDim2.fromOffset(5280, 2720 - r.Max.Y + 2000)
	d.Left.Position, d.Left.Size = UDim2.fromOffset(-2000, r.Min.Y), UDim2.fromOffset(2000 + r.Min.X, r.Max.Y - r.Min.Y)
	d.Right.Position, d.Right.Size = UDim2.fromOffset(r.Max.X, r.Min.Y), UDim2.fromOffset(3280 - r.Max.X + 2000, r.Max.Y - r.Min.Y)
	self._ring.Position = UDim2.fromOffset(r.Min.X - 4, r.Min.Y - 4)
	self._ring.Size = UDim2.fromOffset(r.Width + 8, r.Height + 8)

	-- the bubble sits above the spot (below it when there's no room), centred on it
	local w, h = 520, 150
	local x = math.clamp(r.Min.X + r.Width / 2 - w / 2, 20, 1280 - w - 20)
	local above = r.Min.Y - h - 30 >= 10
	local y = if above then r.Min.Y - h - 26 else r.Max.Y + 26
	self._bubble.Position = UDim2.fromOffset(x, y)
	self._shadow.Position = UDim2.fromOffset(x + 6, y + 6)
	self._arrow.Text = if above then "▼" else "▲"
	self._arrow.Position = UDim2.fromOffset(r.Min.X + r.Width / 2 - 15, if above then y + h - 2 else y - 18)
end

function Tips:_render()
	local step = self._steps and self._steps[self._index]
	if not step then
		self:Hide()
		return
	end
	self._bubble.Tag.Text = `TIP {step.Tip}`
	self._bubble.Title.Text = step.Title
	self._bubble.Body.Text = if step.PadBody and PadBinds.UsingPad()
		then (string.gsub(step.PadBody, "{(%w+)}", function(name)
			local key = PAD_NAMES[name]
			return if key then PadBinds.Label(key) else name
		end))
		else step.Body
	self:_spot(step.Spot)
	self._root.Visible = true
	if not self._unpad then
		self._unpad = PadBinds.Bind("TutorialTips", {
			{ Key = Enum.KeyCode.ButtonA, Chip = self._got, Run = function()
				self:_next()
			end },
			{ Key = Enum.KeyCode.ButtonY, Chip = self._skip, Run = function()
				self:_skipAll()
			end },
		})
	end
	Sounds.Play("Notify", { Volume = 0.75 }) -- the Welcome card's chime, a bit louder
end

function Tips:_next()
	self._index += 1
	self:_render()
end

function Tips:Show(steps: { any })
	self._steps = steps
	self._index = 1
	self:_render()
end

function Tips:Hide()
	self._steps = nil
	self._root.Visible = false
	if self._unpad then
		self._unpad()
		self._unpad = nil
	end
end

function Tips:Destroy()
	self._root:Destroy()
end

return Tips
