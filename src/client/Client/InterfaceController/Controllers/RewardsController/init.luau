--| RewardsController ("Rewards")
-- The Rewards screen (Interface.Frames.Rewards, built by ./Build from the "Rewards — Level
-- rewards" + "Rewards — Quests" boards): level rewards (six cards a page), daily / weekly
-- quests (tabs, one free swap a day, a bonus per tab), the daily login ladder and the one-time
-- group reward. All the rules live in Constants/RewardsCatalog; claims are requests to
-- RewardsService.
-- Also keeps the HUD Rewards badge up to date (how many things are ready to claim), even
-- while the screen is closed.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GroupService = game:GetService("GroupService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Catalog = require(ReplicatedStorage.Constants.RewardsCatalog)
local ShopCatalog = require(ReplicatedStorage.Constants.ShopCatalog)
local Levels = require(ReplicatedStorage.Modules.Levels)
local TierShine = require(ReplicatedStorage.Modules.UI.TierShine)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local CosmeticView = require(ReplicatedStorage.Modules.UI.CosmeticView)

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
local SAND = C("F3EEE5")
local LILAC = C("B9A6FF")
local HEAD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

local PER_PAGE = Build.LEVEL_CARDS
local KIND_NAMES = { Coins = { "coin", "coins" }, Tickets = { "ticket", "tickets" }, Upgrades = { "upgrade", "upgrades" } }

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
	self._tab = "Daily" -- quests tab
	self._page = nil :: number? -- level rewards page (nil = pick the page to show)
	return (self :: any) :: UITypes.Controller
end

-- [[ State ]]

-- One tab's quests with progress, from the client data copy. Counters from an older day /
-- week read as 0 (the server rolls them over on the next write). Returns the list, whether the
-- tab's bonus is claimed, and (daily) whether today's swap is used.
function Rewards:_quests(scope: string)
	local t = now()
	local list, counters, claimedSet, fresh
	if scope == "Weekly" then
		fresh = get(PlayerData.Rewards.QuestWeek, -1) == Catalog.Week(t)
		list = Catalog.WeeklyFor(Catalog.Week(t))
		counters, claimedSet = PlayerData.Rewards.WeekQuest, PlayerData.Rewards.WeekClaimed
	else
		local today = Catalog.Day(t)
		fresh = get(PlayerData.Rewards.QuestDay, -1) == today
		local from = if fresh then get(PlayerData.Rewards.QuestSwapFrom, "") else ""
		local to = if fresh then get(PlayerData.Rewards.QuestSwapTo, "") else ""
		list = Catalog.DailyQuests(today, from, to)
		counters, claimedSet = PlayerData.Rewards.Quest, PlayerData.Rewards.QuestClaimed
	end
	local out = {}
	for _, q in list do
		local have = if fresh then get(counters[q.Stat], 0) else 0
		local claimed = fresh and has(claimedSet, q.Id)
		table.insert(out, { Quest = q, Have = math.min(have, q.Need), Done = have >= q.Need, Claimed = claimed })
	end
	local swapUsed = scope == "Daily" and fresh and get(PlayerData.Rewards.QuestSwapFrom, "") ~= ""
	return out, fresh and has(claimedSet, "Bonus"), swapUsed
end

-- quests + bonus ready to claim on one tab
function Rewards:_questsReady(scope: string): number
	local quests, bonusClaimed = self:_quests(scope)
	local n, claimedAll = 0, true
	for _, q in quests do
		if q.Done and not q.Claimed then
			n += 1
		end
		claimedAll = claimedAll and q.Claimed
	end
	if claimedAll and not bonusClaimed then
		n += 1
	end
	return n
end

function Rewards:_daily()
	return Catalog.DailyState(get(PlayerData.Rewards.DailyStreak, 0), get(PlayerData.Rewards.LastDailyClaim, 0), now())
end

function Rewards:_level(): (number, number, number)
	return Levels.FromXP(get(PlayerData.Player.XP, 0))
end

-- level rewards reached and not claimed yet
function Rewards:_levelsReady(): number
	local level = self:_level()
	local n = 0
	for _, r in Catalog.LEVEL_REWARDS do
		if r.Level <= level and not has(PlayerData.Rewards.LevelClaimed, tostring(r.Level)) then
			n += 1
		end
	end
	return n
end

-- How many things can be claimed right now (HUD badge + header chip).
function Rewards:_readyCount(): number
	local n = self:_questsReady("Daily") + self:_questsReady("Weekly") + self:_levelsReady()
	if (self:_daily()) then
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

-- the group card's ink button (the group card keeps its own look)
local function styleButton(b: TextButton, state: "Ready" | "Done" | "Waiting", label: string)
	b.Text = label
	b.Active = state == "Ready"
	if state == "Ready" then
		b.BackgroundColor3 = INK
		b.TextColor3 = YELLOW
		b.FontFace = HEAD
	elseif state == "Done" then
		b.BackgroundColor3 = DONE
		b.TextColor3 = MUTED
		b.FontFace = BODY
	else
		b.BackgroundColor3 = WHITE
		b.TextColor3 = MUTED
		b.FontFace = BODY
	end
end

-- Season Track claim buttons: mint CLAIM, cream ✓ CLAIMED (same size), white for waiting
-- [[ Claim easing ]] state changes glide instead of snapping: colours cross-fade, the claimed
-- card settles with a soft punch (no elastic wobble), shadows fade.
local EASE = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SETTLE_UP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SETTLE_DOWN = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tween(inst: Instance, props: { [string]: any }, info: TweenInfo?): Tween
	local tw = TweenService:Create(inst, info or EASE, props)
	tw:Play()
	return tw
end

-- grow a touch then ease back, around the object's centre
local function settle(gui: GuiObject?, amount: number?)
	if not gui then
		return
	end
	if gui.AnchorPoint ~= Vector2.new(0.5, 0.5) and not (gui.Parent and gui.Parent:FindFirstChildOfClass("UIListLayout")) then
		local a, size = gui.AnchorPoint, gui.Size
		gui.AnchorPoint = Vector2.new(0.5, 0.5)
		gui.Position += UDim2.new(size.X.Scale * (0.5 - a.X), size.X.Offset * (0.5 - a.X), size.Y.Scale * (0.5 - a.Y), size.Y.Offset * (0.5 - a.Y))
	end
	local s = gui:FindFirstChild("ClaimScale") :: UIScale?
	if not s then
		local existing = gui:FindFirstChildOfClass("UIScale")
		s = existing or Instance.new("UIScale")
		if not existing then
			(s :: UIScale).Name = "ClaimScale";
			(s :: UIScale).Parent = gui
		end
	end
	local up = tween(s :: UIScale, { Scale = 1 + (amount or 0.06) }, SETTLE_UP)
	up.Completed:Once(function()
		tween(s :: UIScale, { Scale = 1 }, SETTLE_DOWN)
	end)
end

-- Season Track claim buttons: mint CLAIM, cream ✓ CLAIMED (same size), white for waiting.
-- A change of state cross-fades the colour.
local function styleClaim(b: TextButton, state: "Ready" | "Claimed" | "Waiting", label: string?)
	local before = b:GetAttribute("ClaimState")
	b:SetAttribute("ClaimState", state)
	b.Active = state == "Ready"
	b.TextColor3 = if state == "Ready" then INK else MUTED
	b.FontFace = if state == "Waiting" then BODY else HEAD
	local colour
	if state == "Ready" then
		colour, b.Text = MINT, label or "CLAIM"
	elseif state == "Claimed" then
		colour, b.Text = SAND, "✓ CLAIMED"
	else
		colour, b.Text = WHITE, label or "LOCKED"
	end
	if before ~= nil and before ~= state and b.Visible then
		tween(b, { BackgroundColor3 = colour })
	else
		b.BackgroundColor3 = colour
	end
end

-- reward chips (Chip1, Chip2…) in `holder` from a reward table, with the currency icons
local function paintChips(holder: Instance, reward)
	local list = Catalog.RewardList(reward)
	for i = 1, 2 do
		local chip = holder:FindFirstChild("Chip" .. i)
		local r = list[i]
		if chip then
			chip.Visible = r ~= nil
			if r then
				chip.Text = `+{r.Amount}`
				chip.BackgroundColor3 = C(Build.REWARD_CHIP[r.Kind] or "FFE07A")
				chip.Icon.Image = Build.ICONS[r.Kind] or Build.ICONS.Coins
			end
		end
	end
end

-- the shop's coin pile that fits an amount (bigger rewards, bigger pile)
local function pileFor(amount: number): string
	local bundles = ShopCatalog.CoinBundles
	local i = if amount <= 150 then 1 elseif amount <= 400 then 2 elseif amount <= 700 then 3 else 4
	return bundles[i].Pile
end

-- XP still needed to reach `target` from `level` + `into`
local function xpTo(level: number, into: number, target: number): number
	local n = -into
	for l = level, target - 1 do
		n += Levels.XPToNext(l)
	end
	return math.max(0, n)
end

function Rewards:_fillLevels()
	local s = self._frame.Panel.Body.Content.Levels
	local level, into, need = self:_level()
	local list = Catalog.LEVEL_REWARDS
	local pages = math.ceil(#list / PER_PAGE)
	if not self._page then
		-- first page with something to claim, else the page with the next reward
		local pick
		for i, r in list do
			local claimed = has(PlayerData.Rewards.LevelClaimed, tostring(r.Level))
			if (r.Level <= level and not claimed) or (not pick and r.Level > level) then
				pick = i
				if r.Level <= level then
					break
				end
			end
		end
		self._page = math.ceil((pick or #list) / PER_PAGE)
	end
	self._page = math.clamp(self._page, 1, pages)
	local first = (self._page - 1) * PER_PAGE + 1

	local h = s.Heading
	h.LevelChip.Text = `LV {level}`
	h.XPBar.Fill.Size = UDim2.fromScale(if level >= Levels.MAX_LEVEL then 1 else math.clamp(into / need, 0, 1), 1)
	h.XPText.Text = if level >= Levels.MAX_LEVEL then "MAX LEVEL" else `{into} / {need} XP`

	local pager = s.Pager
	local lastOnPage = list[math.min(first + PER_PAGE - 1, #list)]
	pager.Page.Text = `Levels {list[first].Level}–{lastOnPage.Level} · {self._page}/{pages}`
	pager.Prev.Active, pager.Prev.TextTransparency = self._page > 1, if self._page > 1 then 0 else 0.6
	pager.Next.Active, pager.Next.TextTransparency = self._page < pages, if self._page < pages then 0 else 0.6
	local ready = self:_levelsReady()
	styleClaim(pager.ClaimAll, if ready > 0 then "Ready" else "Waiting", if ready > 0 then `CLAIM ALL ({ready})` else "CLAIM ALL")

	local lastReached = 0
	local nextShown = false
	local settled = 0
	for i = 1, PER_PAGE do
		local r = list[first + i - 1]
		local holder = s.Cards["Card" .. i]
		local node = s.Track["Node" .. i]
		holder.Visible = r ~= nil
		node.Visible = r ~= nil
		if not r then
			continue
		end
		local face = holder.Face
		local claimed = has(PlayerData.Rewards.LevelClaimed, tostring(r.Level))
		local reached = r.Level <= level
		local isReady = reached and not claimed
		if reached then
			lastReached = i
		end
		face:SetAttribute("Level", r.Level)
		face.Number.Text = `LV {r.Level}`

		-- the level's one reward: a title, or a currency
		local title = r.Reward.Title
		local main = if title then { Kind = "Title", Amount = 1 } else Catalog.RewardList(r.Reward)[1]
		local art = face.Art
		art.BackgroundColor3 = C(Build.ART_BG[main.Kind] or "FFE07A")
		art.Pile.Visible = main.Kind == "Coins"
		art.Icon.Visible = main.Kind == "Tickets" or main.Kind == "Upgrades"
		art.TitleArt.Visible = title ~= nil
		if title then
			art.TitleArt.Player.Text = LOCAL_PLAYER.DisplayName
			local chip = art.TitleArt.Chip
			chip.Text = title
			-- Icon shines, Legend scrolls, the rest wear their colour (Levels.TITLE_COLOURS)
			TierShine.Apply(chip, chip.Rainbow, Levels.TITLE_TIERS[title], Levels.TITLE_COLOURS[title] or YELLOW)
			face.Amount.Text, face.Kind.Text = title, "title"
		else
			if main.Kind == "Coins" then
				art.Pile.Image = pileFor(main.Amount)
			else
				art.Icon.Image = Build.ICONS[main.Kind]
			end
			face.Amount.Text = if main.Kind == "Coins" then tostring(main.Amount) else `×{main.Amount}`
			face.Kind.Text = KIND_NAMES[main.Kind][if main.Amount == 1 then 1 else 2]
		end

		-- same card, new state (claimed just now, or just reached): animate the change
		local cardState = if claimed then "Claimed" elseif isReady then "Ready" else "Locked"
		local animate = face:GetAttribute("ShownLevel") == r.Level and face:GetAttribute("CardState") ~= cardState
		face:SetAttribute("ShownLevel", r.Level)
		face:SetAttribute("CardState", cardState)
		if not animate then
			-- a new page / first paint: no fades carried over from the last card
			face.Claim:SetAttribute("ClaimState", nil)
		end

		local chip = face.State
		if claimed then
			chip.Text, chip.BackgroundColor3 = "✓ CLAIMED", MINT
			styleClaim(face.Claim, "Claimed")
		elseif isReady then
			chip.Text, chip.BackgroundColor3 = "READY", YELLOW
			styleClaim(face.Claim, "Ready")
		elseif not nextShown then
			nextShown = true
			chip.Text, chip.BackgroundColor3 = `{xpTo(level, into, r.Level)} XP`, WHITE
			styleClaim(face.Claim, "Waiting", `REACH LV {r.Level}`)
		else
			chip.Text, chip.BackgroundColor3 = "LOCKED", WHITE
			styleClaim(face.Claim, "Waiting", `REACH LV {r.Level}`)
		end
		local shadow = holder.Shadow
		if animate then
			tween(face.UIStroke, { Thickness = if isReady then 4 else 3 })
			if isReady then
				shadow.Visible, shadow.BackgroundTransparency = true, 1
				tween(shadow, { BackgroundTransparency = 0 })
			else
				tween(shadow, { BackgroundTransparency = 1 }).Completed:Once(function()
					if face:GetAttribute("CardState") ~= "Ready" then
						shadow.Visible = false
					end
				end)
			end
			if claimed then
				-- Claim All settles the cards one after another, left to right
				task.delay(settled * 0.07, settle, face, 0.05)
				settled += 1
			end
		else
			face.UIStroke.Thickness = if isReady then 4 else 3
			shadow.Visible, shadow.BackgroundTransparency = isReady, 0
		end
		local fade = if claimed then 0.35 else 0
		for _, d in face:GetDescendants() do
			if d == face.Claim or d == chip then
				continue
			end
			if d:IsA("TextLabel") then
				if animate then tween(d, { TextTransparency = fade }) else d.TextTransparency = fade end
			elseif d:IsA("ImageLabel") then
				if animate then tween(d, { ImageTransparency = fade }) else d.ImageTransparency = fade end
			end
		end
		node.BackgroundColor3 = if claimed then LILAC elseif isReady then YELLOW else WHITE
	end
	-- the line fills up to the last level reached on this page (all the way past the page)
	local cw, gap = Build.LEVEL_W, Build.LEVEL_GAP
	local onPage = math.min(PER_PAGE, #list - first + 1)
	local fillTo = if lastReached >= onPage and list[first + onPage] and list[first + onPage].Level <= level then onPage else lastReached
	s.Track.Fill.Visible = fillTo > 1
	s.Track.Fill.Size = UDim2.fromOffset((math.max(fillTo, 1) - 1) * (cw + gap), 8)
end

function Rewards:_fillDaily()
	local s = self._frame.Panel.Body.Content.Daily
	local canClaim, nextStreak, index = self:_daily()
	local streak = if canClaim then nextStreak - 1 else nextStreak
	s.Heading.Streak.Text = if streak > 0 then `Streak: day {streak}` else "Streak: start today"
	-- claimed steps this cycle: before `index` (and `index` itself once claimed today)
	local claimedUpTo = if canClaim then index - 1 else index
	s.Track.Fill.Size = UDim2.fromScale(math.clamp((claimedUpTo - 1) / (Build.DAYS - 1), 0, 1), 1)
	s.Track.Fill.Visible = claimedUpTo > 1
	for i = 1, Build.DAYS do
		local claimed = i <= claimedUpTo
		local ready = canClaim and i == index
		local holder = s.Days["Day" .. i]
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
			styleClaim(face.Claim, "Claimed")
		elseif ready then
			styleClaim(face.Claim, "Ready")
		else
			local days = i - index
			styleClaim(face.Claim, "Waiting", if days <= 1 then "Tomorrow" else `In {days} days`)
		end
		local dot = s.Dots["Dot" .. i]
		dot.BackgroundColor3 = if claimed then DONE elseif ready then MINT elseif i == Build.DAYS then YELLOW else WHITE
	end
end

-- a quest's stat icon: a season icon, or a cell in the UI atlas
local function paintQuestIcon(img: ImageLabel, stat: string)
	local spec = Build.QUEST_ICONS[stat] or Build.QUEST_ICONS.Wins
	img.Image = spec[1]
	if spec[2] then
		img.ImageRectOffset, img.ImageRectSize = spec[2], Vector2.new(96, 96)
	else
		img.ImageRectOffset, img.ImageRectSize = Vector2.zero, Vector2.zero
	end
end

function Rewards:_fillQuests()
	local s = self._frame.Panel.Body.Content.Quests
	local tab = self._tab
	local weekly = tab == "Weekly"
	local h = s.Heading
	for _, name in { "Daily", "Weekly" } do
		local b = h.Tabs[name]
		local on = name == tab
		b.BackgroundColor3 = if on then INK else WHITE
		b.TextColor3 = if on then YELLOW else INK
		local n = self:_questsReady(name)
		b.Badge.Visible = n > 0 and not on
		b.Badge.Text = tostring(n)
	end
	local left = if weekly then Catalog.WeekSecondsLeft(now()) else Catalog.SecondsLeft(now())
	h.Reset.Text = `Resets in {ShopCatalog.Countdown(left)}`

	local quests, bonusClaimed, swapUsed = self:_quests(tab)
	h.Note.Text = if weekly then "New quests every Monday." elseif swapUsed then "Today's swap is used." else "One free swap a day."
	Build.LayoutQuests(s, #quests)
	local claimedCount = 0
	for i = 1, Build.QUEST_ROWS do
		local row = s.Rows["Row" .. i]
		local q = quests[i]
		if not q then
			continue
		end
		local quest = q.Quest
		row:SetAttribute("QuestId", quest.Id)
		row.Tile.BackgroundColor3 = C(Build.QUEST_TILE[quest.Stat] or "9ED8F5")
		paintQuestIcon(row.Tile.Icon, quest.Stat)
		row.QuestTitle.Text = quest.Title
		row.Hint.Text = quest.Hint or ""
		row.Bar.Fill.Size = UDim2.fromScale(q.Have / quest.Need, 1)
		row.Bar.Fill.Visible = q.Have > 0
		row.Bar.Fill.BackgroundColor3 = if q.Done then C("3FBF6A") else C("FF5A4E")
		row.Progress.Text = if q.Done then "Done!" else `{q.Have} / {quest.Need}`
		paintChips(row.Rewards, quest.Reward)
		row.BackgroundColor3 = if q.Claimed then SAND else WHITE
		local canSwap = not weekly and not swapUsed and not q.Done and not q.Claimed
		row.Swap.Visible = canSwap
		row.Claim.Visible = not canSwap
		if q.Claimed then
			claimedCount += 1
			styleClaim(row.Claim, "Claimed")
		elseif q.Done then
			styleClaim(row.Claim, "Ready")
		else
			styleClaim(row.Claim, "Waiting", "IN PROGRESS")
		end
	end

	local bonus = s.Bonus
	bonus.BonusTitle.Text = if weekly then `WEEKLY BONUS · finish all {#quests} quests` else `BONUS · finish all {#quests} quests`
	for i = 1, Build.QUEST_ROWS do
		local pip = bonus.Pips["Pip" .. i]
		pip.Visible = i <= #quests
		pip.BackgroundColor3 = if i <= claimedCount then C("3FBF6A") else WHITE
	end
	bonus.Pips.Sub.Text = `{claimedCount} of {#quests} claimed`
	paintChips(bonus.Rewards, if weekly then Catalog.WEEKLY_BONUS else Catalog.BONUS)
	if bonusClaimed then
		styleClaim(bonus.Claim, "Claimed")
	elseif claimedCount >= #quests then
		styleClaim(bonus.Claim, "Ready")
	else
		styleClaim(bonus.Claim, "Waiting", "LOCKED")
	end
end

function Rewards:_fillGroup()
	local group = self._frame.Panel.Body.Content.GroupReward.Group
	local g = Catalog.GROUP
	if group:FindFirstChild("CoinsTile") then
		group.CoinsTile.Amount.Text = tostring(g.Coins)
		group.TitleTile.Tag.Text = g.Title
		group.Sub.Text = `{g.Coins} coins, the Group Exclusive stage and the {g.Title} title. Join our Roblox group, then claim. One time only.`
		CosmeticView.Show(group.StageTile.Art, "Stage", g.Stage) -- the real stage + your avatar
	end
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
	self:_fillLevels()
	self:_fillQuests()
	self:_fillDaily()
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
	local function claim(pending: Instance, packet)
		self._pending = pending
		RewardsRemote:Fire(packet)
	end

	-- level rewards
	local levels = content.Levels
	j:Add(levels.Pager.Prev.Activated:Connect(function()
		if levels.Pager.Prev.Active then
			self._page = (self._page or 1) - 1
			Sounds.Play("Click")
			self:_refresh()
		end
	end))
	j:Add(levels.Pager.Next.Activated:Connect(function()
		if levels.Pager.Next.Active then
			self._page = (self._page or 1) + 1
			Sounds.Play("Click")
			self:_refresh()
		end
	end))
	j:Add(levels.Pager.ClaimAll.Activated:Connect(function()
		if levels.Pager.ClaimAll.Active then
			claim(levels.Pager.ClaimAll, { Action = "ClaimLevels" })
		end
	end))
	for i = 1, Build.LEVEL_CARDS do
		local face = levels.Cards["Card" .. i].Face
		j:Add(face.Claim.Activated:Connect(function()
			if face.Claim.Active then
				claim(face, { Action = "ClaimLevel", Level = face:GetAttribute("Level") })
			end
		end))
	end

	-- quests
	local quests = content.Quests
	for _, name in { "Daily", "Weekly" } do
		j:Add(quests.Heading.Tabs[name].Activated:Connect(function()
			if self._tab ~= name then
				self._tab = name
				Sounds.Play("Click")
				self:_refresh()
			end
		end))
	end
	for i = 1, Build.QUEST_ROWS do
		local row = quests.Rows["Row" .. i]
		j:Add(row.Claim.Activated:Connect(function()
			if row.Claim.Active then
				claim(row, { Action = "ClaimQuest", Id = row:GetAttribute("QuestId"), Scope = self._tab })
			end
		end))
		j:Add(row.Swap.Activated:Connect(function()
			if row.Swap.Visible then
				claim(row, { Action = "SwapQuest", Id = row:GetAttribute("QuestId") })
			end
		end))
	end
	j:Add(quests.Bonus.Claim.Activated:Connect(function()
		if quests.Bonus.Claim.Active then
			claim(quests.Bonus, { Action = "ClaimBonus", Scope = self._tab })
		end
	end))

	-- daily login
	for i = 1, Build.DAYS do
		local face = content.Daily.Days["Day" .. i].Face
		j:Add(face.Claim.Activated:Connect(function()
			if face.Claim.Active then
				claim(face, { Action = "ClaimDaily" })
			end
		end))
	end

	-- group reward
	local groupCard = content.GroupReward.Group
	j:Add(groupCard.Claim.Activated:Connect(function()
		if not groupCard.Claim.Active then
			return
		end
		if self._inGroup then
			self._pending = groupCard
			RewardsRemote:Fire({ Action = "ClaimGroup" })
			return
		end
		-- not in the group: Roblox's join prompt, then claim straight away if they joined
		task.spawn(function()
			local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, Catalog.GROUP.GroupId)
			AnalyticsClient.Event("GroupJoinPrompt", 1, if not ok then "Error"
				elseif status == Enum.GroupMembershipStatus.Joined then "Joined"
				elseif status == Enum.GroupMembershipStatus.AlreadyMember then "AlreadyMember"
				elseif status == Enum.GroupMembershipStatus.JoinRequestPending then "Pending"
				else "Cancelled")
			if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
				self._inGroup = true
				self:_refresh()
				self._pending = groupCard
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
			Sounds.Play("Success")
			local pending = self._pending
			local levelCard = pending and (pending.Name == "ClaimAll" or pending:GetAttribute("ShownLevel") ~= nil)
			if pending and not levelCard then
				settle(pending, if pending.AbsoluteSize.X > 400 then 0.02 else 0.05) -- wide rows barely
			end
		else
			Sounds.Play("Wrong")
		end
		self._pending = nil
		-- CLAIM ALL and the quest bonuses get the "YOU GOT!" reveal (PurchasedController) instead
		local revealed = packet.Ok and ((packet.Action == "ClaimLevel" and packet.All) or packet.Action == "ClaimBonus")
		if self.State ~= "Inactive" and not revealed then
			self:_toast(packet.Text or "")
		end
	end), "Disconnect") -- BridgeNet2 connections have no Destroy

	for _, path in {
		PlayerData.Rewards.DailyStreak,
		PlayerData.Rewards.LastDailyClaim,
		PlayerData.Rewards.QuestDay,
		PlayerData.Rewards.QuestClaimed,
		PlayerData.Rewards.QuestSwapFrom,
		PlayerData.Rewards.QuestSwapTo,
		PlayerData.Rewards.QuestWeek,
		PlayerData.Rewards.WeekClaimed,
		PlayerData.Rewards.LevelClaimed,
		PlayerData.Rewards.Claimed,
		PlayerData.Player.XP,
	} do
		j:Add(path.Observe(function()
			self:_refresh()
		end))
	end
	for _, stat in Catalog.QUEST_STATS do
		for _, counters in { PlayerData.Rewards.Quest, PlayerData.Rewards.WeekQuest } do
			j:Add(counters[stat].Observe(function()
				self:_refresh()
			end))
		end
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
	self._page = nil -- reopen on the page worth looking at
	self:_refresh()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
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
