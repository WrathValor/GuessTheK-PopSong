-- Match results: per-round table, totals, the winner card with what you earned, Rematch / Leave.

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
local ME = tostring(LOCAL_PLAYER.UserId)
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local C = Color3.fromHex
local CELL = { Correct = C("A7E9B8"), Wrong = C("FFD2CE"), None = C("EDE4D4") }

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
	local w = self._frame.Panel.Winner
	self._janitor:Add(w.Rematch.Activated:Connect(function()
		DuelRemote:Fire({ Action = "Rematch" })
		w.Rematch.Active = false
		w.RematchNote.Visible = true
		w.RematchNote.Text = if self._solo then "Starting…" else "Waiting for your rival…"
	end))
	self._janitor:Add(w.Leave.Activated:Connect(function()
		QueueRemote:Fire("Leave")
		self._interface:Close(self.Name)
	end))
end

function Results:Show(packet, info)
	local panel = self._frame.Panel
	local w = panel.Winner
	self._solo = packet.Solo

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

	-- round table
	local rows = panel.Table.Rows
	panel.Table.Header.ColRival.Visible = rivalKey ~= nil
	panel.Table.Header.Song.Text = if packet.Mode == "Choreography" then "SONG · CHOREOGRAPHY" else "SONG · AUDIO"
	for i = 1, 7 do
		local row = rows:FindFirstChild("Round" .. i)
		local round = packet.Rounds[i]
		if row then
			row.Visible = round ~= nil
			if round then
				row.Title.Text = round.Name
				row.Artist.Text = round.Artist
				local function cell(frame, pick)
					frame.Visible = pick ~= nil
					if pick then
						frame.BackgroundColor3 = if pick.Correct then CELL.Correct elseif pick.Picked then CELL.Wrong else CELL.None
						frame.Value.Text = if pick.Points > 0 then `+{pick.Points}` else "0"
					end
				end
				cell(row.You, round.Picks[ME])
				cell(row.Rival, rivalKey and round.Picks[rivalKey] or nil)
			end
		end
	end
	panel.Table.Total.You.Text = tostring(packet.Scores[ME] or 0)
	panel.Table.Total.Rival.Visible = rivalKey ~= nil
	panel.Table.Total.Rival.Text = rivalKey and tostring(packet.Scores[rivalKey] or 0) or ""

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
	w.Index.Visible = (mine.IndexNew or 0) > 0
	w.Index.Value.Text = `+{mine.IndexNew or 0} new`

	w.Rematch.Active = true
	w.RematchNote.Visible = false

	self:_reveal(packet, rivalKey, mine)
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
	total.You.Text = "0"
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
			total.You.Text = tostring(you)
			if rivalKey then
				total.Rival.Text = tostring(rival)
			end
			task.wait(ROW_GAP)
		end

		-- final totals (includes the first-correct bonus), with a punch
		total.You.Text = tostring(packet.Scores[ME] or 0)
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
	if self._revealThread then
		pcall(task.cancel, self._revealThread)
		self._revealThread = nil
	end
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Results:Destroy()
	self._janitor:Destroy()
end

return Results
