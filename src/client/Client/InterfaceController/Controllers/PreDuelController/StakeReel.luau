--| StakeReel
-- The pre-duel stake roll as a real slot reel: a strip of chips slides left under the pointer,
-- fast at first and easing out, overshoots a hair and settles on the rolled stake. The
-- landing chip turns yellow and grows into the design's big chip, then the result row counts up.
-- Big stakes get more: 70 → "BIG STAKE!" sticker, flash + shake; 100 → "JACKPOT!", confetti,
-- a rainbow chip and a bigger shake.
--
-- Built on top of Stake.Reel at run time (nothing to build in Studio): the Studio chips are
-- hidden while the strip spins and shown again, filled with the real reel, when it lands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Modules.Sounds)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)

local C = Color3.fromHex
local INK = C("1E1B2E")
local CHIP = C("EDE4D4")
local CHIP_LINE = C("CFC5B3")
local CHIP_TEXT = C("8A8396")
local YELLOW = C("FFE07A")
local WHITE = C("FFFFFF")
local CONFETTI = { C("FF5A4E"), C("FFE07A"), C("A7E9B8"), C("9ED8F5"), C("B9A6FF"), C("FF9EC4") }
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C("FFB3C7")),
	ColorSequenceKeypoint.new(0.25, C("FFF1A8")),
	ColorSequenceKeypoint.new(0.5, C("B8F0C8")),
	ColorSequenceKeypoint.new(0.75, C("B5DDFF")),
	ColorSequenceKeypoint.new(1, C("D4C2FF")),
})

local STAKES = { 20, 30, 40, 50, 70, 100 }
local STEP = 84 -- chip pitch on the strip (74 wide + 10 gap), same as the Studio reel
local SMALL = Vector2.new(74, 52)
local BIG = Vector2.new(96, 62)
local TRAVEL_CHIPS = 26 -- how many chips scroll past before it lands
local OVERSHOOT = 16 -- px past the target before settling back

-- how much fuss a stake gets
local function tierOf(stake: number): number
	if stake >= 100 then
		return 2
	elseif stake >= 70 then
		return 1
	end
	return 0
end

local StakeReel = {}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function chip(parent: Instance, x: number, value: number): Frame
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, x, 0.5, 0),
		Size = UDim2.fromOffset(SMALL.X, SMALL.Y),
		BackgroundColor3 = CHIP,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, f)
	new("UIStroke", { Name = "Stroke", Color = CHIP_LINE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	new("TextLabel", {
		Name = "Value",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy),
		TextSize = 20,
		TextColor3 = CHIP_TEXT,
		Text = tostring(value),
	}, f)
	return f
end

-- A burst of little paper squares from `origin` (absolute-ish offsets inside `parent`).
local function confetti(parent: GuiObject, origin: Vector2, count: number)
	for _ = 1, count do
		local angle = math.rad(math.random(200, 340)) -- mostly upwards
		local dist = math.random(70, 170)
		local bit = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(math.random(6, 10), math.random(8, 14)),
			BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = 20,
		}, parent)
		local target = origin + Vector2.new(math.cos(angle) * dist, math.sin(angle) * dist)
		local up = TweenService:Create(bit, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(target.X, target.Y),
			Rotation = bit.Rotation + math.random(-260, 260),
		})
		up.Completed:Once(function()
			local fall = TweenService:Create(bit, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X + math.random(-20, 20), target.Y + math.random(60, 120)),
				BackgroundTransparency = 1,
			})
			fall.Completed:Once(function()
				bit:Destroy()
			end)
			fall:Play()
		end)
		up:Play()
	end
end

-- Sticker that slaps on above the reel ("BIG STAKE!" / "JACKPOT!").
local function sticker(parent: GuiObject, text: string, colour: Color3, x: number): GuiObject
	local s = new("TextLabel", {
		Name = "StakeSticker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = colour,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy),
		TextSize = 17,
		TextColor3 = INK,
		Text = text,
		Rotation = -6,
		ZIndex = 15,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 9) }, s)
	new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, s)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, s)
	local scale = new("UIScale", { Scale = 2.2 }, s)
	s.TextTransparency = 1
	s.BackgroundTransparency = 1
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(s, TweenInfo.new(0.15), { TextTransparency = 0, BackgroundTransparency = 0 }):Play()
	return s
end

-- Resets anything a previous roll left behind (call when the screen opens).
function StakeReel.Reset(stake: Frame)
	local reel = stake.Reel
	for _, n in { "Spin", "Window" } do
		local old = reel:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local s = stake:FindFirstChild("StakeSticker")
	if s then
		s:Destroy()
	end
	reel.Chips.Visible = true
	local big = reel.Chips:FindFirstChild("Chip4")
	if big then
		local g = big:FindFirstChild("Jackpot")
		if g then
			g:Destroy()
		end
		big.BackgroundColor3 = YELLOW
	end
end

