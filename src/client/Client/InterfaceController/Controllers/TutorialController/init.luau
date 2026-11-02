--| TutorialController
-- The first-join tutorial (design boards "Tutorial 1–4"). A player who hasn't finished or
-- skipped it (Settings.TutorialDone) gets the Welcome card a moment after joining:
--   PLAY A PRACTICE ROUND → the server puts them on a free stage for a 3-round solo game on
--   well-known songs (DuelService "Tutorial", Duels.Tutorial), with coach-mark tips (./Tips)
--   on the clip, the answers and the reveal;
--   SKIP → marked done (SettingsService "TutorialDone").
-- After the practice game the "You're ready!" card replaces the results (DuelController opens
-- it with the End packet): the one-time +100 coins, then Find a rival / Keep practising.
-- Settings → "Replay tutorial" opens the Welcome card again.
--   Interface:Open("Tutorial", "Welcome" | "Done", endPacket?)

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local Tips = require(script.Tips)
local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")
local ME = tostring(LOCAL_PLAYER.UserId)
local WELCOME_DELAY = 3 -- seconds after joining before the Welcome card

-- the coach marks, in the order they show
local CLIP_TIPS = {
	{ Spot = Tips.SPOTS.Clip, Tip = "1 / 3", Title = "Listen to the clip", Body = "Tap <b>▶</b> to hear a 0.5 second clip. Can't tell yet? Unlock a longer clip, but you'll score less: <b>10 → 7 → 5 → 2 → 1</b>." },
	{ Spot = Tips.SPOTS.Answers, Tip = "2 / 3", Title = "Pick the song", Body = "Tap the song you think it is. Faster answers score more, and wrong answers score nothing, so don't rush blind!" },
}
local REVEAL_TIPS = {
	{ Spot = Tips.SPOTS.Reveal, Tip = "3 / 3", Title = "The answer", Body = "Here's the song and what you scored. In a duel, the most points after 7 rounds wins the coins. 2 practice rounds to go!" },
}

-- ---------------------------------- Class --------------------------------- --
local Tutorial = {}
Tutorial.__index = Tutorial

function Tutorial.new()
	local self = setmetatable({}, Tutorial)
	self.Name = "Tutorial"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._view = "Welcome"
	return (self :: any) :: UITypes.Controller
end

local function markDone()
	SettingsRemote:Fire({ Action = "TutorialDone" })
end

local function tutorialDone(): boolean
	local ok, v = pcall(PlayerData.Settings.TutorialDone.Get)
	return ok and v == true
end

function Tutorial:Initialize(interface)
	self._interface = interface
	local frames = interface.PlayerGui:WaitForChild("Interface"):WaitForChild("Frames")
	-- built in Studio (./Build); built here too if the place hasn't been updated yet
	self._frame = frames:FindFirstChild("Tutorial") or Build.Build(frames)
	self._frame.Visible = false
	Build.AddSettingsButton(frames)
	ButtonScale.ApplyToDescendants(self._frame)
	local j = self._janitor
	local welcome, done = self._frame.Welcome, self._frame.Done

	j:Add(welcome.Play.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Close(self.Name)
		QueueRemote:Fire({ Request = "Tutorial" })
	end))
	j:Add(welcome.Skip.Activated:Connect(function()
		markDone()
		self._interface:Close(self.Name)
	end))
	j:Add(done.FindRival.Activated:Connect(function()
		self._interface:Close(self.Name)
		QueueRemote:Fire("Leave")
		task.delay(0.6, function()
			QueueRemote:Fire("QuickPlay") -- the nearest stage with someone waiting, or an empty one
		end)
	end))
	j:Add(done.KeepPractising.Activated:Connect(function()
		self._interface:Close(self.Name)
		QueueRemote:Fire({ Request = "Solo" }) -- still on the stage: another solo game
	end))

	-- Settings → Replay tutorial
	local settings = frames:FindFirstChild("Settings")
	local replay = settings and settings:FindFirstChild("ReplayTutorial", true)
	if replay and replay:IsA("GuiButton") then
		j:Add(replay.Activated:Connect(function()
			self._interface:Open(self.Name, "Welcome")
		end))
	end

	-- coach marks during the practice round
	self._tips = Tips.new(frames, function()
		self._tipsSkipped = true
		markDone()
	end)
	j:Add(self._tips, "Destroy")
	j:Add(DuelRemote:Connect(function(packet)
		if type(packet) ~= "table" or not packet.Tutorial then
			return
		end
		if packet.Message == "RoundGo" and packet.Round == 1 and not self._tipsSkipped then
			self._tips:Show(CLIP_TIPS)
		elseif packet.Message == "RoundEnd" and packet.Round == 1 and not self._tipsSkipped then
			self._tips:Show(REVEAL_TIPS)
		elseif packet.Message == "RoundEnd" or packet.Message == "End" then
			self._tips:Hide()
		end
	end), "Disconnect")

	-- first join: the Welcome card, once data has loaded and nothing else is open
	task.spawn(function()
		task.wait(WELCOME_DELAY)
		local deadline = os.clock() + 20
		while os.clock() < deadline do
			local ok = pcall(PlayerData.Settings.TutorialDone.Get)
			if ok then
				break
			end
			task.wait(0.5)
		end
		if not tutorialDone() and not LOCAL_PLAYER:GetAttribute("Stage") and self._interface.ActiveController == nil then
			self._interface:Open(self.Name, "Welcome")
		end
	end)
end

function Tutorial:_show(view: string, packet: any?)
	self._view = view
	local welcome, done = self._frame.Welcome, self._frame.Done
	welcome.Visible = view == "Welcome"
	self._frame.WelcomeShadow.Visible = view == "Welcome"
	done.Visible = view == "Done"
	self._frame.DoneShadow.Visible = view == "Done"
	if view == "Done" then
		self._tips:Hide()
		local right, total = 0, 0
		for _, round in (packet and packet.Rounds) or {} do
			total += 1
			local pick = round.Picks and round.Picks[ME]
			if pick and pick.Correct then
				right += 1
			end
		end
		total = math.max(total, DuelConstants.TUTORIAL_ROUNDS)
		done.Score.Text = if right == total then `{right} of {total} right · you know how it works` else `{right} of {total} right · you've got the idea`
		local mine = packet and packet.Rewards and packet.Rewards[ME]
		local coins = mine and mine.Coins or 0
		done.Gift.Visible = coins > 0
		self._frame.Done:FindFirstChild("GiftShadow").Visible = coins > 0
		done.Gift.Amount.Text = `+{coins} coins`
		if coins > 0 then
			Sounds.Play("Coins")
			Juice.Pop(done.Gift, 0.15)
		end
	end
end

function Tutorial:Activate(view: string?, packet: any?)
	self:_show(view or "Welcome", packet)
	-- a cheerful sting as the card pops in (the Done card's coins chime follows on its own)
	Sounds.Play(if (view or "Welcome") == "Welcome" then "Welcome" else "Win")
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	self._frame.Visible = true
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Tutorial:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Tutorial:Destroy()
	self._janitor:Destroy()
end

return Tutorial
