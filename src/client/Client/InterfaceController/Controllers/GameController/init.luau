-- Round screen: scoreboard on top, snippet tiers + Play/Skip + 4 answers at the bottom,
-- and the reveal overlay between rounds.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Scoreboard = require(script.Scoreboard)
local FFABoard = require(script.FFABoard) -- Party Stage matches with 3–6 players
local PickChips = require(script.PickChips) -- reveal: who picked which answer
local Snippet = require(script.Snippet)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)

local REVEAL_FADE = 2 -- the reveal song fades out over the last this-many seconds
local LoadingCard = require(script.LoadingCard)
local EncoreBanner = require(script.EncoreBanner)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)
local PackTag = require(script.PackTag)
local RevealOwner = require(script.RevealOwner)

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
-- pick chip colours in a duel: the scoreboard avatars (Game.Scoreboard You / Rival)
local DUEL_CHIP = { You = C("FFD2CE"), Rival = C("DCD3FF") }
-- check / cross icons in atlas 0
-- reveal pick cards: the result line's colour follows the result (it used to keep the card's
-- Studio colour, so a wrong answer on your card read green)
-- the reveal's points sticker: mint for a score, pink when a wrong guess cost points
local STICKER = { Plus = C("A7E9B8"), Minus = C("FFD2CE") }
local RESULT_TEXT = {
	Correct = C("166534"),
	Wrong = C("B42318"),
	None = C("8A8497"),
}
local MARK = {
	Correct = { Bg = C("A7E9B8"), Rect = Vector2.new(300, 0) },
	Wrong = { Bg = C("FFD2CE"), Rect = Vector2.new(500, 0) },
}

local function fmt(seconds: number): string
	return if seconds < 1 then `{seconds}s` else `{math.floor(seconds)}s`
end

