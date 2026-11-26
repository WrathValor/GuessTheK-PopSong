--| HUD effects
-- Small looping effects that make a few lobby HUD pieces feel alive. Only the pieces that
-- should catch the eye get one:
--   • Shop        – the SALE sticker wobbles (v3: the banner keeps its own red gradient)
--   • Quests      – the unclaimed count gives a little hop now and then (only when shown)
-- Everything stops when `Stop()` is called (HUDController's janitor does it), and the loops
-- skip work while the HUD is hidden.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Effects = {}

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
	local tiles = hud.TopLeft -- (v3: the tiles are the left column)

	local sale = tiles.Shop:FindFirstChild("Sale")
	if sale then
		wobble(sale, janitor)
	end

	local badge = tiles.Quests:FindFirstChild("Count")
	if badge then
		hop(badge, 2.5, janitor, pop)
	end
end

return Effects
