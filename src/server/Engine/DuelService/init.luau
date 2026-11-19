--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

--| Imports

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Duels = require(script.Duels)
local Rewards = require(script.Rewards)
local StageCosmetics = require(script.StageCosmetics)
local StageStatus = require(script.StageStatus)
local Analytics = require(script.Parent.Analytics)
local RivalRecord = require(script.Parent.RivalRecord)
local GhostRecorder = require(script.Parent.GhostRecorder)
local GhostPool = require(script.Parent.GhostPool)
local SettingsService = require(script.Parent.SettingsService)
local StreetScreens = require(script.Parent.StreetScreens)
local StreetScreensConstants = require(ReplicatedStorage.Constants.StreetScreens)
local Themes = require(ReplicatedStorage.Modules.Library.Themes)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server
local Levels = require(ReplicatedStorage.Modules.Levels)
local DuelConstants = require(ReplicatedStorage.Constants.DuelConstants)

--| Types

type Slot = "A" | "B"
export type Stage = {
	Name: string,
	Model: Model,
	State: "Waiting" | "InProgress",
	Spots: { [Slot]: BasePart },
	Prompts: { [Slot]: ProximityPrompt },
	Players: { [Slot]: Player? },
	SlotJanitors: { [Slot]: any },
	Duel: any?,
	Rematch: { [Player]: boolean },
	Solo: boolean?,
	-- open practice: the solo game here was started with "Rivals can join my practice" on,
	-- so the other spot stays open (openPractice)
	OpenSolo: boolean?,
	-- set while the "A rival stepped up!" card counts down (handOver); leave clears it
	HandOver: any?,
	-- ghost rival: the solo game here is against a ghost (Play Again brings a new one),
	-- the pending "nobody came" timer (scheduleGhost), and the ghost's figure on its spot
	GhostGame: boolean?,
	GhostTimer: any?,
	GhostRig: Model?,
	Janitor: any,
}

--| Constants

local PROMPT_DISTANCE = 8
local SLOTS: { Slot } = { "A", "B" }

--| Variables

local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local DuelStages = workspace.Map.DuelStages

-- analytics: when each player stepped on, their Duel funnel id, and whether they've finished a game here
local queuedAt: { [Player]: number } = {}
local sessions: { [Player]: string } = {}
local played: { [Player]: boolean } = {}

-- players still on the results screen of a game on their stage (cleared once they press
-- Rematch, step off or step on again). A rival who steps on meanwhile waits for them to
-- accept instead of pulling them straight into a game.
local onResults: { [Player]: boolean } = {}

-- players with the solo theme picker open on the queue card (QueueRemote "Picking"): they're
-- choosing practice, so no ghost and no move to another stage while it's open (scheduleGhost)
local picking: { [Player]: boolean } = {}

local function newSession(player: Player): string
	local id = `{player.UserId}-{os.time()}-{math.random(1000, 9999)}`
	sessions[player] = id
	Analytics.Funnel(player, "Duel", id, "Queued")
	return id
end

--| DuelService

local DuelService = {}
DuelService.Stages = {} :: { [string]: Stage }
DuelService.PlayerStage = {} :: { [Player]: Stage }
-- whether this player has a duel invite out or in (set by InviteService, which needs this
-- module, so it hands the check over rather than being required here)
DuelService.InvitePending = function(_player: Player): boolean
	return false
end

--| Functions

-- [[ Private ]]

local leave, tryStart, notifyOpponents, requestRematch, handOver, join -- forward declared, join() needs them (and scheduleGhost needs join)

local function otherSlot(slot: Slot): Slot
	return if slot == "A" then "B" else "A"
end

