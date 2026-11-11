--| EncoreBanner
-- The ENCORE moment before the final round (design board "Encore C5 · neon lights up letter
-- by letter + confetti"):
--   in:   the stage dims and the dark neon sign POPS in from nothing (overshoots, settles)
--   then: its letters flicker on one at a time (E-N-C-O-R-E), the crowd cheers, the
--         "EN-CORE!" / "×2" stickers and the stake card pop in one after another
--         ("You're 6 behind · up to 14 to win"), confetti falls
--   out:  stickers + card snap away, the sign swells a touch and POPS out, the dim lifts
-- The server holds the round for DuelConstants.ENCORE_INTRO seconds while it plays.
-- The UI lives in Studio (Interface.Frames.Game.Encore: Dim, Confetti, and Stage, a centred
-- full-screen group with a UIScale "Pop" holding the sign, stickers and card, each of those
-- with its own "Pop" scale); this only finds it and animates it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Modules.Sounds)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)

local C = Color3.fromHex
local LIT = C("FF9EC4")
local DARK = C("3A3550")
local GLOW = 0.55 -- TextStrokeTransparency of a lit letter (the pink "glow")
local DIM_TO = 0.35

local ME = tostring(Players.LocalPlayer.UserId)

local SIGN_IN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PART_IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PART_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local SWELL = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SIGN_OUT = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local DIM_IN = TweenInfo.new(0.2)
local DIM_OUT = TweenInfo.new(0.3)

-- timeline (seconds from the start; all of it fits inside ENCORE_INTRO)
local FIRST_LETTER = 0.45 -- once the sign has landed
local LETTER_GAP = 0.15
local PART_GAP = 0.07 -- stagger between the stickers / card popping in
local OUT_AT = DuelConstants.ENCORE_INTRO - 0.7 -- the pop-out starts here (done ~0.55 s later)

local EncoreBanner = {}
EncoreBanner.__index = EncoreBanner

function EncoreBanner.new(gameFrame: Frame)
	local self = setmetatable({}, EncoreBanner)
	self.Root = gameFrame:WaitForChild("Encore")
	self.Dim = self.Root:WaitForChild("Dim")
	self.Stage = self.Root:WaitForChild("Stage")
	self.Pop = self.Stage:WaitForChild("Pop")
	local sign = self.Stage:WaitForChild("Sign")
	self.Letters = {}
	for i = 1, 6 do
		table.insert(self.Letters, sign:WaitForChild("Letters"):WaitForChild("L" .. i))
	end
	-- the parts that pop in after the word lights up, in order
	self.Parts = {}
	for _, name in { "ChantLeft", "Times2", "ChantRight", "Stake" } do
		local f = self.Stage:WaitForChild(name)
		table.insert(self.Parts, { Frame = f, Pop = f:WaitForChild("Pop"), Y = f.Position.Y.Offset, Bob = name ~= "Stake" })
	end
	self.Stake = self.Stage:WaitForChild("Stake"):WaitForChild("Label")
	self.ConfettiRoot = self.Root:WaitForChild("Confetti")
	self.Confetti = {}
	for _, p in self.ConfettiRoot:GetChildren() do
		if p:IsA("GuiObject") then
			table.insert(self.Confetti, { Frame = p, X = p.Position.X.Offset })
		end
	end
	self._token = 0
	return self
end

-- What's at stake for this player, from the Encore packet
local function stakeText(packet): string
	local max = packet.Max or 0
	local mine = packet.Scores and packet.Scores[ME] or 0
	if packet.Solo then
		return `Up to {max} points this round`
	end
	local best = nil -- the top score among everyone else (the rival, or the Party leader)
	for k, s in packet.Scores or {} do
		if k ~= ME and (best == nil or s > best) then
			best = s
		end
	end
	local gap = (best or mine) - mine
	if gap > max then
		return `You're {gap} behind · go out on a high!`
	elseif gap > 0 then
		return `You're {gap} behind · up to {max} to win`
	elseif gap < 0 then
		return `You're {-gap} ahead · hold on!`
	end
	return `All square · up to {max} on the line`
end

local function setLit(label: TextLabel, on: boolean)
	label.TextColor3 = if on then LIT else DARK
	label.TextStrokeTransparency = if on then GLOW else 1
end

local function tween(obj: Instance, info: TweenInfo, goal)
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

function EncoreBanner:_stop()
	self._token += 1
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

