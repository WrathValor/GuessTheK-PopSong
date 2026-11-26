--| TutorialController
-- The first-join tutorial (design boards "Tutorial 1–4"). A player who hasn't finished or
-- skipped it (Settings.TutorialDone) gets the Welcome card once the loading screen has gone
-- (after the "YOU WERE INVITED!" card, if a friend's invite brought them):
--   PLAY A PRACTICE ROUND → the server puts them on a free stage for a 3-round solo game on
--   well-known songs (DuelService "Tutorial", Duels.Tutorial), with coach-mark tips (./Tips)
--   on the clip, the answers and the reveal;
--   SKIP → marked done (SettingsService "TutorialDone").
-- After the practice game the "You're ready!" card replaces the results (DuelController opens
-- it with the End packet): the one-time +100 coins, then Find a rival / Keep practising. (The
-- DoneRoll card's free first song card went with the song roll: the first free photocard pack
-- comes after picking a bias instead, AlbumConstants.FIRST_ALBUM_KEY.)
-- Settings → "Replay tutorial" opens the Welcome card again.
-- The K-POPPED! onboarding (./Flow) now runs first join instead: its Hello and All set cards
-- are views here too, the practice round is one of its steps (its "You're ready!" card is
-- skipped then), and it resumes at the saved step (Settings.Onboard) until it's "Done".
-- Replay tutorial restarts it (SettingsService "OnboardReplay").
--   Interface:Open("Tutorial", "Welcome" | "Done" | "Hello" | "AllSet" | "None", endPacket | opts?)

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
local Flow = require(script.Flow)
local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")
local ME = tostring(LOCAL_PLAYER.UserId)
local WELCOME_DELAY = 0.6 -- seconds after the loading screen goes before the Welcome card

-- the coach marks, in the order they show
local CLIP_TIPS = {
	{ Spot = Tips.SPOTS.Clip, Tip = "1 / 3", Title = "Listen to the clip", Body = "Tap <b>▶</b> to hear a 0.1 second clip. Can't tell yet? Unlock a longer clip, but you'll score less: <b>6 → 5 → 4 → 2 → 1</b>.",
		PadBody = "Press <b>{LB}</b> to hear a 0.1 second clip. Can't tell yet? <b>{RB}</b> unlocks a longer clip, but you'll score less: <b>6 → 5 → 4 → 2 → 1</b>." },
	{ Spot = Tips.SPOTS.Answers, Tip = "2 / 3", Title = "Pick the song", Body = "Tap the song you think it is. Faster answers score more, and wrong answers score nothing, so don't rush blind!",
		PadBody = "Press the song's button (<b>{A} {B} {X} {Y}</b>). Faster answers score more, and wrong answers score nothing, so don't rush blind!" },
}
local REVEAL_TIPS = {
	{ Spot = Tips.SPOTS.Reveal, Tip = "3 / 3", Title = "The answer", Body = "Here's the song and what you scored. In a duel, the most points after 7 rounds wins the coins, and the last round, the <b>ENCORE</b>, counts double. 2 practice rounds to go!" },
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

-- the onboarding's saved step ("" = not started, "Done" = finished or skipped)
local function onboard(): string?
	local ok, v = pcall(PlayerData.Settings.Onboard.Get)
	return if ok then v or "" else nil
end

-- joined from a friend's invite and hasn't collected the welcome gift yet: their
-- "YOU WERE INVITED!" card (InvitedController) comes before the Welcome card
local function invitePending(): boolean
	local ok, by = pcall(PlayerData.Referral.InvitedBy.Get)
	local ok2, welcomed = pcall(PlayerData.Referral.Welcomed.Get)
	return ok and ok2 and by ~= "" and welcomed == false
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
	self._flow = Flow.new(self, interface, frames)
	j:Add(self._flow, "Destroy")
	local hello, allSet = self._frame.Hello, self._frame.AllSet
	j:Add(hello.Go.Activated:Connect(function()
		Sounds.Play("Click")
		self._flow:Hello("Go")
	end))
	j:Add(hello.Skip.Activated:Connect(function()
		self._flow:Hello("Skip")
		self._flow:Skip()
	end))
	j:Add(allSet.QuickPlay.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Close(self.Name)
		task.delay(0.4, function()
			QueueRemote:Fire("QuickPlay")
		end)
	end))
	j:Add(allSet.Lobby.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Close(self.Name)
	end))

	j:Add(welcome.Play.Activated:Connect(function()
		Sounds.Play("Click")
		self._interface:Close(self.Name)
		QueueRemote:Fire({ Request = "Tutorial" })
	end))
	j:Add(welcome.Skip.Activated:Connect(function()
		markDone()
		self._interface:Close(self.Name)
	end))
	local function findRival()
		self._interface:Close(self.Name)
		QueueRemote:Fire("Leave")
		task.delay(0.6, function()
			QueueRemote:Fire("QuickPlay") -- the nearest stage with someone waiting, or an empty one
		end)
	end
	j:Add(done.FindRival.Activated:Connect(findRival))
	j:Add(done.KeepPractising.Activated:Connect(function()
		self._interface:Close(self.Name)
		QueueRemote:Fire({ Request = "Solo" }) -- still on the stage: another solo game
	end))

	-- Settings → Replay tutorial
	local settings = frames:FindFirstChild("Settings")
	local replay = settings and settings:FindFirstChild("ReplayTutorial", true)
	if replay and replay:IsA("GuiButton") then
		j:Add(replay.Activated:Connect(function()
			if self._flow:Running() then
				return
			end
			SettingsRemote:Fire({ Action = "OnboardReplay" })
			self._flow:Start(nil, true)
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
	-- stepped off mid-tutorial (no End packet comes then): take the tips down too
	j:Add(QueueRemote:Connect(function(packet)
		if type(packet) == "table" and packet.Message == "LeftQueue" then
			self._tips:Hide()
			if self._flow:Practising() then
				task.delay(1, function() -- (the End packet comes first when the game finished)
					if self._flow:Practising() then
						self._flow:Practised(nil)
					end
				end)
			end
		end
	end), "Disconnect")

	-- first join: the Welcome card, once data has loaded and nothing else is open
	task.spawn(function()
		-- wait for the loading screen (ReplicatedFirst/Loading) to finish
		local loadDeadline = os.clock() + 60
		while not LOCAL_PLAYER:GetAttribute("LoadingDone") and os.clock() < loadDeadline do
			task.wait(0.1)
		end
		task.wait(WELCOME_DELAY)
		local deadline = os.clock() + 20
		while os.clock() < deadline do
			if onboard() ~= nil and pcall(PlayerData.Settings.TutorialDone.Get) then
				break
			end
			task.wait(0.5)
		end
		local inviteDeadline = os.clock() + 120
		while os.clock() < inviteDeadline do
			local active = self._interface.ActiveController
			if not invitePending() and not (active and active.Name == "Invited") then
				break
			end
			task.wait(0.25)
		end
		local step = onboard()
		if step and step ~= "Done" and not LOCAL_PLAYER:GetAttribute("Stage") and self._interface.ActiveController == nil then
			-- a returning player (done the old tutorial) gets the short version
			self._flow:Start(if step == "" or step == "Welcome" then nil else step, tutorialDone())
		end
	end)
end

function Tutorial:_show(view: string, packet: any?)
	self._view = view
	local welcome = self._frame.Welcome
	local mine = packet and packet.Rewards and packet.Rewards[ME]
	local coins = mine and mine.Coins or 0
	welcome.Visible = view == "Welcome"
	self._frame.WelcomeShadow.Visible = view == "Welcome"
	self._frame.Done.Visible = view == "Done"
	self._frame.DoneShadow.Visible = view == "Done"
	for _, name in { "Hello", "AllSet" } do
		self._frame[name].Visible = view == name
		self._frame[name .. "Shadow"].Visible = view == name
	end
	local opts = if type(packet) == "table" then packet else {}
	if view == "Hello" then
		local hello = self._frame.Hello
		hello.Badge.Text = if opts.Returning then "WELCOME BACK TO" else "WELCOME TO"
		hello.Steps.Step4.Visible = not opts.Returning
		hello.Sub.Text = if opts.Returning
			then "There's a new way to play: collect photocards, pin them and earn."
			else "Collect K-pop photocards. Guess the songs. Build your binder."
	elseif view == "AllSet" then
		local card = self._frame.AllSet
		for _, name in { "Coins", "Ticket", "XP" } do
			card[name].Visible = opts.Paid == true
			card[name .. "Shadow"].Visible = opts.Paid == true
		end
		card.Sub.Text = if opts.Paid then "Your binder is earning. Here's something for the road:" else "Your binder is earning. Have fun out there!"
		for i, line in opts.Lines or {} do
			local l = card:FindFirstChild("Line" .. i)
			if l then
				l.Text.Text = line
			end
		end
		Sounds.Play("Win")
		if opts.Paid then
			Sounds.Play("Success")
			Juice.Pop(card.Coins, 0.15)
		end
	end
	local done = self._frame.Done
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
		done.Score.Text = if right == total then `{right} of {total} right · you know how it works`
			else `{right} of {total} right · you've got the idea`
		done.Gift.Visible = coins > 0
		done:FindFirstChild("GiftShadow").Visible = coins > 0
		done.Gift.Amount.Text = `+{coins} coins`
		if coins > 0 then
			Sounds.Play("Success")
			Juice.Pop(done.Gift, 0.15)
		end
	end
end

function Tutorial:Activate(view: string?, packet: any?)
	-- the onboarding's practice round: its End (or "no free stage") goes back to the flow
	if self._flow:Practising() and (view == "Done" or view == "Welcome") then
		self._flow:Practised(if view == "Done" then packet else nil)
		view = "None"
	end
	self:_show(view or "Welcome", packet)
	-- a cheerful sting as the card pops in (the Done card's coins chime follows on its own)
	-- the Welcome card uses the shared frame "Open" sound (Interface:Open); Done adds the win jingle
	if view == "Done" then
		Sounds.Play("Win")
	end
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
