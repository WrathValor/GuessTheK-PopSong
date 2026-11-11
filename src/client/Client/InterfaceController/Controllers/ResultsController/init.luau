-- Match results: per-round table, totals, the winner card with what you earned, Rematch / Leave.
-- Solo practice swaps the copied "rival" for its own layout: a GUESSED AT column (how much of
-- the clip you needed), a rank stamp and personal best, Play again and Find a rival.

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
local FitPanel = require(ReplicatedStorage.Modules.UI.FitPanel)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local SeasonArt = require(ReplicatedStorage.Modules.UI.SeasonArt)
local SeasonConstants = require(ReplicatedStorage.Constants.SeasonConstants)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)
local Levels = require(ReplicatedStorage.Modules.Levels)
local FavoritePrompt = require(script.Parent.Parent.Parent.FavoritePrompt) -- Client/FavoritePrompt

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ME = tostring(LOCAL_PLAYER.UserId)
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local C = Color3.fromHex
local CELL = { Correct = C("A7E9B8"), Wrong = C("FFD2CE"), None = C("EDE4D4") }
local WHITE = C("FFFFFF")

-- solo: one scale for the points chip and the clip ladder (fast = green … slow = orange)
local SOLO_FAST, SOLO_MID, SOLO_SLOW, SOLO_MISS = C("A7E9B8"), C("FFE07A"), C("FFB38A"), C("FFD2DE")
local PIP_COLOURS = { SOLO_FAST, SOLO_FAST, SOLO_MID, SOLO_SLOW, SOLO_SLOW } -- by tier used
local PIP_MISS = C("E3DEEA")
-- solo rank: share of the max score needed, best first
local GRADES = {
	{ Letter = "S", Share = 0.9, Colour = C("FF9EC4") },
	{ Letter = "A", Share = 0.7, Colour = C("FFE07A") },
	{ Letter = "B", Share = 0.5, Colour = C("9ED8F5") },
	{ Letter = "C", Share = 0.3, Colour = C("A7E9B8") },
	{ Letter = "D", Share = 0, Colour = C("B9A6FF") },
}
-- total bar stickers: duel columns sit under YOU / RIVAL; solo's "49 / 70" is wider, at the end
local STICKER = {
	You = { X = 513, Colour = C("FF8A80") },
	Rival = { X = 585, Colour = C("B9A6FF") },
	Solo = { X = 568, Width = 96, Colour = C("FFE07A") },
}
local TITLE_TAG = { Duel = C("FFE07A"), Solo = C("9ED8F5") }

-- points → snippet tier (1 = the shortest clip); nil for a miss
local function tierOf(points: number): number?
	for i, p in DuelConstants.TIER_POINTS do
		if p == points then
			return i
		end
	end
	return nil
end

local function soloColour(points: number): Color3
	return if points >= 7 then SOLO_FAST elseif points >= 5 then SOLO_MID elseif points > 0 then SOLO_SLOW else SOLO_MISS
end

local function seconds(s: number): string
	return (if s < 1 then string.format("%.1f", s) else tostring(s)) .. " s"
end

-- XP row: "XP  Lv n" and the bar (lilac = what you had, yellow = this match)
local function fillXP(row, before: number?, gained: number)
	local bar = row:FindFirstChild("Bar")
	if not before or not bar then
		row.Label.Text = "XP"
		if bar then
			bar.Visible = false
		end
		return
	end
	local lvBefore, intoBefore, need = Levels.FromXP(before)
	local lvAfter, intoAfter, needAfter = Levels.FromXP(before + gained)
	row.Label.Text = `XP  <font color="#5C566B" size="12">Lv {lvAfter}</font>`
	local old, gain
	if lvAfter > lvBefore then
		old, gain = 0, intoAfter / needAfter
	else
		old, gain = intoBefore / need, (intoAfter - intoBefore) / need
	end
	bar.Visible = true
	-- both fills are rounded pills from the left: Gain runs to the new total behind Old, so only
	-- its rounded right end shows past Old (no square ends, no notch where they meet)
	bar.Old.Size = UDim2.fromScale(old, 1)
	bar.Gain.Position = UDim2.fromScale(0, 0)
	bar.Gain.Size = UDim2.fromScale(math.clamp(old + gain, 0, 1), 1)
end

