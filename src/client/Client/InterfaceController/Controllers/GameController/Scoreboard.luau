--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local Janitor = require(ReplicatedStorage.Packages.janitor)

--| Variables

local LOCAL_PLAYER = Players.LocalPlayer
local PIP_STATE = {
	Active = {
        UIStrokeThickness = 2.5;
		Colour = Color3.fromRGB(0, 255, 127),
		Size = UDim2.fromScale(0.12, 0.857),
	},
	Inactive = {
		UIStrokeColour = Color3.fromRGB(230, 207, 234),
        UIStrokeThickness = 1,
		Colour = Color3.fromRGB(255, 255, 255),
		Size = UDim2.fromScale(0.08, 0.571),
	},
}

--| Scoreboard

type ScoreboardData = {
	Frame: typeof(game.StarterGui.Interface.Frames.Game.Scoreboard),
	Opponent: Player,
	Round: number,
	PlayerPoints: number,
	OpponentPoints: number,
	_janitor: typeof(Janitor.new()),
}

local Scoreboard = {}
Scoreboard.__index = Scoreboard

--| Functions

-- [[ Private ]]

-- [[ Public ]]

function Scoreboard.new(
	Frame: typeof(game.StarterGui.Interface.Frames.Game.Scoreboard),
	Opponent: Player
): ScoreboardData
	local self: ScoreboardData = setmetatable({}, Scoreboard) :: any

	self.Frame = Frame
	self.Opponent = Opponent

	self.Round = 1
	self.PlayerPoints = 0
	self.OpponentPoints = 0

	self._janitor = Janitor.new()

	return self
end

function Scoreboard:Initialize()
	local Frame = self.Frame
	local Panel = Frame.Panel

	local YouFrame = Panel.You
	local YouAvatarFrame = YouFrame.Avatar
	local YouLabel = YouFrame:FindFirstChild("Name")

	if YouLabel then
		YouLabel.Text = LOCAL_PLAYER.DisplayName
	end

	if YouAvatarFrame and YouAvatarFrame:FindFirstChild("Thumbnail") then
		YouAvatarFrame.Thumbnail.Image = Players:GetUserThumbnailAsync(
			LOCAL_PLAYER.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size420x420
		)
	end

	local RivalFrame = Panel.Rival
	local RivalAvatarFrame = RivalFrame.Avatar
	local RivalLabel = RivalFrame:FindFirstChild("Name")

	if RivalLabel then
		RivalLabel.Text = LOCAL_PLAYER.DisplayName
	end

	if RivalAvatarFrame and RivalAvatarFrame:FindFirstChild("Thumbnail") then
		RivalAvatarFrame.Thumbnail.Image = Players:GetUserThumbnailAsync(
			LOCAL_PLAYER.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size420x420
		)
	end

	local ScoreFrame = Panel.Score
	ScoreFrame.You.Text = 0
	ScoreFrame.Rival.Text = 0

	for _, Pip in Panel.Pips:GetChildren() do
        if not Pip:IsA("Frame") then continue end
		Pip.BackgroundColor3 = PIP_STATE.Inactive.Colour
		Pip.UIStroke.Color = PIP_STATE.Inactive.UIStrokeColour
        Pip.UIStroke.Thickness = PIP_STATE.Inactive.UIStrokeThickness
	end
end

function Scoreboard:UpdateRound(CurrentRound: number)
	local Frame = self.Frame:typeof(game.StarterGui.Interface.Frames.Game.Scoreboard)
	local Panel = Frame.Panel
	local Pips = Panel.Pips

	local PreviousRound = CurrentRound - 1
	if PreviousRound ~= 0 then
		local PreviousPip = Pips:FindFirstChild(`Pip{PreviousRound}`)
		if not PreviousPip then
			return
		end
		PreviousPip.Size = PIP_STATE.Inactive.Size
	end

	local CurrentPip = Pips:FindFirstChild(`Pip{CurrentRound}`)
	if not CurrentPip then
		return
	end

	CurrentPip.BackgroundColor3 = PIP_STATE.Active.Colour
	CurrentPip.UIStroke.Color = PIP_STATE.Active.Colour
    CurrentPip.UIStroke.Thickness = PIP_STATE.Active.UIStrokeThickness
end

function Scoreboard:UpdateScore(Opponent: boolean?, Score: string)
	local Frame = self.Frame
	local Panel = Frame.Panel
    
    local ScoreFrame = Panel.Score
	local PlayerScore = ScoreFrame.You
	local RivalScore = ScoreFrame.Rival

	if Opponent then
        RivalScore.Text = Score
    else
        PlayerScore.Text = Score
	end 
end

--| Return
return Scoreboard
