--| HUD effects
-- Small looping effects that make a few lobby HUD pieces feel alive. Only the pieces that
-- should catch the eye get one:
--   • Shop        – the Rainbow tier's pastel rainbow (Modules/UI/TierShine); SALE sticker wobbles
--   • Rewards     – the unclaimed badge gives a little hop now and then (only when shown)
-- Everything stops when `Stop()` is called (HUDController's janitor does it), and the loops
-- skip work while the HUD is hidden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)

local Effects = {}

-- Rainbow tile: the background takes the Rainbow tier's animation (Modules/UI/TierShine, the
-- pastel rainbow sliding sideways, like the Rainbow cards); the ink outline and shadow stay.
local function rainbow(button: GuiObject, janitor)
	local oldColour = button.BackgroundColor3
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Rainbow"
	gradient.Rotation = 35
	gradient.Parent = button
	TierShine.Apply(button, gradient, "Rainbow", oldColour)
	janitor:Add(function()
		gradient:Destroy()
		button.BackgroundColor3 = oldColour
	end, true)
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
	local tiles = hud.Menu.Tiles

	rainbow(tiles.Shop, janitor)
	local sale = tiles.Shop:FindFirstChild("Sale")
	if sale then
		wobble(sale, janitor)
	end

	local badge = tiles.Rewards:FindFirstChild("Badge")
	if badge then
		hop(badge, 2.5, janitor, pop)
	end
end

return Effects