-- reveal timing: rows drop in one by one, then the totals, then the winner card
local REVEAL_DELAY = 0.45 -- lets the frame finish opening
local ROW_GAP = 0.28
local ROW_SLIDE = 36
local POP = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function scaleOf(gui: GuiObject): UIScale
	local scale = gui:FindFirstChild("RevealScale") :: UIScale?
	if not scale then
		local s = Instance.new("UIScale")
		s.Name = "RevealScale"
		s.Parent = gui
		scale = s
	end
	return scale :: UIScale
end

local Results = {}
Results.__index = Results

function Results.new()
	local self = setmetatable({}, Results)
	self.Name = "Results"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._interface = nil
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._rivalId = nil :: number?
	return (self :: any) :: UITypes.Controller
end

function Results:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Results")
	self._frame.Visible = false
	ButtonScale.ApplyToDescendants(self._frame)
	FitPanel.Watch(self._frame, self._janitor) -- bigger panel on phones, like the Shop
	local w = self._frame.Panel.Winner
	self._janitor:Add(w.Rematch.Activated:Connect(function()
		DuelRemote:Fire({ Action = "Rematch" })
		if self._solo then
			self._rematchRequested = true
			w.Rematch.Active = false
			w.RematchNote.Visible = true
			w.RematchNote.Text = "Starting…"
			return
		end
		-- duels: wait for the rival on the queue screen. The request stays open there (leaving
		-- the stage drops it), so closing this screen mustn't cancel it.
		self._rematchRequested = false
		self._staying = true -- another duel is coming: no favourite prompt yet
		self._interface:Open("Queue")
		local queue = self._interface:GetController("Queue")
		if queue then
			queue:ShowRematch()
		end
	end))
	self._janitor:Add(w.Leave.Activated:Connect(function()
		QueueRemote:Fire("Leave")
		self._interface:Close(self.Name)
	end))
	-- solo: step off and go find a real duel (the nearest stage with someone waiting)
	self._janitor:Add(w.FindRival.Activated:Connect(function()
		QueueRemote:Fire("Leave")
		QueueRemote:Fire("QuickPlay")
		self._interface:Close(self.Name)
	end))
end

