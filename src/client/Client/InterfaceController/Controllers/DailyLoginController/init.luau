--| DailyLoginController ("DailyLogin")
-- The daily login pop-up (Interface.Frames.DailyLogin, built in Studio by ./Build from the
-- "Daily login 1–3" boards): the week of the ladder you're on, days 1–6 in a grid and day 7
-- as the big card, the streak at the top and CLAIM DAY n (then the countdown to the next one
-- and tomorrow's prize). The ladder is two weeks (Constants/RewardsCatalog.DAILY) that take
-- turns without the screen ever naming them; Engine/RewardsService pays the claim.
--   • On join it pops up once a session, FIRST: after the loading screen and the tutorial,
--     once the lobby is free, if today's reward is waiting (What's New waits longer).
--   • The Rewards screen still has its own daily strip and claim; both read the same data.
--   • Claiming with a streak of 2+ offers Roblox's notification opt-in, for the "your streak
--     resets in 4 hours" reminder (Engine/StreakReminders).
--   Interface:Open("DailyLogin")
--   DailyLogin.Icons(reward) -> { image }   -- the card art for a day's reward (≤ 2)

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Currencies = require(ReplicatedStorage.Constants.Currencies)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")
local DAYS = Catalog.DAILY_DAYS

-- the claim animation (DailyLogin:_claimed)
local FADE = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SETTLE = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local DROP = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- the pop-up on join: this long after the loading screen / tutorial, with the lobby free
local JOIN_DELAY = 1.5
local LIFT = 6 -- today's card sits this much higher, tilted
local OPT_IN_STREAK = 2 -- after claiming with a streak this long, offer the streak reminder

-- --------------------------------- Helpers -------------------------------- --
local function now(): number
	return workspace:GetServerTimeNow()
end

local function get(path, fallback)
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else fallback
end

-- canClaim, the streak after today's claim (or today's, once claimed), the ladder index
local function state(): (boolean, number, number)
	return Catalog.DailyState(get(PlayerData.Rewards.DailyStreak, 0), get(PlayerData.Rewards.LastDailyClaim, 0), now())
end

local function countdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h, m = seconds // 3600, (seconds % 3600) // 60
	if h > 0 then
		return `{h}h {m}m`
	end
	return if m > 0 then `{m}m {seconds % 60}s` else `{seconds}s`
end

-- the daily login's own coin piles (assets/ui/CoinPile*.png, drawn for the day cards: the
-- shop's bundle piles sit small in their images and read as cut off here)
local PILES = {
	{ 0, "rbxassetid://70834470931987" }, -- CoinPileSmall: a short stack + a coin
	{ 200, "rbxassetid://78510686592111" }, -- CoinPileMedium: two stacks + a coin
	{ 500, "rbxassetid://139007446543982" }, -- CoinPileBig: three stacks, two coins, sparkles
}
local function pileFor(amount: number): string
	local pick = PILES[1][2]
	for _, step in PILES do
		if amount >= step[1] then
			pick = step[2]
		end
	end
	return pick
end

-- the potion art for potion time: the 2-hour bottle for an hour or more, else the small one
local function potionFor(kind: string, minutes: number): string?
	local want = if minutes >= 60 then "Big" else "Small"
	for _, b in ShopCatalog.Boosts do
		if b.Kind == kind and string.find(b.Id, want, 1, true) then
			return b.Image
		end
	end
	return nil
end

-- ---------------------------------- Class --------------------------------- --
local DailyLogin = {}
DailyLogin.__index = DailyLogin

function DailyLogin.Icons(reward): { string }
	local out = {}
	for _, r in Catalog.RewardList(reward) do
		if r.Kind == "Coins" then
			table.insert(out, pileFor(r.Amount))
		else
			local c = Currencies.Get(r.Kind)
			table.insert(out, c and c.Icon or "")
		end
	end
	for _, b in Catalog.DailyBoosts(reward) do
		table.insert(out, potionFor(b.Kind, b.Minutes) or "")
	end
	return out
end

function DailyLogin.new()
	local self = setmetatable({}, DailyLogin)
	self.Name = "DailyLogin"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._busy = false
	self._animating = false
	self._shownThisSession = false
	return (self :: any) :: UITypes.Controller
end

-- [[ Painting ]]

