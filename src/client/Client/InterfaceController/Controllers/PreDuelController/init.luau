-- Pre-duel screen: rival found, stake reel spin, then a 5 s mode vote.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local STAKES = { 20, 30, 40, 50, 70, 100 }

-- --------------------------------- Helpers -------------------------------- --
local function thumb(userId: number): string
	local ok, img = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	return ok and img or ""
end

local PreDuel = {}
PreDuel.__index = PreDuel

function PreDuel.new()
	local self = setmetatable({}, PreDuel)
	self.Name = "PreDuel"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new() -- lifetime connections
	self._session = Janitor.new() -- per-duel connections/threads
	self._myVote = nil :: string?
	return (self :: any) :: UITypes.Controller
end

function PreDuel:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "PreDuel")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)

	local vote = self._frame.Vote
	for _, mode in { "Song", "Choreography" } do
		self._janitor:Add(vote[mode].Activated:Connect(function()
			if not self._voteOpen then
				return
			end
			self._myVote = mode
			DuelRemote:Fire({ Action = "Vote", Mode = mode })
			Sounds.Play("Vote")
			self:_paintVotes()
		end))
	end
end

function PreDuel:_fillPlayer(card, profile)
	if not profile then
		card.Visible = false
		local shadow = card.Parent:FindFirstChild(card.Name .. "Shadow")
		if shadow then
			shadow.Visible = false
		end
		return
	end
	card.Visible = true
	local shadow = card.Parent:FindFirstChild(card.Name .. "Shadow")
	if shadow then
		shadow.Visible = true
	end
	card:FindFirstChild("Name").Text = profile.Name
	card.Sub.Text = if profile.Streak > 0 then `Lv {profile.Level} · {profile.Streak} streak` else `Lv {profile.Level}`
	task.spawn(function()
		card.Avatar.Thumbnail.Image = thumb(profile.UserId)
	end)
end

function PreDuel:Setup(packet)
	self._session:Cleanup()
	self._votes = { Song = {}, Choreography = {} }
	self._myVote = nil
	self._voteOpen = false
	local f = self._frame

	-- players: "You" is always the local player
	local me, rival
	for _, profile in packet.Players do
		if profile.UserId == LOCAL_PLAYER.UserId then
			me = profile
		else
			rival = profile
		end
	end
	-- solo practice: you vs you, so the screen never looks empty
	if packet.Solo and me then
		rival = me
	end
	self:_fillPlayer(f.You, me)
	self:_fillPlayer(f.Rival, rival)
	f.VS.Visible = rival ~= nil
	f.RivalFound.Visible = rival ~= nil
	f.RivalFoundShadow.Visible = rival ~= nil

	-- stake (solo: the stake is paid out as XP)
	local solo = packet.Solo
	f.Stake.Visible = true
	f.StakeShadow.Visible = true
	f.Stake.Rule.Text = if solo then "Solo practice · win the stake as XP" else "Winner takes it · loser gets 10"
	local chips = f.Stake.Reel.Chips
	local result = f.Stake.Result
	result.Visible = false
	local mult = if solo then 1 else (me and me.Multiplier or 1)
	result.Streak.Visible = mult > 1
	result.Streak.Label.Text = `×{mult} your streak`

	-- vote panel waits for the spin
	f.Vote.Timer.Seconds.Text = tostring(packet.VoteTime)
	f.Vote.TimeBar.Fill.Size = UDim2.fromScale(1, 1)
	self:_paintVotes()

	local spin = packet.SpinTime
	self._session:Add(task.spawn(function()
		-- spin: chips flick through values, slowing down, then settle on the real reel
		local t0 = os.clock()
		while os.clock() - t0 < spin do
			for i = 1, 7 do
				local chip = chips:FindFirstChild("Chip" .. i)
				if chip then
					chip.Value.Text = tostring(STAKES[math.random(1, #STAKES)])
				end
			end
			local p = (os.clock() - t0) / spin
			Sounds.Play("SpinTick", { Pitch = 1 + p * 0.4 })
			task.wait(0.04 + p * p * 0.2)
		end
		for i = 1, 7 do
			local chip = chips:FindFirstChild("Chip" .. i)
			if chip then
				chip.Value.Text = tostring(packet.Reel[i])
			end
		end
		result.Amount.Value.Text = if solo then `{packet.Stake} XP` else `{packet.Stake} coins`
		result.Visible = true
		Sounds.Play("SpinLand")

		-- vote countdown
		self._voteOpen = true
		local fill = f.Vote.TimeBar.Fill
		TweenService:Create(fill, TweenInfo.new(packet.VoteTime, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
		for s = packet.VoteTime, 1, -1 do
			f.Vote.Timer.Seconds.Text = tostring(s)
			if s <= 3 then
				Sounds.Play("Countdown")
			end
			task.wait(1)
		end
		f.Vote.Timer.Seconds.Text = "0"
		self._voteOpen = false
	end), true)
end

function PreDuel:_paintVotes()
	local vote = self._frame.Vote
	for _, mode in { "Song", "Choreography" } do
		local button = vote[mode]
		local ids = self._votes and self._votes[mode] or {}
		button.Voter.Visible = #ids > 0
		local mine = button:FindFirstChild("YourVote")
		if mine then
			mine.Visible = self._myVote == mode
		end
	end
end

function PreDuel:UpdateVotes(votes)
	self._votes = votes
	self:_paintVotes()
end

function PreDuel:ShowMode(mode: string)
	self._voteOpen = false
	Sounds.Play("ModeReveal")
	local vote = self._frame.Vote
	for _, m in { "Song", "Choreography" } do
		local button = vote[m]
		local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", button)
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = if m == mode then 1.08 else 0.92 }):Play()
	end
	vote.DrawNote.Label.Text = if mode == "Song" then "Guess the Song!" else "Guess the Choreography!"
end

function PreDuel:Activate(packet)
	if packet then
		self:Setup(packet)
	end
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	Sounds.Play(if packet and packet.Solo then "Open" else "RivalFound")
	self._frame.Visible = true
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function PreDuel:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
		self._session:Cleanup()
		-- reset vote button scale for next time
		for _, m in { "Song", "Choreography" } do
			local s = self._frame.Vote[m]:FindFirstChildOfClass("UIScale")
			if s then
				s.Scale = 1
			end
		end
		self._frame.Vote.DrawNote.Label.Text = "Draw = random pick"
	end)
end

function PreDuel:Destroy()
	self._session:Destroy()
	self._janitor:Destroy()
end

return PreDuel
