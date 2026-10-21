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

--| Controls

type ControlsData = {
	Frame: typeof(game.StarterGui.Interface.Frames.Game.Controls),
	Opponent: Player,
	Round: number,
	PlayerPoints: number,
	OpponentPoints: number,
	_janitor: typeof(Janitor.new()),
}

local Controls = {}
Controls.__index = Controls

--| Functions

-- [[ Private ]]

-- [[ Public ]]

function Controls.new(
	Frame: typeof(game.StarterGui.Interface.Frames.Game.Controls),
	Opponent: Player
): ControlsData
	local self: ControlsData = setmetatable({}, Controls) :: any
	self._janitor = Janitor.new()

	return self
end

function Controls:Initialize()
	local Frame = self.Frame
	local Panel = Frame.Panel

end


--| Return
return Controls
