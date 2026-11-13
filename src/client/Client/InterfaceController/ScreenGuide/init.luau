--| ScreenGuide
-- First-open guides for screens: the first time a screen opens, a few spotlight steps explain
-- it (the "Screen guides" boards; the same look as the lobby nudges, HUDController/Nudges).
-- The screen dims except one part, ringed in yellow, and a speech bubble points at it with
-- Next (A on a controller) until the last step's Got it. Clicks go only to the bubble while
-- it's up. What each screen says is in ./Guides; the instances are Frames.Guide (./Build).
-- Each guide shows once per player: saved in Settings.Hints (SettingsService "HintSeen")
-- when it's finished or its screen closes part-way.
--   ScreenGuide.Init(interface)                  -- InterfaceController.Start
--   ScreenGuide.Opened(name, controller, args)   -- after a screen's open transition; a screen
--                                                -- with pages calls it per page too, with its
--                                                -- own key (PartyController: "PartyHost", …)
--   ScreenGuide.Closed(name)                     -- when a screen starts closing (a controller's
--                                                -- Name or a guide key: either ends its guide)
-- A guide can wait for its screen to be ready (Guides: Ready), and a bubble that won't fit on
-- the side its step asks for goes on the other side, then above / below.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

-- --------------------------------- Imports -------------------------------- --
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local RollConstants = require(ReplicatedStorage.Constants.RollConstants)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)

local Guides = require(script.Guides)

local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

-- --------------------------------- Tables --------------------------------- --
local GAP = 20 -- design px between the bubble's tail and the lit part
local SPOT_PAD = 8 -- design px of lit space around the part
local TAIL_CLEAR = 26 -- the tail keeps this far from the bubble's rounded corners
local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")

-- ---------------------------------- State --------------------------------- --
local ScreenGuide = {}

local interface = nil :: any
local guide = nil :: Frame?
local current = nil :: {
	Name: string,
	Controller: any,
	Guide: any,
	Frame: GuiObject,
	Step: number,
	Cleanup: (() -> ())?,
}?
local follow: RBXScriptConnection? = nil
local unpad: (() -> ())? = nil
local done: { [string]: boolean } = {} -- marked this session (the save catches up a moment later)

local function seen(id: string): boolean
	if done[id] then
		return true
	end
	local ok, v = pcall(PlayerData.Settings.Hints.Has, id)
	return ok and v == true
end

local function tutorialDone(): boolean
	local ok, v = pcall(PlayerData.Settings.TutorialDone.Get)
	return ok and v == true
end

-- ------------------------------- Placement -------------------------------- --

