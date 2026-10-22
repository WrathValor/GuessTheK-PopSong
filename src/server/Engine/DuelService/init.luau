--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Duels = require(script.Duels)
local Rewards = require(script.Rewards)

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
	Janitor: any,
}

--| Constants

local PROMPT_DISTANCE = 8
local SLOTS: { Slot } = { "A", "B" }

--| Variables

local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
local DuelRemote = Bridgenet.ReferenceBridge("DuelRemote")
local DuelStages = workspace.Map.DuelStages

--| DuelService

local DuelService = {}
DuelService.Stages = {} :: { [string]: Stage }
DuelService.PlayerStage = {} :: { [Player]: Stage }

--| Functions

-- [[ Private ]]

local leave, tryStart -- forward declared, join() needs both

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

local function join(stage: Stage, slot: Slot, player: Player)
	if DuelService.PlayerStage[player] then
		return
	end -- already on a stage
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
	refreshPrompts(stage)
	tryStart(stage)

	player:SetAttribute("Stage", stage.Name)
	QueueRemote:Fire(player, {Message = "Queueing"})
end

function leave(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local stage = DuelService.PlayerStage[player]
	if not stage then
		return
	end -- makes double calls harmless
	DuelService.PlayerStage[player] = nil

	local slot: Slot = if stage.Players.A == player then "A" else "B"
	stage.Players[slot] = nil
	stage.SlotJanitors[slot]:Cleanup()
	stage.Rematch = {}

	if stage.Duel then
		stage.Duel:Forfeit(player)
	end

	if stage.Players.A == nil and stage.Players.B == nil and stage.Solo then
		stage.Solo = false
	end

	player:SetAttribute("Stage", nil)
	character.PrimaryPart.Anchored = false
	local humanoid = character:FindFirstChildOfClass("Humanoid")
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
end

local function onDuelEnded(stage: Stage, result)
	local duel = stage.Duel
	if duel then
		duel:Destroy()
		stage.Duel = nil
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
		end
	end
	if #present > 0 then
		DuelRemote:Fire(Bridgenet.Players(present), {
			Message = "End",
			Winner = result.Winner and result.Winner.UserId or nil,
			Draw = result.Draw,
			Forfeit = result.Forfeit,
			Solo = result.Solo,
			Mode = result.Mode,
			Stake = result.Stake,
			Scores = scores,
			Rounds = rounds,
			Rewards = rewards,
		})
	end

	-- players stay on their spots; a rematch starts once everyone still here presses Rematch
	stage.Rematch = {}
	stage.State = "Waiting"
	refreshPrompts(stage)
end

local function requestRematch(player: Player)
	local stage = DuelService.PlayerStage[player]
	if not stage or stage.State ~= "Waiting" or stage.Duel then
		return
	end
	stage.Rematch = stage.Rematch or {}
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
		if stage.Solo then
			tryStart(stage, true)
		elseif #present == 2 then
			tryStart(stage)
		end
	end
end

function trySolo(player: Player)
	local stage = DuelService.PlayerStage[player]
	if not stage then
		return
	end

	stage.Solo = true
	QueueRemote:Fire(player, {
		Message = "Opponent",
		Opponent = player,
	})

	tryStart(stage, true)
end

function tryStart(stage: Stage, soloStage: boolean?)
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
	duel.Ended:Connect(function(result)
		onDuelEnded(stage, result)
	end)
	task.wait(1)
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
			join(stage, if a then "B" else "A", player)
			return
		elseif a == nil and b == nil and emptyStage == nil then
			emptyStage = stage
		end
	end

	if emptyStage then
		join(emptyStage, "A", player)
	else
		QueueRemote:Fire(player, { Message = "NoStages" })
	end
end

-- [[ Public ]]

function DuelService.Start()
	for _, model in DuelStages:GetChildren() do
		local stage = createStage(model)
		if stage then
			DuelService.Stages[stage.Name] = stage
		end
	end

	Players.PlayerRemoving:Connect(leave)
	QueueRemote:Connect(function(Player: Player, Request: string)
		if Request == "Leave" then
			leave(Player)
		elseif Request == "Solo" then
			trySolo(Player)
		elseif Request == "QuickPlay" then
			quickPlay(Player)
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
		end
		local stage = DuelService.PlayerStage[player]
		if stage and stage.Duel then
			stage.Duel:Action(player, packet)
		end
	end)
end

--| Return
return DuelService
