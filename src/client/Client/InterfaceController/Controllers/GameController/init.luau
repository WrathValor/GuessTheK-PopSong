-- Round screen: scoreboard on top, snippet tiers + Play/Skip + 4 answers at the bottom,
-- and the reveal overlay between rounds.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Scoreboard = require(script.Scoreboard)
local Snippet = require(script.Snippet)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local C = Color3.fromHex
local ME = tostring(LOCAL_PLAYER.UserId)

-- tier button looks (from the design): current = yellow, next = white, locked = beige
local TIER_LOOK = {
	Current = { Bg = C("FFE07A"), Text = C("1E1B2E") },
	Next = { Bg = C("FFFFFF"), Text = C("1E1B2E") },
	Locked = { Bg = C("EDE4D4"), Text = C("6B6577") },
	Used = { Bg = C("D9D2E6"), Text = C("6B6577") },
}
local ANSWER_LOOK = {
	Idle = C("FFFFFF"),
	Picked = C("FFE07A"),
	Correct = C("A7E9B8"),
	Wrong = C("FFD2CE"),
}
-- check / cross icons in atlas 0
local MARK = {
	Correct = { Bg = C("A7E9B8"), Rect = Vector2.new(300, 0) },
	Wrong = { Bg = C("FFD2CE"), Rect = Vector2.new(500, 0) },
}

local function fmt(seconds: number): string
	return if seconds < 1 then `{seconds}s` else `{math.floor(seconds)}s`
end

-- --------------------------------- Class ---------------------------------- --
local Game = {}
Game.__index = Game

function Game.new()
	local self = setmetatable({}, Game)
	self.Name = "Game"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._round = Janitor.new()
	self.Round = nil :: any
	return (self :: any) :: UITypes.Controller
end

function Game:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Game")
	self._frame.Visible = false
	self._frame.Reveal.Visible = false
	ButtonScale.ApplyToDescendants(self._frame.Controls)
	local controls = self._frame.Controls

	self._janitor:Add(controls.PlayButton.Activated:Connect(function()
		self:_play()
	end))
	self._janitor:Add(controls.Skip.Activated:Connect(function()
		local r = self.Round
		if r and r.Tier < #r.Tiers then
			self:_unlock(r.Tier + 1)
			self:_play()
		end
	end))
	for i = 1, 5 do
		local tier = controls.Tiers:FindFirstChild("Tier" .. i)
		if tier then
			self._janitor:Add(tier.Activated:Connect(function()
				local r = self.Round
				if r and i > r.Tier then
					self:_unlock(i)
					self:_play()
				elseif r and i == r.Tier then
					self:_play()
				end
			end))
		end
	end
	for i = 1, 4 do
		local answer = controls.Answers:FindFirstChild("Answer" .. i)
		if answer then
			self._janitor:Add(answer.Activated:Connect(function()
				self:_guess(i)
			end))
		end
	end
end

-- [[ Setup for a duel ]]

function Game:_setupDuel(info, mode)
	self.Mode = mode or "Song"
	self.Solo = info and info.Solo or false
	local me, rival
	for _, profile in (info and info.Players or {}) do
		if profile.UserId == LOCAL_PLAYER.UserId then
			me = profile
		else
			rival = profile
		end
	end
	if self.Solo and me then
		rival = me -- solo practice: you vs you
	end
	self.Me, self.Rival = me, rival
	self.Scoreboard = Scoreboard.new(self._frame.Scoreboard, me, rival)
	self.Scoreboard:Initialize(7)
	local stageName = LOCAL_PLAYER:GetAttribute("Stage")
	self.StageModel = stageName and workspace.Map.DuelStages:FindFirstChild(stageName)
	self._frame.Controls.Visible = true
	self._frame.Reveal.Visible = false
end

-- [[ Rounds ]]

