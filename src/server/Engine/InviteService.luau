--| InviteService
-- Duel invites. A player waiting alone on a stage can invite someone in the server; if they
-- accept they're put straight on the free spot. One invite out per sender, one pending per
-- target, and each lasts INVITE_TIME seconds.
--
-- InviteRemote, client → server: { Action = "List" }
--                                { Action = "Send", Target = userId }
--                                { Action = "Challenge", Target = userId }  (from the player card: takes a
--                                  free stage first when you aren't waiting on one, then sends)
--                                { Action = "Cancel" }
--                                { Action = "Answer", Accept = bool }
-- server → client:               { Message = "List", Players = { {UserId, Name, Level, Streak, Status} } }
--                                { Message = "Invite", From, Name, Level, Streak, Stage, Expires }
--                                { Message = "Sent", Target, Name, Expires }
--                                { Message = "Result", Result = "Accepted" | "Declined" | "Expired" | "Cancelled" | "Failed" | "NoStage", Name }
--                                { Message = "InviteGone" }   (the invite you were shown no longer stands)
-- Status is "Open" | "Sent" | "InDuel" | "Off" | "Cooldown".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local DuelService = require(script.Parent.DuelService)
local Duels = require(script.Parent.DuelService.Duels)
local SettingsService = require(script.Parent.SettingsService)
local Analytics = require(script.Parent.Analytics)

local InviteRemote = Bridgenet.ReferenceBridge("InviteRemote")

--| Constants

local INVITE_TIME = 15
local DECLINE_COOLDOWN = 30 -- the same sender can't re-invite someone who just said no
local MIN_GAP = 0.25

--| Variables

type Invite = { From: Player, To: Player, Stage: string, Expires: number, Timer: thread? }

local outgoing: { [Player]: Invite } = {} -- by sender
local incoming: { [Player]: Invite } = {} -- by target
local cooldowns: { [Player]: { [number]: number } } = {} -- sender → target UserId → until
local last: { [Player]: number } = {}

local InviteService = {}

--| Functions

-- the stage the sender is waiting on alone, or nil
local function waitingStage(player: Player)
	local stage = DuelService.PlayerStage[player]
	if not stage or stage.Solo or stage.Duel or stage.State ~= "Waiting" then
		return nil
	end
	if stage.Players.A and stage.Players.B then
		return nil
	end
	return stage
end

local function statusFor(sender: Player, target: Player): string
	local sent = outgoing[sender]
	if sent and sent.To == target then
		return "Sent"
	end
	if DuelService.PlayerStage[target] then
		return "InDuel"
	end
	if not SettingsService.AcceptsInvites(target) then
		return "Off"
	end
	local until_ = cooldowns[sender] and cooldowns[sender][target.UserId]
	if until_ and until_ > os.clock() then
		return "Cooldown"
	end
	if incoming[target] then
		return "InDuel" -- busy answering someone else
	end
	return "Open"
end

local function close(invite: Invite, result: string)
	if outgoing[invite.From] == invite then
		outgoing[invite.From] = nil
	end
	if incoming[invite.To] == invite then
		incoming[invite.To] = nil
	end
	if invite.Timer and coroutine.running() ~= invite.Timer then
		pcall(task.cancel, invite.Timer)
	end
	if invite.From.Parent then
		InviteRemote:Fire(invite.From, { Message = "Result", Result = result, Name = invite.To.DisplayName })
	end
	if result ~= "Accepted" and result ~= "Declined" and invite.To.Parent then
		InviteRemote:Fire(invite.To, { Message = "InviteGone" })
	end
	Analytics.Event(invite.From, "InviteResult", 1, result, invite.Stage)
end

local function sendList(player: Player)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local profile = Duels.ProfileOf(other)
			table.insert(list, {
				UserId = other.UserId,
				Name = other.DisplayName,
				Level = profile.Level,
				Streak = profile.Streak,
				Status = statusFor(player, other),
			})
		end
	end
	InviteRemote:Fire(player, { Message = "List", Players = list })
end

local function send(player: Player, targetId: any)
	local target = type(targetId) == "number" and Players:GetPlayerByUserId(targetId)
	local stage = waitingStage(player)
	if not target or target == player or not stage or outgoing[player] then
		InviteRemote:Fire(player, { Message = "Result", Result = "Failed" })
		return
	end
	if statusFor(player, target) ~= "Open" then
		InviteRemote:Fire(player, { Message = "Result", Result = "Failed", Name = target.DisplayName })
		sendList(player)
		return
	end

	local invite: Invite = { From = player, To = target, Stage = stage.Name, Expires = workspace:GetServerTimeNow() + INVITE_TIME }
	outgoing[player] = invite
	incoming[target] = invite
	invite.Timer = task.delay(INVITE_TIME, function()
		if outgoing[player] == invite then
			close(invite, "Expired")
		end
	end)

	local profile = Duels.ProfileOf(player)
	InviteRemote:Fire(target, {
		Message = "Invite",
		From = player.UserId,
		Name = player.DisplayName,
		Level = profile.Level,
		Streak = profile.Streak,
		Stage = stage.Name,
		Friend = target:IsFriendsWith(player.UserId),
		Expires = invite.Expires,
	})
	InviteRemote:Fire(player, { Message = "Sent", Target = target.UserId, Name = target.DisplayName, Expires = invite.Expires })
	Analytics.Event(player, "InviteSent", 1, stage.Name)
end

local function answer(player: Player, accept: boolean)
	local invite = incoming[player]
	if not invite then
		return
	end
	if not accept then
		cooldowns[invite.From] = cooldowns[invite.From] or {}
		cooldowns[invite.From][player.UserId] = os.clock() + DECLINE_COOLDOWN
		close(invite, "Declined")
		return
	end
	-- still valid? the sender may have left or someone took the spot
	if not waitingStage(invite.From) or DuelService.PlayerStage[player] then
		close(invite, "Failed")
		return
	end
	-- close before joining: joining starts the intermission straight away
	local stageName = invite.Stage
	close(invite, "Accepted")
	if not DuelService.JoinStage(player, stageName) then
		InviteRemote:Fire(player, { Message = "InviteGone" })
	end
end

--| Public

function InviteService.Start()
	InviteRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" then
			return
		end
		local now = os.clock()
		if last[player] and now - last[player] < MIN_GAP then
			return
		end
		last[player] = now

		if packet.Action == "List" then
			sendList(player)
		elseif packet.Action == "Send" then
			send(player, packet.Target)
		elseif packet.Action == "Challenge" then
			local target = type(packet.Target) == "number" and Players:GetPlayerByUserId(packet.Target)
			if not target or target == player or statusFor(player, target) ~= "Open" then
				InviteRemote:Fire(player, { Message = "Result", Result = "Failed", Name = if target then target.DisplayName else nil })
			elseif waitingStage(player) or DuelService.TakeEmptyStage(player) then
				send(player, packet.Target)
			elseif DuelService.PlayerStage[player] then
				InviteRemote:Fire(player, { Message = "Result", Result = "Failed", Name = target.DisplayName })
			else
				InviteRemote:Fire(player, { Message = "Result", Result = "NoStage", Name = target.DisplayName })
			end
		elseif packet.Action == "Cancel" then
			local invite = outgoing[player]
			if invite then
				close(invite, "Cancelled")
			end
		elseif packet.Action == "Answer" then
			answer(player, packet.Accept == true)
		end
	end)

	-- an invite only stands while its sender is still waiting alone and the target is free
	task.spawn(function()
		while true do
			task.wait(0.5)
			for sender, invite in outgoing do
				if not sender.Parent or not invite.To.Parent then
					close(invite, "Cancelled")
				elseif not waitingStage(sender) then
					close(invite, "Cancelled")
				elseif DuelService.PlayerStage[invite.To] then
					close(invite, "Failed") -- they stepped on another stage
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local a, b = outgoing[player], incoming[player]
		if a then
			close(a, "Cancelled")
		end
		if b then
			close(b, "Cancelled")
		end
		cooldowns[player], last[player] = nil, nil
	end)
end

return InviteService
