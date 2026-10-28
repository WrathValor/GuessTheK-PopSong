--| RewardsController ("Rewards")
-- The Rewards screen (Interface.Frames.Rewards, built by ./Build from the "Rewards" board):
-- daily login ladder, the day's 3 quests + bonus, and the one-time group reward. All the
-- rules live in Constants/RewardsCatalog; claims are requests to RewardsService.
-- Also keeps the HUD Rewards badge up to date (how many things are ready to claim), even
-- while the screen is closed.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local RewardsRemote = Bridgenet.ReferenceBridge("RewardsRemote")

local C = Color3.fromHex
local INK = C("1E1B2E")
local WHITE = C("FFFFFF")
local YELLOW = C("FFE07A")
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local DONE = C("CFC5B3")
local MUTED = C("5C566B")

local function now(): number
	return workspace:GetServerTimeNow()
end

local function get(path, fallback)
	local ok, v = pcall(path.Get)
	return if ok and v ~= nil then v else fallback
end

local function has(set, id: string): boolean
	local ok, v = pcall(set.Has, id)
	return ok and v == true
end

-- ---------------------------------- Class --------------------------------- --
local Rewards = {}
Rewards.__index = Rewards

function Rewards.new()
	local self = setmetatable({}, Rewards)
	self.Name = "Rewards"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._inGroup = false
	return (self :: any) :: UITypes.Controller
end

-- [[ State ]]

-- Today's quests with progress, from the client data copy. Counters from an older day
-- read as 0 (the server rolls them over on the next write).
function Rewards:_quests()
	local t = now()
	local today = Catalog.Day(t)
	local fresh = get(PlayerData.Rewards.QuestDay, -1) == today
	local out = {}
	for _, q in Catalog.QuestsFor(today) do
		local have = if fresh then get(PlayerData.Rewards.Quest[q.Stat], 0) else 0
		local claimed = fresh and has(PlayerData.Rewards.QuestClaimed, q.Id)
		table.insert(out, { Quest = q, Have = math.min(have, q.Need), Done = have >= q.Need, Claimed = claimed })
	end
	return out, fresh and has(PlayerData.Rewards.QuestClaimed, "Bonus")
end

function Rewards:_daily()
	return Catalog.DailyState(get(PlayerData.Rewards.DailyStreak, 0), get(PlayerData.Rewards.LastDailyClaim, 0), now())
end

-- How many things can be claimed right now (HUD badge + header chip).
function Rewards:_readyCount(): number
	local n = 0
	if (self:_daily()) then
		n += 1
	end
	local quests, bonusClaimed = self:_quests()
	local claimedAll = true
	for _, q in quests do
		if q.Done and not q.Claimed then
			n += 1
		end
		claimedAll = claimedAll and q.Claimed
	end
	if claimedAll and not bonusClaimed then
		n += 1
	end
	if self._inGroup and not has(PlayerData.Rewards.Claimed, Catalog.GROUP.ClaimedKey) then
		n += 1
	end
	return n
end

function Rewards:_updateBadge()
	local count = self:_readyCount()
	local hud = self._interface and self._interface:GetController("HUD")
	if hud and hud.SetRewardsBadge then
		hud:SetRewardsBadge(count)
	end
	if self._frame then
		local chip = self._frame.Panel.Header.TitleRow.Ready
		chip.Visible = count > 0
		chip.Text = `{count} ready to claim`
	end
end

-- [[ Drawing ]]

local function styleButton(b: TextButton, state: "Ready" | "Done" | "Waiting", label: string)
	b.Text = label
	b.Active = state == "Ready"
	if state == "Ready" then
		b.BackgroundColor3 = INK
		b.TextColor3 = YELLOW
		b.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
	elseif state == "Done" then
		b.BackgroundColor3 = DONE
		b.TextColor3 = MUTED
		b.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	else
		b.BackgroundColor3 = WHITE
		b.TextColor3 = MUTED
		b.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	end
end

