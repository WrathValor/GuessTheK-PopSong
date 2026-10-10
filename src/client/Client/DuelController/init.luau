--| Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)

local InterfaceController = require(script.Parent.InterfaceController)

--| Variables

local LOCAL_PLAYER = Players.LocalPlayer
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
--| DuelController

local DuelController = {};

--| Functions

-- [[ Private ]]

-- [[ Public ]]

function DuelController.Start()
	QueueRemote:Connect(function(Packet: {Message: string, any: any})
		local Message = Packet.Message
		if Message == "Queueing" then
			InterfaceController.Open(InterfaceController, "Queue")
		elseif Message == "LeftQueue" then
			InterfaceController.Close(InterfaceController, "Queue")
		elseif Message == "Intermission" then
			local QueueController = InterfaceController.GetController(InterfaceController, "Queue")
			if not QueueController then return end
			QueueController:StartIntermission()
		elseif Message == "Opponent" then
			local QueueController = InterfaceController.GetController(InterfaceController, "Queue")
			if not QueueController then return end
			QueueController:UpdateOpponent(Packet.Opponent)
		end
	end)
end

--| Return
return DuelController