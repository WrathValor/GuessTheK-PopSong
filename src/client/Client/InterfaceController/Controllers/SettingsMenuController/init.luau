--| SettingsMenuController ("Settings")
-- The Settings screen (Interface.Frames.Settings, built by ./Build from the "Settings" board):
--   • Audio  – Music / Sound effects / Song clips sliders (0–100%), each with a mute button
--              that remembers the level it muted from
--   • Social – Duel invites on/off (Settings.DuelInvites; the server checks it before
--              delivering an invite, see SettingsService.AcceptsInvites)
--   • Reset to default
-- Dragging a slider applies the volume straight away (Client/SettingsController.Preview);
-- the value is saved through SettingsRemote when you let go. Opened from the HUD cog.

-- -------------------------------- Services -------------------------------- --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- --------------------------------- Imports -------------------------------- --
local Janitor = require(ReplicatedStorage.Packages.janitor)
local Promise = require(ReplicatedStorage.Packages.promise)
local Bridgenet = require(ReplicatedStorage.Packages.bridgenet2)
local PlayerData = require(ReplicatedStorage.Modules.PlayerData).Client
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local FrameTransition = require(ReplicatedStorage.Modules.UI.Animations.FrameTransition)
local ButtonScale = require(ReplicatedStorage.Modules.UI.Animations.ButtonScale)
local Juice = require(ReplicatedStorage.Modules.UI.Animations.Juice)
local UITypes = require(ReplicatedStorage.Types.UITypes)

local Build = require(script.Build)
local ClientSettings = require(script.Parent.Parent.Parent.SettingsController)

-- -------------------------------- Variables ------------------------------- --
local SettingsRemote = Bridgenet.ReferenceBridge("SettingsRemote")

local C = Color3.fromHex
local WHITE = C("FFFFFF")
local RED = C("FF5A4E")
local MINT = C("A7E9B8")
local GREY = C("EDE4D4")
local STEP = 0.05 -- sliders snap to 5%
local TOGGLE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- ---------------------------------- Class --------------------------------- --
local Settings = {}
Settings.__index = Settings

function Settings.new()
	local self = setmetatable({}, Settings)
	self.Name = "Settings"
	self.Exclusive = true
	self.State = "Inactive" :: UITypes.ControllerState
	self._frame = nil :: any
	self._janitor = Janitor.new()
	self._dragging = nil :: string? -- Key of the slider being dragged
	self._unmuteTo = {} :: { [string]: number } -- level to restore when un-muting
	return (self :: any) :: UITypes.Controller
end

local function saved(key: string): number
	local ok, v = pcall(PlayerData.Settings[key].Get)
	return if ok and type(v) == "number" then v else 1
end

-- [[ Drawing ]]

function Settings:_row(spec)
	return self._frame.Panel.Content[spec.Name]
end

-- Paints one volume row at `value` (0–1).
function Settings:_paintVolume(spec, value: number)
	local row = self:_row(spec)
	local track = row.Track
	track.Fill.Size = UDim2.fromScale(value, 1)
	track.Fill.Visible = value > 0
	track.Knob.Position = UDim2.fromScale(value, 0.5)
	row.Percent.Text = `{math.floor(value * 100 + 0.5)}%`
	local muted = value <= 0
	row.Mute.BackgroundColor3 = if muted then RED else WHITE
	row.Mute.Icon.Image = if muted then Build.ICONS.SpeakerOff else Build.ICONS.SpeakerOn
end

function Settings:_paintInvites(on: boolean)
	local row = self._frame.Panel.Content.Invites
	row.State.Text = if on then "On" else "Off"
	TweenService:Create(row.Toggle, TOGGLE_TWEEN, { BackgroundColor3 = if on then MINT else GREY }):Play()
	TweenService:Create(row.Toggle.Knob, TOGGLE_TWEEN, {
		Position = if on then UDim2.new(1, -15, 0.5, 0) else UDim2.new(0, 15, 0.5, 0),
	}):Play()
end

function Settings:_refresh()
	for _, spec in Build.ROWS do
		if self._dragging ~= spec.Key then
			self:_paintVolume(spec, saved(spec.Key))
		end
	end
	local ok, on = pcall(PlayerData.Settings.DuelInvites.Get)
	self:_paintInvites(not ok or on ~= false)
end

-- [[ Changing values ]]

