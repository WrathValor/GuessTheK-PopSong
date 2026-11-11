--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Duels = require(script.Duels)
local Rewards = require(script.Rewards)
local StageCosmetics = require(script.StageCosmetics)
local StageStatus = require(script.StageStatus)
local Analytics = require(script.Parent.Analytics)
local Themes = require(ReplicatedStorage.Modules.Library.Themes)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Server

--| Types

type Slot = "A" | "B"
-- a running rematch series between two players (see seriesFor)
type Series = {
	Games: number, -- games finished in this series
	Wins: { [string]: number }, -- userId -> wins
	LastLoser: number?, -- userId who lost the last game (nil after a draw)
}
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
	Series: Series?,
	Solo: boolean?,
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

-- rematch series, kept per pair of players rather than per stage, so stepping off and back
-- on against the same rival carries it on. It ends when either of them plays someone else
-- or leaves the game.
local seriesByPair: { [string]: Series } = {}
local seriesKey: { [Player]: string } = {}

local function endSeries(key: string)
	seriesByPair[key] = nil
	for p, k in seriesKey do
		if k == key then
			seriesKey[p] = nil
		end
	end
end

local function seriesFor(a: Player, b: Player): Series
	local x, y = a.UserId, b.UserId
	if x > y then
		x, y = y, x
	end
	local key = `{x}-{y}`
	for _, p in { a, b } do
		local old = seriesKey[p]
		if old and old ~= key then
			endSeries(old) -- playing someone else ends your last series
		end
	end
	local series = seriesByPair[key] or { Games = 0, Wins = {}, LastLoser = nil }
	seriesByPair[key] = series
	seriesKey[a], seriesKey[b] = key, key
	return series
end

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

--| Functions

-- [[ Private ]]

local leave, tryStart, notifyOpponents, requestRematch -- forward declared, join() needs them

local function otherSlot(slot: Slot): Slot
	return if slot == "A" then "B" else "A"
end

local function refreshPrompts(stage: Stage)
	for _, slot in SLOTS do
		local prompt = stage.Prompts[slot]
		local opponent = stage.Players[otherSlot(slot)]

		prompt.Enabled = stage.State == "Waiting" and stage.Players[slot] == nil
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

local function join(stage: Stage, slot: Slot, player: Player, how: string?)
	if DuelService.PlayerStage[player] then
		return
	end -- already on a stage
	if player:GetAttribute("PartyStage") then
		return -- on a Party Stage (Engine/PartyService)
	end
	if stage.State ~= "Waiting" or stage.Players[slot] then
		return
	end

	if stage.Solo then
		if stage.Players.A or stage.Players.B then
			return
		end
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	stage.Players[slot] = player
	DuelService.PlayerStage[player] = stage

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

	-- the rival is still on their results screen: stepping on counts as asking for a rematch,
	-- and the game starts once they accept (requestRematch) rather than pulling them off it
	local rival = stage.Players[otherSlot(slot)]
	if rival and onResults[rival] then
		QueueRemote:Fire(player, { Message = "RematchWaiting" })
		requestRematch(player)
		return
	end
	tryStart(stage)
end

function leave(player: Player)
	local character = player.Character
	local stage = DuelService.PlayerStage[player]
	if not stage then
		return
	end -- makes double calls harmless
	DuelService.PlayerStage[player] = nil
	local when = if stage.Duel then "MidDuel" elseif played[player] then "AfterGame" else "Waiting"
	Analytics.Event(player, "QueueLeft", os.clock() - (queuedAt[player] or os.clock()), stage.Name, when)
	queuedAt[player], sessions[player], played[player] = nil, nil, nil

	local slot: Slot = if stage.Players.A == player then "A" else "B"
	stage.Players[slot] = nil
	stage.SlotJanitors[slot]:Cleanup()
	StageCosmetics.Apply(stage, slot, nil)
	stage.Rematch = {}
	stage.Series = nil -- the series itself lives on in seriesByPair
	onResults[player] = nil

	if stage.Duel then
		if stage.Duel.Started and not stage.Duel.Intermission then
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

	if stage.Players.A == nil and stage.Players.B == nil and stage.Solo then
		stage.Solo = false
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
end

