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
			-- (back to an open queue: a walk-on that was running stops)
			call("Queue", "Reset")
			InterfaceController:Open("Queue")
			-- waiting for a rival: the camera shows you on your own stage + mic, the card
			-- steps aside (CameraController.Showcase falls back to the normal camera if it can't)
			if CameraController.Showcase() then
				call("Queue", "ShowAside")
			elseif CameraController.Mode == "WalkOn" then
				CameraController.Reset()
			end
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
			-- rival found: the walk-on shows both players on their own stage + mic while the
			-- countdown runs (it holds the wide shot until the round camera takes over)
			local spots = CameraController.SpotPlayers()
			local running, aLeft = CameraController.WalkOn(function(shot)
				call("Queue", "HighlightWalkOn", shot)
			end)
			if running then
				call("Queue", "ShowWalkOn", spots, aLeft)
			end
		elseif message == "Opponent" then
			call("Queue", "UpdateOpponent", packet.Opponent)
			-- the rival cancelled mid walk-on: back to the waiting shot of you on your stage
			if packet.Opponent == nil and CameraController.Mode == "WalkOn" then
				if CameraController.Showcase() then
					call("Queue", "ShowAside")
				else
					CameraController.Reset()
				end
			end
		elseif message == "RematchWaiting" then
			call("Queue", "ShowRematch") -- stepped back on: the rival is still on their results
		end
	end)

	DuelRemote:Connect(function(packet)
		local message = packet.Message
		if message == "PreDuel" then
			DuelController.Info = packet
			-- the tutorial goes straight into its rounds; a Party Stage match shows its pot roll
			-- (no Reel = a custom pool too small to pay out: straight in too)
			if not packet.Tutorial and (not packet.Party or packet.Reel) then
				InterfaceController:Open("PreDuel", packet)
			end
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
		elseif message == "Encore" then
			call("Game", "OnEncore", packet) -- the final round's ENCORE sign
		elseif message == "Round" then
			call("Game", "OnRound", packet)
		elseif message == "RoundGo" then
			call("Game", "OnRoundGo", packet)
		elseif message == "RivalAnswered" then
			call("Game", "OnRivalAnswered", packet.Seconds)
		elseif message == "PlayerAnswered" then
			call("Game", "OnPlayerAnswered", packet.UserId) -- Party Stage FFA ticket
		elseif message == "RoundEnd" then
			call("Game", "OnRoundEnd", packet)
		elseif message == "End" then
			-- a 1v1 with a winner: the victory shot on the winner's stage first (VictoryController
			-- hands the camera back and opens the results itself)
			-- (Party Stage matches get it too, on whoever came first, before their placement card)
			local partyWinner = false
			for _, p in (packet.Party and packet.Party.Placement) or {} do
				partyWinner = partyWinner or (p.Place == 1 and not p.Left)
			end
			if (packet.Winner and not (packet.Party or packet.Tutorial or packet.Solo or packet.Draw)) or partyWinner then
				BackgroundMusic.Resume()
				InterfaceController:Open("Victory", packet, DuelController.Info)
				return
			end
			backToLobby()
			if packet.Party then
				call("Party", "ShowResults", packet) -- Party Stage placement + coins
			elseif packet.Tutorial then
				InterfaceController:Open("Tutorial", "Done", packet) -- "You're ready!" instead of results
			else
				InterfaceController:Open("Results", packet, DuelController.Info)
			end
		elseif message == "RematchState" then
			call("Results", "UpdateRematch", packet.Wants)
		end
	end)
end

return DuelController