function Rewards:_fillDaily()
	local content = self._frame.Panel.Body.Content
	local canClaim, nextStreak, index = self:_daily()
	local streak = if canClaim then nextStreak - 1 else nextStreak
	content.DailyHeading.Streak.Text = if streak > 0 then `Streak: day {streak}` else "Streak: start today"
	-- claimed steps this cycle: before `index` (and `index` itself once claimed today)
	local claimedUpTo = if canClaim then index - 1 else index
	content.Track.Fill.Size = UDim2.fromScale(math.clamp((claimedUpTo - 1) / (Build.DAYS - 1), 0, 1), 1)
	content.Track.Fill.Visible = claimedUpTo > 1
	for i = 1, Build.DAYS do
		local claimed = i <= claimedUpTo
		local ready = canClaim and i == index
		local holder = content.Days["Day" .. i]
		local face = holder.Face
		face.BackgroundColor3 = C(Catalog.DAY_COLOURS[i])
		face.BackgroundTransparency = if claimed then 0.3 else 0
		holder.FaceShadow.Visible = not claimed
		holder.Glow.Visible = ready
		face.Amount.Text = tostring(Catalog.DAILY[i])
		-- claimed days fade their coin stacks
		for k = 1, Build.MAX_STACKS do
			local stack = face.Coins:FindFirstChild("Stack" .. k)
			if stack then
				stack.ImageTransparency = if claimed then 0.55 else 0
			end
		end
		if claimed then
			styleButton(face.Claim, "Done", "Done")
		elseif ready then
			styleButton(face.Claim, "Ready", "CLAIM!")
		else
			local days = i - index
			styleButton(face.Claim, "Waiting", if days <= 1 then "Tomorrow" else `In {days} days`)
		end
		local dot = content.Dots["Dot" .. i]
		dot.BackgroundColor3 = if claimed then DONE elseif ready then MINT elseif i == Build.DAYS then YELLOW else WHITE
	end
end

function Rewards:_fillQuests()
	local content = self._frame.Panel.Body.Content
	content.QuestHeading.Reset.Text = `Resets in {ShopCatalog.Countdown(Catalog.SecondsLeft(now()))}`
	local quests, bonusClaimed = self:_quests()
	local claimedCount = 0
	for i = 1, Build.QUESTS do
		local card = content.Quests["Quest" .. i]
		local q = quests[i]
		card.Visible = q ~= nil
		content.Quests["Quest" .. i .. "Shadow"].Visible = q ~= nil
		if q then
			card:SetAttribute("QuestId", q.Quest.Id)
			card.BackgroundColor3 = C(Catalog.QUEST_COLOURS[i])
			card.QuestTitle.Text = q.Quest.Title
			card.Bar.Fill.Size = UDim2.fromScale(q.Have / q.Quest.Need, 1)
			card.Bar.Fill.Visible = q.Have > 0
			card.Progress.Text = `{q.Have} / {q.Quest.Need}`
			card.Reward.Text = `+{q.Quest.Reward}`
			if q.Claimed then
				claimedCount += 1
				styleButton(card.Claim, "Done", "Claimed")
			elseif q.Done then
				styleButton(card.Claim, "Ready", "CLAIM!")
			else
				styleButton(card.Claim, "Waiting", "In progress")
			end
		end
	end
	local bonus = content.Bonus
	bonus.Reward.Text = `+{Catalog.BONUS}`
	bonus.Sub.Text = `{claimedCount} of {Build.QUESTS} claimed`
	if bonusClaimed then
		styleButton(bonus.Claim, "Done", "Claimed")
	elseif claimedCount >= Build.QUESTS then
		styleButton(bonus.Claim, "Ready", "CLAIM!")
	else
		styleButton(bonus.Claim, "Waiting", "Locked")
	end
end

function Rewards:_fillGroup()
	local group = self._frame.Panel.Body.Content.Group
	local g = Catalog.GROUP
	group.GroupTitle.Text = `{g.Coins} coins + Group Exclusive stage + "{g.Title}" title`
	if has(PlayerData.Rewards.Claimed, g.ClaimedKey) then
		styleButton(group.Claim, "Done", "Claimed")
	elseif self._inGroup then
		styleButton(group.Claim, "Ready", "CLAIM")
	else
		styleButton(group.Claim, "Ready", "JOIN GROUP") -- opens Roblox's join prompt
	end
end