function Game:OnRound(packet)
	self._round:Cleanup()
	local controls = self._frame.Controls
	self._frame.Reveal.Visible = false
	controls.Visible = true

	self.Round = {
		Number = packet.Round,
		Tiers = packet.Tiers,
		Points = packet.Points,
		Options = packet.Options,
		Tier = 1,
		Guessed = nil :: number?,
	}
	self.Scoreboard.Rounds = packet.Rounds
	self.Scoreboard:UpdateRound(packet.Round)
	self.Scoreboard:SetStatus(false, "Listening…")
	self.Scoreboard:SetStatus(true, "Listening…")

	local snippet = Snippet.new(packet.Clip, packet.Mode, self.StageModel)
	self.Snippet = snippet
	self._round:Add(snippet, "Destroy")

	for i = 1, 4 do
		local answer = controls.Answers:FindFirstChild("Answer" .. i)
		local opt = packet.Options[i]
		if answer then
			answer.Visible = opt ~= nil
			if opt then
				answer.Title.Text = opt.Name
				answer.Artist.Text = opt.Artist
				answer.BackgroundColor3 = ANSWER_LOOK.Idle
				answer.Badge.Number.Text = tostring(i)
				answer.AutoButtonColor = false
			end
		end
	end
	controls.RivalAnswered.Visible = false
	controls.Timer.Visible = false
	self:_paintTiers()

	-- play the first snippet straight away
	task.delay(0.4, function()
		if self.Round and self.Round.Number == packet.Round then
			self:_play()
		end
	end)
	-- round cap countdown (only shown when it gets close)
	local cap = packet.Cap or 20
	self._round:Add(task.spawn(function()
		local start = os.clock()
		while true do
			local left = cap - (os.clock() - start)
			if left <= 0 then
				break
			end
			if left <= 5 and not controls.Timer.Visible then
				self:_countdown(left)
				break
			end
			task.wait(0.25)
		end
	end), true)
end

function Game:_paintTiers()
	local r = self.Round
	local tiers = self._frame.Controls.Tiers
	for i = 1, 5 do
		local b = tiers:FindFirstChild("Tier" .. i)
		if b and r then
			b.Time.Text = fmt(r.Tiers[i])
			b.Points.Text = `+{r.Points[i]}`
			local look = if i == r.Tier then TIER_LOOK.Current elseif i < r.Tier then TIER_LOOK.Used elseif i == r.Tier + 1 then TIER_LOOK.Next else TIER_LOOK.Locked
			b.BackgroundColor3 = look.Bg
			b.Time.TextColor3 = look.Text
			b.Points.TextColor3 = look.Text
			local dashes = b:FindFirstChild("Dashes")
			if dashes then
				dashes.Visible = i == r.Tier + 1
			end
		end
	end
	local skip = self._frame.Controls.Skip
	if r and r.Tier < #r.Tiers then
		skip.Visible = r.Guessed == nil
		skip.Label.Text = `Skip to {fmt(r.Tiers[r.Tier + 1])}`
	else
		skip.Visible = false
	end
	if self._frame.Controls:FindFirstChild("SkipShadow") then
		self._frame.Controls.SkipShadow.Visible = skip.Visible
	end
end

function Game:_unlock(tier: number)
	local r = self.Round
	if not r or r.Guessed or tier <= r.Tier then
		return
	end
	r.Tier = tier
	DuelRemote:Fire({ Action = "Unlock", Tier = tier })
	self:_paintTiers()
end

function Game:_play()
	local r = self.Round
	if r and self.Snippet then
		self.Snippet:Play(r.Tiers[r.Tier])
	end
end

function Game:_guess(index: number)
	local r = self.Round
	if not r or r.Guessed or not r.Options[index] then
		return
	end
	r.Guessed = index
	DuelRemote:Fire({ Action = "Guess", Id = r.Options[index].Id })
	local answers = self._frame.Controls.Answers
	for i = 1, 4 do
		local a = answers:FindFirstChild("Answer" .. i)
		if a then
			a.BackgroundColor3 = if i == index then ANSWER_LOOK.Picked else ANSWER_LOOK.Idle
		end
	end
	self.Scoreboard:SetStatus(false, "Answered!")
	if self.Solo then
		self.Scoreboard:SetStatus(true, "Answered!")
	end
	self:_paintTiers()
end

function Game:_countdown(seconds: number)
	local timer = self._frame.Controls.Timer
	timer.Visible = true
	self._round:Add(task.spawn(function()
		local s = math.ceil(seconds)
		while s >= 0 do
			timer.Seconds.Text = tostring(s)
			if s > 0 and s <= 5 then
				Sounds.Play("Countdown", { Pitch = if s <= 2 then 1.15 else 1 })
			end
			task.wait(1)
			s -= 1
		end
	end), true)
end

function Game:OnRivalAnswered(seconds: number)
	self._frame.Controls.RivalAnswered.Visible = true
	if not self.Solo then
		Sounds.Play("RivalAnswered")
	end
	self.Scoreboard:SetStatus(true, "Answered!")
	if not self._frame.Controls.Timer.Visible then
		self:_countdown(seconds)
	end