function EncoreBanner:Play(packet)
	self:_stop()
	self._leaving = false
	local token = self._token

	-- start state: everything at scale 0, letters dark, confetti waiting above the screen
	for _, l in self.Letters do
		setLit(l, false)
	end
	for _, p in self.Parts do
		p.Pop.Scale = 0
		p.Frame.Position = UDim2.new(p.Frame.Position.X, UDim.new(0, p.Y))
	end
	for _, c in self.Confetti do
		c.Frame.Position = UDim2.fromOffset(c.X, -30)
	end
	self.ConfettiRoot.Visible = false
	self.Stake.Text = stakeText(packet)
	self.Dim.BackgroundTransparency = 1
	self.Pop.Scale = 0
	self.Stage.Rotation = -6
	self.Root.Visible = true

	-- POP IN: the sign springs up from nothing with a little twist
	tween(self.Dim, DIM_IN, { BackgroundTransparency = DIM_TO })
	tween(self.Pop, SIGN_IN, { Scale = 1 })
	tween(self.Stage, SIGN_IN, { Rotation = 0 })

	local start = os.clock()
	local lit = 0
	local cheeredAt = nil
	local leaving = false
	local rng = Random.new()
	local fall = {}
	for i in self.Confetti do
		fall[i] = { Speed = rng:NextNumber(260, 420), Spin = rng:NextNumber(-260, 260), Delay = rng:NextNumber(0, 0.6) }
	end

	self._conn = RunService.RenderStepped:Connect(function()
		if token ~= self._token then
			return
		end
		local t = os.clock() - start

		-- letters switch on one by one, each with a quick flicker
		while lit < #self.Letters and t >= FIRST_LETTER + lit * LETTER_GAP do
			lit += 1
			local label = self.Letters[lit]
			setLit(label, true)
			task.delay(0.05, function()
				if token == self._token then
					setLit(label, false)
				end
			end)
			task.delay(0.1, function()
				if token == self._token then
					setLit(label, true)
				end
			end)
			Sounds.Play("Hover", { Pitch = 0.9 + lit * 0.12 })
		end

		-- the whole word is on: cheer, the stickers + card pop in one after another, confetti
		if not cheeredAt and t >= FIRST_LETTER + #self.Letters * LETTER_GAP then
			cheeredAt = t
			Sounds.Play("Encore")
			for i, p in self.Parts do
				task.delay((i - 1) * PART_GAP, function()
					if token == self._token and not leaving then
						tween(p.Pop, PART_IN, { Scale = 1 })
					end
				end)
			end
			self.ConfettiRoot.Visible = true
		end
		if cheeredAt then
			local since = t - cheeredAt
			for i, p in self.Parts do
				if p.Bob then
					p.Frame.Position = UDim2.new(p.Frame.Position.X, UDim.new(0, p.Y + math.sin(since * 5.7 + i) * 6))
				end
			end
			for i, c in self.Confetti do
				local f = fall[i]
				local ft = math.max(0, since - f.Delay)
				c.Frame.Position = UDim2.fromOffset(c.X + math.sin(ft * 3 + i) * 14, -30 + ft * f.Speed)
				c.Frame.Rotation = ft * f.Spin
			end
		end

		if not leaving and t >= OUT_AT then
			leaving = true
			self:_popOut(token)
		end
	end)
end

-- POP OUT: stickers + card snap away, the sign swells a touch then shrinks to nothing, the dim lifts
function EncoreBanner:_popOut(token: number)
	self._leaving = true
	for _, p in self.Parts do
		tween(p.Pop, PART_OUT, { Scale = 0 })
	end
	task.delay(0.1, function()
		if token ~= self._token then
			return
		end
		tween(self.Pop, SWELL, { Scale = 1.08 }).Completed:Wait()
		if token ~= self._token then
			return
		end
		tween(self.Pop, SIGN_OUT, { Scale = 0 })
		tween(self.Stage, SIGN_OUT, { Rotation = 6 })
		tween(self.Dim, DIM_OUT, { BackgroundTransparency = 1 })
		task.delay(math.max(SIGN_OUT.Time, DIM_OUT.Time), function()
			if token == self._token then
				self:_stop()
				self.Root.Visible = false
				self._leaving = false
			end
		end)
	end)
end

-- The round has started: if the sign is somehow still up (and not already popping out),
-- pop it out now
function EncoreBanner:Hide()
	if not self.Root.Visible or self._leaving then
		return
	end
	self._token += 1
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self:_popOut(self._token)
end

function EncoreBanner:Destroy()
	self:_stop()
	self._leaving = false
	self.Root.Visible = false
end

return EncoreBanner
