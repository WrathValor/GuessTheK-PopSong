--| RivalUpController ("RivalUp")
-- "A rival stepped up!" (design board "Play while waiting 2"): someone stepped onto your
-- stage while you were practising with Settings › Rivals can join my practice on. Shows the
-- rival, the XP your practice banked and a countdown into the duel; the server opens the
-- pre-duel screen when it ends (DuelService.handOver), which closes this one. Leave stage
-- steps off instead (the rival goes back to waiting).
-- Opened by DuelController on DuelRemote "RivalSteppedUp":
--   { Rival = profile (Duels.ProfileOf), XP = number? (nil: the practice had already ended),
--     Rounds = number?, Count = seconds }
-- The UI lives in Studio (Interface.Frames.RivalUp: Scrim, CardShadow, Card with Tag, Title,
-- Sub, You / Rival (Thumbnail, Rival.Level), YouName, RivalName, VS, Banked (XP, Rounds),
-- Count (Number, Caption, UIScale "Tick") and Leave).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")

local POP_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local TICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.2)

local function headshot(image: ImageLabel, userId: number)
	image.Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
end

local RivalUp = {}
RivalUp.__index = RivalUp

function RivalUp.new()
	local self = setmetatable({}, RivalUp)
	self.Name = "RivalUp"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._countdown = nil :: thread?
	return (self :: any) :: UITypes.Controller
end

function RivalUp:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "RivalUp")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	self._scrimAlpha = self._frame.Scrim.BackgroundTransparency
	self._janitor:Add(self._frame.Card.Leave.Activated:Connect(function()
		QueueRemote:Fire("Leave")
	end))
	self._janitor:Add(function()
		self:_stopCountdown()
	end, true)
end

function RivalUp:_stopCountdown()
	if self._countdown then
		pcall(task.cancel, self._countdown)
		self._countdown = nil
	end
end

function RivalUp:_fill(packet)
	local card = self._frame.Card
	local rival = type(packet) == "table" and packet.Rival or nil
	headshot(card.You.Thumbnail, LOCAL_PLAYER.UserId)
	card.YouName.Text = "You"
	if rival then
		headshot(card.Rival.Thumbnail, rival.UserId)
		card.RivalName.Text = rival.Name or "Rival"
		card.Rival.Level.Label.Text = `Lv {rival.Level or 1}`
	end
	local xp = packet and packet.XP
	local rounds = packet and packet.Rounds or 0
	if type(xp) == "number" and rounds == 0 then
		-- they stepped on before round 1 (still on the stake chips)
		card.Banked.XP.Text = "Practice cut short"
		card.Banked.Rounds.Text = "No rounds played yet, so nothing's lost"
	elseif type(xp) == "number" then
		card.Banked.XP.Text = if xp > 0 then `+{xp} XP banked` else "No XP this time"
		card.Banked.Rounds.Text = if rounds == 1 then "From 1 practice round" else `From {rounds} practice rounds`
	else
		-- the practice had already finished (they were on its results)
		card.Banked.XP.Text = "Practice done"
		card.Banked.Rounds.Text = "Your rewards are already in"
	end
end

function RivalUp:_startCountdown(seconds: number)
	self:_stopCountdown()
	local count = self._frame.Card.Count
	local tick = count:FindFirstChild("Tick")
	self._countdown = task.spawn(function()
		for i = seconds, 1, -1 do
			count.Number.Text = tostring(i)
			Sounds.Play("Countdown")
			if tick then
				tick.Scale = 1.15
				TweenService:Create(tick, TICK, { Scale = 1 }):Play()
			end
			task.wait(1)
		end
		count.Number.Text = "0"
		self._countdown = nil
	end)
end

function RivalUp:Activate(packet)
	self:_fill(packet)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local frame = self._frame
	frame.Visible = true
	frame.Scrim.BackgroundTransparency = 1
	TweenService:Create(frame.Scrim, FADE, { BackgroundTransparency = self._scrimAlpha }):Play()
	for _, n in { "Card", "CardShadow" } do
		local pop = frame[n]:FindFirstChild("Pop")
		if pop then
			pop.Scale = 0.6
			TweenService:Create(pop, POP_IN, { Scale = 1 }):Play()
		end
	end
	Sounds.Play("RivalFound")
	local seconds = type(packet) == "table" and tonumber(packet.Count) or DuelConstants.HANDOVER_COUNT
	self:_startCountdown(math.max(1, math.floor(seconds)))
	return Promise.delay(0.45):andThen(function()
		if self.State == "Activating" then
			self.State = "Active"
		end
	end)
end

function RivalUp:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self:_stopCountdown()
	local frame = self._frame
	TweenService:Create(frame.Scrim, FADE, { BackgroundTransparency = 1 }):Play()
	for _, n in { "Card", "CardShadow" } do
		local pop = frame[n]:FindFirstChild("Pop")
		if pop then
			TweenService:Create(pop, POP_OUT, { Scale = 0.6 }):Play()
		end
	end
	return Promise.delay(0.2):andThen(function()
		frame.Visible = false
		self.State = "Inactive"
	end)
end

function RivalUp:Destroy()
	self._janitor:Destroy()
end

return RivalUp
