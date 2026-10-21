--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local InterfaceController = require(script.Parent.InterfaceController)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

--| Variables
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")

--| DuelController
-- Routes queue/duel packets from the server to the screen controllers.
local DuelController = {}

-- Pre-duel info (players, stake) is kept so the round and results screens can use it.
DuelController.Info = nil :: any

local function controller(name: string)
	return InterfaceController:GetController(name)
end

local function call(name: string, method: string, ...)
	local c = controller(name)
	if c and c[method] then
		c[method](c, ...)
	end
end

function DuelController.Start()
	QueueRemote:Connect(function(packet)
		local message = packet.Message
		if message == "Queueing" then
			InterfaceController:Open("Queue")
		elseif message == "LeftQueue" then
			-- leaving can happen from the queue or the results screen
			local active = InterfaceController.ActiveController
			if active and (active.Name == "Queue" or active.Name == "Results") then
				InterfaceController:Close()
			end
			call("SaveStreak", "Hide")
		elseif message == "Intermission" then
			call("Queue", "StartIntermission")
		elseif message == "Opponent" then
			call("Queue", "UpdateOpponent", packet.Opponent)
		end
	end)

	DuelRemote:Connect(function(packet)
		local message = packet.Message
		if message == "PreDuel" then
			DuelController.Info = packet
			InterfaceController:Open("PreDuel", packet)
		elseif message == "Votes" then
			call("PreDuel", "UpdateVotes", packet.Votes)
		elseif message == "Mode" then
			call("PreDuel", "ShowMode", packet.Mode)
		elseif message == "Start" then
			Sounds.Play("GameStart")
			InterfaceController:Open("Game", DuelController.Info, packet.Mode)
		elseif message == "Round" then
			call("Game", "OnRound", packet)
		elseif message == "RivalAnswered" then
			call("Game", "OnRivalAnswered", packet.Seconds)
		elseif message == "RoundEnd" then
			call("Game", "OnRoundEnd", packet)
		elseif message == "End" then
			InterfaceController:Open("Results", packet, DuelController.Info)
		elseif message == "RematchState" then
			call("Results", "UpdateRematch", packet.Wants)
		end
	end)
end

return DuelController