function Results:Show(packet, info)
	local panel = self._frame.Panel
	local w = panel.Winner
	self._solo = packet.Solo
	self._wasDuel = not packet.Solo and not packet.Tutorial
	self._staying = false
	self._max = #packet.Rounds * DuelConstants.TIER_POINTS[1]
	self._rematchRequested = false

	local rivalKey
	for k in packet.Scores do
		if k ~= ME then
			rivalKey = k
		end
	end
	if packet.Solo then
		rivalKey = ME -- you vs you
	end
	self._rivalId = rivalKey and tonumber(rivalKey)
	local rivalName = if packet.Solo then LOCAL_PLAYER.DisplayName else "Rival"
	if info then
		for _, p in info.Players do
			if tostring(p.UserId) == rivalKey then
				rivalName = p.Name
			end
		end
	end

	local solo = packet.Solo == true
	self:_layout(solo, packet.Tutorial == true)

	-- round table
	local rows = panel.Table.Rows
	local header = panel.Table.Header
	header.ColRival.Visible = rivalKey ~= nil
	header.Song.Text = if packet.Mode == "Choreography" then "SONG · CHOREOGRAPHY" else "SONG · AUDIO"
	local ladder = DuelConstants.TIERS[packet.Mode] or DuelConstants.TIERS.Song
	local correct, fastest, fastCount, roundsWon = 0, nil :: number?, 0, 0
	for i = 1, 7 do
		local row = rows:FindFirstChild("Round" .. i)
		local round = packet.Rounds[i]
		if row then
			row.Visible = round ~= nil
			if round then
				row.Title.Text = round.Name
				row.Artist.Text = round.Artist
				local mine = round.Picks[ME]
				local function cell(frame, pick)
					frame.Visible = pick ~= nil
					if pick then
						frame.BackgroundColor3 = if solo then soloColour(pick.Points)
							elseif pick.Correct then CELL.Correct
							elseif pick.Picked then CELL.Wrong
							else CELL.None
						frame.Value.Text = if pick.Points > 0 then `+{pick.Points}` else "0"
					end
				end
				cell(row.You, mine)
				cell(row.Rival, if solo then nil elseif rivalKey then round.Picks[rivalKey] else nil)

				if solo then
					-- how much of the clip you needed: lit pips up to that tier, then its length
					local tier = mine and mine.Correct and tierOf(mine.Points) or nil
					for k = 1, 5 do
						local pip = row.Clip.Pips:FindFirstChild(tostring(k))
						if pip then
							pip.BackgroundColor3 = if not tier then PIP_MISS elseif k <= tier then PIP_COLOURS[tier] else WHITE
						end
					end
					row.Clip.Time.Text = if tier then seconds(ladder[tier]) else "Missed"
					if tier then
						correct += 1
						if not fastest or tier < fastest then
							fastest, fastCount = tier, 1
						elseif tier == fastest then
							fastCount += 1
						end
					end
				elseif rivalKey then
					local theirs = round.Picks[rivalKey]
					if (mine and mine.Points or 0) > (theirs and theirs.Points or 0) then
						roundsWon += 1
					end
				end
			end
		end
	end

	-- total bar: chips + score stickers
	local total = panel.Table.Total
	local chip1, chip2 = total.Chips.Chip1, total.Chips.Chip2
	local myScore = packet.Scores[ME] or 0
	if solo then
		chip1.Text = `{correct} / {#packet.Rounds} correct`
		chip2.Visible = fastest ~= nil
		if fastest then
			chip2.Text = `{fastCount} from {seconds(ladder[fastest])}`
		end
	else
		chip1.Text = if rivalKey then `You won {roundsWon} of {#packet.Rounds}` else `{myScore} points`
		chip2.Visible = false
	end
	total.Rival.Visible = rivalKey ~= nil and not solo
	total.RivalShadow.Visible = false
	self:_setTotal(0)
	if total.Rival.Visible then
		total.Rival.Text = tostring(packet.Scores[rivalKey] or 0)
		-- the higher score gets the tilt + hard shadow
		local theirScore = packet.Scores[rivalKey] or 0
		total.You.Rotation = if myScore > theirScore then -3 else 0
		total.Rival.Rotation = if theirScore > myScore then -3 else 0
		total.YouShadow.Visible = myScore > theirScore
		total.RivalShadow.Visible = theirScore > myScore
	else
		total.You.Rotation = -2
		total.YouShadow.Visible = true
	end
	total.YouShadow.Rotation = total.You.Rotation
	total.RivalShadow.Rotation = total.Rival.Rotation

	self:_season(packet)

	-- winner card
	local winnerId = packet.Winner
	local showId = winnerId or LOCAL_PLAYER.UserId
	local name
	if packet.Solo then
		name = LOCAL_PLAYER.DisplayName
	elseif packet.Draw then
		name = "It's a draw!"
	elseif winnerId == LOCAL_PLAYER.UserId then
		name = LOCAL_PLAYER.DisplayName
	else
		name = rivalName
	end
	w:FindFirstChild("Name").Text = name
	-- points of the player on the card (yours on a draw or in solo)
	local shownKey = tostring(showId)
	if w:FindFirstChild("Points") then
		w.Points.Value.Text = `{packet.Scores[shownKey] or 0} points`
	end
	w.Ribbon.Visible = not packet.Solo and not packet.Draw
	if w:FindFirstChild("RibbonShadow") then
		w.RibbonShadow.Visible = w.Ribbon.Visible
	end
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, showId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok then
			w.Avatar.Thumbnail.Image = img
		end
	end)

	-- what I earned
	local mine = packet.Rewards[ME] or {}
	w.Streak.Visible = not packet.Solo
	w.Streak.Value.Text = if (mine.Streak or 0) > 0 then `{mine.Streak} win streak` else "Streak reset"
	w.Coins.Visible = (mine.Coins or 0) > 0
	w.Coins.Value.Text = `+{mine.Coins or 0}`
	w.Coins.Detail.Text = mine.CoinsDetail or ""
	w.XP.Value.Text = `+{mine.XP or 0}`
	fillXP(w.XP, mine.XPBefore, mine.XP or 0)

	-- solo: rank stamp, personal best and how far the next rank is
	if solo and not packet.Tutorial then
		local max = #packet.Rounds * DuelConstants.TIER_POINTS[1]
		local index = #GRADES
		for i, grade in GRADES do
			if myScore >= math.ceil(grade.Share * max) then
				index = i
				break
			end
		end
		local grade = GRADES[index]
		w.Rank.Grade.Text = grade.Letter
		w.Rank.BackgroundColor3 = grade.Colour
		if index > 1 then
			local up = GRADES[index - 1]
			w.RankHint.Text = `{math.ceil(up.Share * max) - myScore} more points for {up.Letter} rank`
		else
			w.RankHint.Text = "Top rank!"
		end
		local best = w.Best
		best.Visible = mine.PrevBest ~= nil
		if mine.PrevBest ~= nil then
			best.New.Visible = mine.NewBest == true
			best.Old.Text = if not mine.NewBest then `best {mine.PrevBest}`
				elseif mine.PrevBest > 0 then `old best {mine.PrevBest}`
				else "first full run!"
		end
	end
	-- level up: a chip in the XP row, and the title it unlocked under it
	local levelChip = w.XP:FindFirstChild("LevelUp")
	if levelChip then
		levelChip.Visible = mine.LevelUp ~= nil
		levelChip.Text = if mine.LevelUp then `LEVEL UP · Lv {mine.LevelUp}` else ""
	end
	local titleChip = w:FindFirstChild("NewTitle")
	if titleChip then
		titleChip.Visible = mine.NewTitle ~= nil
		titleChip.Text = if mine.NewTitle then `New title unlocked: {mine.NewTitle}` else ""
	end
	-- rematch series score (from the second game on) and the Revenge! banner
	local seriesChip = w:FindFirstChild("Series")
	if seriesChip then
		local series = packet.Series
		seriesChip.Visible = series ~= nil and series.Games >= 2 and rivalKey ~= nil and not packet.Solo
		if seriesChip.Visible then
			seriesChip.Text = `SERIES {series.Wins[ME] or 0}–{series.Wins[rivalKey] or 0}`
		end
	end
	local revenge = w:FindFirstChild("Revenge")
	if revenge then
		revenge.Visible = false -- popped in by _reveal with the winner card
	end

	w.Rematch.Active = true
	w.RematchNote.Visible = false
	-- who's in for a rematch: starts at 0/2 (UpdateRematch counts it up); solo has no rival
	w.Rematch.Count.Visible = not solo
	w.Rematch.Count.Value.Text = "0/2"

	self:_reveal(packet, if solo then nil else rivalKey, mine)
