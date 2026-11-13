--| Nudges
-- Two one-time lobby hints, after the tutorial, as a spotlight (design board "Lobby nudge C"):
-- the lobby dims except the button (HUD.NudgeSpot: Top / Bottom / Left / Right panels that
-- swallow clicks, and a yellow Ring), and the HUD's speech bubble (HUD.Nudge: Shadow, Bubble
-- with Title / Body / GotIt (+ its PadIcon), and a tail: Arrow, a cream square turned 45° under
-- the bubble's edge, and Join over the outline there) points at it. The lit button still works.
--   Money    – the first time the coins reach a roll's price (RollConstants.COST): points at
--              Roll, and mentions the Shop for the bigger buys
--   Rewards  – the first time a level reward or a quest is ready to claim (not the daily login
--              or the group reward, so it can't fire the moment you join): points at Rewards
-- Each shows once per player (Settings.Hints, saved through SettingsService "HintSeen"): it
-- goes on Got it (A on a controller) or when the button it points at is opened. One at a
-- time; the other waits. The bubble sits in the HUD, so it slides away with it.
--   local nudges = Nudges.new(hud, janitor)
--   nudges:RewardsEarned(n)   -- RewardsController (via HUD:SetRewardsBadge): quests + levels ready
--   nudges:Opened(name)       -- HUD: the player opened "Roll" / "Rewards"

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- --------------------------------- Imports -------------------------------- --
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local RollConstants = require(ReplicatedStorage.Constants.RollConstants)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)

local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

-- --------------------------------- Tables --------------------------------- --
local GAP = 18 -- design px between the bubble's pointer and the button it points at
local SPOT_PAD = 8 -- design px of lit space around the button
local FAR = 4000 -- the dim panels reach this far past the canvas (wide screens)

-- what each nudge says and where it points: Side "Below" (bubble under the button, tail up)
-- or "Right" (bubble beside it, tail left)
local NUDGES = {
	Money = {
		Title = "You can roll a song!",
		Body = `You've got {RollConstants.COST} coins: enough to roll for a new song card. Saving up? Stage sets and mics are in the <b>Shop</b>.`,
		Target = function(hud)
			return hud.TopLeft.Roll
		end,
		Side = "Below", -- (to its right would cover UGC)
		Opens = "Roll",
	},
	Rewards = {
		Title = "Rewards to claim!",
		Body = "You levelled up or finished a quest. Open <b>Rewards</b> to collect coins, roll tickets and more.",
		Target = function(hud)
			return hud.Menu.Tiles.Rewards
		end,
		Side = "Right", -- (above it would cover Quick Play)
		Opens = "Rewards",
	},
}

-- ---------------------------------- Class --------------------------------- --
local Nudges = {}
Nudges.__index = Nudges

local function get(path, fallback)
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else fallback
end

local function seen(id: string): boolean
	local ok, v = pcall(PlayerData.Settings.Hints.Has, id)
	return ok and v == true
end

function Nudges.new(hud, janitor)
	local self = setmetatable({}, Nudges)
	self._hud = hud
	self._frame = hud:WaitForChild("Nudge")
	self._frame.Visible = false
	self._spot = hud:WaitForChild("NudgeSpot")
	self._spot.Visible = false
	self._queue = {} :: { string }
	self._showing = nil :: string?
	self._done = {} :: { [string]: boolean } -- marked this session (the save catches up a moment later)

	local bubble = self._frame.Bubble
	janitor:Add(bubble.GotIt.Activated:Connect(function()
		self:_dismiss()
	end))

	-- Money: the coins reaching a roll's price
	janitor:Add(PlayerData.Currencies.Won.Observe(function(coins: number)
		if coins >= RollConstants.COST then
			self:_want("Money")
		end
	end))
	-- the tutorial finishing lets a waiting nudge through
	janitor:Add(PlayerData.Settings.TutorialDone.Observe(function()
		self:_next()
	end))
	return self
end

function Nudges:RewardsEarned(n: number)
	if n > 0 then
		self:_want("Rewards")
	end
end

-- the player opened a screen: a nudge pointing at it has done its job
function Nudges:Opened(name: string)
	if self._showing and NUDGES[self._showing].Opens == name then
		self:_dismiss(true)
	end
end

function Nudges:_want(id: string)
	if self._done[id] or seen(id) or self._showing == id or table.find(self._queue, id) then
		return
	end
	table.insert(self._queue, id)
	self:_next()
end

function Nudges:_next()
	if self._showing or #self._queue == 0 or not get(PlayerData.Settings.TutorialDone, false) then
		return
	end
	local id = table.remove(self._queue, 1)
	if self._done[id] or seen(id) then
		return self:_next()
	end
	self:_show(id)
end

-- ---------------------------------- Showing ------------------------------- --