-- Spins, lands on reel[4] (= the stake), celebrates. Yields for about `spinTime` seconds.
-- `resultText(n)` formats the result row ("70 coins" / "70 XP").
function StakeReel.Spin(stake: Frame, reelValues: { number }, spinTime: number, resultText: (number) -> string)
	StakeReel.Reset(stake)
	local reel = stake.Reel
	local chips = reel.Chips
	local result = stake.Result
	local value = reelValues[4]
	local tier = tierOf(value)
	-- centre of the big chip slot (Juice.Pop re-anchors Chip4 to its centre after the first roll)
	local slot = chips:FindFirstChild("Chip4") :: GuiObject
	local centreX = slot.Position.X.Offset + (0.5 - slot.AnchorPoint.X) * slot.Size.X.Offset

	-- strip: TRAVEL_CHIPS random chips, then the real 7 so the strip ends exactly on the Studio layout
	chips.Visible = false
	local spin = new("Frame", {
		Name = "Spin",
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, reel)
	local strip = new("Frame", { Name = "Strip", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, spin)
	local values = {}
	for i = 1, TRAVEL_CHIPS do
		values[i] = STAKES[math.random(1, #STAKES)]
	end
	for i = 1, 7 do
		values[TRAVEL_CHIPS + i] = reelValues[i]
	end
	-- chip k sits at centreX + (k - 4) * STEP before moving; we slide left by TRAVEL_CHIPS * STEP
	local chipFrames = {}
	for k, v in values do
		chipFrames[k] = chip(strip, centreX - 3 + (k - 4) * STEP, v)
	end
	local landing = chipFrames[TRAVEL_CHIPS + 4]

	-- the fixed window the chips pass under
	local window = new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, centreX, 0.5, 0),
		Size = UDim2.fromOffset(BIG.X, BIG.Y),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, reel)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, window)
	new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, window)

	-- slide: ease-out over most of the time, overshoot a touch, settle back
	local travel = TRAVEL_CHIPS * STEP
	local runTime = math.max(spinTime - 0.3, 0.8)
	local t0 = os.clock()
	local lastIndex = 0
	while true do
		local t = os.clock() - t0
		local x
		if t < runTime then
			local p = t / runTime
			x = (travel + OVERSHOOT) * (1 - (1 - p) ^ 4) -- quart out
		elseif t < runTime + 0.28 then
			local p = (t - runTime) / 0.28
			x = travel + OVERSHOOT * (1 - (p * p * (3 - 2 * p))) -- smoothstep back
		else
			x = travel
		end
		strip.Position = UDim2.fromOffset(-x, 0)
		-- tick each time a chip crosses the pointer; ticks rise in pitch as it slows
		local index = math.floor((x + STEP / 2) / STEP)
		if index ~= lastIndex then
			lastIndex = index
			Sounds.Play("SpinTick", { Pitch = 0.9 + math.min(t / runTime, 1) * 0.5 })
		end
		if t >= runTime + 0.28 then
			break
		end
		RunService.RenderStepped:Wait()
	end

	-- land: the chip under the window turns into the big yellow chip
	Sounds.Play("SpinLand", { Pitch = if tier == 2 then 1.15 elseif tier == 1 then 1.05 else 1 })
	landing.ZIndex = 4
	TweenService:Create(landing, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(BIG.X, BIG.Y),
		BackgroundColor3 = YELLOW,
	}):Play()
	landing.Stroke.Color = INK
	landing.Stroke.Thickness = 3
	landing.Value.TextColor3 = INK
	TweenService:Create(landing.Value, TweenInfo.new(0.22, Enum.EasingStyle.Back), { TextSize = 26 }):Play()
	task.wait(0.24)

	-- swap back to the Studio chips (same spot, same look) so the layout matches the design
	for i = 1, 7 do
		local c = chips:FindFirstChild("Chip" .. i)
		if c then
			c.Value.Text = tostring(reelValues[i])
		end
	end
	chips.Visible = true
	spin:Destroy()
	window:Destroy()
	local big = chips.Chip4
	Juice.Pop(big, if tier == 2 then 0.3 elseif tier == 1 then 0.2 else 0.1)

	-- result row counts up
	result.Visible = true
	Juice.Pop(result.Amount, 0.15)
	Juice.CountUp(result.Amount.Value, 0, value, function(n)
		return resultText(math.floor(n + 0.5))
	end, if tier > 0 then 0.6 else 0.35)

	if tier >= 1 then
		local origin = Vector2.new(reel.Position.X.Offset + centreX, reel.Position.Y.Offset + reel.Size.Y.Offset / 2)
		sticker(stake, if tier == 2 then "JACKPOT!" else "BIG STAKE!", if tier == 2 then C("FF9EC4") else YELLOW, origin.X + 110)
		Juice.Shake(stake)
		Sounds.Play("Coins", { Pitch = if tier == 2 then 1.1 else 1 })
		-- flash: the reel border goes white for a beat
		local stroke = reel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = WHITE
			task.delay(0.12, function()
				stroke.Color = INK
			end)
		end
		confetti(stake, origin, if tier == 2 then 28 else 12)
	end
	if tier == 2 then
		-- jackpot chip shimmers rainbow, and a second burst a moment later
		big.BackgroundColor3 = WHITE
		local g = new("UIGradient", { Name = "Jackpot", Color = RAINBOW }, big)
		task.spawn(function()
			while g.Parent do
				g.Rotation = (g.Rotation + 4) % 360
				RunService.RenderStepped:Wait()
			end
		end)
		Sounds.Play("Perfect")
		task.delay(0.35, function()
			if stake.Parent then
				confetti(stake, Vector2.new(reel.Position.X.Offset + centreX, reel.Position.Y.Offset + reel.Size.Y.Offset / 2), 20)
				Juice.Shake(stake)
			end
		end)
	end
end

return StakeReel
