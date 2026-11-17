--| OpenChip
-- The chip under the scoreboard during open practice (Settings › Rivals can join my practice;
-- design board "Play while waiting 1"):
--   • mint, pulsing dot – STAGE OPEN · a rival can step on any time
--   • yellow            – RIVAL WAITING · <name> steps in after this round (DuelRemote
--                         "RivalWaiting"); back to mint on "RivalLeft"
-- The UI lives in Studio (Interface.Frames.Game.OpenChip + OpenChipShadow, with a "Pop"
-- UIScale, a Dot and a rich-text Label); this only finds it and animates it.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Modules.Sounds)

local C = Color3.fromHex
local OPEN = C("A7E9B8")
local WAITING = C("FFE07A")
local POP_IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local OpenChip = {}
OpenChip.__index = OpenChip

function OpenChip.new(gameFrame: Frame)
	local self = setmetatable({}, OpenChip)
	self.Chip = gameFrame:FindFirstChild("OpenChip")
	self.Shadow = gameFrame:FindFirstChild("OpenChipShadow")
	self._pulse = nil :: Tween?
	self:Hide()
	return self
end

local function escape(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function OpenChip:_paint(waitingFor: string?)
	local chip = self.Chip
	chip.BackgroundColor3 = if waitingFor then WAITING else OPEN
	chip.Label.Text = if waitingFor
		then `<font weight="heavy">RIVAL WAITING</font>  ·  {escape(waitingFor)} steps in after this round`
		else '<font weight="heavy">STAGE OPEN</font>  ·  a rival can step on any time'
end

function OpenChip:_pop()
	local pop = self.Chip:FindFirstChild("Pop")
	if pop then
		pop.Scale = 0.6
		TweenService:Create(pop, POP_IN, { Scale = 1 }):Play()
	end
end

-- open: this solo game was started with the stage open (DuelRemote "Start".Open)
function OpenChip:Show(open: boolean)
	if not self.Chip then
		return
	end
	if not open then
		self:Hide()
		return
	end
	self:_paint(nil)
	self.Chip.Visible = true
	if self.Shadow then
		self.Shadow.Visible = true
	end
	self:_pop()
	if self._pulse then
		self._pulse:Cancel()
	end
	local dot = self.Chip:FindFirstChild("Dot")
	if dot then
		dot.BackgroundTransparency = 0
		self._pulse = TweenService:Create(dot, PULSE, { BackgroundTransparency = 0.6 })
		self._pulse:Play()
	end
end

-- someone stepped onto the other spot: this round is the last one
function OpenChip:Waiting(name: string)
	if not (self.Chip and self.Chip.Visible) then
		return
	end
	self:_paint(name)
	self:_pop()
	Sounds.Play("RivalFound")
end

-- they stepped off again: practice carries on
function OpenChip:Left()
	if self.Chip and self.Chip.Visible then
		self:_paint(nil)
		self:_pop()
	end
end

function OpenChip:Hide()
	if self._pulse then
		self._pulse:Cancel()
		self._pulse = nil
	end
	if self.Chip then
		self.Chip.Visible = false
	end
	if self.Shadow then
		self.Shadow.Visible = false
	end
end

return OpenChip