function Rewards:_refresh()
	self:_updateBadge()
	if not self._frame.Visible then
		return
	end
	self:_fillDaily()
	self:_fillQuests()
	self:_fillGroup()
end

function Rewards:_toast(message: string)
	local toast = self._frame:FindFirstChild("Toast")
	if not toast then
		return
	end
	toast.Text = message
	toast.Visible = true
	Juice.SlideIn(toast, 24)
	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(2.2, function()
		if self._toastToken == token then
			toast.Visible = false
		end
	end)
end

-- -------------------------------- Lifecycle ------------------------------- --

function Rewards:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Rewards")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local content = panel.Body.Content
	local j = self._janitor

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for i = 1, Build.DAYS do
		local face = content.Days["Day" .. i].Face
		j:Add(face.Claim.Activated:Connect(function()
			if face.Claim.Active then
				self._pending = face
				RewardsRemote:Fire({ Action = "ClaimDaily" })
			end
		end))
	end
	for i = 1, Build.QUESTS do
		local card = content.Quests["Quest" .. i]
		j:Add(card.Claim.Activated:Connect(function()
			if card.Claim.Active then
				self._pending = card
				RewardsRemote:Fire({ Action = "ClaimQuest", Id = card:GetAttribute("QuestId") })
			end
		end))
	end
	j:Add(content.Bonus.Claim.Activated:Connect(function()
		if content.Bonus.Claim.Active then
			self._pending = content.Bonus
			RewardsRemote:Fire({ Action = "ClaimBonus" })
		end
	end))
	j:Add(content.Group.Claim.Activated:Connect(function()
		if not content.Group.Claim.Active then
			return
		end
		if self._inGroup then
			self._pending = content.Group
			RewardsRemote:Fire({ Action = "ClaimGroup" })
			return
		end
		-- not in the group: Roblox's join prompt, then claim straight away if they joined
		task.spawn(function()
			local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, Catalog.GROUP.GroupId)
			if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
				self._inGroup = true
				self:_refresh()
				self._pending = content.Group
				RewardsRemote:Fire({ Action = "ClaimGroup" })
			elseif ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
				self:_toast("Join request sent. Claim once you're accepted!")
			end
		end)
	end))

	j:Add(RewardsRemote:Connect(function(packet)
		if type(packet) ~= "table" or packet.Message ~= "Result" then
			return
		end
		if packet.Ok then
			Sounds.Play("Coins")
			if self._pending then
				Juice.Pop(self._pending, 0.12)
			end
		else
			Sounds.Play("Wrong")
		end
		self._pending = nil
		if self.State ~= "Inactive" then
			self:_toast(packet.Text or "")
		end
	end))

	for _, path in {
		PlayerData.Rewards.DailyStreak,
		PlayerData.Rewards.LastDailyClaim,
		PlayerData.Rewards.QuestDay,
		PlayerData.Rewards.QuestClaimed,
		PlayerData.Rewards.Claimed,
	} do
		j:Add(path.Observe(function()
			self:_refresh()
		end))
	end
	for _, stat in Catalog.QUEST_STATS do
		j:Add(PlayerData.Rewards.Quest[stat].Observe(function()
			self:_refresh()
		end))
	end

	-- group membership (client check is only for the badge; the server checks again)
	task.spawn(function()
		local ok, inGroup = pcall(LOCAL_PLAYER.IsInGroup, LOCAL_PLAYER, Catalog.GROUP.GroupId)
		self._inGroup = ok and inGroup == true
		self:_refresh()
	end)
	-- countdown + day rollover
	j:Add(task.spawn(function()
		while true do
			task.wait(if self.State == "Active" then 1 else 30)
			self:_refresh()
		end
	end), true)
end

function Rewards:Activate()
	self._frame.Visible = true
	self._frame.Panel.Body.CanvasPosition = Vector2.zero
	self:_refresh()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local days = self._frame.Panel.Body.Content.Days
	local list = {}
	for i = 1, Build.DAYS do
		table.insert(list, days["Day" .. i])
	end
	Juice.Stagger(list, 0.035)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Rewards:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Rewards:Destroy()
	self._janitor:Destroy()
end

return Rewards