-- Controller: A / B / X / Y pick answers 1–4 (left to right), LB plays the clip, RB skips to
-- the next snippet. Bound above the jump button only while the round screen is up, so A
-- doesn't make you hop on the stage. While a controller is in use each answer's badge shows
-- its button and Play / Skip show their bumper (Studio: AnswerN.Badge.PadIcon,
-- PlayButton.PadIcon, Skip.PadIcon; drawn by Modules/UI/PadBinds).
local PAD_ACTION = "GamePad"
local PAD_ANSWERS = { Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY }
local PAD_PLAY = Enum.KeyCode.ButtonL1
local PAD_SKIP = Enum.KeyCode.ButtonR1

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
	if UserInputService.TouchEnabled then
		for _, item in self._frame.Reveal.Answer:GetDescendants() do
			if item:IsA("TextLabel") and item.Text == "THE ANSWER" then
				item.TextScaled = false
				item.TextSize = 14
			end
		end
	end
	ButtonScale.ApplyToDescendants(self._frame.Controls)
	local controls = self._frame.Controls
	self.Loader = LoadingCard.new(self._frame, controls.PlayButton)
	self.Encore = EncoreBanner.new(self._frame)

	self._janitor:Add(controls.PlayButton.Activated:Connect(function()
		self:_play()
	end))
	self._janitor:Add(controls.Skip.Activated:Connect(function()
		self:_skip()
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

	-- controller button icons, swapped in while a controller is the last thing used
	self._janitor:Add(UserInputService.LastInputTypeChanged:Connect(function()
		self:_paintPad()
	end))
	self:_paintPad()
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
	-- a Party Stage free-for-all (3+ players) uses the FFA ticket instead of you-vs-rival
	local count = 0
	for _ in (info and info.Players or {}) do
		count += 1
	end
	local board = self._frame:FindFirstChild("FFABoard")
	self.FFA = nil
	if info and info.Party and count > 2 and board then
		local party = LOCAL_PLAYER:GetAttribute("PartyStage")
		local title = if type(party) == "string" then (party:gsub("PartyStage", "Party Stage ")) else "Party Stage"
		self.FFA = FFABoard.new(board, info.Players, `{title} · free-for-all · {count} players`)
		self.FFA:Initialize(7)
	end
	self._frame.Scoreboard.Visible = self.FFA == nil
	if board then
		board.Visible = self.FFA ~= nil
	end
	local stageName = LOCAL_PLAYER:GetAttribute("Stage")
	local map = workspace:FindFirstChild("Map")
	self.StageModel = stageName and map and ((map:FindFirstChild("DuelStages") and map.DuelStages:FindFirstChild(stageName)) or (map:FindFirstChild("PartyStages") and map.PartyStages:FindFirstChild(stageName)))
	self._frame.Controls.Visible = true
	self._frame.Reveal.Visible = false
end

-- [[ Rounds ]]

-- The snippet outlives its round so the reveal can play the song; it's swapped here.
function Game:_dropSnippet()
	if self.Snippet then
		-- never cut the song off dead: a short fade if it's still playing
		self.Snippet:FadeAndDestroy(0.4)
		self.Snippet = nil
	end
end

-- The final round's ENCORE moment (./EncoreBanner): the server waits ENCORE_INTRO seconds
-- after sending this before the round itself starts.
function Game:OnEncore(packet)
	self:_revealAnswers(false)
	self._frame.Reveal.Visible = false
	self.Encore:Play(packet)
end

function Game:OnRound(packet)
	self.Encore:Hide()
	self._round:Cleanup()
	self:_dropSnippet()
	local controls = self._frame.Controls
	self._frame.Reveal.Visible = false
	self:_revealAnswers(false)
	controls.Visible = true

	self.Round = {
		Number = packet.Round,
		Tiers = packet.Tiers,
		Points = packet.Points,
		Penalty = packet.Penalty or {}, -- tier → points a wrong answer loses
		Multiplier = packet.Multiplier or 1,
		Options = packet.Options,
		Tier = 1,
		Guessed = nil :: number?,
		Ready = false, -- nothing can be clicked until the clip has loaded
		OwnedTag = packet.OwnedTag, -- who owns the song: shown on the reveal (./RevealOwner)
	}
	self.Scoreboard.Rounds = packet.Rounds
	self.Scoreboard:UpdateRound(packet.Round, packet.Multiplier)
	if self.FFA then
		self.FFA.Rounds = packet.Rounds
		self.FFA:UpdateRound(packet.Round)
		self.FFA:SetAll("Listening…")
	end
	PackTag.Set(self._frame, nil, packet.Theme) -- ownership shows on the reveal now, not during the round
	self.Scoreboard:SetStatus(false, "Loading…")
	self.Scoreboard:SetStatus(true, "Listening…")

	local snippet = Snippet.new(packet.Clip, packet.Mode, self.StageModel)
	self.Snippet = snippet
	controls.Interactable = false
	self.Loader:HideReady()
	self.Loader:ShowLoading(packet.Round, packet.Mode, packet.Multiplier)
	if packet.Swapped then
		self.Loader:SetText("Loading audio…", "That clip wouldn't load, so here's another song")
	end

	for i = 1, 4 do
		local answer = controls.Answers:FindFirstChild("Answer" .. i)
		local opt = packet.Options[i]
		if answer then
			answer.Visible = opt ~= nil
			if opt then
				answer.Title.Text = opt.Name
				answer.Artist.Text = opt.Artist
				answer.BackgroundColor3 = ANSWER_LOOK.Idle
				answer.AutoButtonColor = false
			end
		end
	end
	self:_paintPad() -- the badges' numbers (or controller letters)
	controls.RivalAnswered.Visible = false
	controls.Timer.Visible = false
	self:_paintTiers()

	-- wait for the clip to load and tell the server; the round (and its clock) starts when
	-- the server says everyone's loaded ("RoundGo")
	local round = self.Round
	self._round:Add(task.spawn(function()
		snippet:WaitReady()
		if self.Round ~= round then
			return
		end
		round.Loaded = true
		-- Failed: the server swaps in another song (a new Round packet) or, out of swaps,
		-- starts the round anyway
		DuelRemote:Fire({ Action = "Loaded", Round = round.Number, Attempt = packet.Attempt, Failed = snippet.Failed })
		if snippet.Failed and not round.Go then
			self.Loader:SetText("Loading audio…", "That clip wouldn't load, finding another song")
		elseif round.Go then
			self:_unlockRound(round)
		elseif not self.Solo then
			self.Loader:SetText("Waiting for your rival…", "Your clip's ready — theirs is still loading")
		end
	end), true)
end

-- The server's go signal: everyone has loaded (or the load timeout passed).
function Game:OnRoundGo(packet)
	local round = self.Round
	if not round or round.Number ~= packet.Round then
		return
	end
	round.Go = true
	round.Cap = packet.Cap or 20
	if round.Loaded then
		self:_unlockRound(round)
	end
end

-- Controls on, prompt to press play, and the round-cap countdown from now.
function Game:_unlockRound(round)
	if round.Ready then
		return
	end
	local controls = self._frame.Controls
	round.Ready = true
	controls.Interactable = true
	self.Loader:HideLoading()
	if not round.Guessed then
		self.Scoreboard:SetStatus(false, "Listening…")
		-- no auto-play: nudge the player to press play themselves
		self.Loader:ShowReady()
	end
	-- round cap countdown (only shown when it gets close)
	local cap = round.Cap or 20
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
			-- risky tiers also say what a wrong answer costs (Points is RichText in Studio);
			-- only while that tier is still ahead of you
			local cost = r.Penalty[i] or 0
			b.Points.Text = if cost > 0 and i >= r.Tier
				then `+{r.Points[i]}<br/><font size="10" color="#B42318">−{cost} if wrong</font>`
				else `+{r.Points[i]}`
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
	if not r or not r.Ready or r.Guessed or tier <= r.Tier then
		return
	end
	r.Tier = tier
	DuelRemote:Fire({ Action = "Unlock", Tier = tier })
	self:_paintTiers()
end

function Game:_skip()
	local r = self.Round
	if r and r.Tier < #r.Tiers then
		self:_unlock(r.Tier + 1)
		self:_play()
	end
end

-- [[ Controller ]]

function Game:_padInput(_, state: Enum.UserInputState, input: InputObject)
	if state == Enum.UserInputState.Begin then
		local answer = table.find(PAD_ANSWERS, input.KeyCode)
		if answer then
			self:_guess(answer)
		elseif input.KeyCode == PAD_PLAY then
			self:_play()
		elseif input.KeyCode == PAD_SKIP then
			self:_skip()
		end
	end
	return Enum.ContextActionResult.Sink
end

function Game:_paintPad()
	local pad = PadBinds.UsingPad()
	local controls = self._frame.Controls
	for i, key in PAD_ANSWERS do
		local answer = controls.Answers:FindFirstChild("Answer" .. i)
		local badge = answer and answer:FindFirstChild("Badge")
		local number = badge and badge:FindFirstChild("Number")
		if number then
			number.Text = tostring(i)
			PadBinds.Paint(badge:FindFirstChild("PadIcon"), key, pad)
			number.Visible = not pad
		end
	end
	PadBinds.Paint(controls.PlayButton:FindFirstChild("PadIcon"), PAD_PLAY, pad)
	PadBinds.Paint(controls.Skip:FindFirstChild("PadIcon"), PAD_SKIP, pad)
end

function Game:_play()
	local r = self.Round
	if r and r.Ready and self.Snippet then
		self.Loader:HideReady()
		self.Snippet:Play(r.Tiers[r.Tier])
	end
end

function Game:_guess(index: number)
	local r = self.Round
	if not r or not r.Ready or r.Guessed or not r.Options[index] then
		return
	end
	r.Guessed = index
	self.Loader:HideReady()
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
	if self.FFA then
		self.FFA:SetStatus(LOCAL_PLAYER.UserId, "Answered!", "you")
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

-- Party matches: someone answered (the FFA ticket marks them)
function Game:OnPlayerAnswered(userId: number)
	if self.FFA and userId ~= LOCAL_PLAYER.UserId then
		self.FFA:SetStatus(userId, "Answered!")
	end
end

-- [[ Reveal ]]

function Game:OnRoundEnd(packet)
	local r = self.Round
	self._round:Cleanup()
	self.Round = nil
	local reveal = self._frame.Reveal
	local controls = self._frame.Controls
	controls.Interactable = true
	self.Loader:HideAll()

	-- the answer's out: play the song (or the dance) properly
	if self.Snippet then
		local snippet = self.Snippet
		snippet:PlayFull()
		-- fade it out so it's gone just as the reveal ends
		task.delay(math.max(DuelConstants.REVEAL_TIME - REVEAL_FADE, 0.5), function()
			if self.Snippet == snippet then
				snippet:FadeOut(REVEAL_FADE)
			end
		end)
	end

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
	RevealOwner.Set(reveal, r and r.OwnedTag) -- the owner's tier finish + "Owned by …"
	reveal.Answer.Meta.Text = if packet.Answer.Year then `{packet.Answer.Artist} · {packet.Answer.Year} · {packet.Answer.Generation or ""} Gen` else `{packet.Answer.Artist} · {packet.Answer.Generation or ""} Gen`

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
	if self.FFA then
		-- everyone's result is on the FFA ticket; the reveal card is just yours, centred
		rivalKey, rivalPick = nil, nil
		self.FFA:OnRoundEnd(packet)
	end
	-- who picked what: avatar chips on the answers, which stay up over the reveal (every mode;
	-- a duel's chips take the scoreboard's avatar colours)
	local chipOrder = if self.FFA then self.FFA.Order else {}
	if not self.FFA then
		if self.Me then
			table.insert(chipOrder, { UserId = self.Me.UserId, Name = self.Me.Name, Colour = DUEL_CHIP.You })
		end
		if self.Rival then
			table.insert(chipOrder, { UserId = self.Rival.UserId, Name = self.Rival.Name, Colour = DUEL_CHIP.Rival })
		end
	end
	PickChips.Show(controls.Answers, r and r.Options, packet.Picks, chipOrder)
	self:_revealLayout(self.FFA ~= nil)

	local function describe(pick, tiers)
		if not pick or not pick.Picked then
			return "No answer · 0 points"
		end
		if not pick.Correct then
			-- an early wrong guess costs points (DuelConstants.WRONG_PENALTY)
			return if (pick.Points or 0) < 0 then `Wrong · −{-pick.Points} points` else "Wrong · 0 points"
		end
		local t = tiers and tiers[pick.Tier]
		local s = `Correct on the {t and fmt(t) or "?"} tier`
		if pick.First then
			s ..= " · first!"
		end
		return s
	end
	local tiers = r and r.Tiers

	local got = (mine and mine.Points or 0) + 0 -- (+ 0 turns a -0 into 0, never "+-0")
	local mult = packet.Multiplier or 1
	reveal.Points.Value.Text = if got < 0 then `−{-got}` else `+{got}`
	reveal.Points.BackgroundColor3 = if got < 0 then STICKER.Minus else STICKER.Plus
	-- the caption is narrow (124 px): ENCORE says so instead of the breakdown
	reveal.Points.Detail.Text = if got == 0 then "No points this round"
		elseif mult > 1 then `ENCORE ×{mult}`
		elseif got < 0 then "Wrong too early"
		elseif mine and mine.First then `{got - 1} + first bonus`
		else `{got} points`

	local function fillPick(card, pick, name)
		card.Title.Text = if pick and pick.Picked then `{name} picked {pick.Picked.Name}` else `{name} didn't answer`
		card.Result.Text = describe(pick, tiers)
		card.Result.TextColor3 = if pick and pick.Correct then RESULT_TEXT.Correct
			elseif pick and pick.Picked then RESULT_TEXT.Wrong
			else RESULT_TEXT.None
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
		if self.Round then
			return -- the next round already started
		end
		self:_revealAnswers(true)
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

-- Reveal: the answer row stays up over it (the rest of the controls hide) so the pick chips
-- can show; `false` puts everything back for the next round.
function Game:_revealAnswers(on: boolean)
	local controls = self._frame.Controls
	if on then
		self._hiddenControls = {}
		for _, child in controls:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "Answers" and child.Visible then
				child.Visible = false
				table.insert(self._hiddenControls, child)
			end
		end
		controls.Visible = true
		controls.Interactable = false -- nothing to click on a reveal
		if controls:GetAttribute("BaseZ") == nil then
			controls:SetAttribute("BaseZ", controls.ZIndex)
		end
		controls.ZIndex = self._frame.Reveal.ZIndex + 1 -- above the reveal's scrim
		return
	end
	for _, child in self._hiddenControls or {} do
		child.Visible = true
	end
	self._hiddenControls = nil
	local z = controls:GetAttribute("BaseZ")
	if z then
		controls.ZIndex = z
	end
	controls.Interactable = true
	PickChips.Clear(controls.Answers)
end

-- The reveal's own layout: the pick cards sit a little higher and "Next round in …" goes
-- between them and the answer row (clear of the pick chips). A duel has both cards side by
-- side; FFA centres yours. Each element remembers its Studio spot.
local FFA_PICKS_Y, FFA_NEXT_Y = 432, 524 -- (every mode now, not just FFA)
function Game:_revealLayout(ffa: boolean)
	local reveal = self._frame.Reveal
	local picks = reveal.Picks
	local function base(inst: GuiObject): UDim2
		local saved = inst:GetAttribute("BasePosition")
		if saved == nil then
			inst:SetAttribute("BasePosition", inst.Position)
			saved = inst.Position
		end
		return saved
	end
	local pb = base(picks)
	picks.Position = UDim2.new(pb.X.Scale, pb.X.Offset, 0, FFA_PICKS_Y)
	local you, youShadow = picks.You, picks:FindFirstChild("YouShadow")
	local dx = if ffa then math.floor((picks.Size.X.Offset - you.Size.X.Offset) / 2) - base(you).X.Offset else 0
	you.Position = base(you) + UDim2.fromOffset(dx, 0)
	if youShadow then
		youShadow.Position = base(youShadow) + UDim2.fromOffset(dx, 0)
	end
	local nextRound = reveal.NextRound
	local nb = base(nextRound)
	nextRound.Position = UDim2.new(nb.X.Scale, nb.X.Offset, 0, FFA_NEXT_Y)
end

-- [[ Lifecycle ]]

function Game:Activate(info, mode)
	self:_setupDuel(info, mode)
	ContextActionService:BindActionAtPriority(PAD_ACTION, function(...)
		return self:_padInput(...)
	end, false, Enum.ContextActionPriority.High.Value, PAD_PLAY, PAD_SKIP, table.unpack(PAD_ANSWERS))
	self:_paintPad()
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
	ContextActionService:UnbindAction(PAD_ACTION)
	self._round:Cleanup()
	self:_dropSnippet()
	self:_revealAnswers(false)
	self._frame.Controls.Interactable = true
	self.Loader:HideAll()
	self.Encore:Destroy()
	self.Round = nil
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self._frame.Reveal.Visible = false
		self.State = "Inactive"
	end)
end

function Game:Destroy()
	if self.Loader then
		self.Loader:Destroy()
	end
	if self.Encore then
		self.Encore:Destroy()
	end
	self._round:Destroy()
	self._janitor:Destroy()
end

return Game
