-- -------------------------------- Services -------------------------------- --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

-- --------------------------------- Imports -------------------------------- --

local Janitor = require(ReplicatedStorage.Packages.janitor)
local Signal = require(ReplicatedStorage.Packages.signal)
local Promise = require(ReplicatedStorage.Packages.promise)
local UITypes = require(ReplicatedStorage.Types.UITypes)
local AnalyticsClient = require(ReplicatedStorage.Modules.AnalyticsClient)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FitText = require(ReplicatedStorage.Modules.UI.FitText)
local PadBinds = require(ReplicatedStorage.Modules.UI.PadBinds)
local ScreenGuide = require(script.ScreenGuide)

-- --------------------------------- Tables --------------------------------- --
-- screens that log "ScreenOpened" (Constants/AnalyticsEvents ScreenOpened.Allowed)
local SCREEN_EVENTS = {}
for _, screen in require(ReplicatedStorage.Constants.AnalyticsEvents).Custom.ScreenOpened.Allowed.Screen do
	SCREEN_EVENTS[screen] = true
end
-- frames that open without the "Open" sound (the HUD, the round screen and the victory shot have their own)
local SILENT_OPEN = { HUD = true, Game = true, Victory = true }
-- Controller: when a menu opens (or a controller is picked up while one is open) its first
-- button is selected, so A works straight away; a controller can name a better one with
-- :PadFocus(). B closes menus that have a Close button, like Escape. These screens get no
-- selection: they handle the controller themselves (Game) or have nothing to press.
local NO_PAD_FOCUS = { Game = true, Victory = true }
-- The menus' Close buttons (and back buttons inside a menu, like the Roll picker's X or the
-- Index's ‹ BACK) show B instead of their X while a controller is in use: each has a PadIcon
-- with a PadBack attribute, over the button's "Icon" if it has one. A controller with a step to
-- back out of first gets B before the menu closes: Controller:PadBack() -> true if it handled it.
local backIcons: { GuiObject } = {}

local function paintBackIcons()
	local pad = string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
	for _, icon in backIcons do
		local x = icon.Parent and icon.Parent:FindFirstChild("Icon")
		PadBinds.Paint(icon, Enum.KeyCode.ButtonB, pad)
		if x then
			x.Visible = not pad
		end
	end