-- the lit part and the bubble, in the Frames canvas's design px (redone every frame, so it
-- follows the screen if it moves or the window resizes)
local function place()
	if not current or not guide then
		return
	end
	local step = current.Guide.Steps[current.Step]
	local ok, target = pcall(step.Target, current.Frame)
	if not ok or not target then
		return
	end
	-- one part, or a list lit as one box around the visible ones
	local lo, hi = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, part in (if typeof(target) == "Instance" then { target } else target) do
		if part:IsA("GuiObject") and part.Visible then
			lo = lo:Min(part.AbsolutePosition)
			hi = hi:Max(part.AbsolutePosition + part.AbsoluteSize)
		end
	end
	if lo.X > hi.X then
		return
	end
	local frames = guide.Parent :: GuiObject
	local scale = frames:FindFirstChildOfClass("UIScale")
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	local origin = frames.AbsolutePosition
	local pos = (lo - origin) / s
	local size = (hi - lo) / s

	-- the spotlight: the dim (a frame on the part, padded, whose huge outline covers the rest)
	-- and the ring on its edge
	local spot = guide.Spot
	local x0, y0 = pos.X - SPOT_PAD, pos.Y - SPOT_PAD
	local x1, y1 = pos.X + size.X + SPOT_PAD, pos.Y + size.Y + SPOT_PAD
	for _, f in { spot.Dim, spot.Ring } do
		f.Position, f.Size = UDim2.fromOffset(x0, y0), UDim2.fromOffset(x1 - x0, y1 - y0)
	end

	-- the bubble: beside / under / over the part, kept on the real screen (the canvas is
	-- centred, so its own 0–1280 isn't what's visible on a wide window). The step's side first;
	-- if it won't fit there, the opposite side, then below / above.
	local bubble = guide.Bubble
	local face = bubble.Face
	-- (measured, so a step's height follows its text; less the pop's own scale)
	local pop = bubble:FindFirstChildOfClass("UIScale")
	local k = s * (if pop and pop.Scale > 0 then pop.Scale else 1)
	local w, h = face.AbsoluteSize.X / k, face.AbsoluteSize.Y / k
	bubble.Size = UDim2.fromOffset(w, h)
	bubble.Shadow.Size = UDim2.fromOffset(w, h)
	-- (the ScreenGui's own corner, not 0,0: with IgnoreGuiInset it starts above 0, under the top bar)
	local gui = guide:FindFirstAncestorWhichIsA("ScreenGui") :: ScreenGui
	local corner0, corner1 = gui.AbsolutePosition, gui.AbsolutePosition + gui.AbsoluteSize
	local left, right = (corner0.X - origin.X) / s + 10, (corner1.X - origin.X) / s - 10
	local top, bottom = (corner0.Y - origin.Y) / s + 10, (corner1.Y - origin.Y) / s - 10
	local fits = {
		Left = x0 - GAP - w >= left,
		Right = x1 + GAP + w <= right,
		Below = y1 + GAP + h <= bottom,
		Above = y0 - GAP - h >= top,
	}
	local OPPOSITE = { Left = "Right", Right = "Left", Below = "Above", Above = "Below" }
	local side = step.Side or "Below"
	for _, try in { side, OPPOSITE[side], "Below", "Above" } do
		if fits[try] then
			side = try
			break
		end
	end
	local arrow, join = bubble.Arrow, bubble.Join
	local ap = bubble.AnchorPoint
	if side == "Below" or side == "Above" then
		local centre = pos.X + size.X / 2
		local x = math.clamp(centre - w / 2, left, math.max(left, right - w))
		local tailX = math.clamp(centre - x, TAIL_CLEAR, w - TAIL_CLEAR)
		local below = side == "Below"
		local y = if below then y1 + GAP else y0 - GAP - h
		bubble.Position = UDim2.fromOffset(x + ap.X * w, y + ap.Y * h)
		arrow.Position = UDim2.fromOffset(tailX, if below then 0 else h)
		join.Size = UDim2.fromOffset(24, 8)
		join.Position = UDim2.fromOffset(tailX, if below then 2 else h - 2)
	else
		local middle = pos.Y + size.Y / 2
		local y = math.clamp(middle - h / 2, top, math.max(top, bottom - h))
		local tailY = math.clamp(middle - y, TAIL_CLEAR, h - TAIL_CLEAR)
		local onRight = side == "Right"
		local x = if onRight then x1 + GAP else x0 - GAP - w
		bubble.Position = UDim2.fromOffset(x + ap.X * w, y + ap.Y * h)
		arrow.Position = UDim2.fromOffset(if onRight then 0 else w, tailY)
		join.Size = UDim2.fromOffset(8, 24)
		join.Position = UDim2.fromOffset(if onRight then 2 else w - 2, tailY)
	end
end

-- -------------------------------- Drawing --------------------------------- --

local function copies(n: number): string
	return if n == 1 then "1 copy" else `{n} copies`
end

local function paint(step, index: number, count: number)
	local face = (guide :: Frame).Bubble.Face
	face.Title.Text = step.Title
	face.Body.Text = step.Body

	face.Ladder.Visible = step.Ladder == true
	if step.Ladder then
		face.Ladder.Normal.Copies.Text = copies(1)
		face.Ladder.Gold.Copies.Text = copies(RollConstants.GOLD_COPIES)
		face.Ladder.Rainbow.Copies.Text = copies(RollConstants.RAINBOW_COPIES)
	end

	face.Heading.Visible = step.Heading ~= nil
	face.Heading.Text = step.Heading or ""

	local points = step.Points or {}
	face.Points.Visible = #points > 0
	for i = 1, 3 do
		local row = face.Points:FindFirstChild("Point" .. i)
		local p = points[i]
		if row then
			row.Visible = p ~= nil
			if p then
				row.Swatch.BackgroundColor3 = p.Colour
				row.Text.Text = p.Text
			end
		end
	end

	local tiles = step.Tiles or {}
	face.Tiles.Visible = #tiles > 0
	for i = 1, 3 do
		local tile = face.Tiles:FindFirstChild("Tile" .. i)
		local t = tiles[i]
		if tile then
			tile.Visible = t ~= nil
			if t then
				tile.BackgroundColor3 = t.Colour
				tile.Label.Text = t.Name
				tile.Text.Text = t.Text
			end
		end
	end

	-- dots: one per step, the current one filled; hidden for a one-step guide
	local dots = face.Footer.Dots
	for i = 1, 5 do
		local d = dots:FindFirstChild("Dot" .. i)
		if d then
			d.Visible = count > 1 and i <= count
			d.BackgroundColor3 = if i == index then INK else WHITE
			d.BackgroundTransparency = if i == index then 0 else 1
		end
	end
	dots.Step.Visible = count > 1
	dots.Step.Text = `{index} of {count}`
	face.Footer.Next.Text = if index < count then "Next" else "Got it"
end

-- ------------------------------- Showing ---------------------------------- --

local function endStep()
	if current and current.Cleanup then
		pcall(current.Cleanup)
		current.Cleanup = nil
	end
end

local function finish(quiet: boolean?)
	if not current or not guide then
		return
	end
	endStep()
	local hint = current.Guide.Hint
	done[hint] = true
	SettingsRemote:Fire({ Action = "HintSeen", Id = hint })
	current = nil
	if follow then
		follow:Disconnect()
		follow = nil
	end
	if unpad then
		unpad()
		unpad = nil
	end
	guide.Visible = false
	if not quiet then
		Sounds.Play("Click")
		-- hand the controller selection back to the screen
		if interface and interface._padFocus then
			pcall(interface._padFocus, interface)
		end
	end
end

local function showStep(index: number)
	if not current or not guide then
		return
	end
	endStep()
	local steps = current.Guide.Steps
	local step = steps[index]
	current.Step = index
	if step.Prepare then
		local ok, cleanup = pcall(step.Prepare, current.Frame)
		current.Cleanup = if ok then cleanup else nil
	end
	paint(step, index, #steps)
	place()
	Juice.Pop(guide.Bubble, 0.08) -- (the holder: place() allows for the anchor Pop gives it)
	if index > 1 then
		Sounds.Play("Click")
	end
end

local function advance()
	if not current then
		return
	end
	if current.Step < #current.Guide.Steps then
		showStep(current.Step + 1)
	else
		finish()
	end
end

-- ---------------------------------- API ----------------------------------- --

function ScreenGuide.Init(iface)
	interface = iface
	local ok, frames = pcall(function()
		return iface:ResolveFrame("Interface", "Guide")
	end)
	guide = if ok then frames else nil
	if not guide then
		warn("[ScreenGuide] Frames.Guide isn't built (run ScreenGuide.Build in Studio)")
		return
	end
	guide.Visible = false
	local face = guide.Bubble.Face
	ButtonScale.Apply(face.Footer.Next)
	face.Footer.Next.Activated:Connect(advance)
	-- the Rainbow card on the ladder: the same moving rainbow as Rainbow cards everywhere
	TierShine.Apply(face.Ladder.Rainbow.Card, face.Ladder.Rainbow.Card:FindFirstChild("Rainbow"), "Rainbow", WHITE)
end

function ScreenGuide.Opened(name: string, controller: any, args: { any }?)
	local def = Guides[name]
	if not def or not guide or current or seen(def.Hint) or not tutorialDone() then
		return
	end
	if def.When and not def.When(args or {}, controller) then
		return
	end
	-- let the screen settle (its first layout pass, counters it fills on open) before measuring;
	-- a guide with Ready waits for it (up to 5 s; not ready = try again next time it opens)
	task.spawn(function()
		task.wait(0.15)
		local waited = 0
		while def.Ready and controller._frame and not def.Ready(controller._frame, controller) do
			if waited > 5 then
				return
			end
			waited += task.wait(0.1)
		end
		if current or not interface or interface.ActiveController ~= controller or seen(def.Hint) then
			return
		end
		if def.When and not def.When(args or {}, controller) then
			return -- (a paged screen moved on while it waited)
		end
		local frame = controller._frame
		if not frame then
			return
		end
		current = { Name = name, Controller = controller, Guide = def, Frame = frame, Step = 1, Cleanup = nil }
		guide.Visible = true
		GuiService.SelectedObject = nil
		Sounds.Play("Notify", { Volume = 0.75 })
		showStep(1)
		follow = RunService.RenderStepped:Connect(place)
		unpad = PadBinds.Bind("ScreenGuide", {
			{ Key = Enum.KeyCode.ButtonA, Chip = guide.Bubble.Face.Footer.Next, Run = advance },
		})
	end)
end

function ScreenGuide.Closed(name: string)
	if current and (current.Name == name or current.Controller.Name == name) then
		finish(true)
	end
end

return ScreenGuide
