-- Match results: per-round table, totals, the winner card with what you earned, Rematch / Leave.

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

-- -------------------------------- Variables ------------------------------- --
local LOCAL_PLAYER = Players.LocalPlayer
local ME = tostring(LOCAL_PLAYER.UserId)
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local C = Color3.fromHex
local CELL = { Correct = C("A7E9B8"), Wrong = C("FFD2CE"), None = C("EDE4D4") }

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
		name = "Practice done!"
	elseif packet.Draw then
		name = "It's a draw!"
	elseif winnerId == LOCAL_PLAYER.UserId then
		name = LOCAL_PLAYER.DisplayName
	else
		name = rivalName
	end
	w:FindFirstChild("Name").Text = name
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
	if packet.Solo or winnerId == LOCAL_PLAYER.UserId then
		Sounds.Play("Win")
	elseif packet.Draw then
		Sounds.Play("SpinLand")
	else
		Sounds.Play("Lose")
	end
	if (mine.Coins or 0) > 0 then
		task.delay(1, Sounds.Play, "Coins")
	end
	if mine.Perfect then
		task.delay(1.6, Sounds.Play, "Perfect")
	end
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

	-- lost a streak: offer to save it
	if (mine.StreakLost or 0) >= 2 then
		local saver = self._interface:GetController("SaveStreak")
		if saver then
			task.delay(1.2, function()
				saver:Show(mine.StreakLost)
			end)
		end
	end
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
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Results:Destroy()
	self._janitor:Destroy()
end

return Results