end

-- [[ Reveal ]]

function Game:OnRoundEnd(packet)
	local r = self.Round
	self._round:Cleanup()
	self.Round = nil
	local reveal = self._frame.Reveal
	local controls = self._frame.Controls

	-- colour the answers, then swap to the reveal
	for i = 1, 4 do
		local a = controls.Answers:FindFirstChild("Answer" .. i)
		local opt = r and r.Options[i]
		if a and opt then
			a.BackgroundColor3 = if opt.Id == packet.Answer.Id then ANSWER_LOOK.Correct
				elseif r.Guessed == i then ANSWER_LOOK.Wrong
				else ANSWER_LOOK.Idle
		end
	end

	reveal.Answer.Title.Text = packet.Answer.Name
	reveal.Answer.Meta.Text = `{packet.Answer.Artist} · {packet.Answer.Generation or ""} Gen`

	local mine = packet.Picks[ME]
	Sounds.Play(if mine and mine.Correct then "Correct" else "Wrong")
	local rivalKey, rivalPick
	for k, pick in packet.Picks do
		if k ~= ME then
			rivalKey, rivalPick = k, pick
		end
	end
	if self.Solo then
		rivalKey, rivalPick = ME, mine -- you vs you
	end

	local function describe(pick, tiers)
		if not pick or not pick.Picked then
			return "No answer · 0 points"
		end
		if not pick.Correct then
			return "Wrong · 0 points"
		end
		local t = tiers and tiers[pick.Tier]
		local s = `Correct on the {t and fmt(t) or "?"} tier`
		if pick.First then
			s ..= " · first!"
		end
		return s
	end
	local tiers = r and r.Tiers

	reveal.Points.Value.Text = `+{mine and mine.Points or 0}`
	reveal.Points.Detail.Text = if mine and mine.Correct
		then (if mine.First then `{mine.Points - 1} + first bonus` else `{mine.Points} points`)
		else "No points this round"

	local function fillPick(card, pick, name)
		card.Title.Text = if pick and pick.Picked then `{name} picked {pick.Picked.Name}` else `{name} didn't answer`
		card.Result.Text = describe(pick, tiers)
		local look = if pick and pick.Correct then MARK.Correct else MARK.Wrong
		card.Mark.BackgroundColor3 = look.Bg
		card.Mark.Icon.ImageRectOffset = look.Rect
	end
	fillPick(reveal.Picks.You, mine, "You")
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LOCAL_PLAYER.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok then
			reveal.Picks.You.Avatar.Thumbnail.Image = img
		end
	end)
	local hasRival = rivalPick ~= nil
	reveal.Picks.Rival.Visible = hasRival
	if reveal.Picks:FindFirstChild("RivalShadow") then
		reveal.Picks.RivalShadow.Visible = hasRival
	end
	if hasRival then
		fillPick(reveal.Picks.Rival, rivalPick, if self.Solo then "You" else (self.Rival and self.Rival.Name or "Rival"))
		if self.Rival then
			task.spawn(function()
				local ok, img = pcall(Players.GetUserThumbnailAsync, Players, self.Rival.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				if ok then
					reveal.Picks.Rival.Avatar.Thumbnail.Image = img
				end
			end)
		end
	end

	self.Scoreboard:SetScores(packet.Scores[ME] or 0, rivalKey and packet.Scores[rivalKey] or nil)
	self.Scoreboard:SetStatus(false, "")
	self.Scoreboard:SetStatus(true, "")

	task.delay(0.6, function()
		controls.Visible = false
		reveal.Visible = true
	end)
	local nextIn = packet.Next or 0
	reveal.NextRound.Visible = nextIn > 0
	if nextIn > 0 then
		self._round:Add(task.spawn(function()
			for s = nextIn, 1, -1 do
				reveal.NextRound.Label.Text = `Next round in {s}…`
				task.wait(1)
			end
		end), true)
	end
end

-- [[ Lifecycle ]]

function Game:Activate(info, mode)
	self:_setupDuel(info, mode)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	self._frame.Visible = true
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Game:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self._round:Cleanup()
	self.Round = nil
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self._frame.Reveal.Visible = false
		self.State = "Inactive"
	end)
end

function Game:Destroy()
	self._round:Destroy()
	self._janitor:Destroy()
end

return Game