-- one day card for its state: "Done" (claimed this cycle), "Today" (ready) or "Next"
function DailyLogin:_paintDay(day: number, reward, status: string)
	local holder = self._frame.Days["Day" .. day]
	local face = holder.Face
	local seven = day == DAYS
	face.BackgroundColor3 = Build.COLOURS[status]
	face.Wash.Enabled = seven and status == "Next"
	-- a claimed day fades back, today's sits up and tilts
	local fade = if status == "Done" then 0.35 else 0
	for _, label in { face.DayLabel, face.Big, face.Sub } do
		label.TextTransparency = fade
	end
	holder.Shadow.BackgroundTransparency = if status == "Done" then 0.5 else 0
	-- 5 px of shadow past the stroke (7 for today); the stroke is 4 px outside the face
	local drop = (if status == "Today" then 7 else 5) - 4
	holder.Shadow.Position = UDim2.fromOffset(drop, drop)

	local icons = DailyLogin.Icons(reward)
	local art = face.Art
	art.Icon1.Image = icons[1] or ""
	art.Icon2.Image = icons[2] or ""
	art.Icon2.Visible = icons[2] ~= nil
	-- two rewards share the art box: the first to the left, the second to the right
	art.Icon1.Position = if icons[2] then UDim2.fromScale(if seven then 0.36 else 0.31, 0.55) else UDim2.fromScale(0.5, 0.5)
	-- (smaller when it shares the box, so it stays inside the art's edge)
	local size = if icons[2] then (if seven then 120 else 58) else (if seven then 150 else 72)
	art.Icon1.Size = UDim2.fromOffset(size, size)
	for _, icon in { art.Icon1, art.Icon2 } do
		icon.ImageTransparency = if status == "Done" then 0.55 else 0
	end
	local big, sub = Catalog.DailyLabel(reward)
	face.Big.Text = big
	face.Sub.Text = sub
	face.Big.TextSize = if seven then 24 elseif #big > 7 then 13 else 15

	holder.Stamp.Visible = status == "Done"
	holder.Stamp.Rotation = -12
	local pop = holder.Stamp:FindFirstChild("Pop")
	if pop then
		pop.Scale = 1
	end
	holder.Today.Visible = status == "Today"
	holder.TodayShadow.Visible = status == "Today"
	-- (the claim animation fades the TODAY sticker out)
	holder.Today.BackgroundTransparency, holder.Today.TextTransparency, holder.TodayShadow.BackgroundTransparency = 0, 0, 0
	local todayStroke = holder.Today:FindFirstChildOfClass("UIStroke")
	if todayStroke then
		todayStroke.Transparency = 0
	end
	holder.Rotation = if status == "Today" then -1.5 else 0
	local base = holder:GetAttribute("BaseY")
	if base == nil then
		base = holder.Position.Y.Offset
		holder:SetAttribute("BaseY", base)
	end
	holder.Position = UDim2.fromOffset(holder.Position.X.Offset, base - (if status == "Today" then LIFT else 0))
end

function DailyLogin:_paint()
	local f = self._frame
	local canClaim, streakAfter, index = state()
	local first, today = Catalog.DailyWeek(index)
	for day = 1, DAYS do
		local status = if day < today or (day == today and not canClaim) then "Done" elseif day == today then "Today" else "Next"
		self:_paintDay(day, Catalog.DAILY[first + day - 1], status)
	end
	-- the streak as it stands (today's claim not counted until it's made)
	local streak = if canClaim then streakAfter - 1 else streakAfter
	f.Streak.Row.Days.Text = if streak > 0 then `{streak} DAY STREAK` else "START YOUR STREAK"
	self:_fitStreak()
	f.Claim.Text = `CLAIM DAY {today}`
	f.Claim.Visible = canClaim
	f.ClaimShadow.Visible = canClaim
	-- (the claim animation fades these; a later day shows them again)
	f.Claim.BackgroundTransparency, f.Claim.TextTransparency, f.ClaimShadow.BackgroundTransparency = 0, 0, 0
	local claimStroke = f.Claim:FindFirstChildOfClass("UIStroke")
	if claimStroke then
		claimStroke.Transparency = 0
	end
	f.Next.Visible = not canClaim
	if not canClaim then
		local nextIndex = (index % #Catalog.DAILY) + 1
		local big, sub = Catalog.DailyLabel(Catalog.DAILY[nextIndex])
		f.Next.Tomorrow.Prize.Text = `{big} {sub}`
		self:_tick()
	end
end

-- the streak chip (and its shadow) fit their words: flame + gap + text + padding. TextBounds
-- is in screen pixels, the chip in design pixels, so it's divided by the canvas scale (on a
-- phone the canvas is ~0.5, and the text was measured at half the size it needs)
function DailyLogin:_fitStreak()
	local f = self._frame
	local label = f.Streak.Row.Days
	local canvas = self._canvasScale
	local scale = if canvas and canvas.Scale > 0 then canvas.Scale else 1
	local w = math.ceil(label.TextBounds.X / scale) + 18 + 6 + 30
	f.Streak.Size = UDim2.fromOffset(w, 32)
	f.StreakShadow.Size = UDim2.fromOffset(w + 6, 38) -- under the 3 px stroke
end

function DailyLogin:_tick()
	local left = Catalog.SecondsLeft(math.floor(now()))
	self._frame.Next.Timer.Label.Text = `Next one in {countdown(left)}`
	if left <= 0 then
		self:_paint() -- a new day: today's card is ready
	end
end

-- [[ Claiming ]]

function DailyLogin:_claim()
	if self._busy then
		return
	end
	local canClaim = state()
	if not canClaim then
		return self:_paint()
	end
	self._busy = true
	Sounds.Play("Click")
	RewardsRemote:Fire({ Action = "ClaimDaily" })
	-- the answer comes back on RewardsRemote (Initialize); give up on it after a while
	task.delay(6, function()
		self._busy = false
	end)
end

-- fade a button (and its stroke) in or out; Transparency 1 hides it, 0 restores it
local function fadeButton(button: GuiObject, shadow: GuiObject?, to: number)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	TweenService:Create(button, FADE, { BackgroundTransparency = to, TextTransparency = to }):Play()
	if stroke then
		TweenService:Create(stroke, FADE, { Transparency = to }):Play()
	end
	if shadow then
		TweenService:Create(shadow, FADE, { BackgroundTransparency = to }):Play()
	end
end

-- the server paid: CLAIM fades away, today's card settles back into the grid and turns to
-- "done" as the ✓ stamp drops onto it, the streak ticks up, then the countdown eases in.
-- (The data changes land meanwhile; _animating keeps _paint from snapping over the tweens.)
function DailyLogin:_claimed(packet)
	self._busy = false
	self._animating = true
	Sounds.Play("Coins")
	local f = self._frame
	local day = tonumber(packet.Day)
	local holder = day and f.Days:FindFirstChild("Day" .. day)

	fadeButton(f.Claim, f.ClaimShadow, 1)

	if holder then
		local face = holder.Face
		local base = holder:GetAttribute("BaseY") or holder.Position.Y.Offset
		TweenService:Create(holder, SETTLE, { Rotation = 0, Position = UDim2.fromOffset(holder.Position.X.Offset, base) }):Play()
		TweenService:Create(holder.Shadow, SETTLE, { Position = UDim2.fromOffset(1, 1), BackgroundTransparency = 0.5 }):Play()
		TweenService:Create(face, SETTLE, { BackgroundColor3 = Build.COLOURS.Done }):Play()
		for _, label in { face.DayLabel, face.Big, face.Sub } do
			TweenService:Create(label, SETTLE, { TextTransparency = 0.35 }):Play()
		end
		for _, icon in { face.Art.Icon1, face.Art.Icon2 } do
			TweenService:Create(icon, SETTLE, { ImageTransparency = 0.55 }):Play()
		end
		-- TODAY slips off as the stamp lands
		local today = holder.Today
		local todayStroke = today:FindFirstChildOfClass("UIStroke")
		TweenService:Create(today, FADE, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(holder.TodayShadow, FADE, { BackgroundTransparency = 1 }):Play()
		if todayStroke then
			TweenService:Create(todayStroke, FADE, { Transparency = 1 }):Play()
		end
		local stamp = holder.Stamp
		local pop = stamp:FindFirstChild("Pop") :: UIScale?
		stamp.Visible = true
		stamp.Rotation = -32
		if pop then
			pop.Scale = 1.7
		end
		task.delay(0.1, function()
			Sounds.Play("Success", { Volume = 0.35 })
			TweenService:Create(stamp, DROP, { Rotation = -12 }):Play()
			if pop then
				TweenService:Create(pop, DROP, { Scale = 1 }):Play()
			end
		end)
	end

	task.delay(0.45, function()
		if self.State == "Inactive" then
			self._animating = false
			return
		end
		-- the streak ticks up with a little pop
		local streak = tonumber(packet.Streak)
		if streak then
			f.Streak.Row.Days.Text = `{streak} DAY STREAK`
			Juice.Pop(f.Streak, 0.08)
		end
	end)

	task.delay(0.6, function()
		self._animating = false
		if self.State == "Inactive" then
			return
		end
		self:_paint() -- the same end state the tweens reached, plus the Next row
		local pop = f.Next:FindFirstChild("Pop") :: UIScale?
		if pop then
			pop.Scale = 0.85
			TweenService:Create(pop, DROP, { Scale = 1 }):Play()
		end
	end)

	-- a streak worth keeping: offer the streak reminder (Engine/StreakReminders)
	local streak = tonumber(packet.Streak)
	if streak and streak >= OPT_IN_STREAK then
		task.delay(1.4, function()
			self:_offerReminders()
		end)
	end
end

-- Roblox's own "turn on notifications" prompt (its wording is fixed). Once a session; Roblox
-- itself skips it for under-13s, players who already said yes, and anyone asked in the last
-- 30 days.
function DailyLogin:_offerReminders()
	if self._askedReminders then
		return
	end
	self._askedReminders = true
	local ok, can = pcall(ExperienceNotificationService.CanPromptOptInAsync, ExperienceNotificationService)
	if ok and can then
		pcall(ExperienceNotificationService.PromptOptIn, ExperienceNotificationService)
	end
end

-- [[ The pop-up on join ]]

function DailyLogin:_free(): boolean
	local i = self._interface
	return i.Mode == "Gameplay" and i.ActiveController == nil and not LOCAL_PLAYER:GetAttribute("Stage")
end

function DailyLogin:_joinPopup()
	local deadline = os.clock() + 60
	while not LOCAL_PLAYER:GetAttribute("LoadingDone") and os.clock() < deadline do
		task.wait(0.25)
	end
	-- the player's data has to be there, and the tutorial done (a new player gets it after)
	while true do
		local ok, done = pcall(PlayerData.Settings.TutorialDone.Get)
		if ok and done == true then
			break
		end
		task.wait(0.5)
	end
	task.wait(JOIN_DELAY)
	while not self._shownThisSession do
		local canClaim = state()
		if not canClaim then
			return -- already claimed today (on another server, or the Rewards screen)
		end
		if self:_free() then
			self._shownThisSession = true
			AnalyticsClient.Event("DailyLoginPopup", 1, "Join")
			self._interface:Open(self.Name)
			return
		end
		task.wait(0.5)
	end
end

-- -------------------------------- Lifecycle ------------------------------- --

function DailyLogin:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "DailyLogin")
	self._frame.Visible = false
	local f = self._frame
	local j = self._janitor
	for _, b in { f.Close, f.Claim } do
		ButtonScale.Apply(b)
	end
	-- the Frames canvas UIScale (the streak chip is measured against it)
	self._canvasScale = f.Parent and f.Parent:FindFirstChildOfClass("UIScale")
	j:Add(f.Streak.Row.Days:GetPropertyChangedSignal("TextBounds"):Connect(function()
		self:_fitStreak() -- the font loaded, the text changed, or the screen was resized
	end))
	j:Add(f.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	j:Add(f.Claim.Activated:Connect(function()
		self:_claim()
	end))

	j:Add(RewardsRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" or packet.Action ~= "ClaimDaily" then
			return
		end
		if self.State == "Inactive" then
			return -- claimed from the Rewards screen
		end
		if packet.Ok then
			self:_claimed(packet)
		else
			self._busy = false
			Sounds.Play("Wrong")
			self:_paint()
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy

	for _, path in { PlayerData.Rewards.DailyStreak, PlayerData.Rewards.LastDailyClaim } do
		j:Add(path.Observe(function()
			if self.State ~= "Inactive" and not self._busy and not self._animating then
				self:_paint()
			end
		end))
	end

	j:Add(task.spawn(function()
		self:_joinPopup()
	end))
end

function DailyLogin:Activate()
	self._shownThisSession = true -- opened by hand counts too
	self._frame.Visible = true
	self:_paint()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local f = self._frame
	local cards = {}
	for day = 1, DAYS do
		table.insert(cards, f.Days["Day" .. day])
	end
	Juice.Stagger(cards, 0.035)
	-- the countdown, once a second while it's open
	self._ticker = task.spawn(function()
		while true do
			task.wait(1)
			if self.State ~= "Inactive" and self._frame.Next.Visible then
				self:_tick()
			end
		end
	end)
	return FrameTransition.Open(f):andThen(function()
		self.State = "Active"
		if f.Claim.Visible then
			Juice.Pop(f.Claim, 0.2)
		end
	end)
end

function DailyLogin:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	if self._ticker then
		task.cancel(self._ticker)
		self._ticker = nil
	end
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function DailyLogin:Destroy()
	if self._ticker then
		task.cancel(self._ticker)
	end
	self._janitor:Destroy()
end

return DailyLogin
