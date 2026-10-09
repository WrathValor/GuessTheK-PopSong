--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local InterfaceController = require(script.Parent.InterfaceController)

--| Variables

local LOCAL_PLAYER = Players.LocalPlayer
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
--| DuelController

local DuelController = {};

--| Functions

-- [[ Private ]]

-- [[ Public ]]

function DuelController.Start()
	DuelRemote:Connect(function(Message: string)
		if Message == "Queueing" then
			--setQueued(true)
			InterfaceController.Open(InterfaceController, "Queue")
		elseif Message == "LeftQueue" then
			--setQueued(false)
			InterfaceController.Close(InterfaceController, "Queue")
		end
	end)
end

--| Return
return DuelController