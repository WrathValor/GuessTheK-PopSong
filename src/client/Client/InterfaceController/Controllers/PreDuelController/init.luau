-- Pre-duel screen: rival found, stake reel spin, then a 5 s mode vote (when DuelConstants.MODE_VOTE
-- is on; while it's off the vote panel hides and the screen re-centres). A chip on the stake
-- card says whose owned songs are in play (they come up more often); in solo it names the theme
-- picked on the queue card. The old SoloPool picker stays hidden. See ./Build.
-- Party Stages use the same screen for the pot roll (no vote): the reel shows amounts already
-- times the stage's multiplier, and in a free-for-all the rival card stands for everyone else.

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
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local StakeReel = require(script.StakeReel)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")

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

-- the record chip on the stake card's bottom edge (packet.Record = { [userId] = { W, L, Last } })
local PIP_WIN, PIP_LOSS = Color3.fromHex("A7E9B8"), Color3.fromHex("FFD2CE")
function PreDuel:_fillRecord(packet, rival)
	local f = self._frame
	local chip = f:FindFirstChild("Record")
	if not chip then
		return
	end
	local show = not packet.Solo and not packet.Party and rival ~= nil
	chip.Visible = show
	local shadow = f:FindFirstChild("RecordShadow")
	if shadow then
		shadow.Visible = show
	end
	if not show then
		return
	end
	local record = packet.Record and packet.Record[tostring(LOCAL_PLAYER.UserId)]
	local name = string.upper(rival.Name or "your rival")
	if record then
		chip.Label.Text = `YOUR RECORD VS {name}`
		chip.Score.Text = `{record.W} <font color="#8A8497">–</font> {record.L}`
	else
		chip.Label.Text = `VS {name}`
		chip.Score.Text = "FIRST DUEL"
	end
	local last = record and record.Last or ""
	chip.LastLabel.Visible = last ~= ""
	for k = 1, 5 do
		local pip = chip.Pips:FindFirstChild("P" .. k)
		local r = last:sub(k, k)
		if pip then
			pip.Visible = r ~= ""
			pip.Text = r
			pip.BackgroundColor3 = if r == "W" then PIP_WIN else PIP_LOSS
		end
	end
end

function PreDuel:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "PreDuel")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)

	-- solo song pool picker
	local pool = self._frame:FindFirstChild("SoloPool")
	if pool then
		for _, choice in { "Mix", "Pack" } do
			self._janitor:Add(pool[choice].Activated:Connect(function()
				local info = self._soloPool
				if not info or info.Choice == choice then
					return
				end
				if choice == "Pack" and not info.CanOnly then
					Sounds.Play("Wrong")
					return
				end
				DuelRemote:Fire({ Action = "SoloPool", Choice = choice })
				self:SetSoloPool(choice) -- the server confirms with the same message
				Sounds.Play("Click")
			end))
		end
	end

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

-- [[ Owned songs ]]

local MINT = Color3.fromHex("A7E9B8")
local LILAC = Color3.fromHex("B9A6FF")
local WHITE = Color3.fromHex("FFFFFF")

-- packs = packet.Packs: { On, Owned = { [slot] = song count }, Theme? (solo) }
-- Owned songs come up more often; nothing is equipped, so this only says what's in play.
function PreDuel:_setupPacks(packs, solo: boolean, rivalName: string?)
	local f = self._frame
	local chip, pool = f:FindFirstChild("Packs"), f:FindFirstChild("SoloPool")
	local poolShadow = f:FindFirstChild("SoloPoolShadow")
	if chip then
		chip.Visible = false
	end
	if pool then
		pool.Visible = false
		poolShadow.Visible = false
	end
	self._soloPool = nil
	if type(packs) ~= "table" or not chip then
		return
	end
	if solo then
		-- the theme was picked on the queue card; just say what this game plays
		if packs.Theme then
			chip.Visible = true
			chip.BackgroundColor3 = MINT
			chip.Icon.Off.Visible = false
			chip.Label.Text = if packs.On then `{packs.Theme} · your songs come up more` else packs.Theme
		end
		return
	end
	if not packs.On then
		return -- nobody owns a song yet: nothing to say
	end
	local mine, theirs = 0, 0
	for slot, count in packs.Owned or {} do
		if self._slots and self._slots[slot] == Players.LocalPlayer.UserId then
			mine = count
		else
			theirs = count
		end
	end
	local parts = {}
	if mine > 0 then
		table.insert(parts, `your {mine}`)
	end
	if theirs > 0 then
		table.insert(parts, `{rivalName or "rival"}'s {theirs}`)
	end
	chip.Visible = true
	chip.BackgroundColor3 = MINT
	chip.Icon.Off.Visible = false
	-- (Party Stages send no per-player counts: just the rule)
	chip.Label.Text = if #parts > 0 then `♪ Owned songs come up more · {table.concat(parts, " + ")}` else "♪ Owned songs come up more"