-- Open practice (Settings.SoloOpen): someone's practising solo here and the other spot is
-- still open to a rival. Returns the one practising, or nil (no solo, the setting was off,
-- the tutorial, or a rival's already on the way).
local function openPractice(stage: Stage): Player?
	if not (stage.Solo and stage.OpenSolo) or stage.Tutorial or stage.HandOver then
		return nil
	end
	if stage.Duel and (stage.Duel.Tutorial or stage.Duel.Handover) then
		return nil
	end
	local a, b = stage.Players.A, stage.Players.B
	if (a == nil) == (b == nil) then
		return nil
	end
	return a or b
end

local function refreshPrompts(stage: Stage)
	for _, slot in SLOTS do
		local prompt = stage.Prompts[slot]
		local opponent = stage.Players[otherSlot(slot)]

		-- a free spot on a waiting stage, or beside someone's open practice
		prompt.Enabled = stage.Players[slot] == nil
			and (if stage.Solo then openPractice(stage) ~= nil else stage.State == "Waiting" and not stage.HandOver)
		prompt.ObjectText = if opponent then "vs " .. opponent.DisplayName else "Duel Stage"
	end
	StageStatus.Refresh(stage) -- the neon strip: free / waiting / live
end

local function placeOnSpot(stage: Stage, slot: Slot, player: Player, humanoid: Humanoid)
	local character = player.Character
	if not character then
		return
	end

	local spot = stage.Spots[slot]
	-- stand exactly on the pad (root height = hip height + half the root), so nothing floats
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootHalf = if root then root.Size.Y / 2 else 1
	local standAt = spot.Position + Vector3.new(0, spot.Size.Y / 2 + humanoid.HipHeight + rootHalf, 0)

	-- face the middle of the stage, flattened so they don't tilt
	local rigSpot = stage.Model:FindFirstChild("RigSpot") :: BasePart?
	local lookAt = if rigSpot
		then Vector3.new(rigSpot.Position.X, standAt.Y, rigSpot.Position.Z)
		else standAt + spot.CFrame.LookVector

	-- freeze them: no walking, jumping or turning while on a spot (restored in leave)
	if humanoid:GetAttribute("DuelWalkSpeed") == nil then
		humanoid:SetAttribute("DuelWalkSpeed", humanoid.WalkSpeed)
		humanoid:SetAttribute("DuelJumpPower", humanoid.JumpPower)
		humanoid:SetAttribute("DuelJumpHeight", humanoid.JumpHeight)
	end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)
	character:PivotTo(CFrame.lookAt(standAt, lookAt))
	character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
	character.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
	character.PrimaryPart.Anchored = true

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

-- Tells each player on the stage who's on the other spot (nil = it's empty).
function notifyOpponents(stage: Stage)
	if stage.Solo then
		return
	end
	local a, b = stage.Players.A, stage.Players.B
	if a then
		QueueRemote:Fire(a, { Message = "Opponent", Opponent = b })
	end
	if b then
		QueueRemote:Fire(b, { Message = "Opponent", Opponent = a })
	end
end

-- [[ Ghost rival ]]
-- Alone on a stage for GHOST_AFTER seconds (GHOST_AFTER_FIRST before your first finished
-- duel), a ghost steps up: a recorded game (Engine/GhostPool) replayed as your rival. It's a
-- solo game underneath but plays like a real duel, so the stage is closed while it runs
-- (whatever Settings.SoloOpen says). On its results screen the free spot opens: a real rival
-- stepping on then gets the "A rival stepped up!" hand-over, as from open practice.

local function levelOf(player: Player): number
	local ok, data = pcall(PlayerData.Get, player)
	return if ok and data then (Levels.FromXP(data.Player.XP.Get())) else 1
end

local function firstDuel(player: Player): boolean
	local ok, data = pcall(PlayerData.Get, player)
	return ok and data ~= nil and data.Statistics.Duels.Get() == 0
end

-- The ghost's see-through figure on the free spot (ServerStorage.GhostRig, built in Studio).
-- on = false takes it away.
local function setGhostRig(stage: Stage, on: boolean)
	if stage.GhostRig then
		stage.GhostRig:Destroy()
		stage.GhostRig = nil
	end
	local template = ServerStorage:FindFirstChild("GhostRig")
	if not on or not template then
		return
	end
	local slot: Slot = if stage.Players.A then "B" else "A"
	local spot = stage.Spots[slot]
	local rig = template:Clone() :: Model
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hip = if humanoid then humanoid.HipHeight else 2
	local half = if root then root.Size.Y / 2 else 1
	local standAt = spot.Position + Vector3.new(0, spot.Size.Y / 2 + hip + half, 0)
	local rigSpot = stage.Model:FindFirstChild("RigSpot") :: BasePart?
	local lookAt = if rigSpot then Vector3.new(rigSpot.Position.X, standAt.Y, rigSpot.Position.Z) else standAt + spot.CFrame.LookVector
	rig:PivotTo(CFrame.lookAt(standAt, lookAt))
	rig.Parent = stage.Model
	stage.GhostRig = rig
end

local function clearGhost(stage: Stage)
	stage.GhostGame = nil
	stage.GhostTimer = nil
	setGhostRig(stage, false)
end