end

-- The Season bar under the table: your tier, the SP this duel moved (solo / party / the
-- tutorial aren't rated) and the Stars it earned: your Rewards entry's Season
-- ({ Before, After, Delta, TierUp, TierDown, Stars }, Engine/SeasonService). A duel the server
-- didn't rate (the season's Ends has passed) shows "not rated".
function Results:_season(packet)
	local bar = self._frame.Panel:FindFirstChild("Season")
	if not bar then
		return
	end
	-- seasons off: no Season bar (or its shadow)
	bar.Visible = SeasonConstants.ENABLED
	local barShadow = self._frame.Panel:FindFirstChild("SeasonShadow")
	if barShadow then
		barShadow.Visible = SeasonConstants.ENABLED
	end
	if not SeasonConstants.ENABLED then
		return
	end
	local mine = packet.Rewards and packet.Rewards[tostring(LOCAL_PLAYER.UserId)]
	local season = packet.Season or (mine and mine.Season)
	local rated = season ~= nil and season.After ~= nil
	local unrated = packet.Solo == true or packet.Party ~= nil or packet.Tutorial == true or not rated
	local current = LOCAL_PLAYER:GetAttribute("SeasonSP") or 0
	local after = if rated then season.After else current
	local before = if rated then season.Before else after
	local info = SeasonConstants.TierOf(after)
	SeasonArt.PaintChip(bar.Tier, info)
	bar.Delta.Visible = not unrated
	bar.Bar.Visible = not unrated
	bar.Range.Visible = not unrated
	bar.Note.Visible = unrated
	bar.Note.Text = if packet.Tutorial then "Practice round · not rated"
		elseif packet.Solo then "Solo practice doesn't change SP"
		elseif packet.Party ~= nil then "Party matches don't change SP"
		else "Season over · SP isn't moving"
	local delta = after - before
	bar.Delta.Text = if delta < 0 then `−{-delta} SP` else `+{delta} SP`
	bar.Bar.Fill.Size = UDim2.fromScale(info.Progress, 1)
	bar.Range.Text = if info.Next then `{after} / {info.Next}` else `{after} SP`
	local won = packet.Winner == LOCAL_PLAYER.UserId
	local stars = if season and season.Stars ~= nil then season.Stars
		elseif packet.Tutorial then 0
		elseif packet.Solo then SeasonConstants.SOLO_STARS
		else 10 + (if won then 10 else 0)
	bar.Stars.Text = `+{stars}`
	bar.Stars.Visible = stars > 0
	local promoted = season ~= nil and season.TierUp == true
	bar.Promoted.Visible = promoted
	bar.Promoted.Text = `★ PROMOTED · {info.Label}`
	if promoted then
		Juice.Pop(bar.Promoted, 0.25)
	end