end
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
-- Promises handed in by ModeChanged listeners (e.g. the HUD's slide-out) that an
-- exclusive frame waits on before it opens.
local ModeBlockers = {}
local PendingOpen: { Name: string, Args: { [number]: any, n: number } }? = nil
local StateJanitor = Janitor.new()

-- --------------------------------- Helpers -------------------------------- --

local function usingPad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

-- `gui` and every parent up to `root` are visible
local function shown(gui: Instance, root: Instance): boolean
	local at: Instance? = gui
	while at and at ~= root do
		if at:IsA("GuiObject") and not at.Visible then
			return false
		end
		at = at.Parent
	end
	return at == root
end

-- the menu's own visible Close button, if it has one
local function closeButton(frame: Instance): GuiButton?
	for _, d in frame:GetDescendants() do
		if d.Name == "Close" and d:IsA("GuiButton") and shown(d, frame) then
			return d
		end
	end
	return nil
end

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

-- Called from a ModeChanged listener to make the next exclusive frame wait for an animation.
function Interface.BlockMode(self: Self, promise: any)
	table.insert(ModeBlockers, promise)
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

-- Selects the open menu's first button when a controller is in use (see NO_PAD_FOCUS).
function Interface._padFocus(self: Self)
	local controller = self.ActiveController
	if not controller or NO_PAD_FOCUS[controller.Name] or not usingPad() then
		return
	end
	local frame = controller._frame
	if not frame or not frame.Visible then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(frame) then
		return
	end
	local focus = if controller.PadFocus then controller:PadFocus() else nil
	if focus then
		GuiService.SelectedObject = focus
	else
		GuiService:Select(frame)
	end
end

-- Drops the selection if it's inside a menu that just closed.
local function clearPadFocus(controller)
	local selected = GuiService.SelectedObject
	local frame = controller and controller._frame
	if selected and frame and selected:IsDescendantOf(frame) then
		GuiService.SelectedObject = nil
	end
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
	if SCREEN_EVENTS[name] then
		AnalyticsClient.Event("ScreenOpened", 1, name)
	end
	if not SILENT_OPEN[name] then
		Sounds.Play("Open")
	end

	Transitioning = true
	PendingOpen = nil

	local args = table.pack(...)
	local previous = if controller.Exclusive then self.ActiveController else nil
	clearPadFocus(previous)
	if previous then
		ScreenGuide.Closed(previous.Name)
	end
	local closePrevious = if previous then previous:Deactivate() else nil

	-- switch mode first; the frame waits for anything that blocked (the HUD sliding out)
	local blocked = nil
	if controller.Exclusive and self.Mode ~= "Menu" then
		table.clear(ModeBlockers)
		self.Mode = "Menu"
		self.ModeChanged:Fire(self.Mode)
		if #ModeBlockers > 0 then
			blocked = Promise.all(table.clone(ModeBlockers))
		end
		table.clear(ModeBlockers)
	end

	local function activateNew()
		if previous then
			self.ActiveController = nil
		end

		if blocked then
			return blocked:andThen(function()
				return controller:Activate(table.unpack(args, 1, args.n))
			end)
		end
		return controller:Activate(table.unpack(args, 1, args.n))
	end

	local activation = if closePrevious then closePrevious:andThen(activateNew) else activateNew()

	activation
		:andThen(function()
			if controller.Exclusive then
				self.ActiveController = controller
				self:_padFocus()
				-- the first time this screen opens: its walkthrough (ScreenGuide/Guides)
				ScreenGuide.Opened(name, controller, args)
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
	clearPadFocus(controller)
	ScreenGuide.Closed(controller.Name)

	-- bring the HUD back while the menu closes
	if self.ActiveController == controller then
		self.Mode = "Gameplay"
		self.ModeChanged:Fire(self.Mode)
	end

	controller
		:Deactivate()
		:andThen(function()
			if self.ActiveController == controller then
				self.ActiveController = nil
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
	local interfaceGui = self.PlayerGui:FindFirstChild("Interface")
	if interfaceGui and interfaceGui:IsA("ScreenGui") then
		-- Keep modal headers below Roblox's mobile top bar and device safe area.
		interfaceGui.IgnoreGuiInset = false
	end

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
	ScreenGuide.Init(self)

	-- shrink text and chip rows that would overflow their boxes (mostly on phones, where the
	-- canvas is scaled right down); watches UI the controllers build later too
	if interfaceGui then
		FitText.Watch(interfaceGui)
	end

	-- the loading screen (ReplicatedFirst/Loading) waits for this before it fades out
	Players.LocalPlayer:SetAttribute("UIReady", true)

	-- HUD is the default non-exclusive gameplay overlay, so it opens as soon as it's registered.
	--self:Open("HUD")

	StateJanitor:Add(UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- B closes a menu that has a Close button (checked even if processed: with a button
		-- selected, Roblox also uses B to leave the selection)
		if input.KeyCode == Enum.KeyCode.ButtonB then
			local active = self.ActiveController
			if active and active.PadBack and active:PadBack() then
				return
			end
			if active and active._frame and closeButton(active._frame) then
				self:Close()
			end
			return
		end
		if processed then
			return
		end

		if input.KeyCode == Enum.KeyCode.Escape and self.ActiveController then
			self:Close()
		end
	end))

	-- the Close / back buttons that show B (see paintBackIcons)
	if interfaceGui then
		for _, d in interfaceGui.Frames:GetDescendants() do
			if d.Name == "PadIcon" and d:GetAttribute("PadBack") then
				table.insert(backIcons, d)
			end
		end
	end
	paintBackIcons()

	-- picking up a controller with a menu open selects its first button; going back to the
	-- mouse / touch drops the selection box
	StateJanitor:Add(UserInputService.LastInputTypeChanged:Connect(function()
		paintBackIcons()
		if usingPad() then
			self:_padFocus()
		elseif GuiService.SelectedObject then
			GuiService.SelectedObject = nil
		end
	end))
end

return Interface
