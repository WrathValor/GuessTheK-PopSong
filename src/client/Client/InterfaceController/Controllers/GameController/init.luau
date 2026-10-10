-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local ScoreboardComponent = require(script.Scoreboard)

-- --------------------------------- Variables --------------------------------- --

local LOCAL_PLAYER = Players.LocalPlayer

-- --------------------------------- Tables --------------------------------- --
-- Reusable subcontroller class - NOT a concrete screen. Instantiate one of these per real
-- screen later via GameController.new({ Name, ScreenGui, Frame }), the same dependency-
-- injection shape Interface.Start's commented registration example already demonstrates.
local GameController = {}
GameController.__index = GameController

-- --------------------------------- Methods -------------------------------- --

function GameController.new(config: UITypes.ControllerConfig)
	local self = setmetatable({}, GameController)

	self.Name = "Game"
	self.ScreenGui = "Interface"
	self.FrameName = "Game"
	-- Exclusive controllers are mutually exclusive with any other Exclusive controller
	-- (matches the Frames ScreenGui's one-full-screen-panel-at-a-time convention). Non-
	-- exclusive controllers (Feedback/Extra overlays) can be open alongside anything else.
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState

	self._interface = nil :: any
	self._frame = nil :: Frame?
	self._janitor = Janitor.new()

	return (self :: any) :: UITypes.Controller
end

function GameController.Initialize(self: typeof(GameController.new({} :: UITypes.ControllerConfig)), interface: any)
	self._interface = interface
	self._frame = interface:ResolveFrame(self.ScreenGui, self.FrameName)
	self._frame.Visible = false
end

function GameController.Activate(self: typeof(GameController.new({} :: UITypes.ControllerConfig)), ...: any)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end

	self.State = "Activating"
	self._frame.Visible = true

	local StageAttribute = LOCAL_PLAYER:GetAttribute("Stage")
	if not StageAttribute then
		print(1)
		return
	end

	local StageModel = workspace.Map.DuelStages:FindFirstChild(StageAttribute)
	if not StageModel then
		print(2)
		return
	end

	local StageAttribute = StageModel:GetAttributes()
	local Opponent = LOCAL_PLAYER

	for Name, Value in StageAttribute do
		print(Name, Value)
		if Name == "Round" then
			continue
		end
		if Name == "StageId" then
			continue
		end
		if Name == LOCAL_PLAYER.Name then
			continue
		end
		Opponent = Name
	end

	print(Opponent)
	local OpponentPlayer = Players:FindFirstChild(Opponent.Name)
	if not OpponentPlayer then
		return print(3)
	end

	local Scoreboard = ScoreboardComponent.new(self._frame.Scoreboard, OpponentPlayer)
	Scoreboard:Initialize()
	self._janitor:Add(StageModel:GetAttributeChangedSignal("Round"):Connect(function(...)
		Scoreboard:UpdateRound(StageModel:GetAttribute("Round"))
	end))
	self._janitor:Add(StageModel:GetAttributeChangedSignal(LOCAL_PLAYER.Name):Connect(function(...)
		Scoreboard:UpdateScore(false, StageModel:GetAttribute(LOCAL_PLAYER.Name))
		if Opponent == LOCAL_PLAYER then
			Scoreboard:UpdateScore(false, StageModel:GetAttribute(LOCAL_PLAYER.Name))
		end
	end))
	if Opponent ~= LOCAL_PLAYER then
		self._janitor:Add(StageModel:GetAttributeChangedSignal(Opponent.Name):Connect(function(...)
			Scoreboard:UpdateScore(false, StageModel:GetAttribute(Opponent.Name))
		end))
	end

	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function GameController.Deactivate(self: typeof(GameController.new({} :: UITypes.ControllerConfig)))
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end

	self.State = "Deactivating"

	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function GameController.Destroy(self: typeof(GameController.new({} :: UITypes.ControllerConfig)))
	self._janitor:Destroy()
	self._interface = nil
	self._frame = nil
end

return GameController
