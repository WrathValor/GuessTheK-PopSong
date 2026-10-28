-- Pre-duel screen: rival found, stake reel spin, then a 5 s mode vote (when DuelConstants.MODE_VOTE
-- is on; while it's off the vote panel hides and the screen re-centres). A chip on the stake
-- card says whether duel packs are mixing in; in solo (with a duel pack on) it's the song
-- pool picker instead (Mix / Only my pack, remembered by the server). See ./Build.

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

-- [[ Duel packs ]]

local MINT = Color3.fromHex("A7E9B8")
local GREY = Color3.fromHex("EDE4D4")
local LILAC = Color3.fromHex("B9A6FF")
local WHITE = Color3.fromHex("FFFFFF")

-- packs = packet.Packs: { On, Names = { [slot] = name }, Solo = { Count, CanOnly, Choice }? }
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
	if type(packs) ~= "table" then
		return
	end
	local names = {}
	for _, name in packs.Names or {} do
		table.insert(names, name)
	end
	if solo then
		if packs.On and packs.Solo and pool then
			self._soloPool = table.clone(packs.Solo)
			pool.Visible = true
			poolShadow.Visible = true
			self:SetSoloPool(packs.Solo.Choice)
		end
		return
	end
	if not chip or #names == 0 then
		return -- nobody has a pack on: nothing to say
	end
	chip.Visible = true
	chip.BackgroundColor3 = if packs.On then MINT else GREY
	chip.Icon.Off.Visible = not packs.On
	if packs.On then
		table.sort(names)
		chip.Label.Text = `Packs ON · {table.concat(names, " + ")}`
	else
		-- only one side has a pack on: say who's missing one
		local mine = false
		for slot in packs.Names do
			if self._slots and self._slots[slot] == Players.LocalPlayer.UserId then
				mine = true
			end
		end
		chip.Label.Text = if mine then `Packs off · {rivalName or "Your rival"} has none on` else "Packs off · you have none on"
	end
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
	f.VS.Visible = rival ~= nil
	f.RivalFound.Visible = rival ~= nil
	f.RivalFoundShadow.Visible = rival ~= nil

	-- stake (solo: the stake is paid out as XP)
	local solo = packet.Solo
	self._solo = solo
	f.Stake.Visible = true
	f.StakeShadow.Visible = true
	f.Stake.Rule.Text = if solo then "Solo practice · win the stake as XP" else "Winner takes it · loser gets 10"
	local result = f.Stake.Result
	result.Visible = false
	local mult = if solo then 1 else (me and me.Multiplier or 1)
	result.Streak.Visible = mult > 1
	result.Streak.Label.Text = `×{mult} your streak`

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
			return if solo then `{n} XP` else `{n} coins`
		end)
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