end

-- Solo and duels share the frame; this moves the columns / buttons between the two layouts.
function Results:_layout(solo: boolean, tutorial: boolean)
	local panel = self._frame.Panel
	local header = panel.Table.Header
	panel.TitleTag.BackgroundColor3 = if solo then TITLE_TAG.Solo else TITLE_TAG.Duel
	header.ColYou.Text = if solo then "GUESSED AT" else "YOU"
	header.ColYou.Position = UDim2.fromOffset(if solo then 330 else 478, 0)
	header.ColYou.Size = UDim2.fromOffset(if solo then 150 else 70, 20)
	header.ColYou.TextXAlignment = if solo then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	header.ColRival.Text = if solo then "POINTS" else "RIVAL"
	header.ColRival.Position = UDim2.fromOffset(if solo then 476 else 550, 0)
	for i = 1, 7 do
		local row = panel.Table.Rows:FindFirstChild("Round" .. i)
		if row then
			row.Clip.Visible = solo
			row.You.Position = UDim2.fromOffset(if solo then 487 else 489, 13) -- solo: points under POINTS
			row.Rival.Position = UDim2.fromOffset(561, 13)
			row.Title.Size = UDim2.fromOffset(if solo then 280 else 424, 20)
			row.Artist.Size = UDim2.fromOffset(if solo then 280 else 424, 18)
		end
	end

	local total = panel.Table.Total
	local spot = if solo then STICKER.Solo else STICKER.You
	local width = spot.Width or 60
	total.You.Size = UDim2.fromOffset(width, 38)
	total.You.Position = UDim2.fromOffset(spot.X, 33)
	total.You.BackgroundColor3 = spot.Colour
	total.YouShadow.Size = total.You.Size
	total.YouShadow.Position = UDim2.fromOffset(spot.X + 3, 36)
	total.Rival.Position = UDim2.fromOffset(STICKER.Rival.X, 33)
	total.RivalShadow.Position = UDim2.fromOffset(STICKER.Rival.X + 3, 36)

	local w = panel.Winner
	local extras = solo and not tutorial
	w.Rank.Visible = extras
	w.RankShadow.Visible = extras
	w.RankHint.Visible = extras
	w.Best.Visible = false -- Show() turns it on once it knows the best
	w.Rematch.Label.Visible = not solo
	w.Rematch.SoloLabel.Visible = solo
	w.FindRival.Visible = solo
	w.Leave.Size = UDim2.fromOffset(if solo then 130 else 264, 42)
	w.Leave.Position = UDim2.fromOffset(if solo then 217 else 150, 495)
end

-- The You sticker in the total bar ("49 / 70" in solo, so the max reads at a glance)
function Results:_setTotal(score: number)
	local label = self._frame.Panel.Table.Total.You
	if self._solo and self._max then
		label.Text = `{score}<font size="13" color="#5C566B"> / {self._max}</font>`
	else
		label.Text = tostring(score)
	end
end