-- Applies locally now (so you hear it while dragging); `save` also sends it to the server.
function Settings:_setVolume(spec, value: number, save: boolean)
	value = math.clamp(math.floor(value / STEP + 0.5) * STEP, 0, 1)
	self:_paintVolume(spec, value)
	ClientSettings.Preview(spec.Key, value)
	if save then
		SettingsRemote:Fire({ Action = "SetVolume", Key = spec.Key, Value = value })
	end
end

function Settings:_valueAt(spec, x: number): number
	local track = self:_row(spec).Track
	return (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
end

function Settings:_bindVolume(spec)
	local row = self:_row(spec)
	local j = self._janitor
	local last = saved(spec.Key)

	j:Add(row.Track.Hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = spec.Key
			last = self:_valueAt(spec, input.Position.X)
			self:_setVolume(spec, last, false)
			Juice.Pop(row.Track.Knob, 0.25)
		end
	end))
	j:Add(UserInputService.InputChanged:Connect(function(input: InputObject)
		if self._dragging == spec.Key and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			last = self:_valueAt(spec, input.Position.X)
			self:_setVolume(spec, last, false)
		end
	end))
	j:Add(UserInputService.InputEnded:Connect(function(input: InputObject)
		if self._dragging == spec.Key and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			self._dragging = nil
			self:_setVolume(spec, last, true)
			if spec.Key == "SfxVolume" then
				Sounds.Play("Click") -- a sample of the new level
			end
		end
	end))

	j:Add(row.Mute.Activated:Connect(function()
		local current = saved(spec.Key)
		if current > 0 then
			self._unmuteTo[spec.Key] = current
			self:_setVolume(spec, 0, true)
		else
			self:_setVolume(spec, self._unmuteTo[spec.Key] or 1, true)
		end
		Juice.Pop(row.Mute, 0.15)
	end))
end

-- -------------------------------- Lifecycle ------------------------------- --

function Settings:Initialize(interface)
	self._interface = interface
	self._frame = interface:ResolveFrame("Interface", "Settings")
	self._frame.Visible = false
	local panel = self._frame.Panel
	ButtonScale.ApplyToDescendants(panel)
	local j = self._janitor

	j:Add(panel.Header.Close.Activated:Connect(function()
		self._interface:Close(self.Name)
	end))
	for _, spec in Build.ROWS do
		self:_bindVolume(spec)
	end

	local invites = panel.Content.Invites
	j:Add(invites.Toggle.Activated:Connect(function()
		local ok, on = pcall(PlayerData.Settings.DuelInvites.Get)
		local nextValue = not (not ok or on ~= false)
		self:_paintInvites(nextValue) -- the server confirms through PlayerData
		SettingsRemote:Fire({ Action = "SetInvites", Value = nextValue })
		Sounds.Play("Click")
	end))

	j:Add(panel.Content.Reset.Activated:Connect(function()
		SettingsRemote:Fire({ Action = "Reset" })
		for _, spec in Build.ROWS do
			self:_setVolume(spec, 1, false)
		end
		self:_paintInvites(true)
		Juice.Pop(panel.Content.Reset, 0.12)
	end))

	for _, spec in Build.ROWS do
		j:Add(PlayerData.Settings[spec.Key].Observe(function()
			if self.State ~= "Inactive" then
				self:_refresh()
			end
		end))
	end
	j:Add(PlayerData.Settings.DuelInvites.Observe(function()
		if self.State ~= "Inactive" then
			self:_refresh()
		end
	end))
end

function Settings:Activate()
	self._frame.Visible = true
	self:_refresh()
	if self.State == "Active" or self.State == "Activating" then
		return Promise.resolve()
	end
	self.State = "Activating"
	local content = self._frame.Panel.Content
	local list = {}
	for _, name in { "Music", "SoundEffects", "SongClips", "Invites" } do
		table.insert(list, content[name .. "Shadow"])
		table.insert(list, content[name])
	end
	Juice.Stagger(list, 0.05)
	return FrameTransition.Open(self._frame):andThen(function()
		self.State = "Active"
	end)
end

function Settings:Deactivate()
	if self.State == "Inactive" or self.State == "Deactivating" then
		return Promise.resolve()
	end
	self.State = "Deactivating"
	self._dragging = nil
	return FrameTransition.Close(self._frame):andThen(function()
		self._frame.Visible = false
		self.State = "Inactive"
	end)
end

function Settings:Destroy()
	self._janitor:Destroy()
end

return Settings
