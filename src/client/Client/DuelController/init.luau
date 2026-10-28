--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--| Imports
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local InterfaceController = require(script.Parent.InterfaceController)
local CameraController = require(script.Parent.CameraController)
local BackgroundMusic = require(script.Parent.BackgroundMusic)
local Sounds = require(ReplicatedStorage.Modules.Sounds)

--| Variables
local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")

--| DuelController
-- Routes queue/duel packets from the server to the screen controllers, and drives the
-- music (lobby BGM / round selection track / quiet in Song rounds) and the duel camera.
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

-- Back to the lobby feel: normal camera, the background playlist carries on where it paused.
local function backToLobby()
	CameraController.Reset()
	BackgroundMusic.Resume()
end

function DuelController.Start()
	QueueRemote:Connect(function(packet)
		local message = packet.Message
		if message == "Queueing" then
			call("Queue", "Reset")
			InterfaceController:Open("Queue")
		elseif message == "LeftQueue" then
			-- leaving can happen from the queue or the results screen
			local active = InterfaceController.ActiveController
			if active and (active.Name == "Queue" or active.Name == "Results") then
				InterfaceController:Close()
			end
			call("SaveStreak", "Hide")
			backToLobby()
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
		elseif message == "SoloPool" then
			call("PreDuel", "SetSoloPool", packet.Choice)
		elseif message == "Mode" then
			call("PreDuel", "ShowMode", packet.Mode)
		elseif message == "Start" then
			Sounds.Play("GameStart")
			-- the rounds need silence to hear the snippet: the playlist fades out and pauses
			-- until the duel is over (backToLobby resumes it from the same spot)
			BackgroundMusic.Duck()
			CameraController.Focus(packet.Mode, DuelController.Info)
			InterfaceController:Open("Game", DuelController.Info, packet.Mode)
		elseif message == "Round" then
			call("Game", "OnRound", packet)
		elseif message == "RoundGo" then
			call("Game", "OnRoundGo", packet)
		elseif message == "RivalAnswered" then
			call("Game", "OnRivalAnswered", packet.Seconds)
		elseif message == "RoundEnd" then
			call("Game", "OnRoundEnd", packet)
		elseif message == "End" then
			backToLobby()
			InterfaceController:Open("Results", packet, DuelController.Info)
		elseif message == "RematchState" then
			call("Results", "UpdateRematch", packet.Wants)
		end
	end)
end

return DuelController
