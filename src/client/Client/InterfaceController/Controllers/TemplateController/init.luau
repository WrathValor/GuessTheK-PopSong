-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.Promise)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local UITypes = require(ReplicatedStorage.Types.UITypes)

-- --------------------------------- Tables --------------------------------- --
-- Reusable subcontroller class - NOT a concrete screen. Instantiate one of these per real
-- screen later via TemplateController.new({ Name, ScreenGui, Frame }), the same dependency-
-- injection shape Interface.Start's commented registration example already demonstrates.
local TemplateController = {}
TemplateController.__index = TemplateController

-- --------------------------------- Methods -------------------------------- --

function TemplateController.new(config: UITypes.ControllerConfig)
	local self = setmetatable({}, TemplateController)

	self.Name = config.Name
	self.ScreenGui = config.ScreenGui
	self.FrameName = config.Frame
	-- Exclusive controllers are mutually exclusive with any other Exclusive controller
	-- (matches the Frames ScreenGui's one-full-screen-panel-at-a-time convention). Non-
	-- exclusive controllers (Feedback/Extra overlays) can be open alongside anything else.
	self.Exclusive = config.Exclusive ~= false
	self.State = "Inactive" :: UITypes.ControllerState

	self._interface = nil :: any
	self._frame = nil :: Frame?
	self._janitor = Janitor.new()

	return (self :: any) :: UITypes.Controller
end

function TemplateController.Initialize(self: typeof(TemplateController.new({} :: UITypes.ControllerConfig)), interface: any)
	self._interface = interface
	self._frame = interface:ResolveFrame(self.ScreenGui, self.FrameName)
	self._frame.Visible = false

	local exitButton = self._frame:FindFirstChild("ExitButton", true)

	if exitButton and exitButton:IsA("GuiButton") then
		self._janitor:Add(exitButton.Activated:Connect(function()
			self._interface:Close(self.Name)
		end))
	end
end

function TemplateController.Activate(self: typeof(TemplateController.new({} :: UITypes.ControllerConfig)), ...: any)
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end

	self.State = "Activating"
	self._frame.Visible = true

	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function TemplateController.Deactivate(self: typeof(TemplateController.new({} :: UITypes.ControllerConfig)))
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end

	self.State = "Deactivating"

	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function TemplateController.Destroy(self: typeof(TemplateController.new({} :: UITypes.ControllerConfig)))
	self._janitor:Destroy()
	self._interface = nil
	self._frame = nil
end

return TemplateController
