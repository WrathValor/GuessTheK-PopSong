--| HUD effects
-- Small looping effects that make a few lobby HUD pieces feel alive. Only the pieces that
-- should catch the eye get one:
--   • Shop        – pastel rainbow (holo card) background that keeps turning; SALE sticker wobbles
--   • Quick Play  – a light sheen sweeps across every few seconds
--   • New Drop    – the same sheen, less often
--   • Rewards     – the unclaimed badge gives a little hop now and then (only when shown)
-- Everything stops when `Stop()` is called (HUDController's janitor does it), and the loops
-- skip work while the HUD is hidden.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Effects = {}

-- pastel "holo photocard" rainbow; the ink outline and shadow stay as they are
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFB3C7")),
	ColorSequenceKeypoint.new(0.2, Color3.fromHex("FFD8A8")),
	ColorSequenceKeypoint.new(0.4, Color3.fromHex("FFF1A8")),
	ColorSequenceKeypoint.new(0.6, Color3.fromHex("B8F0C8")),
	ColorSequenceKeypoint.new(0.8, Color3.fromHex("B5DDFF")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("D4C2FF")),
})
local RAINBOW_SPEED = 70 -- degrees per second the gradient turns

-- Rainbow tile: the background becomes a pastel rainbow gradient that slowly turns, like a
-- holographic card catching the light.
local function rainbow(button: GuiObject, janitor)
	local oldColour = button.BackgroundColor3
	button.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient tints the background, so it must be white
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Rainbow"
	gradient.Color = RAINBOW
	gradient.Rotation = 25
	gradient.Parent = button
	janitor:Add(function()
		gradient:Destroy()
		button.BackgroundColor3 = oldColour
	end, true)
	janitor:Add(RunService.RenderStepped:Connect(function(dt)
		if button.Visible then
			gradient.Rotation = (gradient.Rotation + dt * RAINBOW_SPEED) % 360
		end
	end))
end

-- Sheen: a soft white band that sweeps left → right, then waits `every` seconds.
-- Done as a gradient on a full-size overlay (not a moving bar), so it needs no clipping and
-- works on tilted cards (rotated frames can't clip their children) and rounded corners.
local function sheen(frame: GuiObject, every: number, firstDelay: number, janitor, visible: () -> boolean)
	local overlay = Instance.new("Frame")
	overlay.Name = "Sheen"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BorderSizePixel = 0
	overlay.ZIndex = frame.ZIndex + 1
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = overlay
	end
	local band = Instance.new("UIGradient")
	band.Rotation = 18
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Offset = Vector2.new(-1, 0)
	band.Parent = overlay
	overlay.Parent = frame
	janitor:Add(overlay)
	janitor:Add(task.spawn(function()
		task.wait(firstDelay)
		while overlay.Parent do
			if visible() then
				band.Offset = Vector2.new(-1, 0)
				TweenService:Create(band, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
					Offset = Vector2.new(1, 0),
				}):Play()
			end
			task.wait(every)
		end
	end), true)
end

-- Wobble: a sticker rocking gently back and forth around its resting rotation.
local function wobble(gui: GuiObject, janitor)
	local base = gui.Rotation
	local t = 0
	janitor:Add(RunService.RenderStepped:Connect(function(dt)
		if gui.Visible then
			t += dt
			gui.Rotation = base + math.sin(t * 3) * 6
		end
	end))
	janitor:Add(function()
		gui.Rotation = base
	end, true)
end

-- Hop: a quick pop every `every` seconds while the gui is showing.
local function hop(gui: GuiObject, every: number, janitor, pop: (GuiObject) -> ())
	janitor:Add(task.spawn(function()
		while true do
			task.wait(every)
			if gui.Visible then
				pop(gui)
			end
		end
	end), true)
end

-- hud = PlayerGui.Interface.HUD; pop = Juice.Pop-style function; returns nothing, cleaned by `janitor`.
function Effects.Start(hud: any, janitor, pop: (GuiObject) -> ())
	local function hudShown(): boolean
		return hud.Visible and hud.Menu.Visible
	end
	local tiles = hud.Menu.Tiles

	rainbow(tiles.Shop, janitor)
	local sale = tiles.Shop:FindFirstChild("Sale")
	if sale then
		wobble(sale, janitor)
	end

	sheen(hud.Menu.QuickPlay, 3.5, 1.5, janitor, hudShown)
	local newDrop = hud.TopLeft:FindFirstChild("NewDrop")
	if newDrop then
		sheen(newDrop, 7, 4, janitor, function()
			return hud.Visible and newDrop.Visible
		end)
	end

	local badge = tiles.Rewards:FindFirstChild("Badge")
	if badge then
		hop(badge, 2.5, janitor, pop)
	end
end

return Effects
