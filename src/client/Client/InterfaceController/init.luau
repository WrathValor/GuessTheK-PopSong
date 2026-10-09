-- -------------------------------- Services -------------------------------- --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- --------------------------------- Imports -------------------------------- --

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Signal = require(ReplicatedStorage.Packages.signal)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- --------------------------------- Tables --------------------------------- --
local Interface = {}
type Self = typeof(Interface)

-- Registered subcontrollers, keyed by Controller.Name.
Interface.Controllers = {} :: { [string]: UITypes.Controller }
-- The single currently-open Exclusive controller (e.g. a full-screen Frames panel), if any.
Interface.ActiveController = nil :: UITypes.Controller?
-- Explicit global UI mode - "Menu" while any Exclusive controller is open, "Gameplay" otherwise.
Interface.Mode = "Gameplay" :: UITypes.UIMode
Interface.PlayerGui = nil :: PlayerGui?
-- Fired whenever Mode changes, so subcontrollers (e.g. HUDController's slide-out) can react
-- to ANY exclusive frame opening/closing without Interface needing to know about them.
Interface.ModeChanged = Signal.new() :: Signal.Signal<UITypes.UIMode>

-- Transition guard: only one Open/Close may be in flight at a time, preventing overlapping
-- Activate/Deactivate calls from corrupting ActiveController/Mode state.
local Transitioning = false
local PendingOpen: { Name: string, Args: { [number]: any, n: number } }? = nil
local StateJanitor = Janitor.new()

-- --------------------------------- Methods -------------------------------- --

-- Injected into every subcontroller via `Controller:Initialize(interface)` so subcontrollers
-- never `require` Interface (or each other) directly - avoids circular requires entirely.
function Interface.RegisterController(self: Self, controller: UITypes.Controller)
	assert(
		not self.Controllers[controller.Name],
		`Interface: a controller named "{controller.Name}" is already registered`
	)

	self.Controllers[controller.Name] = controller
end

function Interface.GetController(self: Self, name: string): UITypes.Controller?
	return self.Controllers[name]
end

-- Resolves a Frame from the live PlayerGui tree (cloned from StarterGui.<ScreenGui>.<Frame>).
-- This is the single place controller-facing frame lookups go through, matching the existing
-- StarterGui convention of one root ScreenGui per surface (HUD/Extra/Feedback/Frames) holding
-- one Frame per screen.
function Interface.ResolveFrame(self: Self, screenGuiName: string, frameName: string): Frame
	local screenGui = self.PlayerGui:WaitForChild(screenGuiName)
	local frame = screenGui.Frames:WaitForChild(frameName)

	return frame :: Frame
end

local function finishTransition(self: Self)
	Transitioning = false

	local pending = PendingOpen
	PendingOpen = nil
	if pending then
		self:Open(pending.Name, table.unpack(pending.Args, 1, pending.Args.n))
	end
end

function Interface.Open(self: Self, name: string, ...: any)
	local controller = self.Controllers[name]
	assert(controller, `Interface:Open - no controller registered as "{name}"`)

	if Transitioning then
		PendingOpen = {
			Name = name,
			Args = table.pack(...),
		}
		return
	end

	if self.ActiveController == controller then
		return
	end

	Transitioning = true
	PendingOpen = nil

	local args = table.pack(...)
	local previous = if controller.Exclusive then self.ActiveController else nil
	local closePrevious = if previous then previous:Deactivate() else nil

	local function activateNew()
		if previous then
			self.ActiveController = nil
		end

		return controller:Activate(table.unpack(args, 1, args.n))
	end

	local activation = if closePrevious then closePrevious:andThen(activateNew) else activateNew()

	activation
		:andThen(function()
			if controller.Exclusive then
				self.ActiveController = controller
				self.Mode = "Menu"
				self.ModeChanged:Fire(self.Mode)
			end

			finishTransition(self)
		end)
		:catch(function(err)
			warn(`Interface:Open("{name}") failed:`, err)
			finishTransition(self)
		end)
end

function Interface.Close(self: Self, name: string?)
	local controller = if name then self.Controllers[name] else self.ActiveController

	if not controller then
		return
	end

	if Transitioning then
		return
	end

	Transitioning = true

	controller
		:Deactivate()
		:andThen(function()
			if self.ActiveController == controller then
				self.ActiveController = nil
				self.Mode = "Gameplay"
				self.ModeChanged:Fire(self.Mode)
			end

			finishTransition(self)
		end)
		:catch(function(err)
			warn(`Interface:Close({name or "ActiveController"}) failed:`, err)
			finishTransition(self)
		end)
end

-- --------------------------------- Lifecycle ------------------------------ --

function Interface.Start(self: Self)
	self.PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	for _, controller in script.Controllers:GetChildren() do
		if controller.Name == "TemplateController" then
			continue
		end

		local controllerModule = require(controller)
		self:RegisterController(controllerModule.new())
	end

	for _, controller in pairs(self.Controllers) do
		controller:Initialize(self)
	end

	-- HUD is the default non-exclusive gameplay overlay, so it opens as soon as it's registered.
	--self:Open("HUD")

	StateJanitor:Add(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end

		if input.KeyCode == Enum.KeyCode.Escape and self.ActiveController then
			self:Close()
		end
	end))
end

return Interface