-- A ghost rival for `player`, alone on `stage`. Returns whether it started.
local function startGhost(stage: Stage, player: Player, how: string): boolean
	if not DuelConstants.GHOST_ENABLED or stage.State ~= "Waiting" or stage.Duel then
		return false
	end
	local record = GhostPool.Take(player, levelOf(player))
	if not record then
		return false
	end
	stage.Solo = true
	stage.GhostGame = true
	stage.GhostTimer = nil
	-- (value: seconds waited for a rival; Play Again from the results didn't wait)
	local waited = if how == "Rematch" then 0 else math.floor(os.clock() - (queuedAt[player] or os.clock()))
	Analytics.Event(player, "GhostMatched", waited, how, if record.Synthetic then "Synthetic" else "Recorded")
	local again = how == "Rematch" -- Play Again from the results: straight in, like solo
	if not again then
		QueueRemote:Fire(player, { Message = "Opponent", Opponent = Duels.GhostProfile(record) })
	end
	setGhostRig(stage, true)
	tryStart(stage, true, again, again, record)
	return true
end

-- Someone on another stage the player waiting on `stage` could play right now: first a player
-- waiting alone there (not practising, not on a results screen), then open practice or
-- someone on a ghost game's results (either hands over to a real rival). Returns the stage,
-- its free spot and which kind it was.
local function realRivalFor(stage: Stage): (Stage?, Slot?, string?)
	local practice: Stage? = nil
	for _, other in DuelService.Stages do
		if other == stage or other.HandOver then
			continue
		end
		local a, b = other.Players.A, other.Players.B
		if (a == nil) == (b == nil) then
			continue -- empty or full
		end
		local them = (a or b) :: Player
		if DuelService.InvitePending(them) then
			continue -- their spot is promised to whoever they invited
		end
		if other.State == "Waiting" and not other.Solo and not other.Duel and not onResults[them] and not other.Tutorial then
			return other, if a then "B" else "A", "Waiting"
		end
		if openPractice(other) then
			practice = practice or other
		end
	end
	if practice then
		return practice, if practice.Players.A then "B" else "A", "Practice"
	end
	return nil, nil, nil
end

-- Starts the "nobody came" wait for someone alone on `stage`: every GHOST_MATCH_EVERY seconds
-- it looks for a real rival on another stage (realRivalFor) and moves them there; once
-- GHOST_AFTER seconds pass with nobody, a ghost steps up. Anything that ends the wait
-- (a rival stepping on, solo, leaving) clears stage.GhostTimer and the loop stops.
local function scheduleGhost(stage: Stage, player: Player)
	if not DuelConstants.GHOST_ENABLED then
		return
	end
	local token = {}
	stage.GhostTimer = token
	local wait = if firstDuel(player) then DuelConstants.GHOST_AFTER_FIRST else DuelConstants.GHOST_AFTER
	local started = os.clock()
	task.spawn(function()
		while stage.GhostTimer == token do
			-- (the last check lands right on the ghost's time; past it, every GHOST_MATCH_EVERY)
			local left = wait - (os.clock() - started)
			task.wait(if left > 0.05 then math.min(DuelConstants.GHOST_MATCH_EVERY, left) else DuelConstants.GHOST_MATCH_EVERY)
			if stage.GhostTimer ~= token then
				return
			end
			-- still alone, still waiting, and not practising, on a results screen or mid hand-over
			local alone = (stage.Players.A == nil) ~= (stage.Players.B == nil)
			if DuelService.PlayerStage[player] ~= stage or not alone or stage.State ~= "Waiting" or stage.Duel or stage.Solo or stage.HandOver or onResults[player] then
				stage.GhostTimer = nil
				return
			end
			-- an invite out or in, or picking a practice theme: hold on (the clock keeps running,
			-- so a ghost may follow once it's over)
			if DuelService.InvitePending(player) or picking[player] then
				continue
			end
			-- a real rival somewhere else beats a ghost
			local other, slot, kind = realRivalFor(stage)
			if other and slot then
				stage.GhostTimer = nil
				Analytics.Event(player, "RivalMoved", math.floor(os.clock() - started), kind)
				local mySlot: Slot = if stage.Players.A == player then "A" else "B"
				leave(player)
				join(other, slot, player, "Matched")
				if DuelService.PlayerStage[player] ~= other then
					-- (the move didn't take: put them back where they were)
					join(stage, mySlot, player, "Matched")
				end
				return
			end
			if os.clock() - started >= wait then
				stage.GhostTimer = nil
				startGhost(stage, player, "Queue")
				return
			end
		end
	end)
end

function join(stage: Stage, slot: Slot, player: Player, how: string?)
	if DuelService.PlayerStage[player] then
		return
	end -- already on a stage
	if player:GetAttribute("PartyStage") then
		return -- on a Party Stage (Engine/PartyService)
	end
	if stage.Players[slot] then
		return
	end
	-- someone's practising here with "Rivals can join my practice" on: stepping on ends their
	-- practice after the round they're on, then it's a duel (their game may still be running)
	local soloer = openPractice(stage)
	if not soloer and (stage.State ~= "Waiting" or stage.Solo) then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	stage.Players[slot] = player
	DuelService.PlayerStage[player] = stage
	stage.GhostTimer = nil -- a real rival: no ghost needed
	if stage.GhostGame then
		setGhostRig(stage, false) -- (they stand where the ghost stood)
	end

	-- everything that should kick this player off lives in their slot's janitor
	local slotJanitor = stage.SlotJanitors[slot]
	slotJanitor:Add(humanoid.Died:Connect(function()
		leave(player)
	end))
	slotJanitor:Add(player.CharacterRemoving:Connect(function()
		leave(player)
	end))

	placeOnSpot(stage, slot, player, humanoid)
	StageCosmetics.Apply(stage, slot, player) -- their equipped stage + mic on this spot
	refreshPrompts(stage)

	-- open the queue screen first, then tell both players who they're up against,
	-- and only then start (the intermission countdown needs the screen to be open)
	player:SetAttribute("Stage", stage.Name)
	QueueRemote:Fire(player, {Message = "Queueing"})
	queuedAt[player] = os.clock()
	played[player] = nil
	Analytics.Event(player, "QueueJoined", 1, stage.Name, how or "Prompt")
	Analytics.Onboarding(player, "SteppedOnStage")
	newSession(player)
	notifyOpponents(stage)
	onResults[player] = nil

	if soloer then
		Analytics.Event(player, "JoinedOpenPractice", 1, stage.Name, if stage.Duel then "MidGame" else "AfterGame")
		if stage.Duel then
			-- the queue card shows them finishing their round (with roughly how long), and their
			-- round screen says someone's waiting; the duel's end hands the stage over
			local seconds = stage.Duel:Interrupt()
			QueueRemote:Fire(player, { Message = "RivalFinishing", Opponent = soloer, Seconds = seconds })
			DuelRemote:Fire(soloer, { Message = "RivalWaiting", Name = player.DisplayName })
			refreshPrompts(stage)
		else
			-- between games (on their practice results): straight to the hand-over card
			handOver(stage, soloer, player, nil, nil)
		end
		return
	end

	-- the rival is still on their results screen: stepping on counts as asking for a rematch,
	-- and the game starts once they accept (requestRematch) rather than pulling them off it
	local rival = stage.Players[otherSlot(slot)]
	if rival and onResults[rival] then
		QueueRemote:Fire(player, { Message = "RematchWaiting" })
		requestRematch(player)
		return
	end
	tryStart(stage)
	if not (stage.Players.A and stage.Players.B) then
		scheduleGhost(stage, player) -- nobody on the other spot yet
	end
end

function leave(player: Player)
	local character = player.Character
	local stage = DuelService.PlayerStage[player]
	if not stage then
		return
	end -- makes double calls harmless
	DuelService.PlayerStage[player] = nil
	picking[player] = nil
	local when = if stage.Duel then "MidDuel" elseif played[player] then "AfterGame" else "Waiting"
	Analytics.Event(player, "QueueLeft", os.clock() - (queuedAt[player] or os.clock()), stage.Name, when)
	queuedAt[player], sessions[player], played[player] = nil, nil, nil

	local slot: Slot = if stage.Players.A == player then "A" else "B"
	stage.Players[slot] = nil
	stage.SlotJanitors[slot]:Cleanup()
	StageCosmetics.Apply(stage, slot, nil)
	stage.Rematch = {}
	onResults[player] = nil

	-- left during the "A rival stepped up!" countdown: the other one is back to an open queue
	if stage.HandOver then
		stage.HandOver = nil
		local other = stage.Players[otherSlot(slot)]
		if other then
			QueueRemote:Fire(other, { Message = "Queueing" })
		end
	end

	if stage.Duel then
		if stage.Duel.Solo and not table.find(stage.Duel.Players, player) then
			-- the rival waiting on someone's open practice stepped off: practice carries on
			stage.Duel:CancelInterrupt()
			local soloer = stage.Duel.Players[1]
			if soloer then
				DuelRemote:Fire(soloer, { Message = "RivalLeft" })
			end
		elseif stage.Duel.Started and not stage.Duel.Intermission then
			stage.Duel:Forfeit(player)
		else
			-- A duel is prepared one second before Start so the UI can transition, then runs
			-- the intermission countdown (the Cancel button). If a player leaves in either
			-- window, cancel the duel instead of forfeiting it: no stake, no streak change,
			-- and the one left behind goes back to waiting for a rival (notifyOpponents).
			stage.Duel:Destroy()
			stage.Duel = nil
			stage.State = "Waiting"
		end
	end

	if stage.Players.A == nil and stage.Players.B == nil then
		if stage.Solo then
			stage.Solo = false
			stage.OpenSolo = false
		end
		clearGhost(stage)
	end

	player:SetAttribute("Stage", nil)
	local root = character and character.PrimaryPart
	if root then
		root.Anchored = false
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = humanoid:GetAttribute("DuelWalkSpeed") or 16
		humanoid.JumpPower = humanoid:GetAttribute("DuelJumpPower") or 50
		humanoid.JumpHeight = humanoid:GetAttribute("DuelJumpHeight") or 7.2
		humanoid.AutoRotate = true
		humanoid:SetAttribute("DuelWalkSpeed", nil)
		humanoid:SetAttribute("DuelJumpPower", nil)
		humanoid:SetAttribute("DuelJumpHeight", nil)
	end
	QueueRemote:Fire(player, {
		Message = "LeftQueue"
	})
	refreshPrompts(stage)
	notifyOpponents(stage)
	-- the one left behind is waiting alone again: a ghost can step up for them
	local other = stage.Players[otherSlot(slot)]
	if other and not stage.Solo and stage.State == "Waiting" and not stage.Duel and not onResults[other] then
		scheduleGhost(stage, other)
	end
end

local function onDuelEnded(stage: Stage, result)
	local duel = stage.Duel
	if duel then
		duel:Destroy()
		stage.Duel = nil
	end

	-- all-time record against this rival (RivalRecord): 1v1 duels with a winner only; someone
	-- leaving counts as a win for the one who stayed, like the result itself
	local record = nil
	if not result.Solo and not result.Tutorial and not result.Party and not result.Draw and result.Winner then
		for _, p in (duel and duel.Players or {}) do
			if p ~= result.Winner then
				record = RivalRecord.Add(result.Winner, p)
			end
		end
	end

	-- everyone who played, including someone who left mid-duel (they still lose their streak)
	local players = table.clone(duel and duel.Players or {})
	local earned = Rewards.Apply(result, players)
	GhostRecorder.Record(result, players) -- for a future ghost opponent (nothing shows in game)

	-- the street screens: wins + streaks for the jumbotron, and an ENCORE comeback if the
	-- winner was behind going into the final round
	if not result.Solo and not result.Tutorial then
		for p, e in earned do
			if e.Outcome == "Win" then
				StreetScreens.Win(p, e.Streak)
			end
		end
		local before = result.EncoreScores
		if before and result.Winner and not result.Party and not result.Forfeit then
			for _, p in players do
				if p ~= result.Winner then
					local behind = (before[p] or 0) - (before[result.Winner] or 0)
					if behind >= StreetScreensConstants.COMEBACK_MIN then
						StreetScreens.Comeback(result.Winner, behind)
					end
				end
			end
		end
	end

	-- open practice: someone stepped onto the other spot while it was on. No results screen:
	-- the one practising gets the hand-over card instead (or, if they left, the rival is just
	-- waiting on an open stage now)
	if result.Solo and not result.Tutorial then
		local soloer = players[1]
		local rival = nil
		for _, slot in SLOTS do
			local p = stage.Players[slot]
			if p and p ~= soloer then
				rival = p
			end
		end
		if rival then
			if soloer and DuelService.PlayerStage[soloer] == stage then
				handOver(stage, soloer, rival, earned[soloer], #result.Rounds)
			else
				stage.Solo, stage.OpenSolo = false, false
				stage.State = "Waiting"
				refreshPrompts(stage)
				notifyOpponents(stage)
			end
			return
		end
	end

	local function k(p: Player)
		return tostring(p.UserId)
	end
	local scores, rewards = {}, {}
	for p, s in result.Scores do
		scores[k(p)] = s
	end
	local ghost = result.Ghost
	local ghostKey = tostring(DuelConstants.GHOST_USER_ID)
	if ghost then
		scores[ghostKey] = ghost.Score
	end
	for p, e in earned do
		rewards[k(p)] = e
	end
	local rounds = {}
	for i, round in result.Rounds do
		local picks = {}
		for p, pick in round.Picks do
			picks[k(p)] = { Correct = pick.Correct, Points = pick.Points, Picked = pick.Picked ~= nil, Tier = pick.Tier }
		end
		if ghost and ghost.Rounds[i] then
			picks[ghostKey] = ghost.Rounds[i]
		end
		rounds[i] = { Name = round.Song.Name, Artist = round.Song.Artist, Picks = picks, Multiplier = round.Multiplier }
	end

	local present = {}
	for _, slot in SLOTS do
		local p = stage.Players[slot]
		if p then
			table.insert(present, p)
			played[p] = true
			onResults[p] = true
		end
	end
	if #present > 0 then
		DuelRemote:Fire(Bridgenet.Players(present), {
			Message = "End",
			Winner = if result.Winner then result.Winner.UserId
				elseif ghost and ghost.Won then DuelConstants.GHOST_USER_ID
				else nil,
			Draw = result.Draw,
			Forfeit = result.Forfeit,
			-- a ghost game shows as a duel against the ghost (Ghost), not as practice
			Solo = result.Solo and not ghost,
			Ghost = if ghost then true else nil,
			Tutorial = result.Tutorial or nil,
			Mode = result.Mode,
			Stake = result.Stake,
			Scores = scores,
			Rounds = rounds,
			Rewards = rewards,
			Record = record, -- { [userId] = { W, L, Last, Delta } } vs the other player
		})
	end

	-- players stay on their spots; a rematch starts once everyone still here presses Rematch
	stage.Rematch = {}
	stage.State = "Waiting"
	-- a ghost game's over: the free spot opens, so a real rival can step on (hand-over)
	if result.Ghost and stage.GhostGame then
		stage.OpenSolo = true
	end
	refreshPrompts(stage)
end

-- Open practice → duel. The one practising gets the "A rival stepped up!" card (with the XP
-- their practice earned when it was cut short: earned / rounds, nil from their results screen)
-- and the one who stepped on sees their bar fill. After HANDOVER_COUNT seconds both go into
-- a normal duel with no queue intermission (the card was the countdown). Either leaving
-- meanwhile sends the other back to an open queue (leave).
function handOver(stage: Stage, soloer: Player, rival: Player, earned: any?, rounds: number?)
	stage.Solo = false
	stage.OpenSolo = false
	clearGhost(stage) -- a real rival beats a ghost
	stage.State = "Waiting"
	stage.Rematch = {}
	onResults[soloer], onResults[rival] = nil, nil
	local token = {}
	stage.HandOver = token
	refreshPrompts(stage)
	DuelRemote:Fire(soloer, {
		Message = "RivalSteppedUp",
		Rival = Duels.ProfileOf(rival),
		XP = if earned then earned.XP else nil,
		Rounds = rounds,
		Count = DuelConstants.HANDOVER_COUNT,
	})
	QueueRemote:Fire(rival, { Message = "RivalReady", Count = DuelConstants.HANDOVER_COUNT })
	task.delay(DuelConstants.HANDOVER_COUNT, function()
		if stage.HandOver ~= token then
			return -- someone left (leave cleared it)
		end
		stage.HandOver = nil
		local here = DuelService.PlayerStage[soloer] == stage and DuelService.PlayerStage[rival] == stage
		if not here or stage.Duel or stage.State ~= "Waiting" then
			refreshPrompts(stage)
			return
		end
		notifyOpponents(stage)
		tryStart(stage, nil, nil, true)
	end)
end

function requestRematch(player: Player)
	local stage = DuelService.PlayerStage[player]
	if not stage or stage.State ~= "Waiting" or stage.Duel then
		return
	end
	onResults[player] = nil
	stage.Rematch = stage.Rematch or {}
	if not stage.Rematch[player] then
		Analytics.Event(player, "RematchRequested", 1, if stage.Solo then "Solo" else "Duel")
	end
	stage.Rematch[player] = true

	local present, wants, all = {}, {}, true
	for _, slot in SLOTS do
		local p = stage.Players[slot]
		if p then
			table.insert(present, p)
			if stage.Rematch[p] then
				table.insert(wants, p.UserId)
			else
				all = false
			end
		end
	end
	DuelRemote:Fire(Bridgenet.Players(present), { Message = "RematchState", Wants = wants })

	if all then
		stage.Rematch = {}
		if stage.Solo or #present == 2 then
			-- close the last run's funnel, then open a new one for the rematch
			for _, p in present do
				Analytics.Event(p, "RematchStarted", 1, if stage.Solo then "Solo" else "Duel")
				if stage.Solo then
					Analytics.Funnel(p, "Solo", Analytics.SoloSession(p), "PlayedAgain")
					Analytics.SoloSession(p, true)
				else
					if sessions[p] then
						Analytics.Funnel(p, "Duel", sessions[p], "Rematch")
					end
					newSession(p)
				end
			end
		end
		if stage.GhostGame and #present == 1 then
			-- Play Again after a ghost game: a new ghost
			if not startGhost(stage, present[1], "Rematch") then
				clearGhost(stage)
				tryStart(stage, true, true)
			end
		elseif stage.Solo then
			tryStart(stage, true, true)
		elseif #present == 2 then
			tryStart(stage, nil, true)
		end
	end
end

local function cancelRematch(player: Player)
	local stage = DuelService.PlayerStage[player]
	if not stage or stage.State ~= "Waiting" or stage.Duel or not stage.Rematch or not stage.Rematch[player] then
		return
	end
	stage.Rematch[player] = nil

	local present, wants = {}, {}
	for _, slot in SLOTS do
		local p = stage.Players[slot]
		if p then
			table.insert(present, p)
			if stage.Rematch[p] then
				table.insert(wants, p.UserId)
			end
		end
	end
	DuelRemote:Fire(Bridgenet.Players(present), { Message = "RematchState", Wants = wants })
end

-- Saves the theme + pack mix-in picked on the back of the queue card (Duels reads them back,
-- and checks the theme is still open). Unknown ids are ignored.
local function saveSoloChoice(player: Player, packet)
	if type(packet) ~= "table" then
		return
	end
	local ok, data = pcall(PlayerData.Get, player)
	if not ok or not data then
		return
	end
	if type(packet.Theme) == "string" and Themes.Get(packet.Theme) then
		data.Settings.SoloTheme.Set(packet.Theme)
	end
	if type(packet.Mix) == "boolean" then
		data.Settings.SoloPool.Set(if packet.Mix then "Mix" else "Off")
	end
end

function trySolo(player: Player, packet: any?)
	local stage = DuelService.PlayerStage[player]
	if not stage then
		return
	end
	saveSoloChoice(player, packet)
	-- gave up waiting for a rival and went solo from the queue card (Quick Solo or the picker):
	-- these leave the Duel funnel at "Matched" without leaving the game
	if type(packet) == "table" and (packet.From == "Quick" or packet.From == "Picker") and not stage.Solo then
		Analytics.Event(player, "SoloFromQueue", math.floor(os.clock() - (queuedAt[player] or os.clock())), packet.From, stage.Name)
	end

	stage.Solo = true
	QueueRemote:Fire(player, {
		Message = "Opponent",
		Opponent = player,
	})

	tryStart(stage, true)
end

-- skipIntermission: straight after open practice's hand-over card (handOver), which was the countdown
-- ghost: a recording to play against (startGhost); the game is solo underneath, closed like a duel
function tryStart(stage: Stage, soloStage: boolean?, rematch: boolean?, skipIntermission: boolean?, ghost: any?)
	local a, b = stage.Players.A, stage.Players.B

	if stage.State ~= "Waiting" then
		return
	end

	if not soloStage and not (a and b)  then
		return
	end

	-- solo: "Rivals can join my practice" (Settings) keeps the other spot open while they play.
	-- Read every game, so a change in Settings counts from their next Play again.
	if soloStage then
		local me = a or b
		-- (a ghost game plays like a real duel: closed, whatever the setting says)
		stage.OpenSolo = not stage.Tutorial and me ~= nil and not ghost and SettingsService.SoloOpen(me)
	end

	stage.State = "InProgress"
	refreshPrompts(stage)

	local duel = Duels.new(stage, a, b, soloStage)
	duel.SkipIntermission = skipIntermission == true
	if ghost and soloStage then
		duel:SetGhost(ghost) -- (stage.OpenSolo is already false: nobody steps in mid-game, it opens on the results)
	elseif soloStage and stage.GhostGame then
		clearGhost(stage) -- practice after a ghost game: the ghost goes
	end
	stage.Duel = duel
	-- each player's record against the other, for the pre-duel chip
	if a and b and not soloStage then
		duel.Record = RivalRecord.Pair(a, b)
	end
	duel.Tutorial = soloStage == true and stage.Tutorial == true
	stage.Tutorial = nil -- a rematch after the tutorial is ordinary solo practice
	for _, p in duel.Players do
		if soloStage then
			duel.Sessions[p] = Analytics.SoloSession(p)
		else
			duel.Sessions[p] = sessions[p] or newSession(p)
			Analytics.Funnel(p, "Duel", duel.Sessions[p], "Matched")
			if not rematch then
				Analytics.Event(p, "MatchFound", os.clock() - (queuedAt[p] or os.clock()), stage.Name)
			end
		end
	end
	duel.Ended:Connect(function(result)
		onDuelEnded(stage, result)
	end)
	task.wait(1)
	if stage.Duel ~= duel or stage.State ~= "InProgress" then
		return
	end
	duel:Start()
end

local function createStage(model: Model): Stage?
	local spotA = model:FindFirstChild("SpotA") :: BasePart?
	local spotB = model:FindFirstChild("SpotB") :: BasePart?
	if not (spotA and spotB) then
		warn("Stage " .. model.Name .. " is missing SpotA or SpotB.")
		return nil
	end

	local stageJanitor = Janitor.new()
	local stage: Stage = {
		Name = model.Name,
		Model = model,
		State = "Waiting",
		Spots = { A = spotA, B = spotB },
		Solo = false,
		Rematch = {},
		Prompts = {},
		Players = {},
		SlotJanitors = {
			A = stageJanitor:Add(Janitor.new()),
			B = stageJanitor:Add(Janitor.new()),
		},
		Duel = nil,
		Janitor = stageJanitor,
	}

	for _, slot in SLOTS do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Join Duel"
		prompt.ObjectText = "Duel Stage"
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = PROMPT_DISTANCE
		prompt.Parent = stage.Spots[slot]

		stage.Prompts[slot] = stageJanitor:Add(prompt)
		stageJanitor:Add(prompt.Triggered:Connect(function(player: Player)
			join(stage, slot, player)
		end))
	end

	return stage
end

-- Lobby "Quick Play": fill the empty spot on a stage where someone is already waiting,
-- then one beside someone's open practice (they finish their round first), otherwise take
-- the first fully empty stage.
local function quickPlay(player: Player)
	if DuelService.PlayerStage[player] then
		return
	end

	local emptyStage: Stage? = nil
	local practiceStage: Stage? = nil
	for _, stage in DuelService.Stages do
		if openPractice(stage) then
			practiceStage = practiceStage or stage
			continue
		end
		if stage.State ~= "Waiting" or stage.Solo then
			continue
		end

		local a, b = stage.Players.A, stage.Players.B
		if (a == nil) ~= (b == nil) then
			join(stage, if a then "B" else "A", player, "QuickPlay")
			return
		elseif a == nil and b == nil and emptyStage == nil then
			emptyStage = stage
		end
	end

	if practiceStage then
		join(practiceStage, if practiceStage.Players.A then "B" else "A", player, "QuickPlay")
	elseif emptyStage then
		join(emptyStage, "A", player, "QuickPlay")
	else
		QueueRemote:Fire(player, { Message = "NoStages" })
	end
end

-- The first-join tutorial: put the player on a free stage and start a short practice game.
local function startTutorial(player: Player)
	if DuelService.PlayerStage[player] then
		local stage = DuelService.PlayerStage[player]
		if stage.State == "Waiting" and not stage.Duel and not (stage.Players.A and stage.Players.B) then
			stage.Tutorial = true
			trySolo(player)
		end
		return
	end
	for _, stage in DuelService.Stages do
		if stage.State == "Waiting" and not stage.Players.A and not stage.Players.B then
			join(stage, "A", player, "Tutorial")
			if DuelService.PlayerStage[player] == stage then
				stage.Tutorial = true
				trySolo(player)
			end
			return
		end
	end
	QueueRemote:Fire(player, { Message = "NoStages", Tutorial = true })
end

-- [[ Public ]]

-- Puts a player on the free spot of a stage someone is already waiting on (an accepted
-- duel invite). Returns whether they got on.
-- Puts a player on spot A of a fully empty stage (inviting someone from their player card,
-- InviteService "Challenge"). Returns whether they got on.
function DuelService.TakeEmptyStage(player: Player): boolean
	if DuelService.PlayerStage[player] then
		return false
	end
	for _, stage in DuelService.Stages do
		if stage.State == "Waiting" and not stage.Solo and not stage.Duel and not stage.Players.A and not stage.Players.B then
			join(stage, "A", player, "Challenge")
			return DuelService.PlayerStage[player] == stage
		end
	end
	return false
end

function DuelService.JoinStage(player: Player, stageName: string): boolean
	local stage = DuelService.Stages[stageName]
	if not stage or stage.Solo or stage.Duel or stage.State ~= "Waiting" then
		return false
	end
	local a, b = stage.Players.A, stage.Players.B
	if (a and b) or not (a or b) then
		return false -- full, or the inviter already left
	end
	join(stage, if a then "B" else "A", player, "Invite")
	return DuelService.PlayerStage[player] == stage
end

function DuelService.Start()
	for _, model in DuelStages:GetChildren() do
		local stage = createStage(model)
		if stage then
			DuelService.Stages[stage.Name] = stage
			StageStatus.Refresh(stage)
		end
	end

	Players.PlayerRemoving:Connect(leave)
	Players.PlayerRemoving:Connect(function(player)
		onResults[player] = nil
		picking[player] = nil
	end)
	-- Request is a string, or { Request = "Solo", Theme, Mix } from the solo theme picker
	QueueRemote:Connect(function(Player: Player, Request: any)
		local packet = nil
		if type(Request) == "table" then
			packet = Request
			Request = Request.Request
		end
		if Request == "Leave" then
			leave(Player)
		elseif Request == "Solo" then
			trySolo(Player, packet)
		elseif Request == "QuickPlay" then
			quickPlay(Player)
		elseif Request == "Tutorial" then
			startTutorial(Player)
		elseif Request == "Picking" and packet then
			-- the solo theme picker opened / closed (QueueController/SoloPicker)
			picking[Player] = if packet.On == true and DuelService.PlayerStage[Player] then true else nil
		end
	end)

	-- same entry points the client uses, for server code and tests
	function DuelService.Request(player: Player, request: string)
		if request == "Leave" then
			leave(player)
		elseif request == "Solo" then
			trySolo(player)
		elseif request == "QuickPlay" then
			quickPlay(player)
		elseif request == "Rematch" then
			requestRematch(player)
		elseif request == "Tutorial" then
			startTutorial(player)
		end
	end

	DuelRemote:Connect(function(player: Player, packet)
		if type(packet) ~= "table" then
			return
		end
		if packet.Action == "Rematch" then
			requestRematch(player)
			return
		elseif packet.Action == "CancelRematch" then
			cancelRematch(player)
			return
		end
		local stage = DuelService.PlayerStage[player]
		if stage and stage.Duel then
			stage.Duel:Action(player, packet)
		end
	end)
end

--| Return
return DuelService