function Nudges:_show(id: string)
	local nudge = NUDGES[id]
	local frame, bubble = self._frame, self._frame.Bubble
	self._showing = id
	bubble.Title.Text = nudge.Title
	bubble.Body.Text = nudge.Body
	self:_place()
	frame.Visible = true
	self._spot.Visible = true
	Juice.Pop(bubble, 0.12) -- (the bubble, not the frame: Pop re-anchors what it pops, and the frame is placed by its corner)
	Sounds.Play("Notify", { Volume = 0.75 })

	-- the button it points at moves with the HUD (slides, screen size): follow it
	self._follow = RunService.RenderStepped:Connect(function()
		self:_place()
	end)
	self._unpad = PadBinds.Bind("Nudge", {
		{ Key = Enum.KeyCode.ButtonA, Chip = bubble.GotIt, Run = function()
			self:_dismiss()
		end },
	})
end

-- puts the bubble beside / above its button, in the HUD canvas's design px
function Nudges:_place()
	local id = self._showing
	if not id then
		return
	end
	local nudge = NUDGES[id]
	local hud, frame = self._hud, self._frame
	local target = nudge.Target(hud)
	local scale = hud:FindFirstChildOfClass("UIScale")
	local s = if scale and scale.Scale > 0 then scale.Scale else 1
	local origin = hud.AbsolutePosition
	local pos = (target.AbsolutePosition - origin) / s
	local size = target.AbsoluteSize / s
	-- (measured, not read off Size: the size may be set in scale or in offset)
	local w, h = frame.AbsoluteSize.X / s, frame.AbsoluteSize.Y / s
	-- the bubble sits over / under the button, as centred on it as the screen allows; the tail
	-- points at the button's middle (kept clear of the bubble's rounded corners)
	-- kept on the real screen (the canvas is centred and the corner groups are pinned to the
	-- screen's edges, so the canvas's own 0–1280 isn't what's visible)
	local screen = (hud:FindFirstAncestorWhichIsA("ScreenGui") :: ScreenGui).AbsoluteSize
	local left, right = -origin.X / s + 10, (screen.X - origin.X) / s - 10
	local top, bottom = -origin.Y / s + 10, (screen.Y - origin.Y) / s - 10
	local join = frame.Join
	if nudge.Side == "Below" then
		local centre = pos.X + size.X / 2
		local x = math.clamp(centre - w / 2, left, math.max(left, right - w))
		local tailX = math.clamp(centre - x, 28, w - 28)
		frame.Position = UDim2.fromOffset(x, pos.Y + size.Y + GAP)
		frame.Arrow.Position = UDim2.fromOffset(tailX, 0)
		join.Size = UDim2.fromOffset(24, 8)
		join.Position = UDim2.fromOffset(tailX, 2)
	else -- Right
		local middle = pos.Y + size.Y / 2
		local y = math.clamp(middle - h / 2, top, math.max(top, bottom - h))
		local tailY = math.clamp(middle - y, 24, h - 24)
		frame.Position = UDim2.fromOffset(pos.X + size.X + GAP, y)
		frame.Arrow.Position = UDim2.fromOffset(0, tailY)
		join.Size = UDim2.fromOffset(8, 24)
		join.Position = UDim2.fromOffset(2, tailY)
	end

	-- the spotlight: four dim panels around the button (padded), and the ring on its edge
	local spot = self._spot
	local x0, y0 = pos.X - SPOT_PAD, pos.Y - SPOT_PAD
	local x1, y1 = pos.X + size.X + SPOT_PAD, pos.Y + size.Y + SPOT_PAD
	spot.Top.Position, spot.Top.Size = UDim2.fromOffset(-FAR, -FAR), UDim2.fromOffset(1280 + FAR * 2, FAR + y0)
	spot.Bottom.Position, spot.Bottom.Size = UDim2.fromOffset(-FAR, y1), UDim2.fromOffset(1280 + FAR * 2, 720 + FAR - y1)
	spot.Left.Position, spot.Left.Size = UDim2.fromOffset(-FAR, y0), UDim2.fromOffset(FAR + x0, y1 - y0)
	spot.Right.Position, spot.Right.Size = UDim2.fromOffset(x1, y0), UDim2.fromOffset(1280 + FAR - x1, y1 - y0)
	spot.Ring.Position, spot.Ring.Size = UDim2.fromOffset(x0, y0), UDim2.fromOffset(x1 - x0, y1 - y0)
end

function Nudges:_dismiss(quiet: boolean?)
	local id = self._showing
	if not id then
		return
	end
	self._showing = nil
	self._done[id] = true
	SettingsRemote:Fire({ Action = "HintSeen", Id = id })
	if self._follow then
		self._follow:Disconnect()
		self._follow = nil
	end
	if self._unpad then
		self._unpad()
		self._unpad = nil
	end
	self._frame.Visible = false
	self._spot.Visible = false
	if not quiet then
		Sounds.Play("Click")
	end
	-- the next one waits a beat, so two don't land on top of each other
	task.delay(1.5, function()
		self:_next()
	end)
end

return Nudges