end

-- With the vote panel hidden, everything else moves down so the screen stays centred.
-- Each element remembers its Studio position (BaseY), so turning the vote back on restores it.
local NO_VOTE_SHIFT = 140

function PreDuel:_layout(voteOn: boolean)
	local f = self._frame
	f.Vote.Visible = voteOn
	for _, child in f:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Scrim" and child.Name ~= "Vote" then
			local base = child:GetAttribute("BaseY")
			if base == nil then
				base = child.Position.Y.Offset
				child:SetAttribute("BaseY", base)
			end
			local p = child.Position
			child.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, base + (if voteOn then 0 else NO_VOTE_SHIFT))
		end
	end
end

function PreDuel:SetSoloPool(choice: string)
	local pool = self._frame:FindFirstChild("SoloPool")
	if not pool or not self._soloPool then
		return
	end
	self._soloPool.Choice = choice
	for _, c in { "Mix", "Pack" } do
		local b = pool[c]
		local on = c == choice
		b.BackgroundColor3 = if on then LILAC else WHITE
		b.BackgroundTransparency = if on then 0 else 0.65
	end
	pool.Pack.TextTransparency = if self._soloPool.CanOnly then 0 else 0.5
	pool.Pack.Text = if self._soloPool.CanOnly then "Only my pack" else `Only my pack ({self._soloPool.Count}/7)`
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
	card.Sub.Text = if profile.SubText then profile.SubText
		elseif profile.Streak > 0 then `Lv {profile.Level} · {profile.Streak} streak`
		else `Lv {profile.Level}`
	task.spawn(function()
		card.Avatar.Thumbnail.Image = thumb(profile.UserId)
	end)
	-- season: their banner strip + tier chip (party and solo games aren't rated)
	local player = Players:GetPlayerByUserId(profile.UserId)
	local _, tierInfo, banner = SeasonArt.Of(player)
	SeasonArt.PaintBanner(card:FindFirstChild("Banner"), banner)
	local chip = card:FindFirstChild("Tier")
	if chip then
		SeasonArt.PaintChip(chip, tierInfo)
		if self._unrated then
			chip.Label.Text = "NOT RATED"
		end
	end
end

function PreDuel:Setup(packet)
	self._session:Cleanup()
	self._unrated = packet.Party ~= nil or packet.Solo == true
	self._votes = { Song = {}, Choreography = {} }
	self._myVote = nil
	self._voteOpen = false
	local f = self._frame

	-- players: "You" is always the local player
	local me, rival
	local others = {}
	for _, profile in packet.Players do
		if profile.UserId == LOCAL_PLAYER.UserId then
			me = profile
		else
			rival = profile
			table.insert(others, profile)
		end
	end
	-- Party free-for-all: one card for the rest of the stage (first rival's photo, everyone's names)
	if packet.Party and #others > 1 then
		local names = {}
		for _, o in others do
			table.insert(names, o.Name)
		end
		rival = { UserId = others[1].UserId, Name = `{#others} rivals`, Level = others[1].Level, Streak = 0, SubText = table.concat(names, " · ") }
	end
	-- slot -> userId, so the packs chip knows whose pack is missing
	self._slots = {}
	for slot, profile in packet.Players do
		self._slots[slot] = profile.UserId
	end
	self:_setupPacks(packet.Packs, packet.Solo == true, rival and rival.Name)

	-- solo practice: you vs you, so the screen never looks empty
	if packet.Solo and me then
		rival = me
	end
	self:_fillPlayer(f.You, me)
	self:_fillPlayer(f.Rival, rival)

	-- your all-time record against this rival (Build.Record): "6 – 3" + the last five, or
	-- FIRST DUEL. Duels only (not solo or Party)
	self:_fillRecord(packet, rival)
	f.VS.Visible = rival ~= nil
	f.RivalFound.Visible = rival ~= nil
	f.RivalFoundShadow.Visible = rival ~= nil
	-- solo: the banner reads SOLO PRACTICE (RivalFound.SoloLabel) instead of RIVAL FOUND!
	local soloLabel = f.RivalFound:FindFirstChild("SoloLabel")
	if soloLabel then
		soloLabel.Visible = packet.Solo == true
		f.RivalFound.Label.Visible = packet.Solo ~= true
	end
	-- Party free-for-all: no "you vs rival" row (the whole stage is your rival)
	if packet.Party and packet.Kind ~= "Duel" then
		for _, n in { "You", "YouShadow", "Rival", "RivalShadow", "VS", "RivalFound", "RivalFoundShadow" } do
			f[n].Visible = false
		end
	end

	-- stake (solo: the stake is paid out as XP)
	local solo = packet.Solo
	self._solo = solo
	f.Stake.Visible = true
	f.StakeShadow.Visible = true
	local party = packet.Party == true
	f.Stake.Rule.Text = if solo then "Solo practice · right answers win the stake as XP"
		elseif party and packet.Kind == "Duel" then "Pot paid by place · 1st 100% · 2nd 30%"
		elseif party then "Pot paid by place · 1st 100% · 2nd 70% · 3rd 50%"
		else "Winner takes it · loser gets 10"
	local result = f.Stake.Result
	result.Visible = false
	if party then
		-- the stage's multiplier is already in the reel; the chip says what made it up
		local mult = packet.Multiplier or 1
		result.Streak.Visible = mult ~= 1
		result.Streak.Label.Text = if packet.MultiplierText ~= "" then packet.MultiplierText else `×{mult}`
	else
		local mult = if solo then 1 else (me and me.Multiplier or 1)
		result.Streak.Visible = mult > 1
		result.Streak.Label.Text = `×{mult} your streak`
	end

	-- mode vote off (Choreography isn't out yet): no vote panel, the rest sits centred
	local voteOn = packet.ModeVote ~= false
	self:_layout(voteOn)

	-- vote panel waits for the spin
	f.Vote.Timer.Seconds.Text = tostring(packet.VoteTime)
	f.Vote.TimeBar.Fill.Size = UDim2.fromScale(1, 1)
	self:_paintVotes()

	local spin = packet.SpinTime
	self._session:Add(task.spawn(function()
		-- spin: a slot-style strip slides under the pointer and lands on the stake (./StakeReel);
		-- big stakes get a sticker, shake and confetti
		result.Amount.Value.Text = if solo then "0 XP" else "0 coins"
		StakeReel.Spin(f.Stake, packet.Reel, spin, function(n)
			return if solo then `{n} XP` elseif party then `{n} coin pot` else `{n} coins`
		end, packet.Chips)
		if not voteOn then
			return
		end

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

-- One avatar chip per voter on each mode button, overlapping right-to-left, so both votes
-- show when you and your rival pick the same mode. Solo mirrors your vote (you vs you).
local CHIP_STEP = 22

function PreDuel:_voterImage(userId: number, image: ImageLabel)
	self._thumbs = self._thumbs or {}
	local cached = self._thumbs[userId]
	if cached then
		image.Image = cached
		return
	end
	task.spawn(function()
		local img = thumb(userId)
		self._thumbs[userId] = img
		if image.Parent and image:GetAttribute("UserId") == userId then
			image.Image = img
		end
	end)
end

function PreDuel:_paintVotes()
	local vote = self._frame.Vote
	for _, mode in { "Song", "Choreography" } do
		local button = vote[mode]
		local ids = table.clone(self._votes and self._votes[mode] or {})
		if self._solo and #ids == 1 then
			table.insert(ids, ids[1])
		end
		local template = button.Voter
		if template:GetAttribute("BaseX") == nil then
			template:SetAttribute("BaseX", template.Position.X.Offset)
		end
		local baseX = template:GetAttribute("BaseX")
		for _, child in button:GetChildren() do
			if child.Name:match("^VoterExtra") then
				child:Destroy()
			end
		end
		template.Visible = #ids > 0
		for i, userId in ids do
			local chip = template
			if i > 1 then
				chip = template:Clone()
				chip.Name = "VoterExtra" .. i
				chip.Parent = button
			end
			chip.Position = UDim2.new(template.Position.X.Scale, baseX - (i - 1) * CHIP_STEP, template.Position.Y.Scale, template.Position.Y.Offset)
			chip.ZIndex = template.ZIndex + (#ids - i)
			local image = chip:FindFirstChild("Avatar") :: ImageLabel?
			if not image then
				local img = Instance.new("ImageLabel")
				img.Name = "Avatar"
				img.Size = UDim2.fromScale(1, 1)
				img.BackgroundTransparency = 1
				img.ZIndex = chip.ZIndex
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = img
				img.Parent = chip
				image = img
			end
			(image :: ImageLabel).ZIndex = chip.ZIndex
			;(image :: ImageLabel):SetAttribute("UserId", userId)
			self:_voterImage(userId, image :: ImageLabel)
		end
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
	if not (packet and packet.Solo) then
		Sounds.Play("RivalFound") -- (solo: the frame's "Open" sound is enough)
	end
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
