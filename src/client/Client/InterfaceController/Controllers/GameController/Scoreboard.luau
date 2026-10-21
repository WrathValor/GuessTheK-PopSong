--| Scoreboard
-- Top bar of the round screen: both players, round pips and the running score.

local Players = game:GetService("Players")

local LOCAL_PLAYER = Players.LocalPlayer
local C = Color3.fromHex

-- pip look (matches the Studio build)
local PIP = {
	Done = C("1E1B2E"),
	Current = C("FF5A4E"),
	Upcoming = C("FFFFFF"),
}

local Scoreboard = {}
Scoreboard.__index = Scoreboard

local function thumb(userId: number): string
	local ok, img = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	return ok and img or ""
end

function Scoreboard.new(frame, me, rival)
	local self = setmetatable({}, Scoreboard)
	self.Frame = frame
	self.Me = me
	self.Rival = rival
	return self
end

function Scoreboard:Initialize(rounds: number)
	local panel = self.Frame.Panel
	local function fill(card, profile, status)
		if not profile then
			card.Visible = false
			return
		end
		card.Visible = true
		card:FindFirstChild("Name").Text = profile.Name
		if card:FindFirstChild("Status") then
			card.Status.Text = status
		end
		task.spawn(function()
			card.Avatar.Thumbnail.Image = thumb(profile.UserId)
		end)
	end
	fill(panel.You, self.Me or { Name = LOCAL_PLAYER.DisplayName, UserId = LOCAL_PLAYER.UserId }, "")
	fill(panel.Rival, self.Rival, "")
	panel.VS.Visible = self.Rival ~= nil
	panel.Score.Rival.Visible = self.Rival ~= nil
	panel.Score.You.Text = "0"
	panel.Score.Rival.Text = "0"
	self.Rounds = rounds
	self:UpdateRound(1)
end

function Scoreboard:UpdateRound(round: number)
	local panel = self.Frame.Panel
	if panel:FindFirstChild("Round") then
		panel.Round.Text = `{round}/{self.Rounds or 7}`
	end
	for _, pip in panel.Pips:GetChildren() do
		local n = tonumber(pip.Name:match("%d+"))
		if n and pip:IsA("GuiObject") then
			pip.BackgroundColor3 = if n < round then PIP.Done elseif n == round then PIP.Current else PIP.Upcoming
		end
	end
end

function Scoreboard:SetStatus(isRival: boolean, text: string)
	local card = if isRival then self.Frame.Panel.Rival else self.Frame.Panel.You
	if card:FindFirstChild("Status") then
		card.Status.Text = text
	end
end

function Scoreboard:SetScores(mine: number, rival: number?)
	local score = self.Frame.Panel.Score
	score.You.Text = tostring(mine)
	if rival then
		score.Rival.Text = tostring(rival)
	end
end

return Scoreboard