-- Rows come in one at a time with the totals counting up, then the winner card pops in.
function Results:_reveal(packet, rivalKey: string?, mine)
	if self._revealThread then
		pcall(task.cancel, self._revealThread)
	end
	local panel = self._frame.Panel
	local rows = panel.Table.Rows
	local total = panel.Table.Total
	local w = panel.Winner

	-- start state: rows and the winner card hidden, totals at 0
	local shown = {}
	for i = 1, 7 do
		local row = rows:FindFirstChild("Round" .. i)
		if row and row.Visible then
			if row:GetAttribute("BaseX") == nil then
				row:SetAttribute("BaseX", row.Position.X.Offset)
			end
			scaleOf(row).Scale = 0
			row.Position = UDim2.new(row.Position.X.Scale, row:GetAttribute("BaseX") + ROW_SLIDE, row.Position.Y.Scale, row.Position.Y.Offset)
			table.insert(shown, { Row = row, Round = packet.Rounds[i] })
		end
	end
	self:_setTotal(0)
	if rivalKey then
		total.Rival.Text = "0"
	end
	scaleOf(w).Scale = 0

	self._revealThread = task.spawn(function()
		task.wait(REVEAL_DELAY)
		local you, rival = 0, 0
		for n, entry in shown do
			local row = entry.Row
			TweenService:Create(scaleOf(row), POP, { Scale = 1 }):Play()
			TweenService:Create(row, POP, {
				Position = UDim2.new(row.Position.X.Scale, row:GetAttribute("BaseX"), row.Position.Y.Scale, row.Position.Y.Offset),
			}):Play()
			Sounds.Play("SpinTick", { Pitch = 0.9 + n * 0.07 })

			local picks = entry.Round and entry.Round.Picks or {}
			you += picks[ME] and picks[ME].Points or 0
			rival += rivalKey and picks[rivalKey] and picks[rivalKey].Points or 0
			self:_setTotal(you)
			if rivalKey then
				total.Rival.Text = tostring(rival)
			end
			task.wait(ROW_GAP)
		end

		-- final totals (includes the first-correct bonus), with a punch
		self:_setTotal(packet.Scores[ME] or 0)
		if rivalKey then
			total.Rival.Text = tostring(packet.Scores[rivalKey] or 0)
		end
		local totalScale = scaleOf(total)
		totalScale.Scale = 1.08
		TweenService:Create(totalScale, POP, { Scale = 1 }):Play()
		Sounds.Play("SpinLand")
		task.wait(0.5)

		-- winner card
		TweenService:Create(scaleOf(w), TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if packet.Solo or packet.Winner == LOCAL_PLAYER.UserId then
			Sounds.Play("Win")
		elseif packet.Draw then
			Sounds.Play("SpinLand")
		else
			Sounds.Play("Lose")
		end
		if (mine.Coins or 0) > 0 then
			task.delay(0.9, Sounds.Play, "Coins")
		end
		if mine.Perfect then
			task.delay(1.5, Sounds.Play, "Perfect")
		end
		-- revenge win: the stamp slams on over the winner card, after the coins and before
		-- the perfect sound so each gets its own beat
		local revenge = w:FindFirstChild("Revenge")
		if mine.Revenge and revenge then
			task.delay(1.3, function()
				revenge.Visible = true
				local s = scaleOf(revenge)
				s.Scale = 1.6
				TweenService:Create(s, POP, { Scale = 1 }):Play()
				Sounds.Play("Revenge")
			end)
		end

		-- the Rematch button pops in with its own sound, after the coins / revenge / perfect beats
		task.delay(if mine.Perfect then 2.1 elseif mine.Revenge then 1.9 else 1.5, function()
			if self.State ~= "Inactive" and w.Rematch.Visible then
				Juice.Pop(w.Rematch, 0.14)
				-- duel: the Rematch pop; solo: Play again's own bounce
				Sounds.Play(if self._solo then "PlayAgain" else "Rematch")
			end
		end)

		-- lost a streak: offer to save it
		if (mine.StreakLost or 0) >= 2 then
			local saver = self._interface:GetController("SaveStreak")
			if saver then
				task.wait(1.2)
				saver:Show(mine.StreakLost)
			end
		end
		self._revealThread = nil
	end)
end

function Results:UpdateRematch(wants)
	local note = self._frame.Panel.Winner.RematchNote
	local mine, theirs = false, false
	for _, id in wants do
		if id == LOCAL_PLAYER.UserId then
			mine = true
		elseif id == self._rivalId then
			theirs = true
		end
	end
	-- the button's chip counts who's in: 0/2, 1/2, 2/2
	local asked = (if mine then 1 else 0) + (if theirs then 1 else 0)
	local count = self._frame.Panel.Winner.Rematch.Count
	count.Visible = not self._solo
	count.Value.Text = `{asked}/2`
	if theirs and not mine then
		note.Visible = true
		note.Text = "Your rival wants a rematch!"
	elseif mine and not theirs then
		note.Visible = true
		note.Text = "Waiting for your rival…"
	end
end

function Results:Activate(packet, info)
	if packet then
		self:Show(packet, info)
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

function Results:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	if self._rematchRequested then
		DuelRemote:Fire({ Action = "CancelRematch" })
		self._rematchRequested = false
	end
	if self._revealThread then
		pcall(task.cancel, self._revealThread)
		self._revealThread = nil
	end
	-- after a real duel (not solo or the tutorial), once ever: ask them to favourite the game
	local askFavourite = self._wasDuel and not self._staying
	self._wasDuel = false
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
		if askFavourite then
			FavoritePrompt.Try()
		end
	end)
end

function Results:Destroy()
	self._janitor:Destroy()
end

return Results