local function onDuelEnded(stage: Stage, result)
	local duel = stage.Duel
	if duel then
		duel:Destroy()
		stage.Duel = nil
	end

	-- rematch series: a win right after losing to this same rival is a Revenge win (Rewards
	-- pays the bonus) – once per series, so trading wins back and forth can't farm it – then
	-- the series score moves on
	local series = stage.Series
	if series and not result.Solo then
		local winner = result.Winner
		if winner and not result.Draw and series.LastLoser == winner.UserId and result.Leaver == nil and not series.RevengePaid then
			result.Revenge = winner
			series.RevengePaid = true
		end
		series.Games += 1
		series.LastLoser = nil
		if winner and not result.Draw then
			local id = tostring(winner.UserId)
			series.Wins[id] = (series.Wins[id] or 0) + 1
			for _, p in (duel and duel.Players or {}) do
				if p ~= winner then
					series.LastLoser = p.UserId
				end
			end
		end
	end

	-- everyone who played, including someone who left mid-duel (they still lose their streak)
	local players = table.clone(duel and duel.Players or {})
	local earned = Rewards.Apply(result, players)

	local function k(p: Player)
		return tostring(p.UserId)
	end
	local scores, rewards = {}, {}
	for p, s in result.Scores do
		scores[k(p)] = s
	end
	for p, e in earned do
		rewards[k(p)] = e
	end
	local rounds = {}
	for i, round in result.Rounds do
		local picks = {}
		for p, pick in round.Picks do
			picks[k(p)] = { Correct = pick.Correct, Points = pick.Points, Picked = pick.Picked ~= nil }
		end
		rounds[i] = { Name = round.Song.Name, Artist = round.Song.Artist, Picks = picks }
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
			Winner = result.Winner and result.Winner.UserId or nil,
			Draw = result.Draw,
			Forfeit = result.Forfeit,
			Solo = result.Solo,
			Tutorial = result.Tutorial or nil,
			Mode = result.Mode,
			Stake = result.Stake,
			Scores = scores,
			Rounds = rounds,
			Rewards = rewards,
			Series = if series then { Games = series.Games, Wins = table.clone(series.Wins) } else nil,
		})
	end

	-- players stay on their spots; a rematch starts once everyone still here presses Rematch
	stage.Rematch = {}
	stage.State = "Waiting"
	refreshPrompts(stage)
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
		if stage.Solo then
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

	stage.Solo = true
	QueueRemote:Fire(player, {
		Message = "Opponent",
		Opponent = player,
	})

	tryStart(stage, true)
end

function tryStart(stage: Stage, soloStage: boolean?, rematch: boolean?)
	local a, b = stage.Players.A, stage.Players.B

	if stage.State ~= "Waiting" then
		return
	end

	if not soloStage and not (a and b)  then
		return
	end

	stage.State = "InProgress"
	refreshPrompts(stage)

	local duel = Duels.new(stage, a, b, soloStage)
	stage.Duel = duel
	-- rematch series: the same two players carry theirs on, however they got back here
	if soloStage then
		stage.Series = nil
	elseif a and b then
		stage.Series = seriesFor(a, b)
	end
	if stage.Series and stage.Series.Games > 0 then
		duel.Series = { Game = stage.Series.Games + 1, Wins = table.clone(stage.Series.Wins) }
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
-- otherwise take the first fully empty stage.
local function quickPlay(player: Player)
	if DuelService.PlayerStage[player] then
		return
	end

	local emptyStage: Stage? = nil
	for _, stage in DuelService.Stages do
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

	if emptyStage then
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
	QueueRemote:Fire(player, { Message = "NoStages" })
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
		local key = seriesKey[player]
		if key then
			endSeries(key)
		end
		onResults[player] = nil
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
