--| Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--| Imports

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local Duels = require(script.Duels)

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
local REMATCH_DELAY = 5
local SLOTS: { Slot } = { "A", "B" }

--| Variables

local QueueRemote = Bridgenet.ReferenceBridge("QueueRemote")
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
	local standAt = spot.Position + Vector3.new(0, spot.Size.Y / 2 + 3, 0)

	-- face the middle of the stage, flattened so they don't tilt
	local rigSpot = stage.Model:FindFirstChild("RigSpot") :: BasePart?
	local lookAt = if rigSpot
		then Vector3.new(rigSpot.Position.X, standAt.Y, rigSpot.Position.Z)
		else standAt + spot.CFrame.LookVector

	humanoid:Move(Vector3.zero)
	character:PivotTo(CFrame.lookAt(standAt, lookAt))
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

	if stage.Duel then
		stage.Duel:Forfeit(player)
	end

	if stage.Players.A == nil and stage.Players.B == nil and stage.Solo then
		stage.Solo = false
	end

	character.PrimaryPart.Anchored = false
	QueueRemote:Fire(player, {
		Message = "LeftQueue"
	})
	refreshPrompts(stage)
end

local function onDuelEnded(stage: Stage, result)
	if stage.Duel then
		stage.Duel:Destroy()
		stage.Duel = nil
	end

	stage.State = "Waiting"
	refreshPrompts(stage)

	-- TODO: payouts / streaks through DataService using result.Winner

	task.delay(REMATCH_DELAY, tryStart, stage) -- only starts if both are still there
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
		end
	end)
end

--| Return
return DuelService
